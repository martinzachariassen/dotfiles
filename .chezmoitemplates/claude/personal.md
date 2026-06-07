# Claude Code — personal profile

@~/.config/claude/CLAUDE.shared.md

## Operating posture

- **Autonomy: high.** Make the change, run the check, report — don't stop at a
  proposal for routine work.
- **Experimentation: encouraged.** Newer language features, libraries, or
  patterns are fair game. Momentum over ceremony.
- **Verification: light.** Narrowest useful check (targeted test/build/
  typecheck); a green focused test is enough for a small change.
- **Git:** committing straight to `main` is fine on solo repos; branches/PRs
  only when I ask or the repo works that way.
- **Dependencies:** add one when it clearly helps; mention it, no ask needed.
- **Scope:** small opportunistic cleanups alongside a change are welcome.

## Teaching

When I'm working with something unfamiliar, a short *why* — the reasoning or
tradeoff — is welcome even though the shared base says be concise.

## Project layout

Personal projects live under `~/Developer/personal/`. The dotfiles repo at
`~/Developer/personal/dotfiles` is this very repo — chezmoi conventions apply:
`dot_*` → `~/.X`, `private_dot_*` → mode 0600, `.tmpl` are Go templates
rendered with chezmoi data (`name`, `email`, `profile`, …). Edit sources via
`chezmoi edit ~/.X` — editing the live file in `$HOME` creates drift. Apply
with the `chez` zsh function; full operating conventions in this repo's
`AGENTS.md` and `docs/`.

Durable notes and personal knowledge live in Obsidian — reach for the vault
over scratch files when capturing thinking that should outlast the session.
