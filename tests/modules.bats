#!/usr/bin/env bats

setup() {
  load helper
  setup_sandbox

  REPO="$DOT_TMP/repo"
  DOT_ROOT="$REPO"
}

teardown() { teardown_sandbox; }

make_module() {
  local dir="$REPO/modules/$1"
  mkdir -p "$dir/home"
  printf 'description = "%s"\n' "$1" >"$dir/module.toml"
  printf '%s\n' "$dir"
}

hook() {
  printf '#!/usr/bin/env bash\nexit %s\n' "$3" >"$1/$2"
}

@test "doctor: a module whose files are not linked is a failure" {
  local m
  m=$(make_module demo)
  printf 'x\n' >"$m/home/.demorc"

  module_doctor demo
  [ "$DOT_FAILURES" -eq 1 ]
}

@test "doctor: a doctor.sh that exits non-zero is a failure" {
  local m
  m=$(make_module demo)
  hook "$m" doctor.sh 1

  module_doctor demo
  [ "$DOT_FAILURES" -eq 1 ]
}

@test "doctor: a healthy module adds nothing to the tally" {
  local m
  m=$(make_module demo)
  printf 'x\n' >"$m/home/.demorc"
  fs_link_tree "$m"
  hook "$m" doctor.sh 0

  module_doctor demo
  [ "$DOT_FAILURES" -eq 0 ]
}

@test "doctor: a module with no hook and no files is not a failure" {
  make_module demo >/dev/null

  module_doctor demo
  [ "$DOT_FAILURES" -eq 0 ]
}

@test "doctor: a packages-only module says so instead of printing nothing" {
  make_module demo >/dev/null

  run module_doctor demo
  [ "$status" -eq 0 ]
  [[ $output == *"nothing to check"* ]]
}

@test "doctor: a module whose files are all linked says so" {
  local m
  m=$(make_module demo)
  printf 'x\n' >"$m/home/.demorc"
  fs_link_tree "$m" >/dev/null

  run module_doctor demo
  [ "$status" -eq 0 ]
  [[ $output == *"all linked"* ]]
}

@test "doctor: drift and a failing hook are both reported, in one pass" {
  local m
  m=$(make_module demo)
  printf 'x\n' >"$m/home/.demorc"
  hook "$m" doctor.sh 1

  module_doctor demo
  [ "$DOT_FAILURES" -eq 2 ]
}

@test "apply: a packages-only module says so instead of printing nothing" {
  local m
  m=$(make_module demo)
  rmdir "$m/home"

  run module_apply demo
  [ "$status" -eq 0 ]
  [[ $output == *"packages only"* ]]
}

@test "doctor: counting a failure does not abort the caller" {
  local m
  m=$(make_module demo)
  printf 'x\n' >"$m/home/.demorc"

  run env -u DOT_ROOT bash -euo pipefail -c "
    source \"$BATS_TEST_DIRNAME/../lib/dot.sh\"
    DOT_ROOT='$REPO'
    module_doctor demo
    echo REACHED-THE-END
  "
  [ "$status" -eq 1 ]
  [[ $output == *"REACHED-THE-END"* ]]
}

@test "doctor: a doctor.sh that only warns is a warning, not a failure" {
  local m
  m=$(make_module demo)
  hook "$m" doctor.sh "$DOT_STATUS_WARN"

  module_doctor demo
  [ "$DOT_FAILURES" -eq 0 ]
  [ "$DOT_WARNINGS" -eq 1 ]
}

@test "apply: an apply.sh that only warns is not a failed hook" {
  local m
  m=$(make_module demo)
  hook "$m" apply.sh "$DOT_STATUS_WARN"

  module_apply demo
  [ "$DOT_FAILURES" -eq 0 ]
  [ "$DOT_WARNINGS" -eq 1 ]
}

@test "apply: a failing Brewfile stops that module, not the run" {
  local a b
  a=$(make_module alpha)
  b=$(make_module beta)
  printf 'x\n' >"$b/home/.betarc"
  : "$a"

  run env -u DOT_ROOT bash -euo pipefail -c "
    source \"$BATS_TEST_DIRNAME/../lib/dot.sh\"
    DOT_ROOT='$REPO'
    brew_bundle() { fail 'the Brewfile failed'; return 1; }
    module_apply alpha
    module_apply beta
    echo REACHED-THE-END
  "
  [ "$status" -eq 1 ]
  [[ $output == *"REACHED-THE-END"* ]]
  [ -L "$HOME/.betarc" ]
}

@test "apply: apply.sh is skipped when its packages did not install" {
  local m
  m=$(make_module demo)
  printf 'x\n' >"$m/home/.demorc"
  printf '#!/usr/bin/env bash\ntouch "$HOME/apply-ran"\n' >"$m/apply.sh"

  brew_bundle() {
    fail 'the Brewfile failed'
    return 1
  }
  module_apply demo

  [ ! -e "$HOME/apply-ran" ]
  [ -L "$HOME/.demorc" ]
  [ "$DOT_FAILURES" -eq 1 ]
}

@test "doctor: a status that is neither 0 nor the warn status is a failure" {
  local m
  m=$(make_module demo)
  hook "$m" doctor.sh 42

  module_doctor demo
  [ "$DOT_FAILURES" -eq 1 ]
  [ "$DOT_WARNINGS" -eq 0 ]
}

@test "doctor: a hook with a SYNTAX ERROR is a failure, not a warning" {
  local m
  m=$(make_module demo)
  printf '#!/usr/bin/env bash\nif [ 1\n' >"$m/doctor.sh"

  module_doctor demo
  [ "$DOT_FAILURES" -eq 1 ]
  [ "$DOT_WARNINGS" -eq 0 ]
}

@test "remove: a hook with a syntax error reaches the uninstall guard" {
  local m
  m=$(make_module demo)
  printf '#!/usr/bin/env bash\nfor x in\n' >"$m/remove.sh"

  module_remove demo
  [ "$DOT_FAILURES" -eq 1 ]
}

@test "remove: a module with no remove.sh is not a failure" {
  make_module demo >/dev/null

  module_remove demo
  [ "$DOT_FAILURES" -eq 0 ]
  [ "$DOT_WARNINGS" -eq 0 ]
}

@test "remove: a remove.sh that only warns does not block the uninstall" {
  local m
  m=$(make_module demo)
  hook "$m" remove.sh "$DOT_STATUS_WARN"

  module_remove demo
  [ "$DOT_FAILURES" -eq 0 ]
  [ "$DOT_WARNINGS" -eq 1 ]
}

@test "remove: a remove.sh that fails is counted, so the handoff is stopped" {
  local m
  m=$(make_module demo)
  hook "$m" remove.sh 1

  module_remove demo
  [ "$DOT_FAILURES" -eq 1 ]
}

@test "remove: the hook runs with DOT_MODULE and DOT_MODULE_DIR set" {
  local m
  m=$(make_module demo)
  printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "$DOT_MODULE" "$DOT_MODULE_DIR" >"$HOME/env-seen"\n' \
    >"$m/remove.sh"

  module_remove demo
  [ "$(cat "$HOME/env-seen")" = "demo $m" ]
}

run_script() {
  run env -u DOT_ROOT bash -euo pipefail -c "
    source \"$BATS_TEST_DIRNAME/../lib/dot.sh\"
    $1
  "
}

@test "hooks: a script that warns and breaks nothing exits with the warn status" {
  run_script "warn 'something worth saying'"
  [ "$status" -eq "$DOT_STATUS_WARN" ]
}

@test "hooks: the warn status is not one bash uses for anything of its own" {
  [ "$DOT_STATUS_WARN" -ne 0 ]
  [ "$DOT_STATUS_WARN" -ne 1 ]
  [ "$DOT_STATUS_WARN" -ne 126 ]
  [ "$DOT_STATUS_WARN" -ne 127 ]
  [ "$DOT_STATUS_WARN" -lt 128 ]

  printf 'if [ 1\n' >"$DOT_TMP/broken.sh"
  run bash "$DOT_TMP/broken.sh"
  [ "$status" -ne "$DOT_STATUS_WARN" ]
}

@test "hooks: a script that warns AND fails exits 1" {
  run_script "warn 'noise'; fail 'the actual problem'"
  [ "$status" -eq 1 ]
}

@test "hooks: a script that says nothing still exits 0" {
  run_script "true"
  [ "$status" -eq 0 ]
}

enable() {
  printf 'schema = 1\n\n[modules]\nenabled = [\n' >"$DOT_CONFIG"
  local n
  for n in "$@"; do printf '  "%s",\n' "$n" >>"$DOT_CONFIG"; done
  printf ']\n' >>"$DOT_CONFIG"
}

@test "preflight: hooks that parse let the run continue" {
  local m
  m=$(make_module demo)
  hook "$m" apply.sh 0
  hook "$m" doctor.sh 0
  enable demo

  run modules_preflight
  [ "$status" -eq 0 ]
}

@test "preflight: a module with no hooks at all is not a problem" {
  make_module demo
  enable demo

  run modules_preflight
  [ "$status" -eq 0 ]
}

@test "preflight: a hook that will not parse stops the run" {
  local m
  m=$(make_module demo)
  printf '#!/usr/bin/env bash\nif [ 1\n' >"$m/apply.sh"
  enable demo

  run modules_preflight
  [ "$status" -ne 0 ]
}

@test "preflight: the broken hook is named, and so is the way to reproduce it" {
  local m
  m=$(make_module demo)
  printf '#!/usr/bin/env bash\nif [ 1\n' >"$m/doctor.sh"
  enable demo

  run modules_preflight
  [[ $output == *"modules/demo/doctor.sh"* ]]
  [[ $output == *"bash -n"* ]]
}

@test "preflight: it says nothing was changed, because nothing was" {
  local m before
  m=$(make_module demo)
  printf 'x\n' >"$m/home/.demorc"
  printf '#!/usr/bin/env bash\nif [ 1\n' >"$m/apply.sh"
  enable demo

  before=$(home_snapshot)
  run modules_preflight
  [ "$status" -ne 0 ]
  [[ $output == *"nothing was changed"* ]]
  [ "$(home_snapshot)" = "$before" ]
}

@test "preflight: every broken hook is listed, not just the first" {
  local a b
  a=$(make_module alpha)
  b=$(make_module beta)
  printf '#!/usr/bin/env bash\nif [ 1\n' >"$a/apply.sh"
  printf '#!/usr/bin/env bash\ncase x\n' >"$b/remove.sh"
  enable alpha beta

  run modules_preflight
  [[ $output == *"modules/alpha/apply.sh"* ]]
  [[ $output == *"modules/beta/remove.sh"* ]]
}

@test "preflight: a DISABLED module's broken hook does not block the run" {
  local m
  m=$(make_module demo)
  printf '#!/usr/bin/env bash\nif [ 1\n' >"$m/apply.sh"
  enable

  run modules_preflight
  [ "$status" -eq 0 ]
}

@test "preflight: core is parsed too -- it runs like a module" {
  mkdir -p "$REPO/core"
  printf '#!/usr/bin/env bash\nif [ 1\n' >"$REPO/core/apply.sh"
  enable

  run modules_preflight
  [ "$status" -ne 0 ]
  [[ $output == *"core/apply.sh"* ]]
}

@test "preflight: all three hook names are parsed, not only apply.sh" {
  local hook m
  for hook in apply.sh doctor.sh remove.sh; do
    rm -rf "$REPO/modules"
    m=$(make_module demo)
    printf '#!/usr/bin/env bash\nif [ 1\n' >"$m/$hook"
    enable demo

    run modules_preflight
    [ "$status" -ne 0 ] || {
      echo "$hook was not parsed"
      return 1
    }
  done
}
