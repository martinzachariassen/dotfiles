#!/usr/bin/env bats
#
# modules/macos-defaults/apply.sh. `defaults` is shadowed on PATH: it talks to
# cfprefsd, which ignores $HOME, so the real one would rewrite the developer's
# settings. The stub records every call and doubles as the assertion.

load helper

setup() {
  setup_sandbox

  BIN="$DOT_TMP/bin"
  CALLS="$DOT_TMP/defaults-calls"
  TSV="$DOT_ROOT/modules/macos-defaults/data/defaults.tsv"
  mkdir -p "$BIN"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"%s"\n' "$CALLS" >"$BIN/defaults"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$BIN/killall"
  chmod +x "$BIN/defaults" "$BIN/killall"
}

teardown() { teardown_sandbox; }

# with_settings BODY -- a config whose [settings.macos-defaults] table is BODY.
with_settings() {
  printf 'schema = 1\n\n[modules]\nenabled = ["macos-defaults"]\n\n[settings.macos-defaults]\n%s\n' \
    "$1" >"$DOT_CONFIG"
}

apply() {
  run env PATH="$BIN:$PATH" DOT_ROOT="$DOT_ROOT" HOME="$HOME" \
    DOT_CONFIG="$DOT_CONFIG" DOT_STATE="$DOT_STATE" DOT_DRY_RUN="${1:-0}" \
    "$BASH" "$DOT_ROOT/modules/macos-defaults/apply.sh"
}

doctor() {
  run env PATH="$BIN:$PATH" DOT_ROOT="$DOT_ROOT" HOME="$HOME" \
    DOT_CONFIG="$DOT_CONFIG" DOT_STATE="$DOT_STATE" DOT_DRY_RUN=0 \
    "$BASH" "$DOT_ROOT/modules/macos-defaults/doctor.sh"
}

remove() {
  run env PATH="$BIN:$PATH" DOT_ROOT="$DOT_ROOT" HOME="$HOME" \
    DOT_CONFIG="$DOT_CONFIG" DOT_STATE="$DOT_STATE" DOT_DRY_RUN="${1:-0}" \
    "$BASH" "$DOT_ROOT/modules/macos-defaults/remove.sh"
}

# rows -- the data rows of the table, comments and blanks dropped. The same
# expression remove.sh uses; a test that re-derives it is not a second copy of
# the DATA, which is the thing that must not be duplicated.
rows() { grep -v '^[[:space:]]*\(#\|$\)' "$TSV"; }

# A `defaults` that remembers, so apply.sh and doctor.sh can be pointed at one
# machine. cfprefsd stores -bool as 1/0 and `read` prints it back that way --
# the exact translation doctor.sh has to get right.
with_store() {
  export DEFAULTS_STORE="$DOT_TMP/defaults-store"
  : >"$DEFAULTS_STORE"
  cat >"$BIN/defaults" <<'STUB'
#!/usr/bin/env bash
case $1 in
  write)
    value=$5
    case "$4:$5" in
      -bool:true) value=1 ;;
      -bool:false) value=0 ;;
    esac
    printf '%s %s\t%s\n' "$2" "$3" "$value" >>"$DEFAULTS_STORE"
    ;;
  read) awk -F'\t' -v k="$2 $3" '$1 == k { v = $2 } END { if (v == "") exit 1; print v }' "$DEFAULTS_STORE" ;;
esac
STUB
  chmod +x "$BIN/defaults"
}

wrote() { grep -qF "$1" "$CALLS"; }

# --- dock_tilesize -------------------------------------------------------------

@test "tilesize: a number is passed through" {
  with_settings 'dock_tilesize = 64'
  apply
  [ "$status" -eq 0 ] # the logout reminder is a note, not a warning
  wrote 'com.apple.dock tilesize -int 64'
}

@test "tilesize: garbage is refused instead of silently becoming 0" {
  # `defaults write ... -int big` exits 0 and stores 0: a Dock with no icons.
  with_settings 'dock_tilesize = "big"'
  apply
  [ "$status" -ne 0 ]
  [[ $output == *"dock_tilesize"* ]]
  # Refusing must mean the old value survives.
  run grep -c 'tilesize' "$CALLS"
  [ "$output" = "0" ]
}

@test "tilesize: 0 is refused as well" {
  with_settings 'dock_tilesize = 0'
  apply
  [ "$status" -ne 0 ]
  [[ $output == *"dock_tilesize"* ]]
}

@test "tilesize: one bad field does not cost you the rest of the module" {
  with_settings 'dock_tilesize = "big"'
  apply
  [ "$status" -ne 0 ]
  wrote 'com.apple.finder ShowPathbar -bool true'
  wrote 'NSGlobalDomain KeyRepeat -int 2'
}

# --- screenshot_dir ------------------------------------------------------------

@test "screenshots: a relative path is taken from \$HOME" {
  with_settings 'screenshot_dir = "Pictures/Shots"'
  apply
  [ "$status" -eq 0 ] # the logout reminder is a note, not a warning
  wrote "com.apple.screencapture location -string $HOME/Pictures/Shots"
  [ -d "$HOME/Pictures/Shots" ]
}

@test "screenshots: an absolute path is used as given, not nested under \$HOME" {
  with_settings "screenshot_dir = \"$DOT_TMP/shots\""
  apply
  [ "$status" -eq 0 ] # the logout reminder is a note, not a warning
  wrote "com.apple.screencapture location -string $DOT_TMP/shots"
  [ ! -d "$HOME$DOT_TMP" ]
}

@test "screenshots: a leading ~ is expanded, not taken literally" {
  # A tilde in a TOML string is just a character.
  with_settings 'screenshot_dir = "~/Shots"'
  apply
  [ "$status" -eq 0 ] # the logout reminder is a note, not a warning
  wrote "com.apple.screencapture location -string $HOME/Shots"
  [ ! -e "$HOME/~" ]
}

@test "screenshots: the default lands in Pictures/Screenshots" {
  with_settings '# nothing set'
  apply
  [ "$status" -eq 0 ] # the logout reminder is a note, not a warning
  wrote "com.apple.screencapture location -string $HOME/Pictures/Screenshots"
}

# --- dry run --------------------------------------------------------------------

@test "apply: the logout note is a note, and both runs close on it" {
  # As a `warn` it exited DOT_STATUS_WARN on every run, so `dot apply` could
  # never reach "Done" on a machine with this module enabled -- a summary that
  # is always yellow says as little as one that is always green. The dry run
  # stopped before it, so a preview and a real run closed on different words.
  # One string in apply.sh is what keeps the two from drifting apart again.
  with_settings '# nothing set'
  apply 1
  [ "$status" -eq 0 ]
  [[ $output == *"log out and back in"* ]]

  apply
  [ "$status" -eq 0 ]
  [[ $output == *"log out and back in"* ]]
  [ "$(grep -c 'log out and back in' "$DOT_ROOT/modules/macos-defaults/apply.sh")" -eq 1 ]
}

@test "dry run: describes the writes and makes none" {
  with_settings 'dock_tilesize = 64'
  local before
  before=$(home_snapshot)

  apply 1
  [ "$status" -eq 0 ]
  says defaults "write the Dock, Finder and keyboard keys, and restart those apps"
  [ ! -f "$CALLS" ]
  [ "$(home_snapshot)" = "$before" ]
}

# --- data/defaults.tsv ---------------------------------------------------------

@test "table: every row reaches defaults write, with its own type" {
  # The file is the module's only statement of what it changes. A row that is
  # read but not written would be a promise doctor.sh then reports as drift.
  with_settings '# nothing set'
  apply
  [ "$status" -eq 0 ] # the logout reminder is a note, not a warning

  local domain key type value
  while IFS=$'\t' read -r domain key type value _; do
    wrote "$domain $key -$type $value" || {
      echo "not written: $domain $key -$type $value"
      return 1
    }
  done < <(rows)
}

@test "table: the type column is one defaults understands" {
  # `defaults write x y -bogus 1` exits 1 and changes nothing, but apply.sh
  # writes 25 keys and would carry on past it.
  local type bad=()
  while IFS=$'\t' read -r _ _ type _ _; do
    case $type in
      bool | int | float | string) ;;
      *) bad+=("$type") ;;
    esac
  done < <(rows)
  [ ${#bad[@]} -eq 0 ] || {
    printf 'unknown defaults type: %s\n' "${bad[@]}"
    return 1
  }
}

# --- doctor.sh -----------------------------------------------------------------

@test "doctor: a machine apply.sh just wrote to has no drift" {
  # The round trip is what the shared file buys: apply writes -bool true,
  # `defaults read` says 1, and doctor has to call that a match.
  with_store
  with_settings 'dock_tilesize = 64'
  apply
  doctor
  [ "$status" -eq 0 ]
  [[ $output == *"every managed key matches"* ]]
}

@test "doctor: a reverted key is named, including one no sample would cover" {
  # KeyRepeat was not among the six keys the old doctor checked. Full coverage
  # of the table is the point of reading it instead of restating it.
  with_store
  with_settings '# nothing set'
  apply
  printf 'NSGlobalDomain KeyRepeat\t99\n' >>"$DEFAULTS_STORE"

  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"NSGlobalDomain KeyRepeat is 99, expected 2"* ]]
}

@test "doctor: a key nothing ever wrote reads as unset, not as a match" {
  with_store # empty: no apply
  with_settings '# nothing set'
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"<unset>"* ]]
}

@test "doctor: dock_autohide is compared as the setting asks, not as written" {
  with_store
  with_settings 'dock_autohide = false'
  apply
  doctor
  [ "$status" -eq 0 ]
}

@test "doctor: writes nothing, not even a preferences file" {
  with_store
  with_settings '# nothing set'
  local before
  before=$(home_snapshot)
  doctor
  [ "$(home_snapshot)" = "$before" ]
}

# --- remove.sh -----------------------------------------------------------------

@test "remove: warns about exactly the domains the table names" {
  # The list is the user's only record of an irreversible change, so it is cut
  # from the table rather than typed. Proving it covers every domain is what
  # stops apply.sh from gaining one this warning never mentions. apply first:
  # the warning is now conditional on the table actually being in force.
  with_store
  with_settings '# nothing set'
  apply
  remove
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  # As many listed lines as the table has domains, so neither a blank line nor
  # a repeat can slip in: both read as a change to something never touched.
  local want listed
  want=$(rows | cut -f1 | sort -u | wc -l | tr -d ' ')
  # A domain is the only thing here that is one bare token on its own line, so
  # counting those pins the list without pinning how far in ui.sh indents it.
  listed=$(grep -cE '^[[:space:]]+[^[:space:]]+$' <<<"$output" || true)
  [ "$listed" -eq "$want" ]

  local domain
  while IFS= read -r domain; do
    [[ $output == *"$domain"* ]] || {
      echo "remove.sh never named $domain"
      return 1
    }
  done < <(rows | cut -f1 | sort -u)
}

@test "remove: says nothing on a machine that never ran this module" {
  # uninstall.sh calls every module's remove.sh, enabled or not. With no row of
  # the table in force there is nothing irreversible to report, and the warning
  # would be a lie about a change that never happened -- the same silence
  # dev-cli/remove.sh keeps. An empty store: every `defaults read` misses.
  with_store
  with_settings '# nothing set'
  remove
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "remove: changes nothing under a dry run" {
  local before
  before=$(home_snapshot)
  remove 1
  [ "$(home_snapshot)" = "$before" ]
}

@test "remove: an unreadable table is refused, never warned about emptily" {
  # The warning IS the deliverable here -- apply.sh cannot be undone, so the
  # domain list is all the user gets. A missing table used to print the
  # "cannot be put back" line with nothing under it and still exit as a plain
  # warning: the exact lie remove.sh's header comment forbids.
  mkdir -p "$DOT_TMP/nodata"
  cp "$DOT_ROOT/modules/macos-defaults/remove.sh" "$DOT_TMP/nodata/"

  run env PATH="$BIN:$PATH" DOT_ROOT="$DOT_ROOT" HOME="$HOME" \
    DOT_CONFIG="$DOT_CONFIG" DOT_STATE="$DOT_STATE" DOT_DRY_RUN=0 \
    DOT_MODULE=macos-defaults DOT_MODULE_DIR="$DOT_TMP/nodata" \
    "$BASH" "$DOT_TMP/nodata/remove.sh"

  [ "$status" -ne 0 ]
  [ "$status" -ne "$DOT_STATUS_WARN" ]
  [[ $output == *"cannot read"* ]]
  [[ $output != *"cannot be put back"* ]]
}
