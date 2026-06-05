# Forking this repo

The wizard is designed to be fork-friendly. If you cloned this and want to base your own setup on it, here's the minimum surface area you'll want to touch:

1. **Point `install.sh` at your fork.** Change the default `DOTFILES_REPO` near the top of `install.sh`, or invoke with `DOTFILES_REPO=https://github.com/<you>/dotfiles.git bash install.sh`.
2. **Fill in `brewfiles/Brewfile.work`** with your employer's relevant apps (Slack, Zoom, Postman, JetBrains IDEs, …). Or empty it out entirely — it's allowed to be empty.
3. **Edit `brewfiles/Brewfile.personal`** to match your "personal machine" preferences.
4. **Tune the boundary between Brew and mise.** Keep workstation tools in Brewfiles; pin per-project language runtimes in each project's `mise.toml` (start from `examples/mise/`), and keep project CLIs/database servers in Homebrew or Docker.
5. **Replace `.chezmoitemplates/agents/shared.md`** (the shared AI base loaded by both Claude and Codex), **`.chezmoitemplates/claude/personal.md` (and/or `work.md`)**, and the Codex-only tail in **`dot_codex/AGENTS.md.tmpl`** with your own preferences. They currently encode my style; almost certainly not yours.
6. **Update [`AGENTS.md`](../AGENTS.md)** if you restructure the repo (different Brewfile tiers, a different shell, etc.). It's the single source of truth for AI agents working in this repo — Claude Code reads it via the `CLAUDE.md` bridge, Copilot via `.github/copilot-instructions.md`, Codex natively. See [AI tools](ai-tools.md) for the full layering.
7. **Adjust `dot_config/git/config.tmpl`** if you don't want commit signing — the `[gpg "ssh"] program = …` block assumes 1Password's `op-ssh-sign`. The wizard's `useOnePassword` toggle controls whether the block renders.
8. **Re-render the README badges** — the CI badge URL hardcodes my GitHub handle.

Nothing in `install.sh` writes to the original `martinzachariassen` repo URL except the default for `DOTFILES_REPO`. As long as you replace that, every other personal value (name, email, signing key) comes from the setup prompts and is stored locally in `~/.config/chezmoi/chezmoi.toml`, not in the source.
