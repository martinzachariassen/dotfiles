# The install.sh wizard

`install.sh` is the guided, single-file bootstrap a brand-new Mac runs **before**
chezmoi, Homebrew, or mise exist. That makes it the most fragile script in the
repo: it must be self-contained, defensive, work over SSH and `curl | bash`, and
never leave the terminal in a broken state. It has also been the easiest thing to
quietly break — twice now in the prompt/TTY plumbing.

This document is the contract. **If you change `install.sh` (or any `prompt_*` /
TTY code), read this and run the validation at the bottom before committing.**

## Philosophy

- **Small and consistent.** Reuse the existing `prompt_*` helpers. Don't invent a
  new way to read input.
- **Degrade, never crash.** Every interactive feature has a non-tty / `YES=1`
  fallback. The wizard must finish unattended.
- **Reversible by default.** Nothing destructive happens without an explicit
  typed confirmation, and `DRY_RUN=1` prints every state change instead of doing
  it.
- **macOS stock bash 3.2.** No bash 4+ features (see invariant 7).

## Flow

`main()` runs the phases in order:

```
require_non_root → banner → probe → choices → confirm_phase → execute → self_test → next_steps
```

- **banner / probe** (Step 1): detect terminal capabilities and machine state
  (Xcode CLT, brew, chezmoi, repo, 1Password, legacy files). Read-only.
- **choices** (Step 2): gather answers — profile, name, email, then the
  "recommended vs custom" fork and, under custom, the advanced prompts.
- **confirm_phase** (Step 3): show the plan, require a typed phrase for any
  destructive Homebrew cleanup, then a final Proceed gate.
- **execute / self_test / next_steps** (Steps 4–5): apply, verify, hand off.

## Prompt primitives — the only sanctioned way to read input

| Helper | Use for | Non-interactive fallback |
|---|---|---|
| `prompt_read OUT "msg"` | low-level single line from `/dev/tty` | — (callers gate first) |
| `prompt_text OUT title default hint` | free text with a default | emits `default` |
| `prompt_choice OUT title default opts…` | pick one of N | emits `default` |
| `prompt_confirm OUT title default_yes` | yes/no | emits the default |
| `prompt_phrase "PHRASE"` | typed confirmation for destructive ops | returns 1 (caller aborts) |

`prompt_choice` / `prompt_confirm` render an **arrow-key menu** (`ui_select_raw`)
when `UI_RAW=1`, and fall back to a **numbered list** (`_choice_numbered`)
otherwise.

## The TTY model — the danger zone

- **All prompts read from and write to `/dev/tty` directly**, never stdin/stdout.
  That's deliberate: it keeps prompts working when stdin is a pipe
  (`curl … | bash`) and when stdout is redirected to a log.
- **`have_tty()`** decides whether we can prompt at all. No tty ⇒ every helper
  returns its default.
- **`UI_RAW`** (tty + `stty` present + not `YES=1`) decides arrow menus vs the
  numbered fallback.
- **Raw menus** put the terminal into `-icanon -echo` and hide the cursor. They
  **must** restore the saved `stty` and the cursor on *every* exit path. The
  `EXIT`/`INT`/`TERM` trap (`cleanup_background_jobs → restore_terminal`) is the
  safety net — keep it intact.

## Invariants — break these and the wizard breaks

1. **Read input only through the `prompt_*` helpers.** Don't add bare `read`s in
   the flow.
2. **Never hand-roll a non-blocking TTY "drain" around bash's `read -n`.** bash
   installs its *own* termios for `read -n` / `read -s` and ignores your
   `stty min/time`, so a drain loop blocks forever and hangs the wizard. This
   exact bug shipped once (see the case study). If you think you need to flush
   pending input, you almost certainly don't — fix the consumer instead.
3. **Empty input must never hard-abort a long flow.** A reflex Enter or a stray
   newline should re-ask, not nuke the run. `prompt_phrase` loops for this reason.
4. **Every prompt has a non-interactive answer.** Gate with `have_tty` /
   `ASSUME_YES` and emit the default. `YES=1` and CI runs must never block.
5. **Always restore the terminal.** Any new raw-mode path saves `stty` up front,
   sets `UI_STTY_SAVED`, and restores on all exits including signals.
6. **Destructive actions require a typed phrase *and* respect `DRY_RUN`.** Wrap
   state changes in `run` / `timed_run` so a dry run only prints them.
7. **bash 3.2 only.** No `read -t <fraction>`, no `declare -A`, no `${var^^}`, no
   `mapfile`/`readarray`. Guard array access under `set -u` with explicit length
   checks (`[ ${#arr[@]} -eq 0 ]`).
8. **Keep the top-of-file comment honest** about how input actually works.

## Validating a change — do this before every commit

**Static** (CI enforces both in the "shell scripts" job):

```sh
bash -n install.sh
shellcheck --severity=error --shell=bash install.sh
```

**Non-interactive smoke** — must finish without ever blocking:

```sh
YES=1 DRY_RUN=1 bash install.sh            # accept defaults, print actions
DRY_RUN=1 bash install.sh </dev/null       # no-tty path returns defaults
```

**Interactive drive** — the regression guard for the TTY bugs:

```sh
python3 tests/drive-wizard.py clean        # full custom+mirror path, must not hang
python3 tests/drive-wizard.py stray        # stray Enter at the phrase re-asks, doesn't abort
```

`tests/drive-wizard.py` runs the real wizard inside a pseudo-terminal under
`DRY_RUN=1`, plays the user's keystrokes, and **always answers "No" at the final
Proceed** — so nothing is ever installed or removed. It exits non-zero (2) if the
wizard hangs, which is exactly the failure mode that bit us. It assumes a macOS
workstation with Homebrew present (so the cleanup-mode + typed-phrase path is
exercised). Requires `python3` (ships with the Xcode Command Line Tools).

## Case study: the drain that hung the menus

A change tried to "drain leftover TTY bytes" after each arrow menu with
`stty min 0 time 0` plus a `read -n1` loop, to stop a stray newline from being
read as empty at the typed-phrase confirm. Because bash overrides termios for
`read -n`, the loop never saw a non-blocking read and **froze the wizard after
the first selection**. The real fix was smaller: delete the drain and make
`prompt_phrase` re-ask on empty input instead. That's where invariants 2 and 3
come from, and why `tests/drive-wizard.py` now fails on a hang.
