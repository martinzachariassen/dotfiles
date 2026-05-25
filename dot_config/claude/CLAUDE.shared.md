# Claude Code — shared base

Imported by the active profile via `@~/.config/claude/CLAUDE.shared.md`.
Profile-specific operating posture lives in the importing file. Project-level
`<project>/CLAUDE.md` overrides this base; the more specific instruction wins.

## About me

Senior backend developer, macOS (Apple Silicon). Primary stack: Java (21/25) +
Kotlin with Spring Boot; Node/TypeScript when the situation calls for it.

## Communication

- Concise and direct. No preambles ("Certainly!", "Great question!"), no
  restating my question, no summary of what you just did unless I ask.
- Prose over bullet lists for explanations; bullets only for genuinely parallel
  items.
- When you recommend an approach, name its tradeoff and the alternative you'd
  reach for if the situation flipped.
- Don't re-paste code I just saw. Don't apologize when self-correcting — state
  the correction and move on.

## Working approach

- Read the codebase first; follow existing patterns over general preference.
- Use `rg`/`fd`; prefer structured parsers and framework APIs over ad-hoc
  string manipulation.
- When you can't run a verification step, say so plainly and name the risk.
- Trust my installed devbox/Brewfile tool versions — don't hedge about version
  compatibility for tools I have.

## Code style

- Comments explain *why*, not *what* — skip obvious-comment noise.
- Don't add dependencies unless they remove real complexity or match an
  existing project pattern.
- Java: Lombok where the project uses it — `@RequiredArgsConstructor` for
  injection, `@Slf4j` for logging; never field `@Autowired`. `var` only when the
  type is self-evident.
- Spring Boot: constructor injection always; `@ConfigurationProperties` over
  scattered `@Value`; SLF4J parameterized logging (`log.debug("x={}", x)`,
  never concatenation). I run both 3.x and 4.x — don't force-upgrade APIs.
- Tests: JUnit 5 + AssertJ; MockMvc/WebTestClient for the HTTP layer;
  Testcontainers for anything touching a real DB or queue.
- Database: Postgres-first; **UUID primary keys always**; migrations via Flyway.
- Build: Maven and Gradle are both fine — match the project, don't convert.
- API: REST + OpenAPI, spec generated from controllers via `springdoc-openapi`.

## Environment

- Per-project runtimes via **devbox + direnv**. Never suggest mise, asdf, nvm,
  jenv, pyenv, rbenv, Volta, SDKMAN, or installing language runtimes via brew.
- Terminal is Ghostty + Zellij (not tmux); plain zsh (no oh-my-zsh/prezto/zinit).

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
