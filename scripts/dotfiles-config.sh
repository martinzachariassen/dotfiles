#!/usr/bin/env bash
# Manage this repo's chezmoi profile and workstation feature toggles without
# re-running the full bootstrap wizard.

set -euo pipefail

CHEZMOI_CONFIG="${CHEZMOI_CONFIG:-$HOME/.config/chezmoi/chezmoi.toml}"
APPLY=1

# Shared libs: FEATURE_KEYS/feature_default + the chezmoi data reader. Committed
# siblings, so a missing one means a broken checkout — fail loudly.
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/lib" && pwd)"
for _lib in features.sh chezmoi-data.sh; do
    if [ ! -r "$_LIB_DIR/$_lib" ]; then
        echo "dotfiles: missing $_LIB_DIR/$_lib" >&2
        exit 1
    fi
done
# shellcheck source=lib/features.sh
. "$_LIB_DIR/features.sh"
# shellcheck source=lib/chezmoi-data.sh
. "$_LIB_DIR/chezmoi-data.sh"

usage() {
    cat <<EOF
Usage:
  dotfiles profile show
  dotfiles profile set personal|work [--no-apply]
  dotfiles features list
  dotfiles features enable macApps [--no-apply]
  dotfiles features disable macApps [--no-apply]
  dotfiles features set macApps true|false [--no-apply]
  dotfiles signing show
  dotfiles signing set [<ssh-public-key>] [--no-apply]

Environment:
  CHEZMOI_CONFIG   path to chezmoi.toml (default: ~/.config/chezmoi/chezmoi.toml)
EOF
}

die() {
    echo "dotfiles: $*" >&2
    exit 1
}

valid_profile() {
    case "$1" in
        personal | work) return 0 ;;
        *) return 1 ;;
    esac
}

valid_feature() {
    local key
    for key in "${FEATURE_KEYS[@]}"; do
        [ "$1" = "$key" ] && return 0
    done
    return 1
}

toml_quote() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
}

valid_signing_key() {
    case "$1" in
        ssh-ed25519\ * | ssh-rsa\ * | ecdsa-sha2-nistp256\ * | ecdsa-sha2-nistp384\ * | ecdsa-sha2-nistp521\ *) return 0 ;;
        *) return 1 ;;
    esac
}

read_signing_key() {
    if [ -t 0 ]; then
        printf "SSH signing public key: " >&2
        IFS= read -r REPLY
        printf '%s' "$REPLY"
    else
        IFS= read -r REPLY || return 1
        printf '%s' "$REPLY"
    fi
}

parse_common_flags() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --no-apply) APPLY=0 ;;
            -h | --help)
                usage
                exit 0
                ;;
            *) die "unknown option: $1" ;;
        esac
        shift
    done
}

ensure_config() {
    if [ ! -f "$CHEZMOI_CONFIG" ]; then
        die "chezmoi config missing at $CHEZMOI_CONFIG; run install.sh or chezmoi init first"
    fi
}

show_profile() {
    ensure_config
    cm_data_string "$(cm_data_json)" profile
}

show_features() {
    ensure_config
    local data key val
    data="$(cm_data_json)"
    for key in "${FEATURE_KEYS[@]}"; do
        val="$(cm_data_bool "$data" "$key")"
        printf '%-10s %s\n' "$key" "${val:-$(feature_default "$key")}"
    done
}

set_toml_value() {
    local section="$1" key="$2" value="$3" tmp
    tmp="$(mktemp)"
    awk -v section="$section" -v key="$key" -v value="$value" '
        BEGIN {
            in_section = 0
            saw_section = 0
            replaced = 0
            section_header = "[" section "]"
        }
        function emit_key() {
            if (section == "data.features") {
                print "        " key " = " value
            } else {
                print "    " key " = " value
            }
        }
        /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
            if (in_section && !replaced) {
                emit_key()
                replaced = 1
            }
            header = $0
            sub(/^[[:space:]]*/, "", header)
            sub(/[[:space:]]*$/, "", header)
            in_section = (header == section_header)
            if (in_section) {
                saw_section = 1
            }
        }
        {
            if (in_section && $1 == key && $2 == "=") {
                emit_key()
                replaced = 1
                next
            }
            print
        }
        END {
            if (!saw_section) {
                print ""
                print section_header
                emit_key()
            } else if (in_section && !replaced) {
                emit_key()
            }
        }
    ' "$CHEZMOI_CONFIG" >"$tmp"
    mv "$tmp" "$CHEZMOI_CONFIG"
}

apply_if_requested() {
    [ "$APPLY" = "1" ] || return 0
    if command -v chezmoi >/dev/null 2>&1; then
        chezmoi apply --force
    else
        die "chezmoi is not installed; config was updated but not applied"
    fi
}

apply_git_if_requested() {
    [ "$APPLY" = "1" ] || return 0
    if command -v chezmoi >/dev/null 2>&1; then
        chezmoi apply --force "$HOME/.config/git/config" "$HOME/.config/git/allowed_signers"
    else
        die "chezmoi is not installed; config was updated but not applied"
    fi
}

cmd_profile() {
    local action="${1:-}"
    case "$action" in
        show)
            parse_common_flags "${@:2}"
            show_profile
            ;;
        set)
            local profile="${2:-}"
            [ -n "$profile" ] || die "missing profile"
            valid_profile "$profile" || die "profile must be personal or work"
            parse_common_flags "${@:3}"
            ensure_config
            set_toml_value "data" "profile" "\"$profile\""
            echo "dotfiles: profile set to $profile"
            apply_if_requested
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

cmd_features() {
    local action="${1:-}"
    case "$action" in
        list)
            parse_common_flags "${@:2}"
            show_features
            ;;
        enable | disable)
            shift
            local value="true" key
            [ "$action" = "disable" ] && value="false"
            local keys=()
            while [ $# -gt 0 ]; do
                case "$1" in
                    --no-apply | -h | --help) break ;;
                    *) keys+=("$1") ;;
                esac
                shift
            done
            [ ${#keys[@]} -gt 0 ] || die "missing feature"
            parse_common_flags "$@"
            ensure_config
            for key in "${keys[@]}"; do
                valid_feature "$key" || die "unknown feature: $key"
                set_toml_value "data.features" "$key" "$value"
                echo "dotfiles: feature $key=$value"
            done
            apply_if_requested
            ;;
        set)
            local key="${2:-}" value="${3:-}"
            [ -n "$key" ] || die "missing feature"
            valid_feature "$key" || die "unknown feature: $key"
            case "$value" in true | false) ;; *) die "feature value must be true or false" ;; esac
            parse_common_flags "${@:4}"
            ensure_config
            set_toml_value "data.features" "$key" "$value"
            echo "dotfiles: feature $key=$value"
            apply_if_requested
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

cmd_signing() {
    local action="${1:-}"
    case "$action" in
        show)
            parse_common_flags "${@:2}"
            ensure_config
            cm_data_string "$(cm_data_json)" signingKey
            ;;
        set)
            local signing_key=""
            shift
            while [ $# -gt 0 ]; do
                case "$1" in
                    --no-apply) APPLY=0 ;;
                    -h | --help)
                        usage
                        exit 0
                        ;;
                    -*) die "unknown option: $1" ;;
                    *)
                        [ -z "$signing_key" ] || die "only one signing key can be provided"
                        signing_key="$1"
                        ;;
                esac
                shift
            done
            if [ -z "$signing_key" ]; then
                signing_key="$(read_signing_key)" || die "missing SSH public signing key"
            fi
            [ -n "$signing_key" ] || die "missing SSH public signing key"
            valid_signing_key "$signing_key" || die "signing key must be an SSH public key line"
            ensure_config
            set_toml_value "data" "signingKey" "$(toml_quote "$signing_key")"
            set_toml_value "data" "useOnePassword" "true"
            echo "dotfiles: git signing key configured"
            apply_git_if_requested
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main() {
    local cmd="${1:-}"
    case "$cmd" in
        profile)
            shift
            cmd_profile "$@"
            ;;
        features)
            shift
            cmd_features "$@"
            ;;
        signing)
            shift
            cmd_signing "$@"
            ;;
        -h | --help | "") usage ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"
