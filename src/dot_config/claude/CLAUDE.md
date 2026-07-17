# Global defaults

Cross-project defaults for how I work in any repo on this machine. A project's own
`CLAUDE.md` and its existing code patterns always win over anything here — treat
these as the baseline, not the last word.

## Communication

- Concise and direct. Skip preambles ("Certainly!", "Great question!"), don't
  restate the request, and don't recap what you just did unless I ask.
- Prose over bullets; reach for a list only for genuinely parallel items.
- When you recommend something, name the tradeoff and the alternative you'd reach
  for if the situation flipped.
- Don't re-paste code I just saw. Don't apologize when correcting yourself — just
  state the correction.
- A short *why* is welcome when the topic is unfamiliar; otherwise stay terse.

## Working approach

- Read the surrounding code first; existing project patterns beat general
  preference.
- Prefer structured parsers and framework APIs over ad-hoc string manipulation
  when the tooling is available.
- Use `rg` / `rg --files` for search. Treat a dirty worktree as normal — never
  revert changes you didn't make unless I ask.
- For routine work, make the change and run the narrowest useful check, then
  report — don't stop at a proposal. Pause and ask before blast-radius changes:
  schema/migrations, auth, concurrency, public APIs, infra, CI/pipelines.

## Verification

- Verification scales with blast radius: narrowest useful check first (targeted
  test / build / typecheck / lint), broaden to integration when touching
  persistence, cross-module contracts, auth, or user-facing flows.
- State what you did and didn't verify. If you can't verify something, say so and
  name the risk.

## Git & PRs

- **Conventional Commits** for every commit *and* PR title:
  `<type>(<scope>): <subject>` — imperative, ≤ 72 chars. Types: `feat, fix, docs,
  refactor, test, chore, perf, build, ci, style`.
- Body (when needed) explains the *why*, separated from the subject by a blank
  line. Breaking changes append `!` to the type and add a `BREAKING CHANGE:`
  footer.
- Open a PR by default and let CI run; match the repo's workflow when it defines
  one. PR description = what changed, *why*, and any rollout/follow-up — scannable.
- Never commit secrets. Never force-push a shared branch.

## Code style

Assume the usual best practices (readability over cleverness, modern syntax that
clarifies rather than shows off) without being told. My deltas:

- **Comments: keep them to an absolute minimum.** Explain *why*, never *what* —
  the code already says what. Don't restate the line below, don't narrate obvious
  steps, and don't leave commented-out code behind. When a comment earns its place,
  keep it short and scannable. Prefer a clear name or a small refactor over a
  comment.
- Match the surrounding file's naming, structure, and conventions over any general
  preference.

## Output hygiene

- Edit existing files over creating new ones; don't add docs or READMEs unless
  asked.
- Clean up scratch and temp files you create. Leave no debug prints or
  commented-out code behind.

## Secrets & safety — hard rule

- Never print, commit, move, or transform secrets, tokens, keys, credentials,
  signing material, or auth files. Use `.env.example`, placeholders, or
  secret-manager references — never real values.
- Treat `~/.ssh`, `~/.config/{gh,gcloud,1Password}`, `~/.azure`, `~/.claude*`, and
  `.env` files as sensitive unless I say otherwise.
- Keep proprietary or internal context (cluster names, namespaces, internal URLs,
  ticket contents, private code) out of commits, PR descriptions, and prompts to
  external tools. When in doubt, keep it in the repo it came from.
