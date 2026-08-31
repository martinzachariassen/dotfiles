# Development

Everything at the repo root is tooling chezmoi never deploys. Changes here run
the same quality gates twice: **pre-commit** locally before a commit lands,
and **CI** on every push. Both call the same scripts in
[`scripts/ci/`](../scripts/ci), so local and remote never diverge.

## Quality gates

| Gate | Tool / script | pre-commit | CI |
|---|---|:-:|:-:|
| Shell lint | `shellcheck --severity=error` | ✅ | ✅ |
| Shell format | `shfmt -i 4 -ci` (`-d` in CI) | ✅ | ✅ |
| Shell parse | `bash -n` / `zsh -n` | ✅ | ✅ |
| Spelling | `typos` (allowlist in [`.typos.toml`](../.typos.toml)) | ✅ | ✅ |
| Config validity | `scripts/ci/lint-config.sh` (every JSON/JSONC/TOML output parses) | ✅ | ✅ |
| Secret scan | `gitleaks dir` (no tokens/keys/credentials in the tree) | ✅ | ✅ |
| Workflow lint | `actionlint` (workflow YAML + embedded `run:` bash) | ✅ | ✅ |
| Workflow audit | `zizmor` (workflow security; `--offline` locally, online in CI) | ✅ | ✅ |
| Render matrix | `scripts/ci/render-check.sh` (`chezmoi apply --dry-run` across profile × modules) | | ✅ |
| Unit tests | `bats tests/` | | ✅ |
| Homebrew names | `scripts/ci/brew-resolve.sh` (macOS runner) | | ✅ |
| Homebrew bundle check (advisory only) | `scripts/ci/brew-check-modules.sh` (macOS runner, `continue-on-error`) | | ✅ |
| Conventional Commits | `scripts/ci/check-commit-msg.sh` (subject ≤ 72 chars) | ✅ (commit-msg) | ✅ (PR title) |

The CI job matrix lives in
[`.github/workflows/ci.yml`](../.github/workflows/ci.yml); the local hooks in
[`.pre-commit-config.yaml`](../.pre-commit-config.yaml). pre-commit is
installed automatically by the `run_onchange_after_02e-pre-commit-install`
hook (see [lifecycle.md](lifecycle.md)).

## Running the checks locally

```sh
# Lint + parse shell
# The file list comes from git, exactly as CI resolves it, so a script that
# moves between scripts/, core/ and features/ cannot drop out of linting.
git ls-files -z -- '*.sh' '*.bash' ':!:src/**' | xargs -0 shellcheck --severity=error --shell=bash
git ls-files -z -- '*.sh' '*.bash' ':!:src/**' | xargs -0 shfmt -d -i 4 -ci

# Run every bats suite — cross-cutting ones and each feature's own
bats -r tests/ features/

# Render every template across one profile × module set (dry-run)
PROFILE=personal MODULES=macApps,theme,jvmStack bash scripts/ci/render-check.sh "$PWD"

# Validate config outputs (JSON/JSONC/TOML)
bash scripts/ci/lint-config.sh "$PWD"

# Or just run the whole pre-commit set against everything
pre-commit run --all-files
```

## Tests

A suite lives with what it tests: [`features/<name>/tests/`](../features) for
anything one feature owns, [`tests/`](../tests) for what spans them. Together
they cover the data model and shell surface so a rename or drifted default fails
fast:

| Suite | Guards |
|---|---|
| `data-model.bats` | `[profileDefaults]` mirrors the `$defaults` blocks in `.chezmoi.toml.tmpl`. |
| `chezmoi-data.bats` / `chezmoi-scripts.bats` | The data readers and hook conventions. |
| `brewfile-contents.bats` | Brewfile tiers stay well-formed. |
| `features/brew/tests/tiers.bats` | `brew_active_files` picks the tiers this profile/module set actually uses, plus the machine-local overlay. |
| `features/adopt/tests/adopt.bats` | `chez adopt` writes to the right file, refuses what is not installed, and never writes twice. |
| `mise-config.bats` | The rendered mise config. |
| `wizard.bats` | The wizard's prompt tiers and flag mapping. |
| `shell-functions.bats` / `zshrc-wiring.bats` | The zsh verbs and their wiring. |
| `check-commit-msg.bats` / `semver.bats` | The corresponding helpers. |
| `lint-coverage.bats` | Every tracked `*.sh` outside `src/` is linted by both pre-commit and CI. |
| `bats-assertions.bats` | Every bare `[[ ]]` in the suite actually gates its test — see below. |

### Writing assertions

**On a Mac, a bare `[[ ]]` does not fail a bats test unless it is the last
statement in the body.** bats runs test bodies with errexit *off* and detects
failures with an **ERR trap**. The trap fires for `[ ]`, `false`, `grep -q` and
any helper function on every bash — but for `[[ ]]` the behaviour is
version-dependent:

| bash | ERR trap fires for `[[ ]]`? | Where you meet it |
|---|---|---|
| 3.2.57 | **no** | Apple's `/bin/bash` — what bats uses for test bodies on macOS |
| 4.4+ | yes | CI's ubuntu runner (bash 5) |

So 226 of this suite's 385 `[[ ]]` assertions were decorative **locally** while
gating correctly **on CI** — local green did not mean CI green, which is the
worst way for a pre-push check to be wrong. The explicit `|| return 1` makes the
two agree. `bats-assertions.bats` proves the mechanism in a few lines of bash,
asserting the version-appropriate answer rather than asking you to take it on
trust.

So every bare `[[ ]]` carries an explicit `|| return 1`:

```sh
[ "$status" -eq 1 ]                          # gates: [ ] is a builtin
[[ "$output" == *"missing"* ]] || return 1   # gates: explicitly
grep -q 'pattern' "$file"                    # gates: a command
```

The same reasoning is why `doctor.bats` and `mirror.bats` route negative
checks through a `no_match` helper: `! grep …` is exempt from failure detection,
but a function call is not.

**Local and CI differ in two ways that bite.** bats is 1.14 locally (brew) and
1.10 on CI (apt); bash is 3.2 locally (`/bin/bash`) and 5.x on CI. Consequences:

- 1.10 cannot run a bats file from inside another bats test — the child inherits
  the parent's state, its tests become `unknown test name`, and the run ends
  `Executed N instead of expected M`. Scrubbing `BATS_*` to isolate it breaks
  bats' own bootstrap, so just don't nest.
- bash 3.2 vs 5 changes ERR-trap behaviour, per the table above.

Check bats' **exit status** directly: `bats -r tests/ | grep 'not ok'` discards
it, and a run can fail with every individual test printing green. For anything
test-infrastructure-shaped, verify on Linux too —
`docker run --rm -v "$PWD:/w:ro" -w /w bats/bats:1.10.0 tests/<file>.bats`
covers the bash-5 side without installing anything.

## Conventions

- **Conventional Commits** for every commit *and* PR title:
  `<type>(<scope>): <subject>`, imperative, subject ≤ 72 chars.
- **Never commit secrets** — tokens, private keys, credentials, or signing
  material. Use placeholders or a secret-manager reference.
- Keep shell config plain zsh (no oh-my-zsh/prezto/zinit) and no
  language-runtime managers — runtimes are mise's job, global CLIs come from
  Homebrew. See [shell.md](shell.md).
- The full contributor rules are in [`../CLAUDE.md`](../CLAUDE.md), the
  single source of truth for this repo. Claude Code reads it natively;
  [`.github/copilot-instructions.md`](../.github/copilot-instructions.md) is
  a thin pointer to it for GitHub Copilot.
