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
- Tests: JUnit 5 + AssertJ; MockMvc/WebTestClient for the HTTP layer;
  Testcontainers for anything touching a real database or queue.

### Build, database, API

- Maven and Gradle are both fine — match the project, don't convert.
- Postgres-first; **UUID primary keys always** (no serial/bigint surrogates);
  migrations via Flyway.
- REST + OpenAPI via `springdoc-openapi`; treat the generated spec as the source
  of truth for consumers.

## Environment

- Language runtimes via **mise** — global defaults (java, node) in
  `~/.config/mise/config.toml`; per-project versions + env vars in each project's
  own committed `mise.toml` (its `[env]` section, not direnv). On `cd`,
  `mise activate` switches toolchain and sets `JAVA_HOME`. For new projects,
  propose a committed `mise.toml` that pins runtimes. For Node prefer `pnpm`.
- Never suggest asdf/nvm/jenv/pyenv/rbenv/Volta/SDKMAN, or installing runtimes
  via brew. Install global dev CLIs (kubectl, terraform, …) via Homebrew, not
  language installers; database servers and project CLIs stay in Homebrew or run
  via Docker — mise manages language runtimes, not everything.
- Terminal: Ghostty + Zellij (not tmux). Shell: plain zsh (no
  oh-my-zsh/prezto/zinit) — extend the managed `.zshrc`, don't add a framework.
- Editors: VS Code (GUI), Neovim + LazyVim (terminal), IntelliJ for non-trivial
  Java/Kotlin work.
- Prefer modern CLI tools: `eza`/`ls`, `rg`/`grep`, `fd`/`find`, `bat`/`cat`,
  `dust`/`du`. Favor declarative/idempotent approaches; for state-mutating
  shell, detect-then-act so re-runs are cheap.

## Secrets — hard rule

- Never print, commit, move, or transform secrets, tokens, keys, cloud
  credentials, signing material, or auth files.
- Treat `~/.ssh`, `~/.config/{gh,gcloud,1Password}`, `~/.azure`, `~/.claude*`,
  `~/.codex/auth.json`, and `.env` files as sensitive unless I say otherwise.
- Use `.env.example`, placeholders, or secret-manager references — never real
  values.

## Commits — hard rule

- Conventional Commits: `<type>(<scope>): <subject>` — imperative mood, ≤72
  chars. Types: feat, fix, docs, refactor, test, chore, perf, build, ci, style.
- Body (when needed) explains the *why*, separated from the subject by a blank
  line.
- Breaking changes: append `!` to the type (`feat(api)!: drop /v1 endpoints`) and
  add a `BREAKING CHANGE:` footer.
- **Commits are authored by me only. Never add `Co-authored-by`, "Generated
  with…", or any AI attribution.**
