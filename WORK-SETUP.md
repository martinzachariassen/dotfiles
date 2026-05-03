# Work setup (not part of `chezmoi apply`)

The corporate Claude Code distribution lives outside this repo because it's installed by your employer's tooling, not your personal config.

## What lives where

| Path | What it is |
|---|---|
| `~/.storecode/` | Storecode runtime — `dcg`, `pipelock`, `rampart-*` policy hooks, `mcp-allowlist`/`denylist` |
| `~/.rampart/` | Rampart audit + session-state |
| `~/.copilot/` | GitHub Copilot IDE state |
| `~/.claude/` | Work Claude Code profile — settings.json with hooks pointing into `~/.storecode/lib/` |
| `~/.local/bin/storecode` | Storecode CLI binary |

## Install on a fresh machine

This step is **not automated** by `install.sh` — the corporate package isn't public, so the command lives outside this repo. Grab it from your employer's onboarding doc and run it after `chezmoi apply` finishes.

The shape will look like one of these (replace with the real URL/tap from your onboarding doc):

```sh
# Option A: corporate installer
curl -fsSL https://internal.example.com/storecode/install.sh | bash

# Option B: brew tap
brew tap company/internal && brew install storecode
```

Once the install drops `~/.claude/`, `~/.storecode/`, `~/.rampart/`, and `~/.copilot/` into place, the `claude` wrapper function in `~/.config/zsh/.zshrc` will automatically pick the work profile when you `cd ~/Dev/Work/<anything>`.

## Verifying

```sh
ls -la ~/.storecode/lib/        # should contain dcg, pipelock, rampart-*-hook.sh, write-guard.sh, etc.
ls -la ~/.claude/settings.json  # should reference /Users/<you>/.storecode/... in the hooks
cw --version                    # explicitly invokes the work profile
```
