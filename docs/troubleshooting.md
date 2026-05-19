# Troubleshooting

If `chezmoi apply` ever prompts you about a file in `$HOME` having changed, the safest answer is `d` (diff) → look at it → then `o` (overwrite) if the changes don't matter, or `m` (merge) if they do.

A few specific issues worth knowing about:

**VS Code says `java.jdt.ls.java.home` points to a missing folder for a devbox Java project** — don't set `java.jdt.ls.java.home` globally to `${env:JAVA_HOME}` or `${workspaceFolder}/.devbox/...`. GUI-launched VS Code often does not inherit `JAVA_HOME`, and Red Hat's Java extension does not expand `${workspaceFolder}` for that setting. The global dotfiles intentionally leave it unset so the extension can use its bundled JRE to launch the language server.

For devbox-backed Java projects, commit a `.envrc` next to `devbox.json`:

```sh
eval "$(devbox generate direnv --print-envrc)"
```

The VS Code direnv extension then exports the project's JDK/Maven/Gradle environment for the workspace. The Jetify Devbox extension is also installed; for projects where an extension starts before direnv has updated the window environment, run `Devbox: Reopen in Devbox shell environment` from the command palette.

Only use a workspace-local `.vscode/settings.json` as a fallback when Red Hat Java still cannot find a JDK. That setting needs an **absolute** path to that project's devbox profile:

```json
{
  "java.jdt.ls.java.home": "/absolute/path/to/project/.devbox/nix/profile/default"
}
```

**`./install.sh: permission denied`** — run it as `bash install.sh` instead, or `chmod +x install.sh` first. To make the bit stick across clones: `git update-index --chmod=+x install.sh && git commit`.

**The sudo password prompt during `chezmoi apply` gets eaten, treated as a command, or "doesn't work the first time"** — fixed at the chezmoi level: a `run_before_00-sudo-cache` script now runs at the very start of every apply (regardless of whether you invoked it via `chez`, `chezup`, or plain `chezmoi apply -v`). It prompts for sudo *once*, on a clean terminal, before brew bundle or any other heavy output starts. A background keeper refreshes the credentials every 50s for the duration of the apply, so every subsequent sudo call inside cask installs and macos-defaults runs silently — even if brew bundle takes 20 minutes.

You'll see something like:

```text
── Sudo pre-authentication ───────────────────────────────────────
  A few scripts in this apply need sudo (cask installs, macOS
  defaults). Entering your password here — once, on a clean
  terminal — caches it for the rest of the apply…
──────────────────────────────────────────────────────────────────
[chezmoi] sudo password:
```

The distinct `[chezmoi] sudo password:` prompt is intentional — it's the visual signal to *stop typing* until you see it. On GPU-accelerated terminals (Ghostty, Alacritty, Kitty) keystrokes can arrive faster than sudo's TTY mode switch from echo-on to echo-off, eating the first character. A brief settle pause before the prompt closes that race.

If sudo is already cached when apply runs (recent `sudo` command in the same 5-min window), the pre-auth script is a silent no-op — you only get prompted when you actually need to be.

To pick up this fix on an existing machine: `chezup` once, then re-run `chezmoi apply -v`. (Or just run the wizard again: `bash ~/Developer/personal/dotfiles/install.sh`.)

Why this used to happen: chezmoi runs scripts with stdin disconnected by default. Casks like docker-desktop and 1password invoke sudo as part of their install; with stdin closed, sudo's password prompt fires but characters typed at the keyboard end up at the parent shell. Defence in depth: every script that might trigger sudo now does `exec </dev/tty` on entry to re-attach stdin, the pre-auth script prompts once on a clean terminal upfront, and `scripts/macos-defaults.sh` standalone-use also gets a settle pause + distinct prompt for the case when you run it via the `macos-defaults` alias outside of chezmoi.

**`chezmoi apply` seems to halt after the completion banner** — almost always a leftover sudo-keeper. The current code uses a double-fork detach + 2-second poll interval, so the keeper exits within 2 seconds of chezmoi finishing. If you're on a version from before that fix and see a halt: `pgrep -f "sudo -n true"` will show any orphaned keepers; `pkill -f "sudo -n true"` cleans them up. Run `chezup` once to pull the fix so it doesn't happen again.

**`chezmoi apply -v` floods the terminal with per-file content diffs** — that's `-v` doing exactly what it's documented to do: print the contents of every change. For daily use you don't want that; use `chez` instead, which calls `chezmoi apply --force` (no `-v`). Your scripts (brew progress, sudo-cache, completion summary) still produce their normal output — only chezmoi's per-file content dumps are suppressed.

```sh
chez              # quiet apply (recommended daily)
chez -v           # opt back into verbose if you're debugging
chezmoi apply     # also quiet (now that --force is the default via .chezmoi.toml)
```

**`chezmoi apply` drops you into a `diff/overwrite/skip/quit/merge` prompt mid-apply** — that's chezmoi's per-file drift resolver, fired when a managed file in `$HOME` has been changed locally. Fixed by `[apply] force = true` in `.chezmoi.toml.tmpl`. **Existing installs need to re-init to pick this up:**

```sh
chezreinit       # pulls + re-runs chezmoi init + applies
```

After that, plain `chezmoi apply` overwrites local drift without asking. The safety net is `chez` — status preview + one-shot confirmation. If you actually want to *keep* a local edit to a managed file, run `chezmoi re-add ~/.X` first to capture it back into source.

Escape hotkeys for the legacy prompt if you ever hit it: `q` quits the whole apply, `s` skips just this file, `a` applies all remaining without further prompts.

**`chezmoi diff` / `git log` / `git diff` traps you in a pager and you don't know how to escape** — `~/.zshenv` configures `less` with flags that make this painless:

```sh
LESS='-FRK -P"Press q or Ctrl-C to quit · / search · h for help"'
```

What each flag does:

| Flag | Effect |
|---|---|
| `-F` | Auto-quit when output fits in one screen — you go straight back to the prompt with nothing to dismiss |
| `-R` | Pass ANSI color codes through, so delta's syntax highlighting renders |
| `-K` | **Ctrl-C exits less** instead of just interrupting the current search |
| `-P…` | Show a visible status line: `Press q or Ctrl-C to quit · / search · h for help` instead of the cryptic default `:` |

Note the deliberate omission of `-X` (no-terminal-init). With `-X`, less prints to your normal terminal stream — which means the "Press q…" status line sticks around in your scrollback as a stale artifact every time less auto-quits. Without `-X`, less uses the alternate-screen buffer: content and prompt vanish cleanly on exit, leaving your terminal exactly as it was before the pager opened. To re-view a diff, just re-run the command.

Delta's `pager = "less -FRK -P'…'"` in `~/.config/git/config` is the belt-and-braces complement in case `LESS` is unset somewhere upstream.

After this lands you have three independent ways to escape any pager:

- **q** — quit (works in all `less` versions)
- **Ctrl-C** — quit (works because of `-K`)
- **(implicit)** short diffs auto-exit, no key needed

For long-page operations you didn't want, override per-call:

```sh
chezmoi diff | cat                 # pipe past the pager entirely
GIT_PAGER=cat git diff             # one-shot pager override
LESS=-RX chezmoi diff              # one-shot less override (always pages, no -F)
```

**Brew bundle looks frozen — no output for minutes** — long downloads (large casks, slow networks) can sit silently because brew streams output only as steps complete. The brew-bundle script splits the active Brewfiles into individual taps/formulae/casks and prints a heartbeat every 30 seconds during silent stretches:

```text
→ Module 1/4: core (always) (Brewfile, 43 item(s))
→ 35/59  core (always): cask docker-desktop
...brew bundle output...
  … still working on cask docker-desktop — 1m00s elapsed
  … still working on cask docker-desktop — 1m30s elapsed
✓ 35/59  core (always): cask docker-desktop done in 2m48s
```

Plus an upfront plan that tells you what's coming, how many modules will run, and how many Homebrew items are in the selected setup:

```text
◆ Apply 3/5: Homebrew packages
  Profile: both
  Modules: 4
    1. core (always)
    2. mac apps (Rectangle/Raycast/Stats/Chrome/dive)
    3. personal profile extras
    4. work profile extras
  Items: 59 taps/formulae/casks split into individual installs.
  First install usually takes 5-15 minutes. Downloads dominate.
  Quiet stretches print a heartbeat every 30 seconds.
```

If a package fails or the process is interrupted, re-run `chezmoi apply` or the installer. Completed Homebrew items are skipped by the next run, and the output resumes with the next missing item. If you genuinely think brew is frozen (heartbeat stopped firing too), `ps aux | grep brew` will show whether brew is still working — most often it's stuck on a `curl` for a slow mirror.

**The first install stage takes forever before packages appear** — that is usually Xcode Command Line Tools or Homebrew bootstrapping itself. A brand-new Mac often has to install Apple's compiler toolchain before Homebrew can build or verify anything. Phase 4 now prints a sub-plan before it starts:

```text
◆  4/5 - Install and apply
│
│  Fresh Mac bootstrap can pause on Apple and Homebrew installers.
│    4.1                prepare directories and legacy files
│    4.2                Xcode Command Line Tools
│    4.3                Homebrew and chezmoi
│    4.4                clone dotfiles repo
│    4.5                apply dotfiles and package plan
│  Long external installers print a 30-second heartbeat while they run.
```

If Xcode CLT is missing, the script opens Apple's installer and polls for up to 60 minutes with elapsed-time messages. If Homebrew, `brew install chezmoi`, or `git clone` are slow, they print a heartbeat every 30 seconds. If the Mac sleeps or the network drops, rerun `install.sh`; completed steps are detected and skipped.

**`chezmoi apply -v` hangs at `tightening permissions on /opt/homebrew/share/zsh*`** — should finish in <1s now (scoped to just the zsh dirs). If it hangs longer, you're probably running an old version of the script — Ctrl-C, `git pull` (or just re-run `chezmoi apply` from the source dir), and re-apply.

**Old `chezmoi apply` runs prompted about `.zsh_history`** — this used to fight with an active shell because `remove_dot_zsh_history` markers tried to delete a file the shell kept recreating. Those markers are gone. If you still have the legacy files (`~/.zsh_history` or `~/.config/zsh/.zsh_history`), delete them once: `rm -f ~/.zsh_history ~/.config/zsh/.zsh_history`.
