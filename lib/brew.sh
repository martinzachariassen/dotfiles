# shellcheck shell=bash

brew_load() {
  command -v brew >/dev/null 2>&1 && return 0
  local brew_bin=${DOT_BREW_BIN:-/opt/homebrew/bin/brew}
  if [[ -x $brew_bin ]]; then
    eval "$("$brew_bin" shellenv)"
    return 0
  fi
  return 1
}

# 0 satisfied, 1 missing, 2 could not check -- never read 2 as installed.
brew_missing() {
  local file=$1 out status=0
  [[ -f $file ]] || return 0
  command -v brew >/dev/null 2>&1 || return 2

  out=$(HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --file "$file" --no-upgrade --verbose 2>&1) ||
    status=1
  ((status)) || return 0

  # Not the leading arrow: a multibyte glyph matches nothing under a C locale.
  out=$(sed -n -E 's/^.*(Formula|Cask) ([^ ]+) needs to be installed\.$/\1 \2/p' <<<"$out")
  [[ -n $out ]] || return 2
  printf '%s\n' "$out"
  return 1
}

brew_bundle() {
  local file=$1
  local label=${2:-$(basename "$(dirname "$file")")}
  [[ -f $file ]] || return 0

  if ! brew_load; then
    fail packages "Homebrew is not installed -- cannot install for $label"
    return 1
  fi

  local named
  named=$(grep -cE '^[[:space:]]*(brew|cask)[[:space:]]' "$file") || named=0

  if [[ $DOT_DRY_RUN == 1 ]]; then
    local planned kind name status=0
    planned=$(brew_missing "$file") || status=$?
    case $status in
      0) ok packages "$(ui_count "$named" package)" ;;
      1) while read -r kind name; do
        info install "${kind,,} $name"
      done <<<"$planned" ;;
      *) info packages "brew bundle --file ${file#"$DOT_ROOT"/}" ;;
    esac
    return 0
  fi

  __brew_follow "$file" "$named" && return 0

  fail packages "brew bundle failed for $label"

  local missing status=0
  missing=$(brew_missing "$file") || status=$?
  case $status in
    1)
      while IFS= read -r line; do dim 'still missing' "$line"; done <<<"$missing"
      if grep -q '^Cask ' <<<"$missing"; then
        dim 'a cask already in /Applications by hand: brew install --cask --adopt <name>'
      fi
      ;;
    2) dim 'brew could not say what is missing -- see its output above' ;;
  esac
  return 1
}

__brew_kind() {
  local file=$1 name=$2
  if grep -qE "^[[:space:]]*cask[[:space:]]+\"([^\"]*/)?$name\"" "$file"; then
    printf 'cask\n'
  else
    printf 'formula\n'
  fi
}

# 0 when the server will not say. Only asked for a cask, and only while a
# terminal is watching: it costs a request, and a bottle's URL needs a token.
__brew_cask_size() {
  local url
  url=$(brew info --cask --json=v2 "$1" 2>/dev/null | dasel -i json -o yaml 'casks[0].url' 2>/dev/null) || url=''
  url=${url#\"}
  url=${url%\"}
  if [[ $url != https://* ]]; then
    printf '0\n'
    return 0
  fi
  "${DOT_CURL_BIN:-curl}" -sIL --max-time 4 "$url" 2>/dev/null | tr -d '\r' |
    awk 'tolower($1) == "content-length:" { n = $2 } END { print n + 0 }'
}

# The newest download brew has open since `since` (epoch seconds), or nothing.
__brew_partial() {
  local dir=$1 since=$2 f m best='' newest=0
  for f in "$dir"/*.incomplete; do
    [[ -f $f ]] || continue
    m=$(stat -f '%m' "$f") || continue
    if ((m >= since && m >= newest)); then
      best=$f newest=$m
    fi
  done
  if [[ -n $best ]]; then stat -f '%z' "$best"; fi
}

__brew_finish() {
  [[ -n $pkg ]] || return 0
  if grep -qxF "$pkg" <<<"$failed"; then
    pkg=''
    return 0
  fi
  local size=$total note=''
  ((size > 0)) || size=$bytes
  if ((size > 0)); then note=" ($(ui_megabytes "$size"))"; fi
  ok installed "$kind $pkg$note"$'\t'"$(ui_duration $(($(ui_now) - began)))"
  installed=$((installed + 1))
  pkg=''
}

# brew bundle hides each install's own output and says one line as it starts
# the next package, so a long silence is a download or a build, never a hang.
__brew_follow() {
  local file=$1 named=$2 fd pid status=0 line chunk got
  local pkg='' kind='' since=0 began=0 total=0 bytes=0 first=0 first_at=0 rate tick=0
  local using=0 installed=0 idle=0 beat=${DOT_UI_HEARTBEAT:-15} wait_s cache='' live=0
  local failed='' name

  if ((__UI_LIVE)) && [[ -n ${DOT_UI_RECORDS:-} ]]; then
    live=1
    cache="$(brew --cache 2>/dev/null)/downloads"
  fi
  wait_s=$beat
  ((live == 0)) || wait_s=0.25

  exec {fd}< <(brew bundle --file "$file" --no-upgrade 2>&1)
  pid=$!
  line=''
  while true; do
    chunk=''
    if IFS= read -r -t "$wait_s" -u "$fd" chunk; then status=0; else status=$?; fi
    line+=$chunk
    if ((status > 128)); then
      if ((live)) && [[ -n $pkg ]]; then
        tick=$((tick + 1))
        got=$(__brew_partial "$cache" "$since")
        rate=0
        if [[ -n $got ]]; then
          bytes=$got
          if ((first_at == 0)); then first=$bytes first_at=$(ui_now); fi
          if (($(ui_now) - first_at > 500000)); then
            rate=$(((bytes - first) * 1000000 / ($(ui_now) - first_at)))
          fi
        else
          # Downloaded, or never downloading: either way what is left is the install.
          got=0
        fi
        ui_progress "$pkg" "$got" "$total" "$rate" $(($(ui_now) - began)) "$tick"
      elif ((live == 0)); then
        idle=$((idle + beat))
        dim "no output for $(ui_elapsed "$idle") -- still running"
      fi
      continue
    fi
    idle=0
    if ((status != 0)) && [[ -z $line ]]; then break; fi

    case $line in
      'Using '*) using=$((using + 1)) ;;
      'Installing '*' has failed!'* | 'Failed to install '*': '*)
        name=${line#Installing }
        name=${name#Failed to install }
        name=${name%%[ :]*}
        if ! grep -qxF "$name" <<<"$failed"; then
          failed+=$name$'\n'
          fail packages "$(__brew_kind "$file" "$name") $name did not install"
        fi
        if [[ $line == 'Failed to install '* ]]; then __ui_quoted "${line#*: }"; fi
        # The out-of-band form can name another package, or this one by its full tap name.
        if [[ $line == 'Installing '* || ${name##*/} == "${pkg##*/}" ]]; then pkg=''; fi
        ;;
      'Installing '*)
        __brew_finish
        pkg=${line#Installing }
        pkg=${pkg%% *}
        if grep -qxF "$pkg" <<<"$failed"; then
          pkg=''
          line=''
          continue
        fi
        kind=$(__brew_kind "$file" "$pkg")
        info install "$kind $pkg"
        since=$(date +%s) began=$(ui_now) total=0 bytes=0 first=0 first_at=0 tick=0
        if ((live)) && [[ $kind == cask ]]; then total=$(__brew_cask_size "$pkg"); fi
        ((live == 0)) || ui_progress "$pkg" 0 "$total" 0 0 0
        ;;
      *'brew bundle'*' complete!'* | 'Homebrew Bundle complete!'*) ;;
      *) __ui_quoted "$line" ;;
    esac
    line=''
    ((status == 0)) || break
  done
  __brew_finish
  exec {fd}<&-
  status=0
  wait "$pid" || status=$?
  ((status == 0)) || return 1

  if ((installed == 0)); then
    ((using > 0)) || using=$named
    ok packages "$(ui_count "$using" package)"
  fi
  return 0
}

brew_check() {
  local file=$1
  local label=${2:-$(basename "$(dirname "$file")")}
  local missing status=0

  [[ -f $file ]] || return 0
  if ! brew_load; then
    fail packages "Homebrew is not installed -- cannot check $label"
    return 1
  fi

  missing=$(brew_missing "$file") || status=$?
  case $status in
    0) ok packages 'all installed' ;;
    1) while IFS= read -r line; do
      fail packages "$line is not installed -- run: dot apply"
    done <<<"$missing" ;;
    2) warn packages 'could not be checked -- brew bundle check did not answer' ;;
  esac
}

brew_unmanaged() {
  command -v brew >/dev/null 2>&1 || return 2

  # Two lists, never one: `brew "docker"` must not vouch for a hand-installed
  # `cask "docker"`.
  local files named_brew named_cask formulae casks out
  files=$(cat "$DOT_ROOT/core/Brewfile" "$DOT_ROOT"/modules/*/Brewfile 2>/dev/null)
  named_brew=$(sed -n -E 's/^brew "([^"]+)".*/\1/p' <<<"$files" | LC_ALL=C sort -u)
  named_cask=$(sed -n -E 's/^cask "([^"]*\/)?([^"]+)".*/\2/p' <<<"$files" | LC_ALL=C sort -u)

  [[ -n $named_brew || -n $named_cask ]] || return 2

  formulae=$(HOMEBREW_NO_AUTO_UPDATE=1 brew leaves --installed-on-request 2>/dev/null) || return 2
  casks=$(HOMEBREW_NO_AUTO_UPDATE=1 brew list --cask 2>/dev/null) || return 2

  out=$(
    # brew leaves prints a tap formula in full, so only a core one is matched by its bare name.
    awk 'NR == FNR { named[$0]; n = split($0, a, "/"); base[a[n]]; next }
      !NF { next }
      index($0, "/") { if (!($0 in named)) print "Formula", $0; next }
      !($0 in base) { print "Formula", $0 }' \
      <(printf '%s\n' "$named_brew") <(LC_ALL=C sort -u <<<"$formulae")
    comm -23 <(LC_ALL=C sort -u <<<"$casks") <(printf '%s\n' "$named_cask") |
      awk 'NF {print "Cask", $0}'
  )

  [[ -n $out ]] || return 0
  printf '%s\n' "$out"
  return 1
}
