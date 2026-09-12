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

# --- the schema marker ------------------------------------------------------
#
# A version marker that guarantees nothing is worse than none, because it looks
# like a check. These are what make it one. Written as properties of
# DOT_CONFIG_SCHEMA rather than of the number 1, so a bump does not silently
# turn them into tests of nothing.

@test "schema: the generator writes the version this checkout speaks" {
  rm -f "$DOT_CONFIG"
  config_generate 'A' 'a@b.c' 'git' >/dev/null

  run cfg_get 'schema'
  [ "$output" = "$DOT_CONFIG_SCHEMA" ]
  # And what it wrote is what the reader accepts -- the round trip is the point.
  [ -z "$(cfg_parse_problems)" ]
}

@test "schema: a config from an older checkout is reported, not read anyway" {
  printf 'schema = %s\n\n[modules]\nenabled = ["git"]\n' \
    "$((DOT_CONFIG_SCHEMA - 1))" >"$DOT_CONFIG"

  run cfg_parse_problems
  [[ $output == *"schema $((DOT_CONFIG_SCHEMA - 1))"* ]]
  [[ $output == *"schema $DOT_CONFIG_SCHEMA"* ]]
}

@test "schema: a config from a NEWER checkout is caught the same way" {
  # The direction that would otherwise pass: a bigger number is still not one
  # this checkout knows how to read.
  printf 'schema = %s\n\n[modules]\nenabled = ["git"]\n' \
    "$((DOT_CONFIG_SCHEMA + 1))" >"$DOT_CONFIG"

  run cfg_parse_problems
  [ -n "$output" ]
  [[ $output == *"pull the repo"* ]]
}

@test "schema: a config with no marker at all says how to get one" {
  printf '[modules]\nenabled = ["git"]\n' >"$DOT_CONFIG"

  run cfg_parse_problems
  [[ $output == *"no \`schema\` key"* ]]
  [[ $output == *"dot config --init"* ]]
}

@test "schema: a mismatch stops apply, it is not merely printed" {
  # The whole value of the marker is that it refuses. Reported-but-applied is
  # the same as unchecked.
  printf 'schema = %s\n\n[modules]\nenabled = ["git"]\n' \
    "$((DOT_CONFIG_SCHEMA + 1))" >"$DOT_CONFIG"

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

# --- Editing `enabled` ------------------------------------------------------
#
# The one exception to "written once". Every test here is about what must NOT
# change: the file is the user's, and only the array is this code's business.

# The generated shape, which is what `dot add`/`dot remove` will edit.
generated_config() {
  cat >"$DOT_CONFIG" <<'EOF'
# A comment above everything. It must survive.
schema = 1

[user]
name  = "Martin Zachariassen"
email = "m@example.com"

[modules]
# Add or remove names, then run `dot apply`.
enabled = [
  "git",
  # a note the user left between entries
  "zsh",
]

[settings.git]
signingkey = "ssh-ed25519 AAAA"
EOF
}

@test "enabled: adding a module keeps every other byte of the file" {
  generated_config
  local before after
  before=$(grep -v '^  "' "$DOT_CONFIG")

  cfg_module_add cmux
  after=$(grep -v '^  "' "$DOT_CONFIG")

  # Comments, tables, spacing, the user's note inside the array: all of it.
  [ "$before" = "$after" ]
  [[ $(cat "$DOT_CONFIG") == *'# a note the user left between entries'* ]]
}

@test "enabled: a module is added in alphabetical order" {
  generated_config
  cfg_module_add cmux

  # cmux sorts before git, so it must land first, not appended at the end.
  run cfg_list 'modules.enabled'
  [ "${lines[0]}" = "cmux" ]
  [ "${lines[1]}" = "git" ]
  [ "${lines[2]}" = "zsh" ]
}

@test "enabled: a name sorting last goes before the bracket, not after it" {
  generated_config
  cfg_module_add zzz

  run cfg_list 'modules.enabled'
  [ "${lines[2]}" = "zzz" ]
  # Still parseable: an entry written outside the array would not be.
  [ -z "$(cfg_parse_problems)" ]
}

@test "enabled: removing a module drops its line and nothing else" {
  generated_config
  cfg_module_remove git

  run cfg_list 'modules.enabled'
  [ "${#lines[@]}" -eq 1 ]
  [ "${lines[0]}" = "zsh" ]
  [[ $(cat "$DOT_CONFIG") == *'# a note the user left between entries'* ]]
  [[ $(cat "$DOT_CONFIG") == *'signingkey'* ]]
}

# A config where the exact text of an entry also appears in an array that is
# none of this code's business, both before and after the one it may edit.
# Every writer here is line-based, so "looks like an entry" is the whole risk.
decoyed_config() {
  cat >"$DOT_CONFIG" <<'EOF'
schema = 1

[before]
list = [
  "git",
]

[modules]
enabled = [
  "git",
  "zsh",
]

[after]
list = [
  "git",
]
EOF
}

@test "enabled: remove drops the entry in the array, not its twin elsewhere" {
  decoyed_config
  cfg_module_remove git

  run cfg_list 'modules.enabled'
  [ "${#lines[@]}" -eq 1 ]
  [ "${lines[0]}" = "zsh" ]

  # Both decoys untouched: three "git" lines went in, two must remain.
  [ "$(grep -c '^  "git",$' "$DOT_CONFIG")" -eq 2 ]
  [ "$(cfg_list 'before.list')" = "git" ]
  [ "$(cfg_list 'after.list')" = "git" ]
}

@test "enabled: add ignores a look-alike entry outside the array it may edit" {
  # The insert point is chosen by scanning the span only. A decoy sorting
  # around the new name must not be able to pull the line out of the array.
  decoyed_config
  cfg_module_add cmux

  run cfg_list 'modules.enabled'
  [ "${#lines[@]}" -eq 3 ]
  [ "${lines[0]}" = "cmux" ]
  [ "${lines[1]}" = "git" ]
  [ "${lines[2]}" = "zsh" ]

  [ "$(cfg_list 'before.list')" = "git" ]
  [ "$(cfg_list 'after.list')" = "git" ]
  [ -z "$(cfg_parse_problems)" ]
}

@test "enabled: a hand-formatted array is refused, not reformatted" {
  # setup's config has `enabled = ["git", "zsh"]` on one line -- legal TOML and
  # a supported way to write it. Rewriting it would be this code deciding it
  # knows better about a file it does not own.
  local before
  before=$(cat "$DOT_CONFIG")

  run cfg_enabled_editable
  [ "$status" -ne 0 ]

  run cfg_module_add cmux
  [ "$status" -ne 0 ]
  [ "$(cat "$DOT_CONFIG")" = "$before" ]
}

@test "enabled: an entry without its trailing comma is not the shape we wrote" {
  # config_generate writes a comma on every entry, the last one included.
  # Without it this is a file someone reformatted, and guessing is how you
  # lose the line below.
  printf 'schema = 1\n\n[modules]\nenabled = [\n  "git",\n  "zsh"\n]\n' >"$DOT_CONFIG"

  run cfg_enabled_editable
  [ "$status" -ne 0 ]
}

@test "enabled: the file keeps its mode, not mktemp's 0600" {
  generated_config
  chmod 644 "$DOT_CONFIG"

  cfg_module_add cmux

  [ "$(stat -f '%Lp' "$DOT_CONFIG")" = "644" ]
}

@test "taplo: exit 1 means the file is invalid, and says so" {
  # The answer taplo documents for a file with syntax errors.
  generated_config
  printf '#!/bin/sh\nexit 1\n' >"$DOT_TMP/taplo-invalid"
  chmod +x "$DOT_TMP/taplo-invalid"
  export DOT_TAPLO_BIN="$DOT_TMP/taplo-invalid"

  run cfg_parse_problems
  [ "$status" -eq 0 ]
  [[ $output == *"not valid TOML"* ]]
}

@test "taplo: a crash is a third answer, not a verdict about the file" {
  # A rust panic exits 101. Read as "invalid", it told you a perfectly good
  # config was broken -- and, worse, `dot apply` refused over it, so a taplo
  # that fell over locked the machine out of its own configuration.
  generated_config
  printf '#!/bin/sh\necho "panicked at ..." >&2\nexit 101\n' >"$DOT_TMP/taplo-crash"
  chmod +x "$DOT_TMP/taplo-crash"
  export DOT_TAPLO_BIN="$DOT_TMP/taplo-crash"

  run cfg_parse_problems
  [ "$status" -eq 0 ]
  [[ $output != *"not valid TOML"* ]]
  # Nothing at all: a checker that did not answer is not a problem with the file.
  [ -z "$output" ]
}

@test "taplo: the crash is still reported, not swallowed" {
  # Silence would be the opposite mistake: the two heuristics left behind miss
  # a typo in the last table, so doctor has to say the real check did not run.
  generated_config
  printf '#!/bin/sh\nexit 101\n' >"$DOT_TMP/taplo-crash"
  chmod +x "$DOT_TMP/taplo-crash"
  export DOT_TAPLO_BIN="$DOT_TMP/taplo-crash"

  cfg_parse_problems >/dev/null
  run cfg_unchecked
  [ "$status" -eq 0 ]
}

@test "taplo: a clean answer leaves nothing to report" {
  generated_config
  printf '#!/bin/sh\nexit 0\n' >"$DOT_TMP/taplo-ok"
  chmod +x "$DOT_TMP/taplo-ok"
  export DOT_TAPLO_BIN="$DOT_TMP/taplo-ok"

  run cfg_parse_problems
  [ -z "$output" ]
  cfg_parse_problems >/dev/null
  run cfg_unchecked
  [ "$status" -ne 0 ]
}

@test "taplo: not installed yet is not a crash either" {
  # The normal state before phase 1 has run. It must not set the flag doctor
  # warns on, or a fresh machine warns about its own bootstrap order.
  generated_config
  export DOT_TAPLO_BIN="$DOT_TMP/no-such-taplo"

  cfg_parse_problems >/dev/null
  run cfg_unchecked
  [ "$status" -ne 0 ]
}

@test "enabled: an edit that would not parse never replaces the file" {
  # taplo is asked BEFORE the mv, because after it there is nothing to roll
  # back to. A stub that always refuses is what makes that branch reachable.
  generated_config
  local before
  before=$(cat "$DOT_CONFIG")

  printf '#!/bin/sh\nexit 1\n' >"$DOT_TMP/taplo-no"
  chmod +x "$DOT_TMP/taplo-no"
  export DOT_TAPLO_BIN="$DOT_TMP/taplo-no"

  run cfg_module_add cmux
  [ "$status" -ne 0 ]
  [ "$(cat "$DOT_CONFIG")" = "$before" ]
  # And no debris beside it.
  [ -z "$(find "$(dirname "$DOT_CONFIG")" -name 'config.toml.*' -print -quit)" ]
}
