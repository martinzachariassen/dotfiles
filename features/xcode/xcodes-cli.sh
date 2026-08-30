#!/usr/bin/env bash
# xcodes.sh — install the `xcodes` CLI from its upstream prebuilt release.
#
# Why this exists instead of a Brewfile line: `brew "xcodesorg/made/xcodes"`
# builds from source on any current macOS (its only bottles are tagged
# arm64_mojave/mojave, which no modern Apple Silicon fallback chain reaches),
# and that build needs `xcbuild` — which ships inside a full Xcode.app. Since
# `xcodes` is the tool that *installs* Xcode.app, a fresh Mac carrying only the
# Command Line Tools could never satisfy it, and `Brewfile.apple-dev` failed on
# every clean install. Upstream publishes a signed universal binary for this;
# we fetch that, verify it, and drop it on PATH.
#
# The pin (version/url/sha256) lives in src/.chezmoidata/xcode.toml so it sits
# with the rest of the data model rather than being buried in a script.
# shellcheck disable=SC2034,SC2329

[ -n "${__DOTFILES_XCODES_SH:-}" ] && return 0
__DOTFILES_XCODES_SH=1

# Where the binary lands. ~/.local/bin is already first on PATH (dot_zprofile)
# and is not Homebrew-owned, so a later `brew` operation can't clobber it.
XCODES_BIN_DIR="${XCODES_BIN_DIR:-$HOME/.local/bin}"

# xcodes_pin KEY — read version/url/sha256 from .chezmoidata via `chezmoi data`.
# Single source of truth: nothing is baked in as a fallback, so the pin can
# never silently drift from the data file.
xcodes_pin() {
    local key="$1" json
    json="$(chezmoi data --format=json 2>/dev/null || true)"
    [ -n "$json" ] || return 1
    if command -v jq >/dev/null 2>&1; then
        printf '%s\n' "$json" | jq -er --arg k "$key" '.xcodes[$k] // empty' 2>/dev/null
    else
        # Fallback for a machine without jq: the xcodes object is flat and its
        # keys are unique across `chezmoi data`, so a keyed match is safe.
        printf '%s\n' "$json" |
            sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" |
            sed '/^$/d' | tail -1 | grep . || return 1
    fi
}

# xcodes_installed — 0 when a usable `xcodes` is already on PATH.
xcodes_installed() { command -v xcodes >/dev/null 2>&1; }

# xcodes_bootstrap — fetch, verify and install the pinned release. Idempotent:
# returns 0 immediately when `xcodes` is already on PATH (including one that
# came from Homebrew on an older machine, which we leave entirely alone).
#
# Prints progress on its own lines; the caller owns the surrounding step UI.
xcodes_bootstrap() {
    xcodes_installed && return 0

    local version url sha tmp zip
    version="$(xcodes_pin version)" || {
        printf 'xcodes: no pin in .chezmoidata/xcode.toml (is chezmoi initialised?)\n' >&2
        return 1
    }
    url="$(xcodes_pin url)" && sha="$(xcodes_pin sha256)" || {
        printf 'xcodes: pin is incomplete — need url and sha256\n' >&2
        return 1
    }

    # Bare `mktemp -d`, not `-t <prefix>`: that form is BSD-only. GNU coreutils
    # treats the argument as a template and rejects it for having no X's, so on
    # Linux this returned 1 before anything was downloaded.
    tmp="$(mktemp -d)" || return 1
    zip="$tmp/xcodes.zip"
    # Clean up on every exit path, including the failures below.
    trap 'rm -rf "$tmp" 2>/dev/null || true' RETURN

    curl -fsSL --retry 3 -o "$zip" "$url" || {
        printf 'xcodes: download failed — %s\n' "$url" >&2
        return 1
    }

    # Verify before unzipping: an unverified archive is never expanded, let
    # alone made executable.
    # shasum on macOS, sha256sum on most Linux. If neither exists `got` stays
    # empty and the comparison below fails closed — never silently passes.
    local got
    if command -v shasum >/dev/null 2>&1; then
        got="$(shasum -a 256 "$zip" 2>/dev/null | awk '{print $1}')"
    else
        got="$(sha256sum "$zip" 2>/dev/null | awk '{print $1}')"
    fi
    if [ "$got" != "$sha" ]; then
        printf 'xcodes: checksum mismatch for %s\n  expected %s\n  got      %s\n' \
            "$url" "$sha" "${got:-<none>}" >&2
        return 1
    fi

    unzip -qo "$zip" -d "$tmp" || {
        printf 'xcodes: could not unzip the release archive\n' >&2
        return 1
    }
    [ -f "$tmp/xcodes" ] || {
        printf 'xcodes: release archive did not contain an `xcodes` binary\n' >&2
        return 1
    }

    mkdir -p "$XCODES_BIN_DIR" || return 1
    # install(1) over mv: sets the mode and replaces atomically in one step.
    install -m 0755 "$tmp/xcodes" "$XCODES_BIN_DIR/xcodes" || return 1

    # ~/.local/bin is on PATH for login shells, but this script may be running in
    # one that started before the directory existed. Make the new binary
    # reachable for the rest of this process.
    case ":$PATH:" in
        *":$XCODES_BIN_DIR:"*) ;;
        *) PATH="$XCODES_BIN_DIR:$PATH" && export PATH ;;
    esac

    xcodes_installed
}
