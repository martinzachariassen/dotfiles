#!/usr/bin/env bats
#
# modules/claude-code/home/.claude/hooks/git-guard.sh -- the PreToolUse hook
# that turns the skills' "never force-push, never --no-verify" from prose into
# a refusal. A guard that misses is invisible until the damage, and one that
# fires on ordinary work gets switched off, so both directions are pinned.

load helper

setup() {
  setup_sandbox
  SCRIPT="$DOT_ROOT/modules/claude-code/home/.claude/hooks/git-guard.sh"
  FEATURE="$DOT_TMP/feature"
  MAIN="$DOT_TMP/main"
  git init -q -b feat/x "$FEATURE"
  git init -q -b main "$MAIN"
}

teardown() { teardown_sandbox; }

# decide COMMAND [CWD] -- what Claude Code would be told: "deny", or nothing.
decide() {
  run "$BASH" -c 'jq -nc --arg c "$1" --arg d "$2" "{tool_input: {command: \$c}, cwd: \$d}" | "$3"' \
    _ "$1" "${2:-$FEATURE}" "$SCRIPT"
  [ "$status" -eq 0 ]
  decision=$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$output")
}

denied() {
  decide "$@"
  [ "$decision" = deny ] || {
    echo "not denied: $1"
    return 1
  }
  [[ $output == *git-guard:* ]]
}

allowed() {
  decide "$@"
  [ -z "$output" ] || {
    echo "denied: $1 -- $output"
    return 1
  }
}

@test "git-guard: every spelling of a force-push is denied" {
  denied 'git push --force'
  denied 'git push -f origin feat/x'
  # Combined short flags were the first miss: -[a-zA-Z]*f* needs a letter
  # before the f, so -f and -fu both slipped through.
  denied 'git push -fu origin feat/x'
  denied 'git push origin +feat/x'
  denied 'git -C . push --force'
  denied 'FOO=1 git push -f'
}

@test "git-guard: a guarded command later in a chain is still found" {
  denied 'cd sub && git push -f'
  denied 'make check; git push --force'
  denied '(git push -f)'
}

@test "git-guard: --force-with-lease and an ordinary push pass" {
  allowed 'git push --force-with-lease'
  allowed 'git push -u origin feat/x'
  allowed 'git push'
}

@test "git-guard: a push to main or master is denied, a tag push is not" {
  denied 'git push origin HEAD:main'
  denied 'git push origin refs/heads/master'
  denied 'git push origin main v1.0.0'
  allowed 'git push origin v1.0.0'
}

@test "git-guard: a bare push from main is denied, --tags from main is not" {
  denied 'git push' "$MAIN"
  # HEAD names the current branch, so on main it is a push to main.
  denied 'git push -u origin HEAD' "$MAIN"
  allowed 'git push --tags' "$MAIN"
}

@test "git-guard: --no-verify is denied on commit and push" {
  denied 'git commit --no-verify -m wip'
  denied 'git commit -n -m wip'
  denied 'git push --no-verify'
}

@test "git-guard: reset --hard and clean -f are denied, their safe forms pass" {
  denied 'git reset --hard'
  denied 'git reset --hard origin/main'
  denied 'git clean -fd'
  denied 'git clean --force'
  allowed 'git reset --soft HEAD~1'
  allowed 'git clean -n'
  allowed 'git clean -fdn'
}

@test "git-guard: quoted text and heredoc bodies are data, not commands" {
  # A commit message may name the very flags the guard refuses.
  allowed "git commit -m 'never use --no-verify'"
  allowed 'git commit -m "explain git push --force"'
  allowed "$(printf '%s\n' "git commit -F - <<'EOF'" 'fix: x' '' 'git push --force is banned' 'EOF')"
  allowed 'echo git push -f'
}

@test "git-guard: a call that is not a command, or not git, passes silently" {
  run "$BASH" -c 'printf "{}" | "$1"' _ "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  allowed 'rm -rf build'
  allowed 'gitk --all'
}
