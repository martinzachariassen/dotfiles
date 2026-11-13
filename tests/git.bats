#!/usr/bin/env bats

load helper

setup() {
  setup_sandbox

  OPSIGN="$DOT_TMP/op-ssh-sign"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$OPSIGN"
  chmod +x "$OPSIGN"

  DEST="$HOME/.config/git/config.local"
  ALLOW="$HOME/.config/git/allowed_signers"

  ssh-keygen -q -t ed25519 -C '' -N '' -f "$DOT_TMP/id"
  ssh-keygen -q -t ed25519 -C '' -N '' -f "$DOT_TMP/other"
  KEY=$(cut -d' ' -f1,2 <"$DOT_TMP/id.pub")
  OTHER_KEY=$(cut -d' ' -f1,2 <"$DOT_TMP/other.pub")
}

teardown() { teardown_sandbox; }

with_config() { config_generate "$1" "$2" 'git' "${3:-}" >/dev/null; }

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

doctor() {
  run env DOT_ROOT="$DOT_ROOT" HOME="$HOME" \
    XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.local/state" \
    DOT_CONFIG="$DOT_CONFIG" DOT_STATE="$DOT_STATE" DOT_DRY_RUN=0 \
    "$BASH" "$DOT_ROOT/modules/git/doctor.sh"
}

gitcfg() { git config --file "$DEST" --get "$1"; }

@test "identity: name and email reach the file git will read" {
  with_config 'Ada Lovelace' 'ada@example.com'
  apply
  [ "$status" -eq 0 ]
  [ "$(gitcfg user.name)" = 'Ada Lovelace' ]
  [ "$(gitcfg user.email)" = 'ada@example.com' ]
}

@test "identity: a name containing # and a quote survives git's parser" {
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

@test "signing: a key and a signer write the whole block" {
  with_config 'Ada' 'ada@example.com' 'ssh-ed25519 AAAAKEY'
  apply
  [ "$status" -eq 0 ]
  [ "$(gitcfg user.signingkey)" = 'ssh-ed25519 AAAAKEY' ]
  [ "$(gitcfg gpg.format)" = 'ssh' ]
  [ "$(gitcfg commit.gpgsign)" = 'true' ]
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
  with_config 'Ada' 'ada@example.com' 'ssh-ed25519 AAAAKEY'
  apply 0 "$DOT_TMP/not-installed"
  run git config --file "$DEST" --list
  [ "$status" -eq 0 ]
}

@test "editor: written only when VS Code is installed, with an absolute path" {
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

@test "verify: a real signature verifies against the file apply wrote" {
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  [ "$status" -eq 0 ]
  [ -f "$ALLOW" ]

  printf 'a commit object\n' >"$DOT_TMP/payload"
  ssh-keygen -Y sign -q -f "$DOT_TMP/id" -n git "$DOT_TMP/payload"

  run ssh-keygen -Y verify -f "$ALLOW" -I 'ada@example.com' -n git \
    -s "$DOT_TMP/payload.sig" <"$DOT_TMP/payload"
  [ "$status" -eq 0 ]
}

@test "verify: a signature from another key does NOT verify" {
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply

  printf 'a commit object\n' >"$DOT_TMP/payload"
  ssh-keygen -Y sign -q -f "$DOT_TMP/other" -n git "$DOT_TMP/payload"

  run ssh-keygen -Y verify -f "$ALLOW" -I 'ada@example.com' -n git \
    -s "$DOT_TMP/payload.sig" <"$DOT_TMP/payload"
  [ "$status" -ne 0 ]
}

@test "verify: the principal is the identity, so the file names one signer" {
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  [ "$(grep -v '^#' "$ALLOW")" = "ada@example.com $KEY" ]
}

@test "verify: config.local points git at that file, absolutely" {
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  [ "$(gitcfg gpg.ssh.allowedSignersFile)" = "$ALLOW" ]
  [[ $(gitcfg gpg.ssh.allowedSignersFile) == /* ]]
}

@test "verify: no signer means no signing, and so nothing to verify with" {
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply 0 "$DOT_TMP/not-installed"
  [ ! -e "$ALLOW" ]
  run gitcfg gpg.ssh.allowedSignersFile
  [ "$status" -ne 0 ]
}

@test "verify: a signingkey that is a path is refused, not written out" {
  with_config 'Ada' 'ada@example.com' '~/.ssh/id_ed25519.pub'
  apply
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [ ! -e "$ALLOW" ]
  [ "$(gitcfg commit.gpgsign)" = 'true' ]
  run gitcfg gpg.ssh.allowedSignersFile
  [ "$status" -ne 0 ]
}

@test "verify: the key changing in config.toml rewrites the file" {
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  rm -f "$DOT_CONFIG"
  with_config 'Ada' 'ada@example.com' "$OTHER_KEY"
  apply
  [ "$(grep -v '^#' "$ALLOW")" = "ada@example.com $OTHER_KEY" ]
  [ "$(grep -c . "$ALLOW")" -eq 3 ]
}

@test "doctor: an apply that wrote both files is green on both counts" {
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  doctor
  [ "$status" -eq 0 ]
  says git 'commit signing configured'
  says git 'signatures can be verified'
}

@test "doctor: signing with nothing to verify it is a warning" {
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  git config --file "$DEST" --unset gpg.ssh.allowedSignersFile
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"nothing verifies it"* ]]
  [[ $output == *"dot apply"* ]]
}

@test "doctor: a signingkey that is a path names the cause, not a command" {
  with_config 'Ada' 'ada@example.com' '~/.ssh/id_ed25519.pub'
  apply
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"not a literal public key"* ]]
  [[ $output != *"dot apply"* ]]
}

@test "doctor: apply and doctor test the key's shape with one literal" {
  local a d
  a=$(sed -n 's/^[[:space:]]*//; /signingkey == ssh-/p' "$DOT_ROOT/modules/git/apply.sh")
  d=$(sed -n 's/^[[:space:]]*//; /signingkey == ssh-/p' "$DOT_ROOT/modules/git/doctor.sh")
  [ -n "$a" ]
  [ "$a" = "$d" ]
}

@test "doctor: an allowedSignersFile pointing at nothing is a failure" {
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  rm -f "$ALLOW"
  doctor
  [ "$status" -eq 1 ]
  [[ $output == *"missing file"* ]]
}

@test "doctor: a file that does not hold the configured key is drift" {
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  printf '# Generated by the git module.\nada@example.com %s\n' "$OTHER_KEY" >"$ALLOW"
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"does not hold the key"* ]]
}

@test "doctor: no signingkey at all asks nothing about verification" {
  with_config 'Ada' 'ada@example.com'
  apply
  doctor
  [ "$status" -eq 0 ]
  [[ $output != *"verif"* ]]
}

@test "doctor: writes nothing" {
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  local before
  before=$(home_snapshot)
  doctor
  [ "$(home_snapshot)" = "$before" ]
}

@test "dry run: announces both writes and makes neither" {
  with_config 'Ada' 'ada@example.com' "$KEY"
  local before
  before=$(home_snapshot)
  apply 1
  [ "$status" -eq 0 ]
  [[ $output == *"config.local"* ]]
  [[ $output == *"allowed_signers"* ]]
  [ "$(home_snapshot)" = "$before" ]
}

@test "dry run: says the same words as the run it previews" {
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply 1 "$DOT_TMP/not-installed"
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"1Password"* ]]
  [[ $output != *"allowed_signers"* ]]
}

@test "remove: takes back the file apply generated" {
  with_config 'Ada' 'ada@example.com'
  apply
  [ -f "$DEST" ]
  remove
  [ "$status" -eq 0 ]
  [ ! -e "$DEST" ]
}

@test "remove: takes back allowed_signers too, not just config.local" {
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  [ -f "$ALLOW" ]
  remove
  [ "$status" -eq 0 ]
  [ ! -e "$ALLOW" ]
}

@test "remove: leaves an allowed_signers this repo did not write" {
  mkdir -p "$(dirname "$ALLOW")"
  printf 'someone@else.com ssh-ed25519 AAAATHEIRS\n' >"$ALLOW"
  remove
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [ -f "$ALLOW" ]
}

@test "remove: leaves a config.local this repo did not write" {
  mkdir -p "$(dirname "$DEST")"
  printf '[user]\n\tname = Someone Else\n' >"$DEST"
  remove
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [ "$(git config --file "$DEST" --get user.name)" = 'Someone Else' ]
}

@test "remove: the ownership header it greps for is the one apply.sh writes" {
  local literal
  literal=$(sed -n "s/.*grep -q '\(.*\)' \"\$dest\".*/\1/p" "$DOT_ROOT/modules/git/remove.sh")
  [ -n "$literal" ]

  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  grep -qF "$literal" "$DEST"
  grep -qF "$literal" "$ALLOW"

  grep -qF "grep -q '$literal'" "$DOT_ROOT/modules/git/apply.sh"
}

@test "verify: a key that stops being a literal takes its file with it" {
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  [ -f "$ALLOW" ]

  rm -f "$DOT_CONFIG"
  with_config 'Ada' 'ada@example.com' '~/.ssh/id_ed25519.pub'
  apply
  [ ! -e "$ALLOW" ]
  [[ $output == *"remove"* ]]
}

@test "verify: an allowed_signers this repo did not write is not swept up" {
  mkdir -p "$(dirname "$ALLOW")"
  printf 'someone@else.com ssh-ed25519 AAAATHEIRS\n' >"$ALLOW"
  with_config 'Ada' 'ada@example.com' '~/.ssh/id_ed25519.pub'
  apply
  [ -f "$ALLOW" ]
  [ "$(cat "$ALLOW")" = 'someone@else.com ssh-ed25519 AAAATHEIRS' ]
}

@test "verify: a hand-written allowed_signers is not truncated by a run" {
  mkdir -p "$(dirname "$ALLOW")"
  printf 'someone@else.com %s\n' "$OTHER_KEY" >"$ALLOW"
  local before
  before=$(cat "$ALLOW")

  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  [ "$(cat "$ALLOW")" = "$before" ]
  [[ $output == *"not generated by this repo"* ]]
  [ "$(gitcfg commit.gpgsign)" = 'true' ]
  [ "$(gitcfg gpg.ssh.allowedSignersFile)" = "$ALLOW" ]
}

@test "verify: a dry run says the same about a file it will not write" {
  mkdir -p "$(dirname "$ALLOW")"
  printf 'someone@else.com %s\n' "$OTHER_KEY" >"$ALLOW"
  with_config 'Ada' 'ada@example.com' "$KEY"

  local before
  before=$(home_snapshot)
  apply 1
  [[ $output == *"not generated by this repo"* ]]
  [[ $output != *"write"*"allowed_signers"* ]]
  [ "$(home_snapshot)" = "$before" ]
}

@test "doctor: a file this repo did not write, holding the key, verifies" {
  mkdir -p "$(dirname "$ALLOW")"
  printf 'ada@example.com %s\n' "$KEY" >"$ALLOW"
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  doctor
  [ "$status" -eq 0 ]
  says git 'signatures can be verified'
}

@test "doctor: a file this repo did not write names the cause, not a command" {
  mkdir -p "$(dirname "$ALLOW")"
  printf 'someone@else.com %s\n' "$OTHER_KEY" >"$ALLOW"
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"did not write it"* ]]
  [[ $output != *"-- run: dot apply"* ]]
  [[ $output == *"move it aside"* ]]
}

@test "doctor: a commented-out record is not verification" {
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  printf '# Generated by the git module.\n#ada@example.com %s\n' "$KEY" >"$ALLOW"
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"does not hold the key"* ]]
}

@test "doctor: the key inside a comment on another line is not it either" {
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  {
    printf '# Generated by the git module.\n'
    printf '# rotated away from: %s\n' "$KEY"
    printf 'ada@example.com %s\n' "$OTHER_KEY"
  } >"$ALLOW"
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"does not hold the key"* ]]
}

@test "doctor: a record carrying options still counts" {
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  printf '# Generated by the git module.\nada@example.com namespaces="git" %s\n' \
    "$KEY" >"$ALLOW"
  doctor
  [ "$status" -eq 0 ]
  says git 'signatures can be verified'
}

@test "verify: a dry run announces the stale file and keeps it" {
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  rm -f "$DOT_CONFIG"
  with_config 'Ada' 'ada@example.com' '~/.ssh/id_ed25519.pub'

  local before
  before=$(home_snapshot)
  apply 1
  [[ $output == *"remove"* ]]
  [ "$(home_snapshot)" = "$before" ]
}
