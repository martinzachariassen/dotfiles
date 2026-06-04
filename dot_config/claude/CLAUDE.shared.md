# Claude Code — shared base

## About me

Senior backend developer, macOS (Apple Silicon). Primary stack: Java (21/25) +
Kotlin with Spring Boot; Node/TypeScript when the situation calls for it.

## Communication

- Concise and direct. No preambles, no restating my question, no recap of what
  you just did unless I ask.
- Prose over bullets; bullets only for genuinely parallel items.
- Recommendations: name the tradeoff and the alternative if the situation
  flipped.
- Don't re-paste code I just saw. Self-correct without apologizing.

## Working approach

- Read the codebase first; existing patterns beat general preference.
- Prefer structured parsers and framework APIs over ad-hoc string manipulation.
- If you can't verify, say so and name the risk.
- Trust my installed tool versions — don't hedge about compatibility for things
  I have.

## Code style

- Comments explain *why*, not *what*.
- Add dependencies only when they remove real complexity or match a project
  pattern.
- Java: Lombok where the project uses it; constructor injection (never field
  `@Autowired`); `var` only when the type is self-evident.
- Spring Boot: `@ConfigurationProperties` over scattered `@Value`; SLF4J
  parameterized logging, never concatenation. Both 3.x and 4.x in play —
  don't force-upgrade APIs.
- Tests: JUnit 5 + AssertJ; MockMvc/WebTestClient; Testcontainers for real
  DB/queue.
- Database: Postgres-first; **UUID primary keys always**; Flyway migrations.
- Build: Maven or Gradle — match the project, don't convert.
- API: REST + OpenAPI via `springdoc-openapi`.

## Environment

- Language runtimes via **mise** — global defaults (java, node) in
  `~/.config/mise/config.toml`, per-project versions + env vars in each
  project's own `mise.toml` (its `[env]` section, not direnv). Never suggest
  asdf/nvm/jenv/pyenv/rbenv/Volta/SDKMAN or installing runtimes via brew.
- Terminal: Ghostty + Zellij (not tmux). Shell: plain zsh
  (no oh-my-zsh/prezto/zinit).

## Secrets — hard rule

- Never print, commit, move, or transform secrets, tokens, keys, or cloud
  credentials. Treat `~/.ssh`, `~/.config/{gh,gcloud,1Password}`, `~/.azure`,
  `~/.claude*`, and `.env` files as sensitive.
- Use `.env.example`, placeholders, or secret-manager references — never real
  values.

## Commits — hard rule

- Conventional Commits: `<type>(<scope>): <subject>` — imperative, ≤72 chars.
- **Commits are authored by me only. Never add `Co-authored-by`, "Generated
  with…", or any AI attribution.**
