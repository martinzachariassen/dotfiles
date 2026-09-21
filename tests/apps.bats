#!/usr/bin/env bats
#
# modules/apps/doctor.sh. The module has no apply.sh and no home/ -- a cask is
# the whole installation -- so the one thing to test is the one thing it says:
# an app that is on disk and has never been opened.
#
# /Applications is an input (DOT_APPS_DIR), because the branches that matter
# are "installed" and "not installed" and the machine running the tests has
# exactly one of them.

load helper

setup() {
  setup_sandbox
  DOCTOR="$DOT_ROOT/modules/apps/doctor.sh"
  TSV="$DOT_ROOT/modules/apps/data/launch.tsv"
  APPS="$DOT_TMP/Applications"
  mkdir -p "$APPS" "$HOME/Library/Preferences"
}

teardown() { teardown_sandbox; }

doctor() {
  run env HOME="$HOME" DOT_ROOT="$DOT_ROOT" DOT_APPS_DIR="$APPS" \
    "$BASH" "$DOCTOR"
}

# rows -- the data rows of the table. The same expression doctor.sh walks; a
# test that re-derives it is not a second copy of the DATA.
rows() { grep -v '^[[:space:]]*\(#\|$\)' "$TSV"; }

# installed APP -- a bundle where the hook looks. A directory, because that is
# what an .app is and what the hook tests for.
installed() { mkdir -p "$APPS/$1.app/Contents"; }

# opened DOMAIN -- the preferences file macOS writes on first launch.
opened() { : >"$HOME/Library/Preferences/$1.plist"; }

# first_row -- app, cask and domain of the first listed app, so no test has to
# name one. A constant here would break the day the table is reordered.
first_row() { rows | head -1; }

@test "an app that was never opened is a warning naming what it costs" {
  local app domain
  IFS=$'\t' read -r app _ domain _ < <(first_row)
  installed "$app"

  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"never opened"* ]]
  [[ $output == *"open -a $app"* ]]
}

@test "an app that was opened once is green, and stays green" {
  # First launch, not "running now": quitting Stats for an afternoon must not
  # turn the line yellow, and macOS never takes the domain back.
  local app domain
  IFS=$'\t' read -r app _ domain _ < <(first_row)
  installed "$app"
  opened "$domain"

  doctor
  [ "$status" -eq 0 ]
  says "$app" 'opened at least once'
}

@test "an app that is not installed says nothing at all" {
  # The escape hatch. Dropping the cask from Brewfile is how you decline an
  # app, and brew_missing already reports one that was dropped by accident --
  # this hook warning about it too would be a second, louder copy.
  doctor
  [ "$status" -eq 0 ]
  [[ $output != *"never opened"* ]]
}

@test "every listed app is reported, not a sample" {
  # The table is the specification. A hook that looked at two of three would
  # leave the third invisible with nothing on screen to say so.
  local app
  while IFS=$'\t' read -r app _; do installed "$app"; done < <(rows)

  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]

  while IFS=$'\t' read -r app _; do
    [[ $output == *"$app"* ]] || {
      echo "$app is in the table and not in the output"
      return 1
    }
  done < <(rows)
}

@test "the hook writes nothing" {
  # Read-only, like every doctor. The preferences file it tests for is macOS's
  # to create; a hook that touched it would report every machine as healthy
  # from the second run onwards.
  local app before after
  IFS=$'\t' read -r app _ < <(first_row)
  installed "$app"

  before=$(home_snapshot)
  doctor
  after=$(home_snapshot)
  [ "$before" = "$after" ]
}

@test "column 4 finishes the sentence doctor.sh starts" {
  # The warning is "... never opened -- no $lost", so a column holding its own
  # article reads "no the launcher". Two files own half a sentence each, and
  # only one of them can own the grammar; this is where that is decided.
  local app lost
  while IFS=$'\t' read -r app _ _ lost; do
    [[ $lost != the\ * && $lost != a\ * && $lost != an\ * ]] || {
      echo "$app: column 4 starts with an article, and \"no $lost\" is the result"
      return 1
    }
  done < <(rows)
}

@test "the table has four columns on every row" {
  # Column 4 is read into the warning text. A row missing it warns about an
  # app losing nothing, which reads as a bug in the app rather than the table.
  local line
  while IFS= read -r line; do
    [ "$(awk -F'\t' '{print NF}' <<<"$line")" -eq 4 ] || {
      echo "not four columns: $line"
      return 1
    }
  done < <(rows)
}
