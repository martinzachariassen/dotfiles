#!/usr/bin/env bats
#
# lib/dot.sh: root resolution and exit status.

load helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

@test "a clean script that sources the library exits 0" {
  # `[[ $DOT_FAILURES -gt 0 ]] && exit 1; exit $?` leaves $? at 1 when the
  # test is false, so every clean hook would exit 1.
  cat >"$DOT_TMP/clean.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$DOT_ROOT/lib/dot.sh"
ok "did the thing"
EOF
  run bash "$DOT_TMP/clean.sh"
  [ "$status" -eq 0 ]
}

@test "a script that calls fail exits 1" {
  cat >"$DOT_TMP/bad.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$DOT_ROOT/lib/dot.sh"
fail "something is wrong"
EOF
  run bash "$DOT_TMP/bad.sh"
  [ "$status" -eq 1 ]
}

@test "fail does not stop execution" {
  cat >"$DOT_TMP/two.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$DOT_ROOT/lib/dot.sh"
fail "first"
fail "second"
echo "reached the end"
EOF
  run bash "$DOT_TMP/two.sh"
  [ "$status" -eq 1 ]
  [[ $output == *"reached the end"* ]]
}

@test "an explicit non-zero exit is preserved" {
  cat >"$DOT_TMP/code.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$DOT_ROOT/lib/dot.sh"
exit 3
EOF
  run bash "$DOT_TMP/code.sh"
  [ "$status" -eq 3 ]
}

@test "the installed shim invokes the CLI from a clean environment" {
  # A symlinked shim makes BASH_SOURCE point at ~/.local/bin, and bin/dot
  # looks for lib/ there.
  DOT_DRY_RUN=0 bash "$DOT_ROOT/core/apply.sh" >/dev/null

  [ -x "$HOME/.local/bin/dot" ]
  run env -u DOT_ROOT "$HOME/.local/bin/dot" --help
  [ "$status" -eq 0 ]
  [[ $output == *"usage: dot"* ]]
}

@test "the shim records the checkout in the exact form its readers grep for" {
  # core/apply.sh WRITES `export DOT_ROOT="<path>"`; core/doctor.sh and
  # uninstall.sh `grep -qF 'DOT_ROOT="<path>"'`. Written as the readers' own
  # expression so the test fails with them.
  DOT_DRY_RUN=0 bash "$DOT_ROOT/core/apply.sh" >/dev/null
  run grep -qF "DOT_ROOT=\"$DOT_ROOT\"" "$HOME/.local/bin/dot"
  [ "$status" -eq 0 ]
}

@test "doctor and uninstall recognise the shim core/apply.sh just wrote" {
  DOT_DRY_RUN=0 bash "$DOT_ROOT/core/apply.sh" >/dev/null

  run bash "$DOT_ROOT/core/doctor.sh"
  says dot "installed"
  [[ $output != *"different checkout"* ]]
}

@test "a shim from another checkout is left alone, not claimed" {
  # The uninstaller deletes on the strength of this.
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\nexport DOT_ROOT="/somewhere/else"\n' \
    >"$HOME/.local/bin/dot"
  chmod +x "$HOME/.local/bin/dot"

  run bash "$DOT_ROOT/core/doctor.sh"
  [[ $output == *"different checkout"* ]]
}

@test "an inherited DOT_ROOT is not overridden" {
  run bash -c "DOT_ROOT='$DOT_ROOT' bash -c 'source \"$DOT_ROOT/lib/dot.sh\"; echo \$DOT_ROOT'"
  [ "$output" = "$DOT_ROOT" ]
}

# A checkout at PATH. Only lib/ is needed: the guard runs before the first source.
checkout_at() {
  local dir="$DOT_TMP/$1"
  mkdir -p "$dir"
  ln -s "$DOT_ROOT/lib" "$dir/lib"
  printf '%s\n' "$dir"
}

@test "root: every character that survives quoting is refused" {
  # Each is baked verbatim into a generated script (the shim, the uninstall
  # handoff). A `"` breaks the string; a backtick or $( ) is a command it RUNS.
  local bad dir
  for bad in 'dot"files' 'dot`id`files' 'dot$(id)files' 'back\slash'; do
    dir=$(checkout_at "$bad")
    run env DOT_ROOT="$dir" bash -c 'source "$DOT_ROOT/lib/dot.sh"'
    [ "$status" -ne 0 ] || {
      echo "accepted a checkout path containing: $bad"
      return 1
    }
    [[ $output == *"cannot be quoted safely"* ]]
    [[ $output == *"$bad"* ]]
  done
}

@test "root: an ordinary path with spaces or non-ASCII is left alone" {
  # Refusing paths people actually have is how a guard gets deleted.
  local dir
  dir=$(checkout_at 'my dotfiles æøå')

  run env DOT_ROOT="$dir" bash -c 'source "$DOT_ROOT/lib/dot.sh"; ok loaded'
  [ "$status" -eq 0 ]
  [[ $output == *loaded* ]]
}

# --- Failure reporting ------------------------------------------------------

# A real script file, not `bash -c`: the report is built from BASH_SOURCE.
as_hook() {
  local script="$DOT_TMP/hook.sh"
  {
    echo '#!/usr/bin/env bash'
    echo 'set -euo pipefail'
    echo "source \"$DOT_ROOT/lib/dot.sh\""
    echo "$1"
  } >"$script"
  run bash "$script"
}

@test "err: a crash names the file, the command and the status" {
  as_hook 'cp /nonexistent/theme.conf "$HOME/theme.conf"'
  [ "$status" -ne 0 ]
  [[ $output == *"hook.sh"* ]]
  [[ $output == *"cp /nonexistent/theme.conf"* ]]
  [[ $output == *"exit 1"* ]]
}

@test "err: a failure inside a function names the failing line" {
  # bash 3.2 reports the function's DEFINITION line. as_hook writes shebang,
  # `set`, `source`, then the snippet, so the failure is on line 4 -- pinned
  # exactly, since "some number" would pass on 3.2 too.
  as_hook 'inner() { cp /nonexistent/x "$HOME/x"; }; inner'
  [ "$status" -ne 0 ]
  [[ $output == *"cp /nonexistent/x"* ]]
  [[ $output == *"hook.sh:4:"* ]]
}

@test "err: a failure handled inside \$() is not reported" {
  # errtrace makes $() inherit the ERR trap; toml_get's missing-key probe must
  # not report.
  as_hook "val=\$(toml_get '$DOT_ROOT/modules/git/module.toml' nosuchkey FALLBACK)
           echo \"val=\$val\""
  [ "$status" -eq 0 ]
  [[ $output == *"val=FALLBACK"* ]]
  [[ $output != *"exit 1"* ]]
}

@test "err: reported once, not once per stack frame" {
  as_hook 'a() { false; }; b() { a; }; c() { b; }; c'
  [ "$status" -ne 0 ]
  [ "$(grep -c 'exit 1' <<<"$output")" -eq 1 ]
}

# --- The bash version -------------------------------------------------------

@test "bash: the suite itself runs under bash 5" {
  # Under macOS's 3.2, every other test here exercises the wrong shell.
  [ "${BASH_VERSINFO[0]}" -ge 5 ]
}

@test "bash: the library refuses to load under an old bash" {
  [ -x /bin/bash ] || skip 'no /bin/bash on this machine'
  /bin/bash -c '((BASH_VERSINFO[0] < 5))' || skip '/bin/bash is already bash 5'

  run /bin/bash -c "source '$DOT_ROOT/lib/dot.sh'"
  [ "$status" -ne 0 ]
  [[ $output == *"bash 5"* ]]
  [[ $output == *"brew install bash"* ]]
}
