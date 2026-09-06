#!/usr/bin/env bats
#
# modules/git/apply.sh -- the one module that GENERATES a file. Nothing but
# this stands between a quoting bug and a git identity that is not yours.

load helper

setup() {
  setup_sandbox

  # Stand-in for 1Password's signer, which lives inside an .app bundle.
  OPSIGN="$DOT_TMP/op-ssh-sign"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$OPSIGN"
  chmod +x "$OPSIGN"

  DEST="$HOME/.config/git/config.local"
}

teardown() { teardown_sandbox; }

# The real chain: on a first run these values come through config_generate,
# whose quoting is under test here.
with_config() { config_generate "$1" "$2" 'git' "${3:-}" >/dev/null; }

# apply [DRY_RUN] [SIGNER] [CODE] -- unset SIGNER means the stub; unset CODE
# means "not installed". Pass a missing path to model a machine without the app.
apply() {
  run env DOT_ROOT="$DOT_ROOT" HOME="$HOME" \
    XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.local/state" \
    DOT_CONFIG="$DOT_CONFIG" DOT_STATE="$DOT_STATE" DOT_DRY_RUN="${1:-0}" \
    DOT_OP_SSH_SIGN="${2-$OPSIGN}" DOT_CODE_BIN="${3-$DOT_TMP/not-installed}" \
    "$BASH" "$DOT_ROOT/modules/git/apply.sh"
}

remove() {
  run env DOT_ROOT="$DOT_ROOT" HOME="$HOME" DOT_CONFIG="$DOT_CONFIG" \
    DOT_STATE="$DOT_STATE" DOT_DRY_RUN=0 \
    "$BASH" "$DOT_ROOT/modules/git/remove.sh"
}

# Ask git, not grep: what matters is the value git PARSES back out.
gitcfg() { git config --file "$DEST" --get "$1"; }

# --- identity ---------------------------------------------------------------

@test "identity: name and email reach the file git will read" {
  with_config 'Ada Lovelace' 'ada@example.com'
  apply
  [ "$status" -eq 0 ]
  [ "$(gitcfg user.name)" = 'Ada Lovelace' ]
  [ "$(gitcfg user.email)" = 'ada@example.com' ]
}

@test "identity: a name containing # and a quote survives git's parser" {
  # Unquoted, `#` starts a comment and a bare `"` is stripped -- silently.
  with_config 'Martin # "Zach" \ Z' 'm@example.com'
  apply
  [ "$status" -eq 0 ]
  [ "$(gitcfg user.name)" = 'Martin # "Zach" \ Z' ]
}

@test "identity: an empty one warns and writes no file at all" {
  printf 'schema = 1\n\n[user]\nname  = ""\nemail = ""\n\n[modules]\nenabled = ["git"]\n' \
    >"$DOT_CONFIG"
  apply
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"user.name"* ]]
  [ ! -e "$DEST" ]
}

# --- signing ----------------------------------------------------------------

@test "signing: a key and a signer write the whole block" {
  with_config 'Ada' 'ada@example.com' 'ssh-ed25519 AAAAKEY'
  apply
  [ "$status" -eq 0 ]
  [ "$(gitcfg user.signingkey)" = 'ssh-ed25519 AAAAKEY' ]
  [ "$(gitcfg gpg.format)" = 'ssh' ]
  [ "$(gitcfg commit.gpgsign)" = 'true' ]
  # Without this git falls back to `ssh-keygen -Y sign`, which never reads
  # ~/.ssh/config, and every commit dies on `No private key found`.
  [ "$(gitcfg gpg.ssh.program)" = "$OPSIGN" ]
}

@test "signing: no signer disables signing instead of breaking every commit" {
  with_config 'Ada' 'ada@example.com' 'ssh-ed25519 AAAAKEY'
  apply 0 "$DOT_TMP/not-installed"

  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"1Password"* ]]

  run gitcfg commit.gpgsign
  [ "$status" -ne 0 ]
  run gitcfg gpg.format
  [ "$status" -ne 0 ]
  run gitcfg gpg.ssh.program
  [ "$status" -ne 0 ]

  [ "$(git config --file "$DEST" --get user.name)" = 'Ada' ]
}

@test "signing: no key means no signing block, and nothing to warn about" {
  with_config 'Ada' 'ada@example.com'
  apply
  [ "$status" -eq 0 ]
  run gitcfg commit.gpgsign
  [ "$status" -ne 0 ]
}

@test "signing: an advisory never lands inside the generated file" {
  # stdout inside the generator block IS config.local; parsing the whole file
  # catches a misplaced `dim` generically.
  with_config 'Ada' 'ada@example.com' 'ssh-ed25519 AAAAKEY'
  apply 0 "$DOT_TMP/not-installed"
  run git config --file "$DEST" --list
  [ "$status" -eq 0 ]
}

# --- editor -----------------------------------------------------------------

@test "editor: written only when VS Code is installed, with an absolute path" {
  # git from a GUI inherits no shell PATH, and an editor that is not there
  # fails every commit -- the minimal profile has no apps module.
  with_config 'Ada' 'ada@example.com'
  apply
  [ "$status" -eq 0 ]
  run gitcfg core.editor
  [ "$status" -ne 0 ]

  local code="$DOT_TMP/code"
  printf '#!/usr/bin/env bash\n' >"$code"
  chmod +x "$code"
  apply 0 "$OPSIGN" "$code"
  [ "$status" -eq 0 ]
  [ "$(gitcfg core.editor)" = "$code --wait" ]
}

# --- dry run ----------------------------------------------------------------

@test "dry run: announces the write and makes none" {
  with_config 'Ada' 'ada@example.com' 'ssh-ed25519 AAAAKEY'
  local before
  before=$(home_snapshot)
  apply 1
  [ "$status" -eq 0 ]
  [[ $output == *"config.local"* ]]
  [ "$(home_snapshot)" = "$before" ]
}

# --- remove.sh --------------------------------------------------------------

@test "remove: takes back the file apply generated" {
  with_config 'Ada' 'ada@example.com'
  apply
  [ -f "$DEST" ]
  remove
  [ "$status" -eq 0 ]
  [ ! -e "$DEST" ]
}

@test "remove: leaves a config.local this repo did not write" {
  mkdir -p "$(dirname "$DEST")"
  printf '[user]\n\tname = Someone Else\n' >"$DEST"
  remove
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [ "$(git config --file "$DEST" --get user.name)" = 'Someone Else' ]
}

@test "remove: the ownership header it greps for is the one apply.sh writes" {
  # The header is the entire proof that this repo wrote config.local. Reword it
  # in apply.sh alone and remove.sh stops taking back its own file, silently.
  # The literal is read out of remove.sh so this test is not a third copy.
  local literal
  literal=$(sed -n "s/.*grep -q '\(.*\)' \"\$dest\".*/\1/p" "$DOT_ROOT/modules/git/remove.sh")
  [ -n "$literal" ]

  with_config 'Ada' 'ada@example.com'
  apply
  grep -qF "$literal" "$DEST"
}
