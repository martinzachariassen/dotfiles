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

  # The three checks doctor.sh makes that are not `defaults` keys at all. Each
  # reads real system state, so each is shadowed -- and shadowed to a HEALTHY
  # machine by default, so every other test in this file says only what it is
  # about. The tests that vary them vary one at a time.
  FW="$DOT_TMP/socketfilterfw"
  SUDO_LOCAL="$DOT_TMP/sudo_local"
  with_filevault 'FileVault is On.'
  with_firewall 'Firewall is enabled. (State = 1)'
  with_touch_id 'auth       sufficient     pam_tid.so'
}

# with_filevault TEXT / with_firewall TEXT -- a tool that answers TEXT. The
# answer goes in a file the stub cats, not into the generated script: these
# strings carry parentheses and quotes, and escaping them into a heredoc is a
# second thing to get wrong.
with_filevault() {
  printf '%s\n' "$1" >"$DOT_TMP/filevault-answer"
  printf '#!/usr/bin/env bash\ncat "%s"\n' "$DOT_TMP/filevault-answer" >"$BIN/fdesetup"
  chmod +x "$BIN/fdesetup"
}

with_firewall() {
  printf '%s\n' "$1" >"$DOT_TMP/firewall-answer"
  printf '#!/usr/bin/env bash\ncat "%s"\n' "$DOT_TMP/firewall-answer" >"$FW"
  chmod +x "$FW"
}

# with_touch_id LINE -- the contents of pam.d/sudo_local. An empty LINE means
# no file at all, which is what macOS actually ships.
with_touch_id() {
  if [[ -z $1 ]]; then
    rm -f "$SUDO_LOCAL"
  else
    printf '%s\n' "$1" >"$SUDO_LOCAL"
  fi
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
    DOT_SOCKETFILTERFW="$FW" DOT_SUDO_LOCAL="$SUDO_LOCAL" \
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
  # Answers that do not fit on one line: the store is key<TAB>value, and
  # LSHandlers is a plist array. A file per key rather than a second store, so
  # the stub stays one `case` and any key can be given either shape.
  export DEFAULTS_DIR="$DOT_TMP/defaults-answers"
  : >"$DEFAULTS_STORE"
  mkdir -p "$DEFAULTS_DIR"
  cat >"$BIN/defaults" <<'STUB'
#!/usr/bin/env bash
key_file() { printf '%s/%s' "$DEFAULTS_DIR" "$(printf '%s %s' "$1" "$2" | tr -c '[:alnum:]' '_')"; }
case $1 in
  write)
    value=$5
    case "$4:$5" in
      -bool:true) value=1 ;;
      -bool:false) value=0 ;;
    esac
    printf '%s %s\t%s\n' "$2" "$3" "$value" >>"$DEFAULTS_STORE"
    ;;
  read)
    f=$(key_file "$2" "$3")
    if [[ -f $f ]]; then cat "$f"; exit 0; fi
    awk -F'\t' -v k="$2 $3" '$1 == k { v = $2 } END { if (v == "") exit 1; print v }' "$DEFAULTS_STORE"
    ;;
esac
STUB
  chmod +x "$BIN/defaults"

  # A healthy machine by default, so every test that is about something else
  # says only that. The same rule setup() follows for FileVault and the
  # firewall -- these reads reach /Library/Preferences and the LaunchServices
  # database, neither of which a fake $HOME can hold.
  with_updates AutomaticCheckEnabled 1
  with_updates AutomaticDownload 1
  with_updates CriticalUpdateInstall 1
  with_updates ConfigDataInstall 1
  with_updates_domain /Library/Preferences/com.apple.commerce AutoUpdate 1
  # Written, not left out: all six keys ship ON, so the healthy machine for the
  # one the repo wants OFF is an explicit 0. Leaving it unwritten here would
  # make every test in this file carry that warning.
  with_updates AutomaticallyInstallMacOSUpdates 0
  with_browser com.google.chrome
}

# with_updates KEY VALUE -- one software update switch on the system domain.
with_updates() {
  with_updates_domain /Library/Preferences/com.apple.SoftwareUpdate "$1" "$2"
}

with_updates_domain() {
  printf '%s %s\t%s\n' "$1" "$2" "$3" >>"$DEFAULTS_STORE"
}

# without_updates KEY -- a key macOS never wrote, which is not the same as one
# written to 0 and is the whole point of the two tests that use it.
without_updates() {
  grep -v "^/Library/Preferences/com.apple.SoftwareUpdate $1	" \
    "$DEFAULTS_STORE" >"$DEFAULTS_STORE.new" || true
  mv "$DEFAULTS_STORE.new" "$DEFAULTS_STORE"
}

# with_browser BUNDLE -- the LaunchServices handler list as `defaults` prints
# it, BUNDLE handling https. The "-" inside LSHandlerPreferredVersions is not
# decoration: it sorts before LSHandlerRoleAll and is the thing doctor.sh's
# awk has to skip, so a stub without it would pass over the bug.
with_browser() {
  local f
  f="$DEFAULTS_DIR/$(printf '%s %s' com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers | tr -c '[:alnum:]' '_')"
  cat >"$f" <<EOF
(
        {
        LSHandlerPreferredVersions =         {
            LSHandlerRoleAll = "-";
        };
        LSHandlerRoleAll = "$1";
        LSHandlerURLScheme = https;
    }
)
EOF
}

# with_browser_after BUNDLE -- BUNDLE claiming a content type in an EARLIER
# array element, and the https element carrying no LSHandlerRoleAll of its own.
# A real LSHandlers list is a mix of both shapes, and an awk that carried its
# last-seen role across elements would answer https with BUNDLE.
with_browser_after() {
  local f
  f="$DEFAULTS_DIR/$(printf '%s %s' com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers | tr -c '[:alnum:]' '_')"
  cat >"$f" <<EOF
(
        {
        LSHandlerContentType = "public.html";
        LSHandlerRoleAll = "$1";
    },
        {
        LSHandlerRoleViewer = "com.apple.Safari";
        LSHandlerURLScheme = https;
    }
)
EOF
}

# with_no_browser -- a Mac nobody ever answered the "make default?" sheet on.
with_no_browser() {
  rm -f "$DEFAULTS_DIR/$(printf '%s %s' com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers | tr -c '[:alnum:]' '_')"
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

@test "apply: a real run says what it did, in the same column as everything else" {
  # The hook runs for real here, against the `defaults` stub. What was never
  # checked is the line it closes on: a module whose whole job is invisible
  # changes has nothing else to show for itself.
  with_settings 'dock_tilesize = 64'

  apply
  [ "$status" -eq 0 ]
  says defaults 'written'
  [ -f "$CALLS" ]
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

# --- what the module can only report -----------------------------------------
#
# FileVault, the firewall and Touch ID for sudo are not `defaults` keys: each
# needs root to change and two need a GUI, so apply.sh cannot write them and
# data/defaults.tsv must not list them. doctor.sh reports them anyway, because
# this is the module for macOS system state and nothing else in the repo would
# ever look at a machine with the firewall off.

@test "system: FileVault on is one green line" {
  with_settings '# nothing set'
  with_store
  apply
  doctor
  [ "$status" -eq 0 ]
  says filevault 'on'
}

@test "system: FileVault off is a warning that says what is at stake" {
  # The only one of the three that cannot be fixed after the laptop is gone.
  with_settings '# nothing set'
  with_store
  apply
  with_filevault 'FileVault is Off.'
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"FileVault"* ]] || [[ $output == *"filevault"* ]]
  [[ $output == *"Privacy & Security"* ]]
}

@test "system: an fdesetup that answers nothing is never read as healthy" {
  # A question that could not be asked is not a green answer -- the same
  # three-state rule brew_missing exists to keep.
  with_settings '# nothing set'
  with_store
  apply
  with_filevault ''
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"could not be read"* ]]
}

@test "system: the firewall blocking everything still counts as on" {
  # State 2 is "on, and block all incoming". Matching only 1 would nag the
  # most locked-down machine there is.
  with_settings '# nothing set'
  with_store
  apply
  with_firewall 'Firewall is enabled. (State = 2)'
  doctor
  [ "$status" -eq 0 ]
  says firewall 'on'
}

@test "system: the firewall off names the command that turns it on" {
  with_settings '# nothing set'
  with_store
  apply
  with_firewall 'Firewall is disabled. (State = 0)'
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"--setglobalstate on"* ]]
}

@test "system: no socketfilterfw at all says so, rather than nothing" {
  with_settings '# nothing set'
  with_store
  apply
  rm -f "$FW"
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"cannot be checked"* ]]
}

@test "system: Touch ID for sudo is the uncommented line, not the file" {
  # macOS ships sudo_local.template with pam_tid commented out. Copying it and
  # changing nothing is the most likely half-done state there is, and testing
  # for the file alone would call it finished.
  with_settings '# nothing set'
  with_store
  apply
  with_touch_id '#auth       sufficient     pam_tid.so'
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"does not unlock sudo"* ]]
}

@test "system: no sudo_local at all is the same answer" {
  with_settings '# nothing set'
  with_store
  apply
  with_touch_id ''
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"does not unlock sudo"* ]]
}

@test "system: touch_id_sudo = false says nothing at all about it" {
  # A taste, not a baseline. Without the setting a machine that does not want
  # it stays yellow forever, which is the bug a permanently green line is.
  with_settings 'touch_id_sudo = false'
  with_store
  apply
  with_touch_id ''
  doctor
  [ "$status" -eq 0 ]
  [[ $output != *"sudo"* ]]
}

@test "system: none of the three is in the table apply.sh writes" {
  # data/defaults.tsv is the list of what this module WRITES, and remove.sh
  # derives the domains it warns about from column 1. A row here would make
  # apply.sh run `defaults write` against a setting that is not one.
  ! grep -qiE 'filevault|socketfilterfw|pam_tid|com\.apple\.alf' "$TSV"
}

# --- software update ----------------------------------------------------------
#
# Five switches macOS does not treat as one, split here the same way: four that
# have a right answer, and the one that installs a whole new major version.
# This machine went from macOS 26 to 27 on its own and the only way anyone
# would have known is that the check exists.

@test "updates: every switch on is one green line" {
  with_settings '# nothing set'
  with_store
  apply
  doctor
  [ "$status" -eq 0 ]
  says updates 'checked, downloaded and security-patched automatically'
}

@test "updates: a switch turned off is named, one line each" {
  with_settings '# nothing set'
  with_store
  with_updates CriticalUpdateInstall 0
  apply
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"security responses"* ]]
  [[ $output == *"Software Update"* ]]
}

@test "updates: a key macOS never wrote is not read as off" {
  # The trap this check had to avoid. All five ship ON, so a Mac whose owner
  # never opened the pane has no key at all -- and calling that "off" sends
  # you to a checkbox that is already ticked.
  with_settings '# nothing set'
  with_store
  # A store holding nothing but the browser answer: no update key exists. The
  # sixth is written back, because the same rule points the other way for it
  # and the test below is the one about that.
  : >"$DEFAULTS_STORE"
  with_updates AutomaticallyInstallMacOSUpdates 0
  apply
  doctor
  [ "$status" -eq 0 ]
  says updates 'checked, downloaded and security-patched automatically'
}

@test "updates: an unwritten version-bump key is the fresh Mac, not a quiet one" {
  # The same rule as the four above, pointing the other way: this key ships ON
  # too, so a Mac whose owner never opened the pane IS set to install whole
  # versions unasked. Reading the missing key as "off" made the default answer
  # green on exactly the machine the row exists for -- a fresh install, which
  # is the machine this whole check was written for.
  with_settings '# nothing set'
  with_store
  without_updates AutomaticallyInstallMacOSUpdates
  apply
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"including major ones"* ]]
  # And only that: the four are still green beside it.
  says updates 'checked, downloaded and security-patched automatically'
}

@test "updates: macos_auto_update = true is green on a Mac that never wrote it" {
  # The mirror of the test above, and what keeps the two branches from
  # disagreeing about what an unwritten key means: ON either way. Getting this
  # pair to disagree is what made the default answer green on a fresh install.
  with_settings 'macos_auto_update = true'
  with_store
  without_updates AutomaticallyInstallMacOSUpdates
  apply
  doctor
  [ "$status" -eq 0 ]
  says updates 'macOS updates install automatically'
}

@test "updates: macOS installing its own versions is a warning by default" {
  # The expensive failure, and the reason the default is off: a major version
  # that arrives on its own cannot be undone without erasing the disk.
  with_settings '# nothing set'
  with_store
  with_updates AutomaticallyInstallMacOSUpdates 1
  apply
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"including major ones"* ]]
  [[ $output == *"AutomaticallyInstallMacOSUpdates -bool false"* ]]
}

@test "updates: turning the version bump off leaves the other four alone" {
  # The whole point of splitting them. The fix named above must not be a fix
  # that costs you security patches, so the four stay green beside it.
  with_settings '# nothing set'
  with_store
  with_updates AutomaticallyInstallMacOSUpdates 1
  apply
  doctor
  says updates 'checked, downloaded and security-patched automatically'
}

@test "updates: macos_auto_update = true wants the opposite, and says so" {
  # A setting is only a setting if both answers are checked. With it on, a
  # machine NOT installing macOS updates is the one that has drifted.
  with_settings 'macos_auto_update = true'
  with_store
  with_updates AutomaticallyInstallMacOSUpdates 0
  apply
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"macos_auto_update"* ]]
}

@test "updates: macos_auto_update = true is green when macOS does install them" {
  with_settings 'macos_auto_update = true'
  with_store
  with_updates AutomaticallyInstallMacOSUpdates 1
  apply
  doctor
  [ "$status" -eq 0 ]
  says updates 'macOS updates install automatically'
}

# --- default browser ----------------------------------------------------------
#
# Installing a browser and being sent to it are two things, and `apps` only
# does the first. No script may do the second: the confirmation sheet is the
# whole point of it.

@test "browser: the browser the setting names passes" {
  with_settings '# nothing set'
  with_store
  apply
  doctor
  [ "$status" -eq 0 ]
  says browser 'com.google.chrome opens https links'
}

@test "browser: a Mac nobody answered the sheet on still opens Safari" {
  with_settings '# nothing set'
  with_store
  with_no_browser
  apply
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"Safari"* ]]
}

@test "browser: a different browser is named, not just called wrong" {
  # Both halves, because "not chrome" does not tell you what you are looking
  # at -- an installer you forgot running is a different problem to a sheet
  # you never answered.
  with_settings '# nothing set'
  with_store
  with_browser com.brave.browser
  apply
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"com.brave.browser"* ]]
  [[ $output == *"com.google.chrome"* ]]
}

@test "browser: the placeholder inside LSHandlerPreferredVersions is skipped" {
  # `defaults` prints dict keys alphabetically, so that nested LSHandlerRoleAll
  # = "-" arrives BEFORE the real one. An awk that took the last value seen
  # without the guard would report every machine as handing https to "-".
  with_settings '# nothing set'
  with_store
  apply
  doctor
  [[ $output != *'"-"'* ]]
  [[ $output != *'browser - '* ]]
}

@test "browser: a role from an earlier entry is not the https answer" {
  # LSHandlers is an array, and the handler for https is whatever THAT element
  # says. An awk keeping its last-seen LSHandlerRoleAll across elements would
  # report the content-type entry above it -- a confident wrong name, which
  # reads as a browser you forgot installing rather than as a sheet you never
  # answered. Cleared at each bare `{`, which a nested `KEY = {` is not.
  with_settings '# nothing set'
  with_store
  with_browser_after com.google.chrome
  apply
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"still open in Safari"* ]]
}

@test "browser: an empty setting says nothing at all" {
  # The escape hatch, and the same shape as touch_id_sudo: a machine that
  # wants Safari must not stay yellow forever.
  with_settings 'browser = ""'
  with_store
  with_no_browser
  apply
  doctor
  [ "$status" -eq 0 ]
  [[ $output != *"browser"* ]]
}
