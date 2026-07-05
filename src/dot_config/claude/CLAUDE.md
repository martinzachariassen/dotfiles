# Global AI defaults

My cross-project working agreement — loaded for every project on this machine.
Project-level instructions and existing code patterns always win over anything
here.

## About me

Senior backend developer on macOS (Apple Silicon).

**Primary stack:** Kotlin with Spring Boot on Java 25; plain Java when a project
already uses it or the situation calls for it. Node/TypeScript for tooling,
scripts, and edge/serverless work.

**Cloud / infra:** Kubernetes, Azure, GCP. Terraform for IaC. I'm still building
intuition with Terraform, so a brief *why* behind Terraform suggestions is
welcome. For my main stack (Kotlin/Java + Spring Boot), don't over-explain
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
- A short *why* — the reasoning or tradeoff — is welcome when I'm working with
  something unfamiliar, even though the default is to be concise.
- Default cloud examples to Azure or GCP. AWS is fine when I ask, or when the
  topic is cloud-agnostic and AWS is the most recognizable baseline.

## Operating posture

These are all my own personal/solo repos — high autonomy is the default:

- Make the change, run the narrowest useful check, report — don't stop at a
  proposal for routine work. Committing straight to `main` is fine.
  Experimentation and small opportunistic cleanups alongside a change are
  welcome. Add a dependency when it clearly helps and just mention it.
- Still pause and ask before blast-radius changes — schema/migrations, auth,
  concurrency, public APIs, infra, CI/pipelines.
- **Verification scales with blast radius:** narrowest useful check first
  (targeted test/build/typecheck/lint); broaden to integration when touching
  persistence, cross-module contracts, auth, or user-facing flows. State what you
  did and didn't verify; if you can't verify, say so and name the risk.

## Working approach

- Read the codebase first; existing project patterns beat general preference.
- Prefer structured parsers and framework APIs over ad-hoc string manipulation
  when the tooling is already available.
- Treat a dirty worktree as normal — never revert changes you didn't make unless
  I ask.
- Use `rg` / `rg --files` for searching whenever possible.

## Code style

These are my deltas from sensible defaults — assume the usual best practices
(readability over cleverness, comments for *why* not *what*, modern syntax that
clarifies rather than shows off) without being told.

### Kotlin (primary) & Java

- Kotlin: avoid `!!` outside truly unreachable paths; constructor injection is
  implicit — no annotation on primary-constructor params.
- Java: Lombok in projects that use it (and new Spring Boot Java services unless
  there's a concrete reason not to): `@RequiredArgsConstructor` for injection,
  `@Slf4j` for the logger, `@Value`/`@Data`/`@Builder` where they earn their
  keep. Never field-level `@Autowired`.

### Spring Boot

- Both 3.x and 4.x in play: new projects target 4+, maintenance projects stay on
  what they already use. Don't force-upgrade APIs unless I ask.
- `@ConfigurationProperties` (typed) over scattered `@Value`; Jakarta Bean
  Validation at boundaries.
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
  (`ZDOTDIR=~/.config/zsh`). The dotfiles repo lives at
  `~/Developer/personal/dotfiles`; edit chezmoi sources via `chezmoi edit ~/.X`
  (editing the live file in `$HOME` creates drift) and apply with the `chez` zsh
  function. Full conventions for that repo are in its `CLAUDE.md`.
- **mise owns runtimes, env, and tasks** — global defaults in
  `~/.config/mise/config.toml`, per-project versions + env in each project's
  committed `mise.toml` (`[env]` section, not direnv). Reach for `[tasks]` +
  `mise run` over ad-hoc scripts or a Makefile, and mise backends (cargo/npm/
  pipx/aqua/ubi) to pin project-local CLIs. For new projects propose a committed
  `mise.toml`; for Node prefer `pnpm`. Never suggest
  asdf/nvm/jenv/pyenv/rbenv/Volta/SDKMAN or installing runtimes via brew.
- **Global CLIs and apps come from Homebrew**; databases and project services run
  via Docker / Testcontainers — mise owns language runtimes, not everything.
- **Kubernetes:** `kubectx` / `kubens` for context + namespace switching; AKS
  auth via `kubelogin`.
- **Secrets in deployed environments** come from a secret manager (Azure Key
  Vault / GCP Secret Manager) — never plain env files, never values in committed
  config. Local dev may use `.env` + Spring profiles with placeholders.
- Shell: plain zsh, no framework (oh-my-zsh/prezto/zinit) — extend the managed
  `.zshrc`. Terminal: Ghostty + Zellij (not tmux). Prompt: Starship. Prefer
  modern CLI replacements when present: `rg`, `fd`, `bat`, `eza`, `zoxide`.
- Editors: VS Code (GUI), Neovim + LazyVim (terminal), IntelliJ for non-trivial
  Java/Kotlin. Commits signed through 1Password's `op-ssh-sign`.
- Favor declarative/idempotent approaches; for state-mutating shell,
  detect-then-act so re-runs are cheap.
- Durable notes and personal knowledge live in Obsidian — reach for the vault
  over scratch files when capturing thinking that should outlast the session.

## Secrets & confidentiality — hard rule

- Never print, commit, move, or transform secrets, tokens, keys, cloud
  credentials, signing material, or auth files. Use `.env.example`,
  placeholders, or secret-manager references — never real values.
- Treat `~/.ssh`, `~/.config/{gh,gcloud,1Password}`, `~/.azure`, `~/.claude*`,
  and `.env` files as sensitive unless I say otherwise.
- Keep proprietary or internal context (cluster names, namespaces, internal
  URLs, ticket contents, chat messages, private code) out of commits, PR
  descriptions, and prompts to external tools or pastebins. When in doubt, treat
  it as need-to-know and keep it in the repo it came from.

## Commits & PRs

- Conventional Commits: `<type>(<scope>): <subject>` — imperative mood, ≤72
  chars. Types: feat, fix, docs, refactor, test, chore, perf, build, ci, style.
- Body (when needed) explains the *why*, separated from the subject by a blank
  line.
- Breaking changes: append `!` to the type (`feat(api)!: drop /v1 endpoints`) and
  add a `BREAKING CHANGE:` footer.
- PR descriptions follow the same shape — what changed, *why*, and any rollout
  or follow-up notes. Keep them scannable.
