# Containers (colima)

Docker Desktop is gone. `colima` runs dockerd inside a Lima VM and the plain
Homebrew `docker` CLI talks to it over the `colima` docker context — no GUI, no
licence terms, no privileged helper.

This feature owns the *convergence*: registering the login agent, keeping the
managed config reachable, and clearing what Docker Desktop left behind. The VM's
shape, the agent and the CLI itself are files elsewhere, because chezmoi deploys
them.

| Piece | Where |
|---|---|
| Apply engine | [`hook.sh`](hook.sh), run by `run_onchange_after_07-colima` |
| VM shape | [`src/dot_config/colima/_templates/default.yaml`](../../src/dot_config/colima/_templates/default.yaml) |
| Start at login | [`src/Library/LaunchAgents/no.mlz.colima.plist.tmpl`](../../src/Library/LaunchAgents/no.mlz.colima.plist.tmpl) |
| CLI + plugins | `colima`, `docker`, `docker-compose`, `docker-buildx` in [`../brew/Brewfile`](../brew/Brewfile) |
| Plugin wiring | `symlink_docker-{compose,buildx}` under [`src/dot_docker/cli-plugins`](../../src/dot_docker/cli-plugins) |

Prose on the VM's shape and the shell aliases lives in
[docs/shell.md](../../docs/shell.md#containers-colima).

## What the hook does

Three jobs, in order, none of which can fail an apply:

1. **Clears a shadowing `~/.colima`.** colima resolves its home from
   `$XDG_CONFIG_HOME` — but only while `~/.colima` does not exist. A bare one
   silently wins and strands the managed template, starting an unconfigured VM
   instead. An *empty* one was created by accident and is removed; a *populated*
   one holds a real instance, so only its owner can decide to move it and the
   hook just says so.
2. **Prunes dangling cli-plugin symlinks.** Docker Desktop left one per plugin.
   Only links whose target is gone are removed — the managed compose/buildx
   links resolve and stay.
3. **Re-registers the launchd agent.** This is how an edited plist takes effect
   at all: launchd caches the loaded copy, so rewriting the file changes
   nothing until something boots the agent out and back in.

The template keeps the darwin guard and passes the destination home, which only
a render knows. It hashes `hook.sh`, the plist and the VM template, so an edit
to any of the three re-fires the hook; hashing only itself would freeze the
engine at the recorded hash and the hook would never run again.

`COLIMA_BIN` overrides the hard-coded `/opt/homebrew/bin/colima` — the path is
absolute because chezmoi runs hooks without a login shell, and overridable
because that is what makes [`tests/hook.bats`](tests/hook.bats) able to drive
the branches above without colima installed.

## Gotchas

**The template only shapes a VM at creation.** Editing
`_templates/default.yaml` does nothing to a VM that already exists; `colima
delete && colima start` is what adopts a change. The hook says so when it sees
an existing `default` instance.

**Registration can fail transiently.** `launchctl bootstrap` occasionally
refuses while the preceding boot-out is still settling. The hook prints
launchctl's own message rather than swallowing it, never fails the apply — hook
99's "Next moves" block comes after this one — and the next `chezapply` fixes
it. `chezdoctor` reports an unregistered agent too, so it does not go unnoticed.

**The plugin symlinks are chezmoi's, not Homebrew's.** Homebrew's caveat
suggests `cliPluginsExtraDirs` in `~/.docker/config.json`, but `docker login`
writes credentials into that same file and a `--force` apply would clobber them.

Logs: `~/.local/state/colima/logs/startup.log`.
