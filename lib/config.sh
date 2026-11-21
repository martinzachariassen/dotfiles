# shellcheck shell=bash

cfg_exists() { [[ -f $DOT_CONFIG ]]; }

DOT_CONFIG_SCHEMA=1

# Only "" and '' are undone: a \t rule would corrupt literal backslashes.
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

DOT_CFG_UNCHECKED=0

cfg_unchecked() { ((DOT_CFG_UNCHECKED)); }

# Only taplo's documented exit 1 means invalid; a panic exits 101.
__cfg_taplo() {
  local taplo=${DOT_TAPLO_BIN:-taplo} status=0
  command -v "$taplo" >/dev/null 2>&1 || return 3
  "$taplo" check "$DOT_CONFIG" >/dev/null 2>&1 || status=$?
  case $status in
    0) return 0 ;;
    1) return 1 ;;
    *) return 2 ;;
  esac
}

# dasel stops at a malformed line and exits 0, so taplo is asked first.
cfg_parse_problems() {
  local -A seen=()
  local name status=0

  DOT_CFG_UNCHECKED=0
  __cfg_taplo || status=$?
  case $status in
    1)
      printf 'is not valid TOML -- see:  %s check %s\n' \
        "${DOT_TAPLO_BIN:-taplo}" "$DOT_CONFIG"
      return 0
      ;;
    2) DOT_CFG_UNCHECKED=1 ;;
  esac

  # Names are only compared, never built into a selector: dasel reads `-` as
  # subtraction.
  while IFS= read -r name; do
    seen[$name]=1
  done < <(dasel -i toml -o yaml 'keys()' <"$DOT_CONFIG" 2>/dev/null | sed 's/^- //')

  while IFS= read -r name; do
    if [[ -z ${seen[$name]:-} ]]; then
      printf 'declares [%s] but the parser cannot see it -- syntax error above that line\n' "$name"
    fi
  done < <(sed -n 's/^\[\[*\([A-Za-z0-9_-]\{1,\}\)[].].*/\1/p' "$DOT_CONFIG" | sort -u)

  if [[ -n ${seen[modules]:-} ]] &&
    ! dasel -i toml -o yaml 'modules.enabled' <"$DOT_CONFIG" >/dev/null 2>&1; then
    printf 'has a [modules] table with no readable `enabled` list\n'
  fi

  local schema
  schema=$(toml_get "$DOT_CONFIG" 'schema' '')
  if [[ -z $schema ]]; then
    printf 'has no `schema` key -- it predates this checkout; regenerate it with `dot config --init`\n'
  elif [[ $schema != "$DOT_CONFIG_SCHEMA" ]]; then
    printf 'is schema %s but this checkout speaks schema %s -- pull the repo, or regenerate the config\n' \
      "$schema" "$DOT_CONFIG_SCHEMA"
  fi
}

# One stray `"` in a value makes dasel drop every table below it.
__cfg_quote() {
  local v=$1
  v=${v//\\/\\\\}
  v=${v//\"/\\\"}
  printf '"%s"' "$v"
}

config_generate() {
  local name=$1 email=$2 modules=$3 signingkey=${4:-} line

  if cfg_exists; then
    fail config "${DOT_CONFIG/#$HOME/\~} already exists -- delete it first to regenerate"
    return 1
  fi

  if [[ $DOT_DRY_RUN == 1 ]]; then
    info write "${DOT_CONFIG/#$HOME/\~}"
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

  ok config "wrote ${DOT_CONFIG/#$HOME/\~}"
}

__cfg_enabled_span() {
  local -a lines
  local i n start=0 end=0
  mapfile -t lines <"$DOT_CONFIG"
  n=${#lines[@]}

  for ((i = 0; i < n; i++)); do
    if [[ ${lines[i]} == 'enabled = [' ]]; then
      start=$((i + 1))
      break
    fi
  done
  ((start)) || return 1

  for ((i = start; i < n; i++)); do
    [[ ${lines[i]} == ']' ]] && {
      end=$i
      break
    }
    [[ ${lines[i]} =~ ^\ \ \"[^\"]+\",$ || ${lines[i]} =~ ^[[:space:]]*(#.*)?$ ]] ||
      return 1
  done
  ((end)) || return 1

  printf '%s %s\n' "$start" "$end"
}

cfg_enabled_editable() { __cfg_enabled_span >/dev/null; }

__cfg_write_lines() {
  local tmp taplo=${DOT_TAPLO_BIN:-taplo}
  tmp=$(mktemp "${DOT_CONFIG}.XXXXXX")
  # mktemp creates 0600, and `mv` would carry that onto the user's file.
  chmod "$(stat -f '%Lp' "$DOT_CONFIG")" "$tmp"

  if ! printf '%s\n' "$@" >"$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  if command -v "$taplo" >/dev/null 2>&1 && ! "$taplo" check "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"
    return 1
  fi
  # `if`, never `... && mv`: set -e ignores a non-final member of an && list.
  if mv "$tmp" "$DOT_CONFIG"; then
    return 0
  fi
  rm -f "$tmp"
  return 1
}

cfg_module_add() {
  local name=$1 start end i at
  local -a lines
  read -r start end < <(__cfg_enabled_span) || return 1
  mapfile -t lines <"$DOT_CONFIG"

  at=$end
  for ((i = start; i < end; i++)); do
    if [[ ${lines[i]} =~ ^\ \ \"([^\"]+)\",$ && ${BASH_REMATCH[1]} > $name ]]; then
      at=$i
      break
    fi
  done

  __cfg_write_lines "${lines[@]:0:at}" "  \"$name\"," "${lines[@]:at}"
}

cfg_module_remove() {
  local name=$1 start end i
  local -a lines out=()
  read -r start end < <(__cfg_enabled_span) || return 1
  mapfile -t lines <"$DOT_CONFIG"

  for ((i = 0; i < ${#lines[@]}; i++)); do
    if ((i >= start && i < end)) && [[ ${lines[i]} == "  \"$name\"," ]]; then
      continue
    fi
    out+=("${lines[i]}")
  done

  __cfg_write_lines "${out[@]}"
}
