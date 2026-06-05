# Lifecycle: bootstrap & convergence

This is the **structural / UX contract** for how a machine gets set up and kept
in sync. It is deliberately *package- and version-agnostic* — it describes the
shape of the experience and the guarantees it must keep, not which formulae or
app versions happen to be installed today (those live in the Brewfiles and are
expected to change constantly).

If you change `install.sh`, the `.chezmoiscripts/run_after_*` scripts, the
`scripts/lib/brew-bundle.sh` engine, or the `chez*` shell functions, keep this
contract intact.

## The mental model: two verbs, one engine

There are exactly **two things a human does**, and they share one underlying
convergence engine so they look and behave the same on every Mac:

| Verb | Command | When |
|---|---|---|
| **Bootstrap** | `install.sh` | A brand-new Mac with nothing on it. Installs Xcode CLT, Homebrew, chezmoi, clones the repo, applies. |
| **Converge** | `chezup` | An existing Mac. Pull the repo and make this machine match it. |

Both end in the same place — `chezmoi apply` — which runs the same
`run_after_*` scripts through the same `scripts/lib/brew-bundle.sh` engine with
the same `◆ / → / ✓` progress vocabulary. A fresh install and a routine update
*feel* like the same product because they literally are the same apply path.

`chezdoctor` is the third everyday command: a read-only health check you run
whenever something feels off. It never changes state.

## The convergence guarantee (the important part)

> **Every `chezmoi apply` reconciles real installed state — not just changed
> files.**

Packages are installed based on what is *actually present on the machine*,
compared against what the active Brewfile modules declare. This holds no matter
how the apply was triggered (`install.sh`, `chezup`, `chez`, `chezreinit`).

This is why the package-install scripts are `run_after_*` (run on every apply)
and **not** `run_onchange_*` (run only when the Brewfile *text* changes).
Hash-gating tracks *inputs*, not *state*: a package can go missing — manual
uninstall, a half-finished apply, a new module you enabled — while the Brewfile
text is unchanged, and a hash-gated script would do nothing. That gap is exactly
why a separate `chezfix` once had to exist; with state-based convergence, it
doesn't anymore.

A fast short-circuit keeps this cheap: `bb_modules_satisfied` (a presence check —
is each declared formula/cask/tap installed?) and `mise ls --missing` let a clean
machine finish in a second or two and print "already matches" instead of grinding
through installs. It checks *presence*, not freshness — upgrading already-installed
packages is `chezbump`'s job, so a routine apply never surprise-upgrades anything.

## Robustness rules

- **Continue-on-error.** One flaky cask must never block the rest of the apply.
  The engine collects failures, keeps installing, prints a summary, and exits
  successfully so later steps (VS Code extensions, macOS defaults) still run.
- **Idempotent — re-run heals.** Any command is safe to run repeatedly. A failed
  item is simply retried on the next `chezup`; nothing needs manual repair.
- **Degrade, never crash.** Works over SSH and `curl | bash`, with non-UTF-8
  locales (ASCII glyph fallback via `scripts/lib/ui.sh`), and unattended
  (`YES=1` / no-tty paths). See `docs/wizard.md` for the installer's TTY rules.

## Look & feel — one product across all Macs

- The same engine prints the same `◆` phase headers, `→` per-item lines, and
  `✓ / ✗` results everywhere.
- Color and box/line glyphs come from one place, `scripts/lib/ui.sh`
  (`ui_init_colors` / `ui_init_glyphs`), which already falls back to plain ASCII
  and no-color when the terminal can't render them.
- `chezup`'s banner sources that same helper, so the update path is framed like
  the install wizard.

## Command map

**Everyday (the whole surface most days):**

- `install.sh` — bootstrap a new Mac
- `chezup` — converge this Mac to the repo
- `chezdoctor` — health check

**Advanced / occasional (kept, but not part of the daily flow):**

- `chez` — apply without pulling (the building block `chezup` calls)
- `chezreinit` — re-run `chezmoi init` to pick up new data-model keys, then apply
- `chezbump` — routine dependency upgrade (`brew upgrade` + `mise upgrade`)
- `chezaudit` — list Homebrew packages installed locally but not tracked here
- `dotfiles` — jump to the repo, or manage `profile` / feature toggles

**Installer flags (advanced, in the README `<details>`):** `--configure-only`,
`--mirror-brew`, `--reset-brew`, plus `DRY_RUN=1` / `YES=1` / `SKIP_BACKUP=1`.

## Invariants — don't regress these

1. **Apply always converges real state.** Never re-gate package install on input
   hashes. The package scripts stay `run_after_*` with a real-state check.
2. **Two everyday verbs only.** Don't reintroduce parallel "install"/"fix"/"sync"
   commands that do overlapping things. New capability folds into `chezup`,
   `chezdoctor`, or an advanced helper — it does not become a fourth daily verb.
3. **One engine, one look.** Package installs go through
   `scripts/lib/brew-bundle.sh`; terminal styling goes through `scripts/lib/ui.sh`.
   Don't fork a second installer loop or a second color scheme.
4. **Continue-on-error + idempotent.** A single failure never aborts the apply,
   and re-running always heals.

## Where each piece lives

| Piece | File |
|---|---|
| Convergence engine (progress, short-circuit, continue-on-error) | `scripts/lib/brew-bundle.sh` |
| Homebrew apply step (module selection + plan + drive) | `.chezmoiscripts/run_after_02-brew-bundle.sh.tmpl` |
| mise runtime apply step | `.chezmoiscripts/run_after_02b-mise-install.sh.tmpl` |
| Shared color/glyph helpers | `scripts/lib/ui.sh` |
| Everyday verbs (`chezup`, `chezdoctor`) + advanced helpers | `dot_config/zsh/dot_zshrc.tmpl` |
| Bootstrap wizard | `install.sh` (rules in `docs/wizard.md`) |
| Closing summary / reference card | `.chezmoiscripts/run_onchange_after_99-completion.sh.tmpl` |
