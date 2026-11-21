#!/usr/bin/env bats

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

rows() { grep -v '^[[:space:]]*\(#\|$\)' "$TSV"; }

installed() { mkdir -p "$APPS/$1.app/Contents"; }

opened() { : >"$HOME/Library/Preferences/$1.plist"; }

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
  local app domain
  IFS=$'\t' read -r app _ domain _ < <(first_row)
  installed "$app"
  opened "$domain"

  doctor
  [ "$status" -eq 0 ]
  says "$app" 'opened at least once'
}

@test "an app that is not installed says nothing at all" {
  doctor
  [ "$status" -eq 0 ]
  [[ $output != *"never opened"* ]]
}

@test "every listed app is reported, not a sample" {
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
  local app before after
  IFS=$'\t' read -r app _ < <(first_row)
  installed "$app"

  before=$(home_snapshot)
  doctor
  after=$(home_snapshot)
  [ "$before" = "$after" ]
}

@test "column 4 finishes the sentence doctor.sh starts" {
  local app lost
  while IFS=$'\t' read -r app _ _ lost; do
    [[ $lost != the\ * && $lost != a\ * && $lost != an\ * ]] || {
      echo "$app: column 4 starts with an article, and \"no $lost\" is the result"
      return 1
    }
  done < <(rows)
}

@test "the table has four columns on every row" {
  local line
  while IFS= read -r line; do
    [ "$(awk -F'\t' '{print NF}' <<<"$line")" -eq 4 ] || {
      echo "not four columns: $line"
      return 1
    }
  done < <(rows)
}
