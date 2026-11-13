#!/usr/bin/env bats

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

  FW="$DOT_TMP/socketfilterfw"

  SU_DOMAIN="$DOT_TMP/SoftwareUpdate"
  COMMERCE_DOMAIN="$DOT_TMP/commerce"
  with_filevault 'FileVault is On.'
  with_firewall 'Firewall is enabled. (State = 1)'
}

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

teardown() { teardown_sandbox; }

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
    DOT_SOCKETFILTERFW="$FW" \
    DOT_SOFTWAREUPDATE_PREFS="$SU_DOMAIN" DOT_COMMERCE_PREFS="$COMMERCE_DOMAIN" \
    "$BASH" "$DOT_ROOT/modules/macos-defaults/doctor.sh"
}

remove() {
  run env PATH="$BIN:$PATH" DOT_ROOT="$DOT_ROOT" HOME="$HOME" \
    DOT_CONFIG="$DOT_CONFIG" DOT_STATE="$DOT_STATE" DOT_DRY_RUN="${1:-0}" \
    "$BASH" "$DOT_ROOT/modules/macos-defaults/remove.sh"
}

rows() { grep -v '^[[:space:]]*\(#\|$\)' "$TSV"; }

with_store() {
  export DEFAULTS_STORE="$DOT_TMP/defaults-store"
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
    # A read with no key is a read of the whole DOMAIN, which doctor.sh makes
    # to tell "this key was never written" from "this domain did not answer".
    # It succeeds when the store knows the domain at all, in either shape.
    if [[ -z $3 ]]; then
      p=$(printf '%s' "$2" | tr -c '[:alnum:]' '_')
      compgen -G "$DEFAULTS_DIR/${p}_*" >/dev/null && exit 0
      awk -F'\t' -v d="$2 " 'index($1, d) == 1 { f = 1 } END { exit !f }' "$DEFAULTS_STORE"
      exit
    fi
    awk -F'\t' -v k="$2 $3" '$1 == k { v = $2 } END { if (v == "") exit 1; print v }' "$DEFAULTS_STORE"
    ;;
esac
STUB
  chmod +x "$BIN/defaults"

  with_updates AutomaticCheckEnabled 1
  with_updates AutomaticDownload 1
  with_updates CriticalUpdateInstall 1
  with_updates ConfigDataInstall 1
  with_updates_domain "$COMMERCE_DOMAIN" AutoUpdate 1
  with_updates AutomaticallyInstallMacOSUpdates 0
  with_browser com.google.chrome
}

with_updates() {
  with_updates_domain "$SU_DOMAIN" "$1" "$2"
}

with_updates_domain() {
  printf '%s %s\t%s\n' "$1" "$2" "$3" >>"$DEFAULTS_STORE"
}

without_updates() {
  grep -v "^$SU_DOMAIN $1	" \
    "$DEFAULTS_STORE" >"$DEFAULTS_STORE.new" || true
  mv "$DEFAULTS_STORE.new" "$DEFAULTS_STORE"
}

unreadable_domain() {
  grep -v "^$1 " "$DEFAULTS_STORE" >"$DEFAULTS_STORE.new" || true
  mv "$DEFAULTS_STORE.new" "$DEFAULTS_STORE"
  : >"$1.plist"
}

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

with_no_browser() {
  rm -f "$DEFAULTS_DIR/$(printf '%s %s' com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers | tr -c '[:alnum:]' '_')"
}

wrote() { grep -qF "$1" "$CALLS"; }

@test "tilesize: a number is passed through" {
  with_settings 'dock_tilesize = 64'
  apply
  [ "$status" -eq 0 ]
  wrote 'com.apple.dock tilesize -int 64'
}

@test "tilesize: garbage is refused instead of silently becoming 0" {
  with_settings 'dock_tilesize = "big"'
  apply
  [ "$status" -ne 0 ]
  [[ $output == *"dock_tilesize"* ]]
  run grep -c 'tilesize' "$CALLS"
  [ "$output" = "0" ]
}

@test "tilesize: a refused field is not followed by a claim that all was written" {
  with_settings 'dock_tilesize = "big"'
  apply
  [ "$status" -ne 0 ]
  [[ $output != *written* ]]
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

@test "screenshots: a relative path is taken from \$HOME" {
  with_settings 'screenshot_dir = "Pictures/Shots"'
  apply
  [ "$status" -eq 0 ]
  wrote "com.apple.screencapture location -string $HOME/Pictures/Shots"
  [ -d "$HOME/Pictures/Shots" ]
}

@test "screenshots: an absolute path is used as given, not nested under \$HOME" {
  with_settings "screenshot_dir = \"$DOT_TMP/shots\""
  apply
  [ "$status" -eq 0 ]
  wrote "com.apple.screencapture location -string $DOT_TMP/shots"
  [ ! -d "$HOME$DOT_TMP" ]
}

@test "screenshots: a leading ~ is expanded, not taken literally" {
  with_settings 'screenshot_dir = "~/Shots"'
  apply
  [ "$status" -eq 0 ]
  wrote "com.apple.screencapture location -string $HOME/Shots"
  [ ! -e "$HOME/~" ]
}

@test "screenshots: the default lands in Pictures/Screenshots" {
  with_settings '# nothing set'
  apply
  [ "$status" -eq 0 ]
  wrote "com.apple.screencapture location -string $HOME/Pictures/Screenshots"
}

@test "apply: the logout note is a note, and both runs close on it" {
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
  says defaults "write the Dock, Finder, input and screenshot keys, and restart those apps"
  [ ! -f "$CALLS" ]
  [ "$(home_snapshot)" = "$before" ]
}

@test "table: every row reaches defaults write, with its own type" {
  with_settings '# nothing set'
  apply
  [ "$status" -eq 0 ]

  local domain key type value
  while IFS=$'\t' read -r domain key type value _; do
    wrote "$domain $key -$type $value" || {
      echo "not written: $domain $key -$type $value"
      return 1
    }
  done < <(rows)
}

@test "table: the type column is one defaults understands" {
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

@test "doctor: a machine apply.sh just wrote to has no drift" {
  with_store
  with_settings 'dock_tilesize = 64'
  apply
  doctor
  [ "$status" -eq 0 ]
  [[ $output == *"every managed key matches"* ]]
}

@test "doctor: a reverted key is named, including one no sample would cover" {
  with_store
  with_settings '# nothing set'
  apply
  printf 'NSGlobalDomain KeyRepeat\t99\n' >>"$DEFAULTS_STORE"

  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"NSGlobalDomain KeyRepeat is 99, expected 2"* ]]
}

@test "doctor: a key nothing ever wrote reads as unset, not as a match" {
  with_store
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

@test "remove: warns about exactly the domains the table names" {
  with_store
  with_settings '# nothing set'
  apply
  remove
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  local want listed
  want=$(rows | cut -f1 | sort -u | wc -l | tr -d ' ')
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

@test "system: FileVault on is one green line" {
  with_settings '# nothing set'
  with_store
  apply
  doctor
  [ "$status" -eq 0 ]
  says filevault 'on'
}

@test "system: FileVault off is a warning that says what is at stake" {
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
  with_settings '# nothing set'
  with_store
  apply
  with_filevault ''
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"could not be read"* ]]
}

@test "system: the firewall blocking everything still counts as on" {
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

@test "system: none of the two is in the table apply.sh writes" {
  ! grep -qiE 'filevault|socketfilterfw|com\.apple\.alf' "$TSV"
}

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
  with_settings '# nothing set'
  with_store
  : >"$DEFAULTS_STORE"
  with_updates AutomaticallyInstallMacOSUpdates 0
  apply
  doctor
  [ "$status" -eq 0 ]
  says updates 'checked, downloaded and security-patched automatically'
}

@test "updates: an unwritten version-bump key is the fresh Mac, not a quiet one" {
  with_settings '# nothing set'
  with_store
  without_updates AutomaticallyInstallMacOSUpdates
  apply
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"including major ones"* ]]
  says updates 'checked, downloaded and security-patched automatically'
}

@test "updates: macos_auto_update = true is green on a Mac that never wrote it" {
  with_settings 'macos_auto_update = true'
  with_store
  without_updates AutomaticallyInstallMacOSUpdates
  apply
  doctor
  [ "$status" -eq 0 ]
  says updates 'macOS updates install automatically'
}

@test "updates: macOS installing its own versions is a warning by default" {
  with_settings '# nothing set'
  with_store
  with_updates AutomaticallyInstallMacOSUpdates 1
  apply
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"including major ones"* ]]
  [[ $output == *"AutomaticallyInstallMacOSUpdates -bool false"* ]]
}

@test "updates: turning the version bump off leaves the other five alone" {
  with_settings '# nothing set'
  with_store
  with_updates AutomaticallyInstallMacOSUpdates 1
  apply
  doctor
  says updates 'checked, downloaded and security-patched automatically'
}

@test "updates: macos_auto_update = true wants the opposite, and says so" {
  with_settings 'macos_auto_update = true'
  with_store
  with_updates AutomaticallyInstallMacOSUpdates 0
  apply
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"macos_auto_update"* ]]
}

@test "updates: a domain that does not answer warns instead of passing" {
  with_settings '# nothing set'
  with_store
  unreadable_domain "$SU_DOMAIN"
  apply
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"could not be read"* ]]
  [[ $output != *"security-patched automatically"* ]]
}

@test "updates: one unreadable domain does not speak for the other" {
  with_settings '# nothing set'
  with_store
  unreadable_domain "$COMMERCE_DOMAIN"
  apply
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"could not be read"* ]]
  [[ $output == *"App Store apps"* ]]
}

@test "updates: an unreadable version-bump key is not read as on, or as off" {
  with_settings '# nothing set'
  with_store
  unreadable_domain "$SU_DOMAIN"
  apply
  doctor
  [[ $output == *"could not be read -- whether macOS installs new versions"* ]]
  [[ $output != *"including major ones"* ]]
  [[ $output != *"waits for you"* ]]
}

@test "updates: a domain that answers with no key at all is still the default" {
  with_settings '# nothing set'
  with_store
  without_updates AutomaticCheckEnabled
  apply
  doctor
  [ "$status" -eq 0 ]
  says updates 'checked, downloaded and security-patched automatically'
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
  with_settings '# nothing set'
  with_store
  apply
  doctor
  [[ $output != *'"-"'* ]]
  [[ $output != *'browser - '* ]]
}

@test "browser: a role from an earlier entry is not the https answer" {
  with_settings '# nothing set'
  with_store
  with_browser_after com.google.chrome
  apply
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"still open in Safari"* ]]
}

@test "browser: a LaunchServices database that does not answer says so" {
  with_settings '# nothing set'
  with_store
  with_no_browser
  mkdir -p "$HOME/Library/Preferences/com.apple.LaunchServices"
  : >"$HOME/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist"
  apply
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"could not be read"* ]]
  [[ $output != *"still open in Safari"* ]]
}

@test "browser: a Mac with no handler list at all is the fresh one, not a mute one" {
  with_settings '# nothing set'
  with_store
  with_no_browser
  apply
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"still open in Safari"* ]]
  [[ $output != *"could not be read"* ]]
}

@test "browser: an empty setting says nothing at all" {
  with_settings 'browser = ""'
  with_store
  with_no_browser
  apply
  doctor
  [ "$status" -eq 0 ]
  [[ $output != *"browser"* ]]
}
