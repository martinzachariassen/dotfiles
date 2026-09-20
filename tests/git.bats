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
  ALLOW="$HOME/.config/git/allowed_signers"

  # Real keypairs, because the allowed_signers test signs and verifies for
  # real. A made-up "ssh-ed25519 AAAAKEY" can only ever prove that a string
  # was copied from one file to another, and the format is the whole point.
  ssh-keygen -q -t ed25519 -C '' -N '' -f "$DOT_TMP/id"
  ssh-keygen -q -t ed25519 -C '' -N '' -f "$DOT_TMP/other"
  KEY=$(cut -d' ' -f1,2 <"$DOT_TMP/id.pub")
  OTHER_KEY=$(cut -d' ' -f1,2 <"$DOT_TMP/other.pub")
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

doctor() {
  run env DOT_ROOT="$DOT_ROOT" HOME="$HOME" \
    XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.local/state" \
    DOT_CONFIG="$DOT_CONFIG" DOT_STATE="$DOT_STATE" DOT_DRY_RUN=0 \
    "$BASH" "$DOT_ROOT/modules/git/doctor.sh"
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

# --- allowed_signers ---------------------------------------------------------
#
# Signing and verifying are two settings, and only the first was ever written.
# The failure is quiet in the worst way: every commit carries a signature and
# `git log --show-signature` reports "No signature", so a repo full of signed
# commits reads as a repo with none.

@test "verify: a real signature verifies against the file apply wrote" {
  # The round trip, with ssh-keygen doing exactly what git shells out to do.
  # Anything weaker only proves a string was copied between two files, and the
  # bug this closes was never about the string -- it was about there being no
  # file for ssh-keygen to check the key against at all.
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
  # The guard on the guard. A file ssh-keygen merely parses would pass the
  # test above even if it named the wrong key, and an allowed_signers that
  # accepts anything is worse than none.
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
  # git run from a GUI inherits no shell and expands no ~.
  [[ $(gitcfg gpg.ssh.allowedSignersFile) == /* ]]
}

@test "verify: no signer means no signing, and so nothing to verify with" {
  # The file would name a key nothing can sign with. All of it or none.
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply 0 "$DOT_TMP/not-installed"
  [ ! -e "$ALLOW" ]
  run gitcfg gpg.ssh.allowedSignersFile
  [ "$status" -ne 0 ]
}

@test "verify: a signingkey that is a path is refused, not written out" {
  # git accepts a path in user.signingkey. An allowed_signers line holding one
  # is a file ssh-keygen cannot read, which git reports as a verification
  # failure rather than as the bad config it is.
  with_config 'Ada' 'ada@example.com' '~/.ssh/id_ed25519.pub'
  apply
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [ ! -e "$ALLOW" ]
  # Signing itself still stands: only the verification half is refused.
  [ "$(gitcfg commit.gpgsign)" = 'true' ]
  run gitcfg gpg.ssh.allowedSignersFile
  [ "$status" -ne 0 ]
}

@test "verify: the key changing in config.toml rewrites the file" {
  # config.local and allowed_signers must not drift apart: one names a key and
  # the other decides whose signatures count.
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  rm -f "$DOT_CONFIG"
  with_config 'Ada' 'ada@example.com' "$OTHER_KEY"
  apply
  [ "$(grep -v '^#' "$ALLOW")" = "ada@example.com $OTHER_KEY" ]
  [ "$(grep -c . "$ALLOW")" -eq 3 ]
}

# --- doctor -----------------------------------------------------------------
#
# The half the generator cannot speak for. config.local is generated, so
# fs_check_tree never sees it, and a verification that is off has no symptom
# at all beyond `git log --show-signature` answering "No signature" for a
# commit that carries one.

@test "doctor: an apply that wrote both files is green on both counts" {
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  doctor
  [ "$status" -eq 0 ]
  says git 'commit signing configured'
  says git 'signatures can be verified'
}

@test "doctor: signing with nothing to verify it is a warning" {
  # config.local from before allowed_signers existed: signing on, no pointer.
  # `dot apply` is the whole fix, which is what makes naming it right here.
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  git config --file "$DEST" --unset gpg.ssh.allowedSignersFile
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"nothing verifies it"* ]]
  [[ $output == *"dot apply"* ]]
}

@test "doctor: a signingkey that is a path names the cause, not a command" {
  # The one branch that must NOT say "run: dot apply". apply.sh refuses this
  # key on purpose, so that advice is a yellow line that stays yellow with a
  # command that changes nothing -- the same bug as a summary green on a
  # broken machine, and the reason doctor repeats apply's words instead.
  with_config 'Ada' 'ada@example.com' '~/.ssh/id_ed25519.pub'
  apply
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"not a literal public key"* ]]
  [[ $output != *"dot apply"* ]]
}

@test "doctor: apply and doctor test the key's shape with one literal" {
  # Two hooks, one rule. Drift here is invisible until it produces exactly the
  # loop above: doctor sending you to an apply that refuses.
  local a d
  a=$(sed -n 's/^[[:space:]]*//; /signingkey == ssh-/p' "$DOT_ROOT/modules/git/apply.sh")
  d=$(sed -n 's/^[[:space:]]*//; /signingkey == ssh-/p' "$DOT_ROOT/modules/git/doctor.sh")
  [ -n "$a" ]
  [ "$a" = "$d" ]
}

@test "doctor: an allowedSignersFile pointing at nothing is a failure" {
  # Not a warning: git cannot verify anything at all, and unlike the cases
  # above the file was promised by config.local itself.
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  rm -f "$ALLOW"
  doctor
  [ "$status" -eq 1 ]
  [[ $output == *"missing file"* ]]
}

@test "doctor: a file that does not hold the configured key is drift" {
  # The key rotated in config.toml and apply never ran: every commit is signed
  # with a key the file does not name, and every one of them fails to verify.
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  printf '# Generated by the git module.\nada@example.com %s\n' "$OTHER_KEY" >"$ALLOW"
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"does not hold the key"* ]]
}

@test "doctor: no signingkey at all asks nothing about verification" {
  # A machine that does not sign must not be told its signatures are unusable.
  with_config 'Ada' 'ada@example.com'
  apply
  doctor
  [ "$status" -eq 0 ]
  [[ $output != *"verif"* ]]
}

@test "doctor: writes nothing" {
  # Read-only, like every doctor. It reads two files apply generated.
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  local before
  before=$(home_snapshot)
  doctor
  [ "$(home_snapshot)" = "$before" ]
}

# --- dry run ----------------------------------------------------------------

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
  # The signing decision settles which files get written, so it has to be made
  # before the preview prints -- a dry run that announces a file the real run
  # then skips is the one thing --dry-run may not do.
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply 1 "$DOT_TMP/not-installed"
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"1Password"* ]]
  [[ $output != *"allowed_signers"* ]]
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

@test "remove: takes back allowed_signers too, not just config.local" {
  # Two generated files now, and the sweep sees neither: both are written, not
  # linked. A second file added to apply.sh and not to remove.sh is a file left
  # behind that nothing in the repo would ever mention again.
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
  # The header is the entire proof that this repo wrote config.local. Reword it
  # in apply.sh alone and remove.sh stops taking back its own file, silently.
  # The literal is read out of remove.sh so this test is not a third copy.
  local literal
  literal=$(sed -n "s/.*grep -q '\(.*\)' \"\$dest\".*/\1/p" "$DOT_ROOT/modules/git/remove.sh")
  [ -n "$literal" ]

  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  grep -qF "$literal" "$DEST"
  # Both generated files carry it, because remove.sh greps both with the one
  # literal above. A header on only one of them is the other left behind.
  grep -qF "$literal" "$ALLOW"

  # apply.sh greps for it too, to recognise a stale allowed_signers as its own.
  # A third spelling would make it walk past the file it wrote itself.
  grep -qF "grep -q '$literal'" "$DOT_ROOT/modules/git/apply.sh"
}

@test "verify: a key that stops being a literal takes its file with it" {
  # Switching signingkey to a path leaves config.local pointing at nothing, and
  # the old allowed_signers on disk naming a key nothing refers to any more. No
  # fault -- nothing reads it -- but a generated file this repo has stopped
  # accounting for is one only uninstall.sh would ever find again.
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
  # Same proof of ownership as remove.sh needs. A conventional name may well
  # predate this module, and apply is no more entitled to it than remove is.
  mkdir -p "$(dirname "$ALLOW")"
  printf 'someone@else.com ssh-ed25519 AAAATHEIRS\n' >"$ALLOW"
  with_config 'Ada' 'ada@example.com' '~/.ssh/id_ed25519.pub'
  apply
  [ -f "$ALLOW" ]
  [ "$(cat "$ALLOW")" = 'someone@else.com ssh-ed25519 AAAATHEIRS' ]
}

@test "verify: a hand-written allowed_signers is not truncated by a run" {
  # The file this module generates and the file a git user has kept for years
  # share a conventional path. Writing over it is the wholesale rewrite of
  # someone else's file the root CLAUDE.md forbids -- and remove.sh already
  # refuses the same file, so apply doing it was the two halves disagreeing.
  mkdir -p "$(dirname "$ALLOW")"
  printf 'someone@else.com %s\n' "$OTHER_KEY" >"$ALLOW"
  local before
  before=$(cat "$ALLOW")

  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  [ "$(cat "$ALLOW")" = "$before" ]
  [[ $output == *"not generated by this repo"* ]]
  # Signing still stands, and git is still pointed at the file: reading one
  # somebody else maintains costs nothing, and doctor says whether it works.
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
  # And never announces a write it would not make.
  [[ $output != *"write"*"allowed_signers"* ]]
  [ "$(home_snapshot)" = "$before" ]
}

@test "doctor: a file this repo did not write, holding the key, verifies" {
  # Not a finding at all. The user's own file names the key git signs with, so
  # `git log --show-signature` works -- which is the only thing being asked.
  mkdir -p "$(dirname "$ALLOW")"
  printf 'ada@example.com %s\n' "$KEY" >"$ALLOW"
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  doctor
  [ "$status" -eq 0 ]
  says git 'signatures can be verified'
}

@test "doctor: a file this repo did not write names the cause, not a command" {
  # apply.sh will not touch it, so sending the reader to `dot apply` is a line
  # that stays yellow forever -- the same rule as the path-shaped signingkey.
  mkdir -p "$(dirname "$ALLOW")"
  printf 'someone@else.com %s\n' "$OTHER_KEY" >"$ALLOW"
  with_config 'Ada' 'ada@example.com' "$KEY"
  apply
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"did not write it"* ]]
  # The bare "-- run: dot apply" of the generated-file branch is the line that
  # would change nothing here. Advice that first moves the file aside is not.
  [[ $output != *"-- run: dot apply"* ]]
  [[ $output == *"move it aside"* ]]
}

@test "doctor: a commented-out record is not verification" {
  # ssh-keygen ignores the line, so git does too. A substring search does not,
  # and would call a machine that cannot verify a single commit healthy.
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
  # allowed_signers puts optional flags between the principals and the key.
  # Matching the key as a field PAIR rather than by position is what keeps a
  # real-world file from reading as drift.
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
