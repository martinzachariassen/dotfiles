#!/usr/bin/env bats
#
# bin/dot: how it reads the command line, and the Result line of each verb.

load helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

dot() { run "$DOT_ROOT/bin/dot" "$@"; }

# Make the core checks pass so a doctor test isolates one thing. The real
# generator, not a printf'd lookalike: a hand-written shim is a second
# definition of the format core/doctor.sh greps for.
pass_core_checks() {
  DOT_DRY_RUN=0 bash "$DOT_ROOT/core/apply.sh" >/dev/null
  export PATH="$HOME/.local/bin:$PATH"
}

@test "cli: no arguments prints the usage" {
  dot
  [ "$status" -eq 0 ]
  [[ $output == *"usage: dot"* ]]
}

@test "cli: an unknown command exits 1 and shows the usage" {
  dot frobnicate
  [ "$status" -eq 1 ]
  [[ $output == *"unknown command frobnicate"* ]]
  [[ $output == *"usage: dot"* ]]
}

@test "apply: a mistyped --dry-run is refused, not ignored" {
  dot apply --dry
  [ "$status" -ne 0 ]
  [[ $output == *"unknown option '--dry'"* ]]
  # Stopped before phase 1.
  [[ $output != *"Core packages"* ]]
}

@test "apply: --dry-run is accepted and changes nothing" {
  config_generate "A" "a@b.c" ""

  dot apply --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"Dry run: nothing was changed."* ]]
  [ ! -e "$HOME/.local/bin/dot" ]
}

@test "apply: says which config it read before it changes anything" {
  config_generate "A" "a@b.c" ""

  dot apply --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"$DOT_CONFIG"* ]]
  [[ $output == *"dry run -- nothing will be changed"* ]]
}

@test "apply: module headings say how many are left" {
  config_generate "A" "a@b.c" "git"

  dot apply --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"[1/1]"* ]]
  says modules "1 applied"
}

@test "apply: a real run leaves a transcript and names it" {
  # brew is stubbed: this is about the transcript, not packages. ~/.local/bin
  # is on PATH because apply now ends by running the doctor checks, and
  # core/doctor.sh rightly fails a machine that cannot reach its own shim.
  config_generate "A" "a@b.c" ""
  mkdir -p "$DOT_TMP/stub"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$DOT_TMP/stub/brew"
  chmod +x "$DOT_TMP/stub/brew"

  run env PATH="$DOT_TMP/stub:$HOME/.local/bin:$PATH" "$DOT_ROOT/bin/dot" apply
  [ "$status" -eq 0 ]

  local log="$DOT_STATE/logs/$DOT_RUN_ID-apply.log"
  [ -f "$log" ]
  [[ $(cat "$log") == *"Core packages"* ]]
  [[ $(cat "$log") == *"Summary"* ]]
  [[ $output == *"-apply.log"* ]]
}

@test "apply: a dry run writes no log" {
  # The log is the one non-symlink file an apply writes.
  config_generate "A" "a@b.c" ""

  dot apply --dry-run
  [ "$status" -eq 0 ]
  [ ! -d "$DOT_STATE/logs" ]
}

@test "apply: keeps the twenty most recent logs" {
  config_generate "A" "a@b.c" ""
  mkdir -p "$DOT_TMP/stub" "$DOT_STATE/logs"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$DOT_TMP/stub/brew"
  chmod +x "$DOT_TMP/stub/brew"

  # Names below this run's id, so they sort as older however the clock reads.
  local i
  for i in $(seq -w 1 25); do
    printf 'old\n' >"$DOT_STATE/logs/00000000-0000$i.log"
  done

  run env PATH="$DOT_TMP/stub:$HOME/.local/bin:$PATH" "$DOT_ROOT/bin/dot" apply
  [ "$status" -eq 0 ]

  local kept
  kept=$(find "$DOT_STATE/logs" -name '*.log' | wc -l | tr -d ' ')
  [ "$kept" -eq 20 ]
  # This run's own log survives its own prune.
  [ -f "$DOT_STATE/logs/$DOT_RUN_ID-apply.log" ]
}

@test "doctor: an unlinked module fails the whole run" {
  config_generate "A" "a@b.c" "git"
  pass_core_checks

  run "$DOT_ROOT/bin/dot" doctor

  [ "$status" -eq 1 ]
  [[ $output == *"not linked"* ]]
  [[ $output != *"Everything looks right"* ]]
}

@test "doctor: a warning is not drowned out by the summary" {
  config_generate "A" "a@b.c" ""
  pass_core_checks

  mkdir -p "$HOME/.config/git"
  ln -s "$DOT_ROOT/bin/dot" "$HOME/.config/git/leftover"

  run "$DOT_ROOT/bin/dot" doctor

  [[ $output == *"unclaimed"* ]]
  [[ $output != *"Everything looks right"* ]]
  [[ $output == *warning* ]]
  # Still 0: `dot doctor && ...` must keep working.
  [ "$status" -eq 0 ]
}

@test "doctor: a clean machine still says so" {
  # A summary that never says "fine" is as useless as one that always does.
  config_generate "A" "a@b.c" ""
  pass_core_checks

  run "$DOT_ROOT/bin/dot" doctor

  [ "$status" -eq 0 ]
  [[ $output == *"Everything looks right"* ]]
}

@test "doctor: a healthy module is one line, and --verbose is the way back" {
  # The point of the collapse: forty green lines hid the three red ones. What
  # must not happen is that the detail becomes unreachable.
  config_generate "A" "a@b.c" "git"
  pass_core_checks
  fs_link_tree "$DOT_ROOT/modules/git"

  run "$DOT_ROOT/bin/dot" doctor
  [[ $output != *"all linked"* ]]

  run "$DOT_ROOT/bin/dot" doctor --verbose
  [[ $output == *"all linked"* ]]
}

@test "apply: five real modules, then the checks accept what they produced" {
  # The end-to-end nothing covered: link the files, run the hooks, then observe
  # the machine. brew is stubbed, so what runs for real is every file and every
  # hook, not Homebrew. Two modules are left out because they are the two that
  # reach outside $HOME -- macos-defaults writes system preferences, dev-cli
  # downloads runtimes -- and containers needs a real Homebrew prefix to find
  # the docker plugins it links. Each of those three has its own file here.
  config_generate "A" "a@b.c" "$(printf 'claude-code\ncmux\ngit\nssh\nzsh\n')"
  mkdir -p "$DOT_TMP/stub"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$DOT_TMP/stub/brew"
  chmod +x "$DOT_TMP/stub/brew"
  # Inherited from the developer's own shell, it reads as drift in the sandbox.
  unset ZDOTDIR

  run env PATH="$DOT_TMP/stub:$HOME/.local/bin:$PATH" "$DOT_ROOT/bin/dot" apply
  # 0 or a warning: the 1Password agent socket is not in a throwaway $HOME.
  [ "$status" -eq 0 ] || [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output != *problem* ]]

  # The verifying pass is the assertion, but only if the files really moved.
  [ -L "$HOME/.config/git/config" ]
  [ -L "$HOME/.config/zsh/.zshrc" ]
  [ -L "$HOME/.ssh/config" ]
  [ -L "$HOME/.config/cmux/cmux.json" ]
  [ -f "$HOME/.claude/settings.json" ]
  [ -f "$HOME/.config/git/config.local" ]

  # Every module reported, and the healthy ones as one line each.
  local name
  for name in claude-code cmux git ssh zsh; do
    says "$name" "$(module_desc "$name")"
  done
}

@test "apply: a second run of the same five changes nothing and says so" {
  # Idempotence is the promise `dot apply` makes, and the converged run is the
  # one people actually see. It must not report work it did not do.
  config_generate "A" "a@b.c" "$(printf 'claude-code\ncmux\ngit\nssh\nzsh\n')"
  mkdir -p "$DOT_TMP/stub"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$DOT_TMP/stub/brew"
  chmod +x "$DOT_TMP/stub/brew"
  unset ZDOTDIR

  env PATH="$DOT_TMP/stub:$HOME/.local/bin:$PATH" "$DOT_ROOT/bin/dot" apply >/dev/null 2>&1 || true
  local after_first
  after_first=$(home_snapshot)

  run env PATH="$DOT_TMP/stub:$HOME/.local/bin:$PATH" DOT_RUN_ID=second \
    "$DOT_ROOT/bin/dot" apply
  [[ $output != *problem* ]]
  # Nothing linked, nothing relinked: the tally says unchanged and only that.
  [[ $output == *unchanged* ]]
  [[ $output != *"linked,"* ]]

  # And the second run really did leave $HOME alone. The transcript is the one
  # file it is allowed to add.
  local after_second
  after_second=$(home_snapshot)
  [ "$after_first" = "$after_second" ]
}

@test "doctor: an unknown option is refused, like every other verb's" {
  config_generate "A" "a@b.c" ""
  run "$DOT_ROOT/bin/dot" doctor --verbos
  [ "$status" -ne 0 ]
  [[ $output == *"unknown option"* ]]
}

@test "apply: a taplo that crashed does not stop the run" {
  # cfg_parse_problems used to read any non-zero exit as "your config is not
  # valid TOML", and apply dies on any problem line -- so a broken checker
  # locked the machine out of a configuration that was never wrong.
  config_generate "A" "a@b.c" ""
  pass_core_checks
  printf '#!/bin/sh\nexit 101\n' >"$DOT_TMP/taplo-crash"
  chmod +x "$DOT_TMP/taplo-crash"

  export DOT_TAPLO_BIN="$DOT_TMP/taplo-crash"

  run "$DOT_ROOT/bin/dot" apply
  [ "$status" -eq 0 ]
  [[ $output != *"not valid TOML"* ]]
}

@test "doctor: a taplo that crashed is reported as a check that did not run" {
  config_generate "A" "a@b.c" ""
  pass_core_checks
  printf '#!/bin/sh\nexit 101\n' >"$DOT_TMP/taplo-crash"
  chmod +x "$DOT_TMP/taplo-crash"

  export DOT_TAPLO_BIN="$DOT_TMP/taplo-crash"

  run "$DOT_ROOT/bin/dot" doctor
  [[ $output == *"could not check it"* ]]
  [[ $output != *"not valid TOML"* ]]
}

@test "doctor: a shim that lost its executable bit is not called missing" {
  config_generate "A" "a@b.c" ""
  pass_core_checks
  chmod -x "$HOME/.local/bin/dot"

  run "$DOT_ROOT/bin/dot" doctor

  [ "$status" -eq 1 ]
  [[ $output == *"not executable"* ]]
  [[ $output != *"not installed"* ]]
}

@test "doctor: a shim that is genuinely absent is still called missing" {
  config_generate "A" "a@b.c" ""

  run "$DOT_ROOT/bin/dot" doctor

  [ "$status" -eq 1 ]
  says dot "not installed at ~/.local/bin/dot -- run: dot apply"
  [[ $output != *"not executable"* ]]
}

@test "doctor: a stale module name is a failure, not a shrug" {
  # Reported, not fatal: doctor is read-only and must reach the checks below.
  config_generate "A" "a@b.c" "$(printf 'git\ntypoo\n')"
  pass_core_checks

  run "$DOT_ROOT/bin/dot" doctor

  [ "$status" -eq 1 ]
  [[ $output == *"unknown module 'typoo'"* ]]
  [[ $output != *"Everything looks right"* ]]
  # The real module is still reached: its group line is there, named and described.
  says git "$(module_desc git)"
}

@test "config: an unknown option is refused" {
  dot config --initt
  [ "$status" -ne 0 ]
  [[ $output == *"unknown option '--initt'"* ]]
}

@test "config: --init refuses to overwrite a config that already exists" {
  config_generate "A" "a@b.c" ""

  dot config --init
  [ "$status" -ne 0 ]
  [[ $output == *"already exists"* ]]
}

@test "config: with no config yet, points at --init instead of opening an editor" {
  EDITOR=false dot config
  [ "$status" -ne 0 ]
  [[ $output == *"dot config --init"* ]]
}

@test "config: opens \$EDITOR on the config file, and on nothing else" {
  config_generate "A" "a@b.c" ""
  printf '#!/usr/bin/env bash\nprintf "EDITED[%%s]\\n" "$@"\n' >"$DOT_TMP/fake-editor"
  chmod +x "$DOT_TMP/fake-editor"

  EDITOR="$DOT_TMP/fake-editor" dot config
  [ "$status" -eq 0 ]
  [ "$output" = "EDITED[$DOT_CONFIG]" ]
}

@test "apply: a dry run on a fresh machine does not run the wizard" {
  # The fzf stub is the tripwire: if the wizard is reached, it says so.
  mkdir -p "$DOT_TMP/stub"
  printf '#!/usr/bin/env bash\necho WIZARD-RAN\n' >"$DOT_TMP/stub/fzf"
  chmod +x "$DOT_TMP/stub/fzf"

  run env PATH="$DOT_TMP/stub:$PATH" "$DOT_ROOT/bin/dot" apply --dry-run

  [ "$status" -ne 0 ]
  [[ $output != *"WIZARD-RAN"* ]]
  [[ $output == *"dot config --init"* ]]
  # Phase 1 was skipped on purpose, so there is no brew output to point at.
  [[ $output != *"brew output above"* ]]
  [ ! -f "$DOT_CONFIG" ]
}

@test "doctor: with no config, says how to make one rather than crashing" {
  run "$DOT_ROOT/bin/dot" doctor
  [ "$status" -ne 0 ]
  [[ $output == *"dot config --init"* ]]
  [[ $output != *dasel* ]]
}

@test "apply: ends by running the doctor checks against what it produced" {
  # The whole point of the pass: "Done." must mean "I looked", not "nothing
  # threw while I worked".
  config_generate "A" "a@b.c" ""
  mkdir -p "$DOT_TMP/stub"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$DOT_TMP/stub/brew"
  chmod +x "$DOT_TMP/stub/brew"

  run env PATH="$DOT_TMP/stub:$HOME/.local/bin:$PATH" "$DOT_ROOT/bin/dot" apply
  [ "$status" -eq 0 ]
  says orphans "none"
  says dot 'installed'
}

@test "apply: a machine the checks reject does not report success" {
  # Same run, with the shim unreachable. The work all succeeded; the machine
  # is still wrong, and the exit status has to say so.
  config_generate "A" "a@b.c" ""
  mkdir -p "$DOT_TMP/stub"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$DOT_TMP/stub/brew"
  chmod +x "$DOT_TMP/stub/brew"

  run env PATH="$DOT_TMP/stub:$PATH" "$DOT_ROOT/bin/dot" apply
  [ "$status" -ne 0 ]
  [[ $output == *problem* ]]
}

@test "apply: a dry run does not run the checks" {
  # They would report the drift the run deliberately did not fix.
  config_generate "A" "a@b.c" ""

  dot apply --dry-run
  [ "$status" -eq 0 ]
  [[ $output != *"Orphaned links"* ]]
}

@test "doctor: an orphan is attributed, and sent to the module's remove.sh" {
  # The links are all that is left mentioning a module you switched off, and
  # they are not the whole of what it left. Asserted first, or a git that lost
  # its remove.sh would make this pass over nothing.
  [ -f "$DOT_ROOT/modules/git/remove.sh" ]

  config_generate "A" "a@b.c" ""
  pass_core_checks

  mkdir -p "$HOME/.config/git"
  ln -s "$DOT_ROOT/modules/git/home/.config/git/ignore" "$HOME/.config/git/ignore"

  run "$DOT_ROOT/bin/dot" doctor

  [[ $output == *"git is not enabled"* ]]
  [[ $output == *"modules/git/remove.sh"* ]]
  [ "$status" -eq 0 ]
}

@test "doctor: a module with no remove.sh is not sent to one" {
  # Naming a hook that is not there sends you to a file that does not exist.
  # Asserted, not skipped: a cmux that gains one makes this the wrong module.
  [ ! -f "$DOT_ROOT/modules/cmux/remove.sh" ]

  config_generate "A" "a@b.c" ""
  pass_core_checks

  mkdir -p "$HOME/.config/cmux"
  ln -s "$DOT_ROOT/modules/cmux/home/.config/cmux/cmux.json" \
    "$HOME/.config/cmux/cmux.json"

  run "$DOT_ROOT/bin/dot" doctor

  [[ $output == *"cmux is not enabled"* ]]
  [[ $output == *"nothing else behind"* ]]
  [[ $output != *"remove.sh"* ]]
}

# --- add / remove -----------------------------------------------------------
#
# The verbs that switch a module off. `remove` is the one that had no path at
# all before, so most of this is about it doing the whole job -- and about
# --dry-run doing none of it.

# A config listing one module, in the shape config_generate writes.
listing() {
  printf 'schema = 1\n\n[user]\nname = "A"\nemail = "a@b.c"\n\n[modules]\nenabled = [\n' \
    >"$DOT_CONFIG"
  local name
  for name in "$@"; do printf '  "%s",\n' "$name" >>"$DOT_CONFIG"; done
  printf ']\n' >>"$DOT_CONFIG"
}

# git as if apply had run: both links, plus the file only remove.sh can find.
staged_git() {
  mkdir -p "$HOME/.config/git"
  ln -s "$DOT_ROOT/modules/git/home/.config/git/config" "$HOME/.config/git/config"
  ln -s "$DOT_ROOT/modules/git/home/.config/git/ignore" "$HOME/.config/git/ignore"
  printf '# Generated by the git module.\n' >"$HOME/.config/git/config.local"
}

@test "remove: unlinks the module, runs its hook, and drops it from the list" {
  # The three halves of the job. config.local is the point: no symlink sweep
  # can see it, so only remove.sh running proves the hook was reached.
  listing git zsh
  pass_core_checks
  staged_git

  run "$DOT_ROOT/bin/dot" remove git
  [ "$status" -eq 0 ]

  [ ! -e "$HOME/.config/git/config" ]
  [ ! -e "$HOME/.config/git/ignore" ]
  [ ! -e "$HOME/.config/git/config.local" ]
  run cfg_list 'modules.enabled'
  [ "${#lines[@]}" -eq 1 ]
  [ "${lines[0]}" = "zsh" ]
}

@test "remove: --dry-run changes nothing at all" {
  listing git
  pass_core_checks
  staged_git

  local before after config_before
  before=$(home_snapshot)
  config_before=$(cat "$DOT_CONFIG")

  run "$DOT_ROOT/bin/dot" remove git --dry-run
  [ "$status" -eq 0 ]

  after=$(home_snapshot)
  [ "$before" = "$after" ]
  [ "$config_before" = "$(cat "$DOT_CONFIG")" ]
}

@test "remove: says the packages are staying, every time" {
  # "removed" reads as if they went too, and that is the one thing it does not
  # do. Said in the run itself, not only in the README.
  listing git
  pass_core_checks
  staged_git

  run "$DOT_ROOT/bin/dot" remove git
  says packages 'stay installed. Removing those is `brew uninstall`, yours to run.'
}

@test "remove: a module already out of the list is still swept" {
  # What a hand-edited config leaves behind, which is the state `doctor`
  # reports as orphaned links. The verb has to be able to finish that job.
  listing zsh
  pass_core_checks
  staged_git

  run "$DOT_ROOT/bin/dot" remove git
  [ "$status" -eq 0 ]
  [[ $output == *"not in the list"* ]]
  [ ! -e "$HOME/.config/git/config" ]
  [ ! -e "$HOME/.config/git/config.local" ]
}

@test "add: --dry-run neither writes the config nor links anything" {
  listing zsh
  pass_core_checks

  local before
  before=$(cat "$DOT_CONFIG")

  run "$DOT_ROOT/bin/dot" add git --dry-run
  [ "$status" -eq 0 ]
  [ "$before" = "$(cat "$DOT_CONFIG")" ]
  [ ! -e "$HOME/.config/git/config" ]
}

@test "add: puts the module in the list and links its files" {
  listing zsh
  pass_core_checks

  run "$DOT_ROOT/bin/dot" add git
  [ "$status" -eq 0 ]

  run cfg_list 'modules.enabled'
  [[ $output == *git* ]]
  [ -L "$HOME/.config/git/config" ]
}

@test "add and remove refuse a name that is not a module" {
  listing zsh
  pass_core_checks

  run "$DOT_ROOT/bin/dot" add frobnicate
  [ "$status" -ne 0 ]
  [[ $output == *"no module 'frobnicate'"* ]]
  [[ $output == *available* ]]

  run "$DOT_ROOT/bin/dot" remove frobnicate
  [ "$status" -ne 0 ]
}

@test "add and remove refuse an array they cannot edit safely" {
  # Checked BEFORE anything is touched: unlinking and then failing to update
  # the list would leave the machine and the file disagreeing.
  printf 'schema = 1\n\n[modules]\nenabled = ["git"]\n' >"$DOT_CONFIG"
  pass_core_checks
  staged_git

  run "$DOT_ROOT/bin/dot" remove git
  [ "$status" -ne 0 ]
  [[ $output == *"edit it by hand"* ]]
  # Nothing was swept on the way to that refusal.
  [ -L "$HOME/.config/git/config" ]
}

@test "add: one module at a time, and a mistyped flag is fatal" {
  listing zsh
  pass_core_checks

  run "$DOT_ROOT/bin/dot" add git zsh
  [ "$status" -ne 0 ]
  [[ $output == *"one module at a time"* ]]

  run "$DOT_ROOT/bin/dot" remove git --dry
  [ "$status" -ne 0 ]
  [[ $output == *"unknown option '--dry'"* ]]

  run "$DOT_ROOT/bin/dot" add
  [ "$status" -ne 0 ]
  [[ $output == *"which module?"* ]]
}

@test "add and remove refuse a config that does not parse" {
  # dasel stops at a malformed line and exits 0, so `enabled` can read empty on
  # a file that is merely truncated. Splicing a line into that loses the rest.
  printf 'schema = 1\n\n[modules]\nenabled = [\n  "git",\n]\n\n[settings\n' \
    >"$DOT_CONFIG"
  pass_core_checks

  run "$DOT_ROOT/bin/dot" add zsh
  [ "$status" -ne 0 ]
  [[ $output == *"did not parse"* ]]

  run "$DOT_ROOT/bin/dot" remove git
  [ "$status" -ne 0 ]
  [[ $output == *"did not parse"* ]]
}

# --- The transcript ---------------------------------------------------------

@test "logs: every verb that changes the machine writes one, named for it" {
  # The name is the point: twenty bare timestamps cannot tell you which one was
  # the apply that broke something.
  listing zsh
  pass_core_checks
  staged_git

  "$DOT_ROOT/bin/dot" add git >/dev/null 2>&1
  "$DOT_ROOT/bin/dot" remove git >/dev/null 2>&1

  [ -f "$DOT_STATE/logs/$DOT_RUN_ID-add.log" ]
  [ -f "$DOT_STATE/logs/$DOT_RUN_ID-remove.log" ]
  # And it holds the run, not just its name.
  [[ $(cat "$DOT_STATE/logs/$DOT_RUN_ID-remove.log") == *"1 module"* ]]
}

@test "logs: the two read-only verbs write none" {
  # Not style. `config` hands the terminal to \$EDITOR and a tee in the way
  # makes vi unusable; `doctor` is advertised read-only and also runs as the
  # tail of `apply`, where a second transcript would nest inside the first.
  listing zsh
  pass_core_checks

  run "$DOT_ROOT/bin/dot" doctor
  [ ! -d "$DOT_STATE/logs" ]

  EDITOR=true run "$DOT_ROOT/bin/dot" config
  [ ! -d "$DOT_STATE/logs" ]
}

@test "logs: a dry run of any verb writes none" {
  listing git
  pass_core_checks
  staged_git

  "$DOT_ROOT/bin/dot" add zsh --dry-run >/dev/null 2>&1
  "$DOT_ROOT/bin/dot" remove git --dry-run >/dev/null 2>&1

  [ ! -d "$DOT_STATE/logs" ]
}

@test "logs: the twenty kept are counted across verbs, not per verb" {
  # One budget for the directory. A burst of `dot add` evicting the apply log
  # is the trade; twenty runs of anything is the policy.
  listing zsh
  pass_core_checks
  mkdir -p "$DOT_STATE/logs"
  local i
  for i in $(seq -w 1 25); do
    printf 'old\n' >"$DOT_STATE/logs/00000000-0000$i-apply.log"
  done

  "$DOT_ROOT/bin/dot" add git >/dev/null 2>&1

  local kept
  kept=$(find "$DOT_STATE/logs" -name '*.log' | wc -l | tr -d ' ')
  [ "$kept" -eq 20 ]
  [ -f "$DOT_STATE/logs/$DOT_RUN_ID-add.log" ]
}
