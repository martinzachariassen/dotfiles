# shellcheck shell=bash
#
# Reading config.toml. There is no general writer: every TOML writer drops
# comments, so the file is generated once and never rewritten.
#
# dasel v3: input on stdin, -i is the INPUT format, a missing key exits 1.
# Everything is read as -o yaml so __cfg_unquote has one set of rules to undo.

cfg_exists() { [[ -f $DOT_CONFIG ]]; }

# Bump only when the file's shape changes enough that an older `dot` would
# misread a newer config, or the reverse. Checked, not just written: a version
# marker that guarantees nothing is worse than none, because it looks like one.
DOT_CONFIG_SCHEMA=1

# Only "" and '' need undoing. YAML's other escapes are deliberately absent: no
# setting here can contain a tab or newline, and a \t rule would corrupt the
# literal backslashes config_generate supports.
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

# Set when taplo ran and did not answer, so doctor can say so. Never a problem
# line: a checker that crashed is not evidence about the file, and refusing to
# apply over it would make a broken taplo lock the machine out of its config.
DOT_CFG_UNCHECKED=0

# Only meaningful after cfg_parse_problems has run in this process.
cfg_unchecked() { ((DOT_CFG_UNCHECKED)); }

# __cfg_taplo -- four answers: 0 valid, 1 invalid, 2 could not be checked,
# 3 not installed yet. taplo documents 1 for a file with syntax errors, so
# anything else is taplo itself falling over (a rust panic exits 101) -- and
# that must never render as "your config is not valid TOML". Not installed is
# its own answer because it is the normal state before phase 1, not a fault.
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

# cfg_parse_problems -- one line per sign the config did not parse whole.
#
# dasel does not validate: on a malformed line it stops, keeps what it read and
# exits 0. A missing comma in `enabled` drops the whole [modules] table, and
# with nothing enabled doctor calls every link orphaned. taplo answers outright
# and so runs first; the two heuristics below are what is left before phase 1
# has installed it, and they miss a typo in the LAST table.
cfg_parse_problems() {
  local -A seen=()
  local name status=0

  # An INPUT, like DOT_BREW_BIN: without one the "not installed yet" branch is
  # unreachable on any machine that has taplo, and that is the branch the two
  # heuristics below exist for.
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

# --- Editing `enabled` ------------------------------------------------------
#
# The one exception to "config.toml is written once", and the narrowest one
# available: a single array, a line at a time, every other byte copied through.
# Same trade claude-code makes with ~/.claude/settings.json. Hand-editing stays
# supported, so an array that lost the generated shape makes these REFUSE.

# __cfg_enabled_span -- "first last" line indices of the array body: the line
# after `enabled = [` and the line holding `]`. Fails when the array was
# reformatted by hand, and the caller must then say so rather than guess.
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
    # An entry, or a comment or blank the user put between them. Anything else
    # and the array is no longer a shape this can edit without losing part of it.
    [[ ${lines[i]} =~ ^\ \ \"[^\"]+\",$ || ${lines[i]} =~ ^[[:space:]]*(#.*)?$ ]] ||
      return 1
  done
  ((end)) || return 1

  printf '%s %s\n' "$start" "$end"
}

cfg_enabled_editable() { __cfg_enabled_span >/dev/null; }

# __cfg_write_lines -- give the user's file back the way it came. mktemp is 0600
# and `mv` carries that onto the destination, so a config kept at 0644 would come
# back private (claude-code's hooks guard the same way). Validated before the
# swap: after `mv` there is nothing to roll back to.
__cfg_write_lines() {
  local tmp taplo=${DOT_TAPLO_BIN:-taplo}
  tmp=$(mktemp "${DOT_CONFIG}.XXXXXX")
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

# cfg_module_add NAME -- alphabetical, the order config_generate wrote and every
# report prints. Comments keep their place; a duplicate is the caller's problem.
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

# cfg_module_remove NAME -- drops the one line, inside the array body only. A
# string that looks like an entry anywhere else in the file is not one.
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
