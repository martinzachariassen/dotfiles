# shellcheck shell=bash
#
# Reading config.toml. There is no general writer: every TOML writer drops
# comments, so the file is generated once and never rewritten.
#
# dasel v3: input on stdin, -i is the INPUT format, a missing key exits 1.
# Everything is read as -o yaml so __cfg_unquote has one set of rules to undo.

cfg_exists() { [[ -f $DOT_CONFIG ]]; }

# The schema config_generate writes and cfg_parse_problems demands. Bump it
# only when the file's shape changes enough that an older `dot` would misread a
# newer config, or the reverse. It is checked, not just written: a version
# marker that guarantees nothing is worse than none, because it looks like one.
DOT_CONFIG_SCHEMA=1

# Only "" and ': ' need undoing. YAML's other escapes are deliberately absent:
# no setting here can contain a tab or newline, and a \t rule would corrupt the
# literal backslashes config_generate now supports.
__cfg_unquote() {
  local v=$1
  case $v in
    "'"*"'")
      v=${v:1:${#v}-2}
      v=${v//\'\'/\'}
      ;;
    '"'*'"')
      v=${v:1:${#v}-2}
      v=${v//\\\"/\"}
      v=${v//\\\\/\\}
      ;;
  esac
  printf '%s\n' "$v"
}

# toml_get FILE KEY [DEFAULT] -- one reader for config.toml and module.toml.
toml_get() {
  local file=$1 key=$2 default=${3:-} raw
  [[ -f $file ]] || {
    printf '%s\n' "$default"
    return 0
  }
  if raw=$(dasel -i toml -o yaml "$key" <"$file" 2>/dev/null); then
    __cfg_unquote "$raw"
  else
    printf '%s\n' "$default"
  fi
}

# toml_list FILE KEY -- one element per line.
toml_list() {
  local file=$1 key=$2 line
  [[ -f $file ]] || return 0
  dasel -i toml -o yaml "$key" <"$file" 2>/dev/null | while IFS= read -r line; do
    [[ $line == '[]' ]] && continue
    line=$(__cfg_unquote "${line#- }")
    if [[ -n $line ]]; then printf '%s\n' "$line"; fi
  done
}

cfg_get() { toml_get "$DOT_CONFIG" "$1" "${2:-}"; }
cfg_list() { toml_list "$DOT_CONFIG" "$1"; }

# cfg_parse_problems -- one line per sign the config did not parse whole.
#
# dasel does not validate: on a malformed line it stops, keeps what it read,
# and exits 0. A missing comma in `enabled` drops the whole [modules] table
# while keys above it still answer -- and with nothing enabled, doctor reports
# every link as orphaned and tells you to delete your dotfiles.
#
# Two checks, because there is no real TOML parser here. Residual: a typo in
# the LAST table drops only that table's remaining scalars, unnoticed.
cfg_parse_problems() {
  local -A seen=()
  local name

  while IFS= read -r name; do
    seen[$name]=1
  done < <(dasel -i toml -o yaml 'keys()' <"$DOT_CONFIG" 2>/dev/null | sed 's/^- //')

  # 1. Every declared [table] must be visible to the parser. Names are only
  #    compared, never turned into a selector (dasel reads `-` as subtraction).
  while IFS= read -r name; do
    if [[ -z ${seen[$name]:-} ]]; then
      printf 'declares [%s] but the parser cannot see it -- syntax error above that line\n' "$name"
    fi
  done < <(sed -n 's/^\[\[*\([A-Za-z0-9_-]\{1,\}\)[].].*/\1/p' "$DOT_CONFIG" | sort -u)

  # 2. modules.enabled must be READABLE -- `enabled = []` is legal; a missing
  #    key is a truncated file.
  if [[ -n ${seen[modules]:-} ]] &&
    ! dasel -i toml -o yaml 'modules.enabled' <"$DOT_CONFIG" >/dev/null 2>&1; then
    printf 'has a [modules] table with no readable `enabled` list\n'
  fi

  # 3. The schema must be one this checkout speaks. Reported rather than
  #    migrated: config.toml is the user's file and nothing here rewrites it.
  local schema
  schema=$(toml_get "$DOT_CONFIG" 'schema' '')
  if [[ -z $schema ]]; then
    printf 'has no `schema` key -- it predates this checkout; regenerate it with `dot config --init`\n'
  elif [[ $schema != "$DOT_CONFIG_SCHEMA" ]]; then
    printf 'is schema %s but this checkout speaks schema %s -- pull the repo, or regenerate the config\n' \
      "$schema" "$DOT_CONFIG_SCHEMA"
  fi
}

# __cfg_quote VALUE -- a TOML basic string. Every user-supplied value goes
# through here: one stray `"` makes dasel drop every table below it.
__cfg_quote() {
  local v=$1
  v=${v//\\/\\\\}
  v=${v//\"/\\\"}
  printf '"%s"' "$v"
}

# config_generate NAME EMAIL MODULES [SIGNINGKEY] -- the one writer. Refuses
# to clobber; after this the file belongs to the user.
config_generate() {
  local name=$1 email=$2 modules=$3 signingkey=${4:-} line

  if cfg_exists; then
    fail "$DOT_CONFIG already exists -- delete it first to regenerate"
    return 1
  fi

  if [[ $DOT_DRY_RUN == 1 ]]; then
    info "write   $DOT_CONFIG"
    return 0
  fi

  mkdir -p "$(dirname "$DOT_CONFIG")"
  {
    cat <<'HEADER'
# dotfiles configuration.
#
# Generated once by `dot config --init`. From here on this file is yours --
# edit it freely, comments and all. Nothing in the tool rewrites it.
#
# Apply changes with:  dot apply
# Check the machine:   dot doctor

HEADER
    printf 'schema = %s\n\n' "$DOT_CONFIG_SCHEMA"

    printf '[user]\nname  = %s\nemail = %s\n\n' \
      "$(__cfg_quote "$name")" "$(__cfg_quote "$email")"

    printf '[modules]\n'
    printf '# Add or remove names, then run `dot apply`.\n'
    printf '# Available: %s\n' "$(modules_all | tr '\n' ' ' | sed 's/ $//')"
    printf 'enabled = [\n'
    while IFS= read -r line; do
      if [[ -n $line ]]; then printf '  %s,\n' "$(__cfg_quote "$line")"; fi
    done <<<"$modules"
    printf ']\n\n'

    cat <<'FOOTER'
# Per-module settings live under [settings.<module>]. A module reads them with
# module_setting, and ignores anything it does not recognise.
FOOTER

    if [[ -n $signingkey ]]; then
      printf '\n[settings.git]\nsigningkey = %s\n' "$(__cfg_quote "$signingkey")"
    else
      printf '#\n# [settings.git]\n# signingkey = "ssh-ed25519 AAAA..."\n'
    fi
  } >"$DOT_CONFIG"

  ok "wrote $DOT_CONFIG"
}
