#!/usr/bin/env bats
#
# Config reading, and the one generator. Several pin surprising dasel v3
# behaviour; a future dasel changing it shows up here.

load helper

setup() {
  setup_sandbox
  cat >"$DOT_CONFIG" <<'EOF'
schema = 1

[user]
name  = "Martin Zachariassen"
email = "m@example.com"

[modules]
enabled = ["git", "zsh"]

[settings.git]
signingkey = "ssh-ed25519 AAAA"

[settings.macos-defaults]
dock_autohide = false
dock_tilesize = 64
EOF
}
teardown() { teardown_sandbox; }

@test "get: reads a scalar without quotes" {
  run cfg_get 'user.name'
  [ "$output" = "Martin Zachariassen" ]
}

@test "get: falls back to the default for a missing key" {
  run cfg_get 'user.nickname' 'none'
  [ "$output" = "none" ]
}

@test "get: an absent config file yields the default, not an error" {
  rm "$DOT_CONFIG"
  run cfg_get 'user.name' 'fallback'
  [ "$status" -eq 0 ]
  [ "$output" = "fallback" ]
}

@test "get: a value containing a colon survives the YAML round trip" {
  # YAML would read `x: y` as a mapping, so dasel single-quotes it.
  printf 'note = "time: 10:30"\n' >"$DOT_CONFIG"
  run cfg_get 'note'
  [ "$output" = "time: 10:30" ]
}

@test "get: an empty string reads back as empty, not as two quote marks" {
  printf 'note = ""\n' >"$DOT_CONFIG"
  run cfg_get 'note' 'fallback'
  [ "$output" = "" ]
}

@test "list: reads an array one element per line" {
  run cfg_list 'modules.enabled'
  [ "${lines[0]}" = "git" ]
  [ "${lines[1]}" = "zsh" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "list: an empty array yields nothing" {
  printf 'x = []\n' >"$DOT_CONFIG"
  run cfg_list 'x'
  [ -z "$output" ]
}

@test "setting: reads a dashed module name via bracket syntax" {
  # dasel parses settings.macos-defaults.x as a subtraction.
  run module_setting macos-defaults dock_tilesize
  [ "$output" = "64" ]
}

@test "setting: bool is true only for the literal true" {
  run module_setting_bool macos-defaults dock_autohide true
  [ "$status" -eq 1 ]
  run module_setting_bool macos-defaults nothing_here true
  [ "$status" -eq 0 ]
}

@test "setting: undefined module setting returns the default" {
  run module_setting git nonexistent 'fallback'
  [ "$output" = "fallback" ]
}

# --- a config that does not parse whole --------------------------------------
# dasel stops at the first malformed line, keeps what it read, and exits 0.
# cfg_parse_problems asks taplo first and falls back to two heuristics, so both
# paths need exercising: the binary is named away the way DOT_BREW_BIN is, or
# the fallback is unreachable on any machine that has phase 1 installed.

without_taplo() { export DOT_TAPLO_BIN="$DOT_TMP/no-such-taplo"; }

@test "parse: dasel really does truncate silently -- rc 0, half a document" {
  # If a future dasel rejects this outright, cfg_parse_problems is dead weight.
  printf 'schema = 1\n[modules]\nenabled = [ "git" "zsh" ]\n' >"$DOT_CONFIG"
  run dasel -i toml -o yaml 'schema' <"$DOT_CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "parse: a clean config reports no problems" {
  run cfg_parse_problems
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "parse: a missing comma in enabled is caught, not waved through" {
  printf 'schema = 1\n[modules]\nenabled = [ "git" "zsh" ]\n\n[settings.git]\nsigningkey = "k"\n' \
    >"$DOT_CONFIG"

  without_taplo

  # Nothing else in the engine objects to this file.
  run modules_require_known
  [ "$status" -eq 0 ]
  run cfg_list 'modules.enabled'
  [ -z "$output" ]

  run cfg_parse_problems
  [ -n "$output" ]
  [[ $output == *settings* ]]
}

@test "parse: an empty enabled list is valid, not a parse failure" {
  # The `none` profile writes exactly this.
  rm "$DOT_CONFIG"
  config_generate "A" "a@b.c" ""

  run cfg_parse_problems
  [ -z "$output" ]
}

@test "parse: a [modules] table whose enabled key was eaten is caught" {
  # [modules] itself parsed and is in keys(); only the list below it was lost.
  printf 'schema = 1\n[modules]\nenabled = [ "git"\n' >"$DOT_CONFIG"
  without_taplo
  run cfg_parse_problems
  [ "$status" -eq 0 ]
  [[ $output == *"no readable"* ]]
}

@test "parse: a dropped table is reported once, by name, with the cause" {
  printf 'schema = 1\n[modules]\nenabled = ["git"]\nstray line\n\n[settings.git]\nk = "v"\n' \
    >"$DOT_CONFIG"
  without_taplo
  run cfg_parse_problems
  [ "${#lines[@]}" -eq 1 ]
  [[ $output == *"[settings]"* ]]
}

@test "parse: apply refuses a truncated config instead of doing nothing quietly" {
  printf 'schema = 1\n[modules]\nenabled = [ "git" "zsh" ]\n\n[settings.git]\nk = "v"\n' \
    >"$DOT_CONFIG"

  run "$DOT_ROOT/bin/dot" apply --dry-run
  [ "$status" -ne 0 ]
  [[ $output == *"did not parse"* ]]
  [[ $output != *"None enabled"* ]]
}

@test "parse: doctor reports it and does not tell you to delete your dotfiles" {
  printf 'schema = 1\n[modules]\nenabled = [ "git" "zsh" ]\n\n[settings.git]\nk = "v"\n' \
    >"$DOT_CONFIG"

  without_taplo
  run bash "$DOT_ROOT/core/doctor.sh"
  [ "$status" -ne 0 ]
  [[ $output == *"cannot see it"* ]]
}

@test "parse: taplo catches the typo the heuristics structurally cannot" {
  # A broken LAST table. [settings] is still in dasel's keys(), so check 1 says
  # nothing and check 2 only ever looks at [modules] -- while `signingkey`
  # quietly reads as empty and commit signing goes off with no line saying why.
  printf 'schema = 1\n[modules]\nenabled = ["git"]\n\n[settings.git]\nsigningkey = "ssh-ed25519 AAAA\nextra = "x"\n' \
    >"$DOT_CONFIG"

  without_taplo
  run cfg_parse_problems
  [ -z "$output" ] # everything the heuristics alone have to say about it
  run module_setting git signingkey ''
  [ -z "$output" ]

  unset DOT_TAPLO_BIN
  run cfg_parse_problems
  [[ $output == *"not valid TOML"* ]]

  # And it has to stop the run, not just be printed somewhere.
  run "$DOT_ROOT/bin/dot" apply --dry-run
  [ "$status" -ne 0 ]
  [[ $output == *"did not parse"* ]]
}

# --- the generator ----------------------------------------------------------

@test "generate: refuses to overwrite an existing config" {
  run config_generate "A" "a@b.c" "git"
  [ "$status" -ne 0 ]
  run cfg_get 'user.name'
  [ "$output" = "Martin Zachariassen" ]
}

@test "generate: writes a file that reads back correctly" {
  rm "$DOT_CONFIG"
  config_generate "Ada Lovelace" "ada@example.com" "$(printf 'git\nzsh\n')"

  run cfg_get 'user.name'
  [ "$output" = "Ada Lovelace" ]
  run cfg_get 'user.email'
  [ "$output" = "ada@example.com" ]
  run cfg_list 'modules.enabled'
  [ "${#lines[@]}" -eq 2 ]
}

@test "generate: the result keeps its comments" {
  rm "$DOT_CONFIG"
  config_generate "A" "a@b.c" "git"
  run grep -c '^#' "$DOT_CONFIG"
  [ "$output" -gt 3 ]
}

@test "generate: a quote in the git identity does not truncate the config" {
  # Written raw, the quote closes the TOML string early and every table below
  # it vanishes from the parsed document.
  rm "$DOT_CONFIG"
  config_generate 'Martin "Zach" Z' 'a@b.c' "$(printf 'git\n')"

  run cfg_get 'user.name'
  [ "$output" = 'Martin "Zach" Z' ]
  run cfg_list 'modules.enabled'
  [ "$output" = "git" ]
  run cfg_parse_problems
  [ -z "$output" ]
}

@test "generate: a backslash survives too, and does not eat the next character" {
  # Backslash must be escaped BEFORE the quote in __cfg_quote.
  rm "$DOT_CONFIG"
  config_generate 'back\slash and "quote"' 'a@b.c' ""

  run cfg_get 'user.name'
  [ "$output" = 'back\slash and "quote"' ]
  run cfg_parse_problems
  [ -z "$output" ]
}

@test "generate: dry run writes nothing" {
  rm "$DOT_CONFIG"
  export DOT_DRY_RUN=1
  config_generate "A" "a@b.c" "git"
  [ ! -f "$DOT_CONFIG" ]
}
