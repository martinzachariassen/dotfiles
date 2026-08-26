# Commands

The everyday surface is **two verbs plus a health check**. Both verbs end in the
same `chezmoi apply`, which reconciles *real installed state* on every run, so it
always installs what the Brewfile declares. It never *uninstalls*: `chezapply` only
flags packages you have but the Brewfile doesn't, and `chezmirror` reconciles
that removal direction on demand. `chezmirror` is **removal-only** — the install
direction is what every `chezapply`/`chezup` already does; `chezreconcile` chains
the two (`chezup` then `chezmirror`) when you want a full both-directions package
reconcile in one step.

The verbs are defined in
[`src/dot_config/zsh/dot_zshrc.tmpl`](../src/dot_config/zsh/dot_zshrc.tmpl) and
delegate to the scripts in [`scripts/bin/`](../scripts/bin).

## Everyday

| Command | What it does |
|---|---|
| `chezup` | **Converge this Mac to the repo:** pull the latest changes, offer any module added since this Mac was set up, preview file drift and pending hooks, then apply. The everyday command, and the way to retry a partial install. |
| `install.sh` | **Bootstrap a new Mac** from scratch (the same apply path under the hood — see [install.md](install.md)). |
| `chezdoctor` | Read-only **health check** for repo, chezmoi, brew, auth, signing, mise, shell layout, and — when the module is on — the nightly distiller. |

**`chezup` runs in four phases**, honouring `DRY_RUN=1` (print, don't run) and
`YES=1` (skip the confirm gate), and passing any trailing arguments through to
`chezmoi apply` (e.g. `chezup -v`):

1. **Update repo** — `git pull --ff-only` in the source dir; reports how many
   commits arrived.
2. **Offer new modules** — see below. Runs after the pull, because that's when
   the catalog may have grown, and before the drift check, so a module enabled
   here is applied in the same run.
3. **Review pending changes** — two questions, because they fail
   independently: `chezmoi status --exclude scripts` lists file drift between
   repo and `$HOME` (`A` add, `M` modify, `D` remove), and
   `chezmoi status --include scripts` lists pending apply hooks. Stops here only
   when **both** are empty. A partial install (a brew bundle that died mid-way)
   leaves no file drift at all, so gating on files alone would make `chezup` a
   no-op exactly when a retry is needed.
4. **Apply** — one confirmation gate, then `chezmoi apply --force`.

### New modules since this Mac was set up

Module choices are saved by `promptMultichoiceOnce`, which reads the saved answer
back on every later run, and `chezup` only ever calls `chezmoi apply` — never
`init`. So a module **added to the catalog after a machine was set up** would stay
invisible on it forever; the only way in was `chezsetup --reset`, which re-asks
about everything.

Phase 2 closes that gap. It diffs `[moduleCatalog]` against two saved lists —
`modules` (enabled here) and `modulesSeen` (offered here at least once) — and
offers the difference:

```text
ℹ 1 new module since this Mac was set up:
    claudeDistiller — Nightly distillation of Claude sessions into a persistent memory
  Enable claudeDistiller? [y/N]
```

- **`[y/N]`, defaulting to no** — unlike the apply gate's `[Y/n]`. This rewrites
  your configuration rather than installing something you already asked for.
- **Every module offered is written to `modulesSeen`, accepted or not.** That is
  what stops a declined module being asked about on every single run. Enabling it
  later is `chezsetup` (tick the box); the gate itself asks exactly once.
- **`YES=1` or no TTY: nothing is enabled.** The new modules are listed and the
  run continues to the apply. `YES=1` means "don't ask before applying", not
  "decide my configuration for me" — an unattended `chezreconcile` or a cron job
  must not silently take on a module.
- **`DRY_RUN=1`**: lists what's new, asks nothing, writes nothing.
- If `jq` is missing or `chezmoi data` can't be read, the phase stays silent
  rather than guessing — it fails closed, offering nothing.

Both lists live in `~/.config/chezmoi/chezmoi.toml`, are emitted by
[`src/.chezmoi.toml.tmpl`](../src/.chezmoi.toml.tmpl) (so `chezmoi init`
round-trips them rather than wiping them), and are read and rewritten through
[`scripts/lib/modules.sh`](../scripts/lib/modules.sh), shared with
`chezdistill --setup` so the two can't write the list differently.

## When a command says its script is missing

The verbs are shell functions with the helper-script path **baked into
`~/.config/zsh/.zshrc` at apply time** (fast — no `chezmoi source-path`
subprocess per call). A `git pull` updates the repo on disk but never rewrites
the live rc. So if a repo restructure **moves or renames a script** (the
`scripts/` → `scripts/bin/` regroup, say), a machine that pulled but hasn't
re-applied has a function pointing at a path that no longer exists.

The wrappers self-heal through `_chez_run`: on a missing script they run
`git pull` + `chezmoi apply` to regenerate the functions with corrected paths,
then `exec zsh` to reload. You'll see:

```text
dotfiles: …/scripts/bin/chezup.sh is missing — this shell's config predates a repo change.
  re-syncing this machine (git pull + chezmoi apply)…
  synced — reloading your shell. Re-run your command.
```

**The one case this can't fix automatically:** a `.zshrc` applied *before*
`_chez_run` itself existed — you can't repair a broken bootstrap from inside the
broken file. Recover it once by running the script directly (bypassing the
stale function), then reload:

```sh
bash ~/Developer/personal/dotfiles/scripts/bin/chezup.sh   # pull + preview + apply
exec zsh
```

From then on the self-heal is in your rc and any future script move is
automatic. If the script path itself differs in your clone, the
provider-agnostic fallback is `chezmoi apply && exec zsh` (`chezmoi` is on
`PATH` via Homebrew and reads `.chezmoiroot` itself).

## Changing your setup

Change your profile, optional modules, or signing with `chezsetup`:

```sh
chezsetup               # fill in any newly-added setup keys; keeps existing answers
chezsetup --reset       # re-ask profile / modules / signing, then apply
chezsign                # set only the git signing key; keeps every other answer
chezxcode               # install Xcode + the iOS simulator runtime (appleDev only)
```

**Left the email blank during setup?** `chezsetup` is the fix — it re-asks that
one question and keeps every other answer. A blank email is not stored as an
answer, so it stays "unanswered" until you fill it in, and until then
`~/.config/git/config` carries `user.useConfigOnly = true` so git *refuses* to
commit rather than authoring one as `Your Name <>` (unattributable on GitHub,
and undoable only by rewriting history). `chezdoctor` reports it, and the
apply's closing summary lists it as a numbered next move. Your GitHub noreply
address is at github.com → Settings → Emails.

The default mode runs plain `chezmoi init`, which — via chezmoi's
`prompt*Once` functions — keeps every answer you've given and only asks for
setup keys still blank. So it fills in newly added questions but never lets you
re-choose existing ones; pass `--reset`/`-r` for that (it also resets chezmoi's
persistent state so `run_once_*`/`run_onchange_*` hooks fire again — confirm-gated,
never uninstalls anything). See [packages.md](packages.md#the-wizard) for how the
wizard works.

## Advanced / occasional helpers

| Command | What it does |
|---|---|
| `chezhelp` | Print every dotfiles verb, grouped, one line each. Static text — instant, no subprocesses. The entry point when you forget a command. |
| `dotfiles` | Jump to the source repo (with args, points you at `chezsetup` / `chezhelp`). |
| `chezapply` | Apply without pulling — the building block `chezup` calls. Flags Brewfile drift (packages installed but untracked); never uninstalls. |
| `chezstatus` | Read-only drift report: plain-language file drift (what `chezapply` would push, and what you edited locally in `$HOME`) **and** untracked-package drift, in one report. `chezstatus PATH` or `chezstatus -v` drops to raw `chezmoi diff`. |
| `chezsign` | Set **only** the git signing key, keeping profile, modules and identity exactly as they are. Exists because of a bootstrap chicken-and-egg: the signing key lives in 1Password, which Homebrew doesn't install until *after* the wizard has already asked for it, so a fresh Mac has to defer the answer. Offers the keys the SSH agent is already holding (1Password's socket first, else `$SSH_AUTH_SOCK`) so there's nothing to paste — or takes a key as an argument: `chezsign "ssh-ed25519 AAAA…"`. Strips any trailing agent comment, since `allowed_signers` is `<email> <key>` per line. No-ops when the key is already set, refuses when `signingMode` is `off` (that's a `chezsetup --reset`), and finishes with a real signed commit as a smoke test. `DRY_RUN=1` prints the `chezmoi init` it would run; `YES=1` takes a lone offered key unprompted. |
| `chezxcode` | **`appleDev` only.** Bring the Xcode layer up to "can build and run an iOS app", in five idempotent steps: install Xcode.app via `xcodes`, point `xcode-select` at it, accept the licence, run `xcodebuild -runFirstLaunch`, and download an iOS simulator runtime. Exists because none of that can happen during an apply: `install.sh` deliberately installs only the **Command Line Tools** (Homebrew needs them and nothing more), `xcodes install` authenticates against an Apple ID with 2FA so it can't run unattended, and the downloads are ~40 GB. The two states it exists to catch both look healthy otherwise — the CLT satisfying `xcode-select -p` while `xcodebuild` has no iOS SDK behind it, and a complete Xcode with **no simulator runtime** (separate downloads since Xcode 16, so every iOS device reports "Unavailable"). `chezxcode --check` reports all five read-only and exits non-zero if any fails; `chezdoctor` runs the same probes from [`scripts/lib/xcode.sh`](../scripts/lib/xcode.sh). The `xcodes` CLI it drives is fetched by `chezxcode` itself (upstream's signed prebuilt binary into `~/.local/bin`, checked against the sha256 in [`src/.chezmoidata/xcodes.toml`](../src/.chezmoidata/xcodes.toml)) rather than installed by Homebrew — the tap formula builds from source and that build needs a full Xcode.app, so it can never succeed on a fresh Mac. The fetch happens only *after* you accept the Xcode download, so declining still changes nothing. Signing stays manual — Xcode → Settings → Accounts, then the team on a target's Signing & Capabilities tab. **Opting out is the default:** nothing in `install.sh` or an apply ever invokes it, each of the two large downloads is confirmed separately (decline either and it exits cleanly, having changed nothing), and `SKIP_RUNTIME=1` takes Xcode without the simulator runtime. Requires a TTY for the confirm gate — with no terminal it refuses rather than starting a ~40 GB download unasked; `YES=1` is the deliberate way past that. `DRY_RUN=1` previews every step and works headless, `XCODE_VERSION=26.6` pins a version instead of `--latest`. |
| `chezsetup` | Configure profile/modules/signing. Default fills in **newly added** setup keys only, keeping existing answers. `--reset`/`-r` sets this Mac up **as new**: resets chezmoi's persistent state so `run_once_*`/`run_onchange_*` hooks fire again, re-asks the full wizard (overriding saved answers), then applies. Confirm-gated in `--reset` mode; never uninstalls packages or deletes files. |
| `chezbump` | Routine dependency upgrade (`brew update && brew upgrade` + `mise upgrade`). |
| `chezdistill` | **`claudeDistiller` only.** Distil this machine's Claude Code transcripts and render the `MAIN.md` the global persona `@`-imports, so yesterday's conclusions are in context tomorrow. launchd runs it at 01:00; it fires on **wake** when the Mac slept through, coalescing missed firings into one run — which is why the job tracks a cursor rather than "yesterday" and so cannot lose a night. **Two destinations:** the memory tier (`MAIN.md`, `Topics/`, `Candidates.md`) to `~/.config/claude/memory`, beside the persona that imports it; the extract corpus, the hand-written `Pinned.md`, cursor, spend and run log to `~/.local/state/chezdistill`, in a git repo whose remote is optional — add one and every run pushes it, so a replacement Mac clones the corpus instead of starting from an empty memory. Only the corpus and `Pinned.md` are tracked there; the cursor, spend log and run log describe one machine, are append-only, and would make two Macs conflict on every line. The corpus is sharded per host (`extracts/<date>.<host>.json`) so two Macs *within a profile* can share one remote — across profiles they must not, since `hits` is counted over the whole corpus, hence one private repo each (`claude-memory-personal`, `claude-memory-work`). **There is no human-facing output**: the audience is Claude, and what it knows you read with `--status`, `MAIN.md` or a note in `Topics/` — with `chezdoctor` carrying the passive "is it still alive" check. Nothing reaches `MAIN.md` until it has been seen in **two** distinct sessions, so one misreading can't become a global rule; `hits` is derived from the extract corpus rather than incremented, which is what makes a repeat run of an already-distilled day free. `--setup` is the way to turn the whole thing on: it adds `claudeDistiller` to the module list in `chezmoi.toml`, applies so the plist and the `MAIN.md` import render, and registers the launchd agent — idempotent, and no API calls. Before the module is on, the shell verb does not exist yet, so the first run goes through `bash scripts/bin/distill.sh --setup`. Every run — nightly, hand-run, succeeded or failed — appends a record to `runs.jsonl`, so a job that failed or harvested nothing is visible rather than leaving its only trace in a launchd log. `--status` reports where everything lives, MAIN size against its 6 KB cap, 7-day spend and the last run. `--render` rebuilds from the corpus with no API calls, `--since 7d` backfills, `--undo` reverts the state repo's last distiller commit and re-renders the memory from it, `-n` previews without calling the model. Costs roughly $1–2 a night, bounded by `maxSpendUsd7d` in [`src/.chezmoidata/distill.toml`](../src/.chezmoidata/distill.toml) — a rolling 7-day ceiling checked in preflight *and* before every session, so a long `--since` backfill stops part-way (keeping what it paid for, holding the cursor) instead of running past it. Full guide: [docs/distill.md](distill.md). |
| `chezmirror` | Enforce the Brewfile as truth in the removal direction: preview the untracked items (formulae, casks, orphaned taps), then confirm each removal **one at a time** (via `gum` when installed); casks go through `--cask`, taps through `brew untap`. Pass `--all` (aliases `-a`, `--yes`, `-y`) to remove the **whole** set after one confirmation, `--dry-run`/`-n` (or `DRY_RUN=1`) to preview only, or `YES=1 chezmirror` to accept-all with no prompt. Requires a TTY for the confirm gate. **Removal only** — installs happen via `chezapply`/`chezup`; `chezreconcile` runs both. "Untracked" means *declared by no Brewfile active on this machine* — core, your enabled modules and your profile's tier, resolved by [`scripts/lib/brewfiles.sh`](../scripts/lib/brewfiles.sh), the same set the apply hook installs from and `chezdoctor` checks. So a package you move to the other profile's tier is offered for removal here on the next run; the other profile's Brewfile does not keep it alive. If the tier set can't be resolved it offers **nothing** rather than guessing wider. |
| `chezreconcile` | **Full package reconcile in one step:** `chezup` (converge + install what the Brewfiles declare) then `chezmirror` (uninstall what they don't). `chezup` only adds and `chezmirror` only removes; `chezreconcile` does both directions. Untracked *files* stay separate — that's `chezclean`. Honours `DRY_RUN=1` (previews both directions, using `chezmirror -n` for the removal side so nothing is touched) and `YES=1` (skips both confirm gates); trailing args pass through to `chezup` → `chezmoi apply`. |
| `chezclean` | The **file** analogue of `chezmirror`: reconcile untracked dotfiles to what chezmoi manages, across two scopes — the top level of `$HOME` (keep-list `cleanup.keepHome`) and `~/.config` (keep-list `cleanup.keepConfig`), both in [`src/.chezmoidata/cleanup.toml`](../src/.chezmoidata/cleanup.toml). Lists the untracked entries — everything that chezmoi neither manages nor a keep-list spares — then removes only what you confirm **one at a time** (via `gum` when installed). **Tool-aware:** config whose owning tool is still present is kept automatically — the union of three signals: the tool's brew package is installed, its command is on PATH (mise/gcloud tools count too), **or** its owning VS Code extension is in `code --list-extensions`; uninstall the tool (or drop the extension) and its config re-surfaces as removable. Most tools are matched by a stem heuristic (`command -v <name-minus-dot>`, e.g. `.gradle`→`gradle`); the `cleanup.owners` map holds only the aliases where the dir name and the command/package/extension diverge (`.kube`→`kubectl`, `.m2`→`mvn`, `.sonarlint`→`sonarsource.sonarlint-vscode`). Offered entries are labelled `orphan` (a known tool, now gone) or `untracked` (no known owner); `-v`/`--verbose` also lists what tool-ownership kept. Pass `--all` (`-a`/`--yes`/`-y`) to remove the whole set after one confirmation, or `YES=1 chezclean` to accept-all; both need a TTY. `DRY_RUN=1` (or `-n`/`--dry-run`) previews and works headless. **Safe by construction:** only names beginning with `.` are ever considered (so `~/Library`, `~/Documents`, … are structurally out of scope), it never descends past an immediate child, and it removes nothing without a controlling terminal. Keep an entry for good by adding it to `cleanup.keepHome`/`cleanup.keepConfig` (or, if it's a tool whose dir name diverges from its command, map it in `cleanup.owners`). |

### Progress

Where a real denominator exists, you get a real bar:

```
│  ████████████░░░░░░░░░░░░  50%  34/67  docker-desktop  4m18s
```

The number is not an estimate. `brew bundle` prints exactly one line per
Brewfile entry — `Using <name>` when it is already present, or
`<verb> <name>` (Installing / Upgrading / Tapping) when it acts — so the total is
the count of declared entries and each line is one entry genuinely resolved. The
parsing lives in [`scripts/lib/brew-progress.sh`](../scripts/lib/brew-progress.sh)
and is pinned by `tests/progress.bats`.

The bar redraws on a 1-second timeout as well as on new output, so during a
single large cask download the clock keeps moving instead of looking frozen.

**The bar gets out of the way of a password prompt.** A cask that ships an Apple
installer package runs it under `sudo`, and Homebrew hands that child a closed
stdin — so `sudo` opens `/dev/tty` itself and its prompt lands *outside* the
pipeline the bar is reading, where the next redraw erased it. The install really
was halted, waiting on a prompt nobody could see, until `sudo`'s `passwd_timeout`
gave up and failed that one cask; that is what made it look intermittent. Now
`brew-progress.sh` polls `sudo -n true` and, the moment the ticket is missing,
stops drawing entirely and prints an **Administrator password needed** banner
instead — the counter keeps advancing off-screen, finished packages print as
plain `[n/total]` lines, and the bar only comes back after an `✓ password
accepted`. The apply hook also asks up front, before the bar exists, so on a
normal run the prompt never has to happen here at all.

**Where there is no denominator, there is no bar.** Apple's Command Line Tools
installer exposes no progress data, so that step gets an elapsed timer only —
`ui_wait_tick`, not `ui_progress_*`. mise renders its own per-tool progress, so
the hook reports how many runtimes are missing and then stays out of the way.
A bar that is not backed by data is worse than none, because it invites you to
trust it.

### Output and quietness

Every verb opens with a short plain-language note: what it is about to do, and
what it will never do (`chezmirror` removes packages; nothing else does). Long
steps are numbered `[2/5]` and print elapsed time once they pass a few seconds,
so a slow install reads as *working* rather than *hung*.

Set `QUIET=1` on any verb — including `install.sh` — to drop the explanations and
keep only results:

```sh
QUIET=1 chezup
```

The vocabulary lives in [`scripts/lib/log.sh`](../scripts/lib/log.sh)
(`explain`, `ui_init_steps`, `step_begin`, `ui_elapsed`). `install.sh` mirrors it
by hand rather than sourcing it: it runs via `curl | bash` **before the repo
exists on disk**, so there is nothing to source yet — `tests/setup-ux.bats`
guards that it never grows a `source scripts/lib/…` line, and that neither file
uses a `printf '\uXXXX'` escape, which bash 3.2 (what a fresh Mac ships) prints
literally.

> **Why apply never uninstalls.** An apply must be safe to run at any time, so
> it only *adds* presence. Freshness is `chezbump`'s job; *removal* is
> `chezmirror`'s, always behind a confirm. See
> [lifecycle.md](lifecycle.md#convergence-guarantee).

> **`~/.config` is reconciled by `chezclean` too.** It's a normal `dot_config`
> dir, so an apply never prunes it; `chezclean` handles untracked
> `~/.config/X` (keep-list `cleanup.keepConfig`) alongside the top level of
> `$HOME`. See
> [lifecycle.md](lifecycle.md#reconciling-untracked-dotfiles-chezclean).
