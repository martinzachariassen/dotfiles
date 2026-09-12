# dev-cli

Repo: [dotfiles](../../README.md) · The module contract:
[docs/modules.md](../../docs/modules.md)

Development CLI tools, plus the language runtimes they assume.

Two package managers, and the split is deliberate: **Homebrew owns CLIs, mise
owns runtimes.** A `brew`-installed runtime moves when Homebrew decides it
does; a mise-installed one moves when you edit a file.

```mermaid
flowchart TD
  B["Brewfile<br/>gh · jq · lazygit · mise · zoxide · …"] --> M
  M["mise"] --> RT["mise install<br/>runtimes pinned in home/.config/mise/config.toml"]
```

## Why `apply.sh` exists

`mise activate` never installs anything. Linking `config.toml` alone leaves it
unread until someone runs `mise install` by hand, so this hook runs it.

## `doctor.sh` never invokes mise

`mise ls` **creates** `~/.local/share/mise` and `~/.local/state/mise` on a
machine that has neither — a check that writes to the `$HOME` it is checking.
So the hook reads the install tree directly instead:

```
~/.local/share/mise/installs/<tool>/  runtime present
```

`doctor.sh` reads the `[tools]` table out of the repo's own `config.toml`, so a
runtime added there is checked without editing the hook. `contract.bats`
enforces this with a `mise` stub on `PATH` that records any invocation — the
generic `$HOME` snapshot only fires on a machine that *has* mise, and CI has
none.

Both `doctor.sh` and `remove.sh` rebuild mise's default data directory by hand
(`MISE_DATA_DIR`, else `XDG_DATA_HOME`, else `~/.local/share/mise`), because
mise does not expose it for scripting and it has to keep resolving once mise
itself is gone. A test holds the two lines identical.

## Removal deletes nothing

There is nothing safe to delete, and that is the point. `apply.sh` downloads
into a directory full of other projects' toolchains, so `remove.sh` reports
what is left rather than guessing which of it was ours:

| Left alone | Yours to run |
|---|---|
| `~/.local/share/mise` — language runtimes | `mise implode` |

Same trade as `macos-defaults`: no state file, so the warning *is* the
deliverable. It stays silent when the directory does not exist, because
`uninstall.sh` runs every module's `remove.sh` and a machine that never
enabled this one must hear nothing.
