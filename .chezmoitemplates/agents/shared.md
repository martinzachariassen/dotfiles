## About me

Senior backend developer on macOS (Apple Silicon).

**Primary stack:** Java (21 or 25) + Kotlin with Spring Boot. Reach for
Node/TypeScript when the situation calls for it.

**Cloud / infra:** Kubernetes, Azure, GCP. Terraform for IaC. I'm still building
intuition with Terraform, so a brief *why* behind Terraform suggestions is
welcome. For my main stack (Java/Kotlin/Spring Boot), don't over-explain
fundamentals.

## Communication

- Concise and direct. Skip preambles ("Certainly!", "Great question!"), don't
  restate my question, and don't recap what you just did unless I ask.
- Prose over bullets; reach for bullet lists only for genuinely parallel items,
  not as a default format.
- Recommendations: name the tradeoff and the alternative you'd reach for if the
  situation flipped.
- Don't re-paste code I just saw — assume I can scroll up.
- Don't apologize when correcting yourself; just state the correction.
- Don't surface "this might not work in older versions" caveats for tools I have
  installed. Trust my mise/Brewfile versions; if compatibility genuinely matters
  for a snippet, say so once and move on.
- Default cloud examples to Azure or GCP. AWS is fine when I ask, or when the
  topic is cloud-agnostic and AWS is the most recognizable baseline.

## Working approach

- Read the codebase first; existing project patterns beat general preference.
- Prefer structured parsers and framework APIs over ad-hoc string manipulation
  when the tooling is already available.
- Keep edits scoped to the request; no opportunistic refactors unless they're
  needed to finish the task safely. Treat a dirty worktree as normal — never
  revert changes you didn't make unless I ask.
- Use `rg` / `rg --files` for searching whenever possible.
- Verification: run the narrowest useful check first (targeted test, formatter,
  typecheck, linter). Broaden when the change touches shared behavior,
  persistence, auth, concurrency, or user-facing workflows. If you can't verify,
  say so plainly and name the risk.

## Code style

### General

- Readability over cleverness; code is read more than it's written.
- Apply language/framework best practices, but don't reach for advanced features
  just because they exist — modern syntax should clarify, not show off.
- Add dependencies only when they remove real complexity or match an existing
  project pattern.
- Comments explain *why*, not *what* — surprising decisions, workarounds,
  non-obvious algorithms. Skip obvious-comment noise.

### Java (target 21, ready for 25)

- Records for immutable carriers; sealed interfaces/classes for closed
  hierarchies.
- Pattern matching + switch expressions over `if`/`instanceof` chains.
- `var` only when the type is self-evident from the right-hand side.
- Lombok in projects that use it (and new Spring Boot Java services unless
  there's a concrete reason not to): `@RequiredArgsConstructor` for injection,
  `@Slf4j` for the logger, `@Value`/`@Data`/`@Builder` where they earn their
  keep. Never field-level `@Autowired`.

### Kotlin

- `data class` for value types; `sealed interface` for closed hierarchies.
- Immutable by default (`val`, `List`, `Map`).
- Scope functions (`let`/`apply`/`also`/`run`/`with`) only where they genuinely
  improve readability; extension functions over utility classes.
- Lean on null safety; avoid `!!` outside truly unreachable paths.
- Constructor injection is implicit — no annotation on primary-constructor
  params.

### Spring Boot

- Both 3.x and 4.x in play: new projects target 4+, maintenance projects stay on
  what they already use. Don't force-upgrade APIs unless I ask.
- Constructor injection always. Thin controllers, services for business logic,
  repositories for persistence.
- `@ConfigurationProperties` (typed) over scattered `@Value`.
- Jakarta Bean Validation (`@Valid`, `@NotNull`, …) at boundaries.
- SLF4J parameterized logging (via Lombok `@Slf4j` in Java), never
  concatenation: `log.debug("user {} requested {}", userId, resource)`.
- Error responses via `@RestControllerAdvice` returning `ProblemDetail` (RFC
  7807). Throw unchecked exceptions for non-recoverable conditions and map them
  in one place — don't catch-and-rethrow through the call stack.
- Tests: JUnit 5 + AssertJ. Prefer the narrow slice annotations
  (`@WebMvcTest`, `@DataJpaTest`, `@JsonTest`) over `@SpringBootTest`; reach
  for a full context only when the test genuinely needs one. MockMvc /
  WebTestClient for the HTTP layer; Testcontainers for anything touching a
  real database or queue.

### Logging & observability

- Structured JSON logs in deployed services (Spring Boot 3.4+'s
  `logging.structured.format`, or logstash-logback-encoder on older versions);
  plain console output in dev.
- Correlation IDs via SLF4J MDC at the request boundary; make sure they
  propagate across async / reactive contexts.
- Metrics via Micrometer (built-in Spring Boot bridge); OpenTelemetry for
  traces, and for logs too when the project's collector supports it.
- Never log secrets, full tokens, raw PII, or full request/response bodies on
  hot paths — log identifiers and shapes, not contents.

### Build, database, API

- Maven and Gradle are both fine — match the project, don't convert.
- Postgres-first; **UUID primary keys always** (no serial/bigint surrogates);
  migrations via Flyway.
- REST + OpenAPI via `springdoc-openapi`; treat the generated spec as the source
  of truth for consumers.

## Environment

This is the durable shape of the machine. Specific packages come and go — don't
assume any one tool is installed; if a workflow needs something, say so and add
it to the Brewfile or mise rather than reaching for `npm -g` / `pip --user`.

- macOS (Apple Silicon) workstation managed by chezmoi, XDG layout
  (`ZDOTDIR=~/.config/zsh`).
- **Language runtimes come from mise** — global defaults in
  `~/.config/mise/config.toml`, per-project versions + env in each project's
  committed `mise.toml` (`[env]` section, not direnv). For new projects propose a
  committed `mise.toml`; for Node prefer `pnpm`. Never suggest
  asdf/nvm/jenv/pyenv/rbenv/Volta/SDKMAN or installing runtimes via brew.
- **Global CLIs and apps come from Homebrew**; databases and project services run
  via Docker / Testcontainers — mise owns language runtimes, not everything.
- Shell: plain zsh, no framework (oh-my-zsh/prezto/zinit) — extend the managed
  `.zshrc`. Terminal: Ghostty + Zellij (not tmux). Prompt: Starship. Prefer
  modern CLI replacements where they exist.
- Editors: VS Code (GUI), Neovim + LazyVim (terminal), IntelliJ for non-trivial
  Java/Kotlin. Commits signed through 1Password's `op-ssh-sign`.
- Favor declarative/idempotent approaches; for state-mutating shell,
  detect-then-act so re-runs are cheap.

## Secrets — hard rule

- Never print, commit, move, or transform secrets, tokens, keys, cloud
  credentials, signing material, or auth files.
- Treat `~/.ssh`, `~/.config/{gh,gcloud,1Password}`, `~/.azure`, `~/.claude*`,
  `~/.codex/auth.json`, and `.env` files as sensitive unless I say otherwise.
- Use `.env.example`, placeholders, or secret-manager references — never real
  values.

## Commits & PRs — hard rule

- Conventional Commits: `<type>(<scope>): <subject>` — imperative mood, ≤72
  chars. Types: feat, fix, docs, refactor, test, chore, perf, build, ci, style.
- Body (when needed) explains the *why*, separated from the subject by a blank
  line.
- Breaking changes: append `!` to the type (`feat(api)!: drop /v1 endpoints`) and
  add a `BREAKING CHANGE:` footer.
- PR descriptions follow the same shape — what changed, *why*, and any rollout
  or follow-up notes. Keep them scannable.
- **All of the above is authored by me only. Never add `Co-authored-by`,
  "Generated with…", or any AI attribution to commits, PR descriptions, code
  comments, or docs.**
