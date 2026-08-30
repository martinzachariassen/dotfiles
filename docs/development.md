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
shellcheck --severity=error --shell=bash install.sh scripts/bin/*.sh scripts/ci/*.sh scripts/lib/*.sh
shfmt -d -i 4 -ci install.sh scripts/bin/*.sh scripts/ci/*.sh scripts/lib/*.sh

# Run every bats suite
bats tests/

# Render every template across one profile × module set (dry-run)
PROFILE=personal MODULES=macApps,theme,jvmStack bash scripts/ci/render-check.sh "$PWD"

# Validate config outputs (JSON/JSONC/TOML)
bash scripts/ci/lint-config.sh "$PWD"

# Or just run the whole pre-commit set against everything
pre-commit run --all-files
```

## Tests

The [`tests/`](../tests) bats suites cover the data model and shell surface
so a rename or drifted default fails fast:

| Suite | Guards |
|---|---|
| `data-model.bats` | `[profileDefaults]` mirrors the `$defaults` blocks in `.chezmoi.toml.tmpl`. |
| `chezmoi-data.bats` / `chezmoi-scripts.bats` | The data readers and hook conventions. |
| `brewfile-contents.bats` | Brewfile tiers stay well-formed. |
| `brewfiles-lib.bats` | `brew_active_files` picks the tiers this profile/module set actually uses. |
| `mise-config.bats` | The rendered mise config. |
| `wizard.bats` | The wizard's prompt tiers and flag mapping. |
| `shell-functions.bats` / `zshrc-wiring.bats` | The zsh verbs and their wiring. |
| `check-commit-msg.bats` / `semver.bats` | The corresponding helpers. |
| `lint-coverage.bats` | Every tracked `*.sh` outside `src/` is linted by both pre-commit and CI. |
| `bats-assertions.bats` | Every bare `[[ ]]` in the suite actually gates its test — see below. |

### Writing assertions

**A bare `[[ ]]` does not fail a bats test unless it is the last statement in
the body.** bats runs test bodies with errexit *off* and detects failures with
an **ERR trap**. bash's ERR trap fires for `[ ]`, `false`, `grep -q` and any
helper function — but not for `[[ ]]`, which is a compound command the trap does
not observe. So a failing `[[ ]]` is invisible unless it happens to be the last
command, whose exit status becomes the test's result. Before this was found, 226
of the suite's 385 `[[ ]]` assertions were decorative.
`bats-assertions.bats` proves the mechanism in a few lines of bash rather than
asking you to take it on trust.

So every bare `[[ ]]` carries an explicit `|| return 1`:

```sh
[ "$status" -eq 1 ]                          # gates: [ ] is a builtin
[[ "$output" == *"missing"* ]] || return 1   # gates: explicitly
grep -q 'pattern' "$file"                    # gates: a command
```

The same reasoning is why `doctor.bats` and `chezmirror.bats` route negative
checks through a `no_match` helper: `! grep …` is exempt from failure detection,
but a function call is not.

**Two bats versions are in play.** CI installs 1.10 from apt; Homebrew ships
1.14 locally. They differ in ways that bite: 1.10 cannot run a bats file from
inside another bats test (the child inherits the parent's state and reports
`unknown test name`, then the run ends with `Executed N instead of expected M`).
Verify anything test-infrastructure-shaped against both. Also check bats' exit
status directly — `bats -r tests/ | grep 'not ok'` discards it, and a run can
fail with every individual test green.

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
