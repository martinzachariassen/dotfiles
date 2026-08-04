# Global defaults

Cross-project defaults for working in any repo on this machine — deltas from
Claude Code's own built-in defaults, not a restatement of them. A project's own
`CLAUDE.md` and existing code patterns always win over anything here.

## Communication

- Skip preambles ("Certainly!", "Great question!") and don't restate the request.
- Prose over bullets; reach for a list only for genuinely parallel items.
- When you recommend something, name the tradeoff and the alternative you'd reach
  for if the situation flipped.
- Don't re-paste code shown just above. Don't apologize when correcting yourself —
  just state the correction.
- A short *why* is welcome when the topic is unfamiliar; otherwise stay terse.

## Working approach

- Existing project patterns beat general preference — in code style, naming, and
  structure alike.
- Use `rg` for search. Treat a dirty worktree as normal — never revert changes you
  didn't make unless asked.
- Pause and ask before schema/migration, auth, concurrency, public-API, infra, or
  CI/pipeline changes, even for local in-repo edits — and broaden verification to
  integration checks for that same list.
- State what you did and didn't verify; name the risk if you couldn't.

## Git & PRs

- **Conventional Commits** for every commit *and* PR title:
  `<type>(<scope>): <subject>` — imperative, ≤ 72 chars. Types: `feat, fix, docs,
  refactor, test, chore, perf, build, ci, style`.
- Body (when needed) explains the *why*, separated from the subject by a blank
  line. Breaking changes append `!` to the type and add a `BREAKING CHANGE:`
  footer.
- Open a PR by default and let CI run; match the repo's workflow when it defines
  one.

## Code style

- Prefer a clear name or a small refactor over a comment; don't leave
  commented-out code behind.
- Clean up scratch and temp files you create.

## Secrets & safety — hard rule

- Never print, commit, move, or transform secrets, tokens, keys, credentials,
  signing material, or auth files. Use `.env.example`, placeholders, or
  secret-manager references — never real values.
- Treat `~/.ssh`, `~/.config/{gh,gcloud,1Password}`, `~/.azure`, `~/.claude*`, and
  `.env` files as sensitive unless told otherwise.
- Keep proprietary or internal context (cluster names, namespaces, internal URLs,
  ticket contents, private code) out of commits, PR descriptions, and prompts to
  external tools. When in doubt, keep it in the repo it came from.
