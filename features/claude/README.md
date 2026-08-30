# Claude configuration

The Claude Code environment on this Mac: the persona, the settings allowlist,
and the status line. There is no verb and no hook — everything here is a file
chezmoi deploys — so this directory holds the tests and this document, and the
deployed files stay under `src/` where chezmoi can render them.

| Piece | Where |
|---|---|
| Persona | [`src/dot_config/claude/CLAUDE.md.tmpl`](../../src/dot_config/claude/CLAUDE.md.tmpl) |
| Settings | [`src/dot_config/claude/settings.json`](../../src/dot_config/claude/settings.json) |
| Status line | [`src/dot_config/claude/executable_statusline.sh`](../../src/dot_config/claude/executable_statusline.sh) |
| Rules and skills | `src/dot_config/claude/rules/`, `src/dot_config/claude/skills/` |

The full tour is [docs/ai.md](../../docs/ai.md).

## The boundary with `distill`

The persona `@`-imports `~/.config/claude/memory/MAIN.md`, and that file is
**not** chezmoi's. It is written by [`distill`](../distill) from past sessions,
into a directory chezmoi does not manage. This feature deploys the persona that
reads the memory; the other one writes it.

That split is why the gate is empty rather than `claudePersona`: the settings
and status line deploy on every machine regardless of which modules are
selected, so a feature-wide module gate would be wrong.

## The status line

`statusline.sh` reads a JSON payload on stdin and prints one line: model,
directory, git state, context usage, cost. It is the one piece of real code
here, and [`tests/statusline.bats`](tests/statusline.bats) covers field
extraction, the conditional mode flags and the number/duration formatters.

Two things shape those tests. The git section is exercised only for its
"absent" path, because the script reads live repository state and asserting on
branch names or dirty counts would make the suite depend on the worktree it runs
in. And the Nerd Font icons are `eval`'d straight out of the script rather than
written out as literals — a private-use codepoint is invisible in a test file,
so a second copy would be unreviewable and would drift silently.
