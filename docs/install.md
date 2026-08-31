# Installing

One installer covers every machine. [`install.sh`](../install.sh) is a tiny
hand-written bootstrap fetched via `curl | bash` **before this repo exists on
disk**, so it installs only the prerequisites — Xcode Command Line Tools,
Homebrew, chezmoi, and the repo clone — then hands off to the setup wizard
([`features/setup/cli.sh`](../features/setup/cli.sh)), which asks the setup
questions and runs `chezmoi init --apply`. See [lifecycle.md](lifecycle.md) for
what `apply` does. Every step is idempotent and safe to re-run.

The installer narrates itself: five numbered steps, an upfront estimate, and a
visible tick while Apple's GUI installer runs (that step can take many minutes
and used to look like a hang). The wizard then asks four questions, each with a
line or two on why it matters. `QUIET=1` drops the prose and keeps the results.

**About the password prompts.** You are asked for your macOS login password
more than once: `install.sh` needs it to create `/opt/homebrew`, the apply
pre-authorises it again for Homebrew casks (several link binaries into
`/usr/local/bin`), and `chez macos` needs it if that session has since
expired. Each ask says why it is happening and that nothing echoes as you type;
if **Touch ID for sudo** is enabled ([macos.md](macos.md#touch-id-for-sudo-sonoma-14),
applied by the `macosDefaults` module) you can tap instead. Immediately after
the first one, Homebrew's own installer prints a long wall of `/usr/bin/sudo …`
lines — that is what it always does, not a failure.

Every ask is deliberately placed on a clean screen *before* a long noisy step,
never in the middle of one — the package step re-checks the ticket and asks
before its progress bar starts, and holds it warm for the length of the bundle.
If the ticket lapses anyway, the bar stops drawing and an **Administrator
password needed** banner takes its place rather than a prompt being overwritten
mid-redraw (see [commands.md](commands.md#progress)). You always get an explicit
`✓ password accepted` when it lands, and a warning naming the password — not the
download — if a cask failed because the prompt went unanswered.

**"Xcode Command Line Tools" is not Xcode.** Step 1 installs Apple's compilers
because Homebrew needs them, and nothing more: no iOS SDK, no Simulator, no
SourceKit-LSP. Selecting the `appleDev` module gets you the Swift *tooling*
(SwiftLint, SwiftFormat, SweetPad …) but still not Xcode itself — `xcodes
install` needs an Apple ID with 2FA, so it can't run unattended from an apply.
The `xcodes` CLI isn't a Brewfile entry either: its formula builds from source
and that build needs a full Xcode.app, so `chez xcode` fetches the upstream
prebuilt binary (pinned by sha256 in `src/.chezmoidata/xcode.toml`) itself. Run **`chez xcode`** once afterwards to close that gap; the apply's
closing summary prompts you when it's outstanding, and `chez doctor` stays red
until it's done. See [commands.md](commands.md#advanced--occasional-helpers).

## Scenarios

### Brand-new Mac

One command bootstraps everything and applies:

```sh
curl -fsSL https://raw.githubusercontent.com/martinzachariassen/dotfiles/main/install.sh | bash
```

> **The signing key is a chicken-and-egg.** The wizard asks for your git signing
> key, but on a just-wiped Mac that key is still inside 1Password — which
> Homebrew only installs a few steps *later*. So when the wizard asks *when* you
> want to set the key, answer **later**. Signing is simply omitted from the
> rendered gitconfig until a key exists (git works fine, commits are just
> unsigned), and the closing summary reminds you to finish with `chez sign`.

When the wizard finishes, sign in and reload:

```sh
open -a 1Password                                                 # skip if disabled
                                                                  # → Settings → Developer → enable the SSH agent
exec zsh                                                          # reload the managed shell
chez sign                                                         # set the signing key deferred above
chez auth                                                         # sign in to gh / cloud CLIs
chez doctor                                                       # verify everything is healthy
sudo shutdown -r now                                              # reboot to finish macOS defaults
```

**Reload first.** `chez` is a shell function the managed `.zshrc` defines, so
until `exec zsh` has run it does not exist — the shell you ran the installer
from is the one you had before. The apply's closing summary puts `exec zsh` at
step 1 for the same reason.

`chez sign` reads the keys the 1Password agent is already holding, so there's
nothing to copy-paste — pick one and it replays every other setup answer
untouched, then proves it worked with a real signed commit. It re-asks nothing
else, so you never have to walk the whole wizard again just to supply a key.

### Existing Mac with an older setup

Use the **same installer** — but note it takes no backup of what is already
there. The first apply writes managed files over their live counterparts and
deletes the legacy ones this repo declares gone (`~/.zshrc`, `~/.gitconfig`,
`~/.bash_profile`, `~/.bashrc`, `~/.profile`, `~/.zprofile`, `~/.continue`).
Copy anything you want to keep somewhere safe first. Removing what the repo no
longer tracks is a separate, confirm-gated step — see
[cleaning up drift](#cleaning-up-drift-on-an-existing-mac):

```sh
curl -fsSL https://raw.githubusercontent.com/martinzachariassen/dotfiles/main/install.sh | bash
```

Afterwards, reload and sanity-check:

```sh
exec zsh
chez doctor      # warns about any leftover direnv it couldn't remove
```

### Already set up

Just stay current with [`chez up`](commands.md#everyday) — no installer needed.

## Advanced flags

With no arguments `install.sh` runs the wizard. **Any** extra arguments bypass
the wizard and forward straight to `chezmoi init --apply` (for scripted/CI use).
It also reads two environment variables:

```sh
DOTFILES_REPO=<repo-url> bash install.sh                  # point at a fork
DOTFILES_DIR=<path>      bash install.sh                  # clone somewhere else
curl -fsSL …/install.sh | bash -s -- --promptDefaults     # non-interactive (CI): skip wizard, accept defaults
```

`install.sh` is **not** generated — edit it directly.

## Cleaning up drift on an existing Mac

The installer only ever **adds** — it renders managed files, installs the
Brewfile, and runs `mise install`. It never uninstalls or deletes, so an
existing Mac can carry forward tools, packages, and config the repo no longer
manages (an old `~/.config/direnv`, a dropped `node` formula, leftover Nix
remnants). Reconciling that drift back to the repo is a deliberate, **manual**
step you run when you want to:

- `chez mirror` — remove Homebrew packages, casks, and taps the Brewfiles no
  longer declare (confirm-gated, one at a time), then `brew autoremove` orphaned
  dependencies.
- `chez clean` — remove untracked dotfiles the repo doesn't manage, across the
  top level of `$HOME` (the dangling `~/.nix-profile` symlink, say) and
  `~/.config` (`~/.config/direnv`). Tool-aware, confirm-gated. See
  [lifecycle.md](lifecycle.md#reconciling-untracked-dotfiles-chez-clean).

Anything nested deeper than an immediate child is out of `chez clean`'s scope —
remove it once by hand instead (`rm -rf ~/.local/state/nix` for an empty
leftover state dir, for example). On a fresh machine that never had the old
stack, there's nothing to reconcile.

## Work-profile security tooling (storecode)

On the **work** profile the apply also ensures `storecode` — an internal
security tool that guards shell commands — is installed. It ships via its
**own** installer, not Homebrew, so it's never a Brewfile entry and
`chez status`/`chez mirror` never flag it; `~/.storecode` sits on the cleanup
keep-list (`cleanup.keepHome`), so `chez clean` never offers to remove it. The
installer command is data-driven in
[`src/.chezmoidata/storecode.toml`](../src/.chezmoidata/storecode.toml)
(`storecode.installCmd`); until it's set, the
`run_onchange_after_05-storecode` hook prints how to finish the install and
exits cleanly — an apply never fails just because storecode isn't wired up yet.
On any non-work profile the hook is a no-op.

### Coming from the direnv setup

Runtimes (Java/Node/Python) are now managed by **mise**: global defaults live
in `~/.config/mise/config.toml`, and each project pins its own versions and env
vars in a committed `mise.toml` (its `[env]` block replaces `.envrc`). See
[shell.md](shell.md#runtimes-mise) for the runtime setup.
