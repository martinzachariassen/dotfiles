# Forking this repo

The wizard is designed to be fork-friendly. If you cloned this and want to base your own setup on it, here's the minimum surface area you'll want to touch:

1. **Point `install.sh` at your fork.** Change the default `DOTFILES_REPO` near the top of `install.sh`, or invoke with `DOTFILES_REPO=https://github.com/<you>/dotfiles.git bash install.sh`.
2. **Fill in `brewfiles/Brewfile.work`** with your employer's relevant apps (Slack, Zoom, Postman, JetBrains IDEs, …). Or empty it out entirely — it's allowed to be empty.
3. **Edit `brewfiles/Brewfile.personal`** to match your "personal machine" preferences.
4. **Tune the boundary between Brew and Devbox.** Keep workstation tools in Brewfiles; put project runtimes and CLIs in `examples/devbox/` templates or directly in each project's `devbox.json`.
5. **Replace `dot_config/claude/personal/CLAUDE.md` and `dot_codex/AGENTS.md`** with your own preferences. They currently encode my style; almost certainly not yours.
6. **Adjust `dot_config/git/config.tmpl`** if you don't want commit signing — the `[gpg "ssh"] program = …` block assumes 1Password's `op-ssh-sign`. The wizard's `useOnePassword` toggle controls whether the block renders.
7. **Re-render the README badges** — the CI badge URL hardcodes my GitHub handle.

Nothing in `install.sh` writes to the original `martinzachariassen` repo URL except the default for `DOTFILES_REPO`. As long as you replace that, every other personal value (name, email, signing key) comes from the setup prompts and is stored locally in `~/.config/chezmoi/chezmoi.toml`, not in the source.
