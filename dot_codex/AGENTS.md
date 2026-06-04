# Personal Codex global config

This file is loaded automatically into every personal Codex session.
Project-specific overrides go in `<project>/AGENTS.md` and layer on top of this
one. Project instructions win when they are more specific.

---

## About me

Senior backend developer on macOS (Apple Silicon).

**Primary stack:** Java (21 or 25) + Kotlin with Spring Boot. Reach for
Node/TypeScript when the situation calls for it.

**Cloud / infra:** Kubernetes, Azure, GCP. **Terraform** for IaC. I am still
building intuition here, so briefly explaining the *why* behind Terraform
suggestions is welcome. For my main stack (Java/Kotlin/Spring Boot), do not
over-explain fundamentals.

---

## Communication style

- **Concise, direct.** Skip preambles like "Certainly!", "Great question!", or
  restating my question before answering.
- **Prose over bullets** for explanations. Reach for bullet lists only when
  enumerating genuinely parallel items, not as a default format.
- **Show tradeoffs, not just answers.** When recommending one approach, briefly
  name what it costs and what alternative I would reach for if the situation
  flipped.
- **Do not repeat code I just wrote** in a follow-up. Assume I can scroll up.
- **Do not pad** with summaries of what you just did unless I asked for one.

---

## Working model

- Read the codebase first and follow existing project patterns.
- Prefer making the change, running the relevant checks, and reporting the
  result over stopping at a proposal.
- Keep edits scoped to the request. Do not do opportunistic refactors unless
  they are needed to finish the task safely.
- Treat a dirty worktree as normal. Never revert changes you did not make
  unless I explicitly ask.
- Use `rg` / `rg --files` for searching whenever possible.
- Use structured parsers or framework APIs instead of ad hoc string
  manipulation when the tooling is already available.
- When you cannot run a relevant verification step, say that plainly and name
  the remaining risk.

---

## Verification

- Run the narrowest useful check first: a targeted test, formatter, typecheck,
  linter, or command that directly exercises the change.
- Broaden verification when the change touches shared behavior, cross-module
  contracts, persistence, auth, concurrency, or user-facing workflows.
- If a relevant check is expensive, unavailable, or blocked, say exactly what
  was not verified and what risk remains.

---

## Secrets and safety

- Never print, commit, move, or transform secrets, tokens, private keys, cloud
  credentials, signing material, or auth files.
- Treat `~/.ssh`, `~/.config/gh`, `~/.azure`, `~/.config/gcloud`,
  `~/.config/1Password`, `~/.codex/auth.json`, and local `.env` files as
  sensitive unless I explicitly say otherwise.
- Prefer `.env.example`, documented placeholders, or secret-manager references
  over real values.

---

## What I use

This machine is set up via my chezmoi-managed dotfiles repo at
`~/Developer/personal/dotfiles`. The following are assumed available. When suggesting
alternatives, default to these unless a specific project uses something else.

**Runtimes & version management**

- **`mise`** for language runtimes: java, node, python, etc. Global defaults
  (java, node) live in `~/.config/mise/config.toml`; each project pins its own
  versions + env vars in a committed `mise.toml`. On `cd`, `mise activate`
  switches to that project's toolchain and sets `JAVA_HOME` automatically — its
  `[env]` block carries project env vars, so no separate per-project env tool is
  needed.
- For a new Spring Boot service the scaffold is:
  ```sh
  mise use java@temurin-21 gradle@latest node@lts
  ```
  Commit the resulting `mise.toml`. Project env vars go in its `[env]` section.
- Common mise tools for my stack: `java@temurin-21` / `java@temurin-25`,
  `gradle`, `maven`, `node`, `python`. Database servers (Postgres, Redis) and
  CLIs (kubectl, terraform) stay in Homebrew or run via Docker — mise manages
  language runtimes, not everything.
- **No other runtime manager** (no asdf, nvm, jenv, pyenv, sdkman, ...) and
  never install runtimes via brew. Need a one-off version? `mise use -g
  java@temurin-21`, but default to per-project pins.

**Shell & terminal**

- zsh, XDG layout (`ZDOTDIR=~/.config/zsh`), `fzf` for fuzzy history search
  (`Ctrl-R`) backed by `fd` instead of `find`.
- `zsh-autosuggestions`, `zsh-syntax-highlighting`, and `zsh-completions`.
- Terminal: **Ghostty** | Multiplexer: **Zellij** | Prompt: **Starship**.
- `k` is aliased to `kubectl`.

**Editors**

- VS Code (GUI).
- Neovim with LazyVim (terminal).
- IntelliJ for non-trivial Java/Kotlin work.

**Git & ops**

- Signed commits via 1Password's `op-ssh-sign`; `delta` as the diff pager.
- `lazygit` for interactive git ops; `pre-commit` for hook frameworks.

**Databases**

- `pgcli` (Postgres) and `redis-cli` available globally via Brewfile.
- Prefer per-project datastores via Docker / Testcontainers instead of global
  brew services.

**HTTP / RPC**

- `httpie`, `grpcurl`, `mkcert` for local TLS.

**Kubernetes**

- Project tools: `kubectl`, `k9s`, `stern`, `helm` via Homebrew.
- Work-profile helpers: `kubectx`/`kubens`, AKS `kubelogin`, and GCP `gcloud`.
- GKE auth: `gke-gcloud-auth-plugin`.

**Cloud CLIs**

- Work-profile tools only: `az` (Azure), `gcloud` (GCP). My cloud stack is Azure + GCP.

**Infrastructure-as-Code**

- **Terraform** from HashiCorp's official tap, plus `tflint` and
  `terraform-docs`.

**Containers**

- Docker Desktop, `dive` for image introspection.

---

## Code style preferences

### General principles

- **Readability over cleverness.** Code is read more often than written.
- Apply language and framework best practices, but do not reach for advanced
  features just because they exist. Modern syntax should clarify, not show off.
- Do not add new dependencies unless they remove real complexity, match
  existing project patterns, or are clearly justified by the problem.
- **Comments explain why, not what.** Comment surprising decisions, non-obvious
  algorithms, workarounds, and topics that might confuse a future reader. Skip
  obvious-comment noise.

### Java (target 21, ready for 25)

- Records for immutable data carriers; sealed interfaces/classes for closed
  hierarchies.
- `var` only when the type is self-evident from the right-hand side.
- Pattern matching + switch expressions over `if`/`instanceof` chains.
- Use Lombok in projects that already use it, and for new Spring Boot Java
  services unless there is a concrete reason not to. Prefer
  `@RequiredArgsConstructor` for injection, `@Slf4j` for the logger, and
  `@Value`/`@Data`/`@Builder` where they earn their keep. Avoid field-level
  `@Autowired`.

### Kotlin

- `data class` for value types; `sealed interface` for closed hierarchies.
- Immutable by default (`val`, `List`, `Map`).
- Scope functions (`let`, `apply`, `also`, `run`, `with`) only where they
  genuinely improve readability.
- Extension functions over utility classes.
- Lean on null safety; avoid `!!` outside truly unreachable paths.
- Constructor injection is implicit. No annotation needed for primary
  constructor params.

### Spring Boot

- I work with **both 3.x and 4.x**. New projects target 4+; ongoing maintenance
  projects stay on whatever they already use. Do not force-upgrade APIs unless
  I ask.
- **Constructor injection always** (Lombok `@RequiredArgsConstructor` in Java;
  implicit primary constructor in Kotlin).
- Thin controllers, services for business logic, repositories for persistence.
- `@ConfigurationProperties` (typed) over scattered `@Value`.
- Jakarta Bean Validation (`@Valid`, `@NotNull`, etc.) at boundaries.
- **Logging via SLF4J**, accessed through Lombok's `@Slf4j` in Java. Always use
  parameterized logging:
  `log.debug("user {} requested {}", userId, resource)`.
- Tests: JUnit 5 + AssertJ; MockMvc/WebTestClient for the HTTP layer;
  Testcontainers for anything touching a real database or queue.

### Build tools

- **Maven and Gradle are both fine.** Match whatever the project already uses;
  do not suggest converting.

### Database

- **Postgres-first.**
- **Always UUIDs for primary keys**. No serial/bigint surrogates.
- Migrations via **Flyway**.

### API

- **REST + OpenAPI** as the default.
- Use `springdoc-openapi` to generate the spec from controllers; treat the
  generated spec as the source of truth for consumers.

---

## What to suggest

- Modern replacements for legacy CLI tools: `eza` over `ls`, `ripgrep` over
  `grep`, `fd` over `find`, `bat` over `cat`, `dust` over `du`.
- Declarative / idempotent approaches over imperative one-shots.
- For shell scripts that mutate state: detect-then-act patterns so re-runs are
  cheap, for example:
  ```sh
  if ! brew list foo >/dev/null 2>&1; then
      brew install foo
  fi
  ```
- Catch obvious correctness issues before style nits: error handling, race
  conditions, unbounded resource use, missing transaction boundaries, and
  missing tests for changed behavior.

---

## Commit conventions

- **Conventional Commits** format: `<type>(<scope>): <subject>`.
- Common types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `perf`,
  `build`, `ci`, `style`.
- Subject in imperative mood (`add`, not `added` or `adds`); <= 72 chars.
- Body, when needed, explains the *why*, separated from subject by a blank
  line.
- Breaking changes: append `!` to the type (`feat(api)!: drop /v1 endpoints`)
  and add a `BREAKING CHANGE:` footer.
- **Author attribution: commits are authored by me only, unless I explicitly
  ask otherwise.** Never add `Co-authored-by:`, "Generated with...", or any
  AI-generated attribution.

Examples:

```text
feat(auth): add JWT refresh endpoint
fix: handle null user-agent in middleware
chore(deps): bump spring-boot to 3.4
```

---

## Tooling conventions (positive defaults)

- **Always assume `mise`** for per-project language runtimes (JDK, Kotlin,
  Node, Python, etc.). Do not suggest `nvm`, `jenv`, `pyenv`, `rbenv`, `asdf`,
  `volta`, `sdkman`, or installing language runtimes via `brew` directly.
- **For new projects, propose a committed `mise.toml`** that pins the runtime
  versions and carries project env vars in its `[env]` section. The toolchain
  travels with the project repo, so onboarding is `git clone && cd` and `mise
  activate` switches to it automatically.
- **For Node, prefer `pnpm`** (pin it per project with `mise use node@lts pnpm@latest`).
- **For installing dev CLIs globally** (things I want available outside any
  project, such as `kubectl` or `terraform`), add them to my Brewfile rather
  than language-specific installers (`npm install -g`, `pip install --user`).
  Database servers and project CLIs stay in Homebrew or run via Docker, not mise.
- **For zsh customization**, add things to my managed `.zshrc` rather than
  introducing a framework (oh-my-zsh, prezto, zinit). My setup is plain zsh +
  brew `zsh-completions` + `zsh-syntax-highlighting`.

---

## Behavioral rules

- **Do not apologize** when correcting yourself. Just state the correction.
- **Do not surface "this might not work in older versions" caveats** for tools I
  have installed. Trust my mise/Brewfile versions; if compatibility genuinely
  matters for a snippet, say so once and move on.
- **Default cloud examples to Azure or GCP.** AWS is fine when I explicitly ask
  or when the topic is cloud-agnostic and AWS is the most-recognizable baseline;
  otherwise lead with Azure or GCP.

---

## When working in this dotfiles repo

The repo at `~/Developer/personal/dotfiles` uses chezmoi conventions:

- Source files prefixed `dot_*` map to `~/.X`; `private_dot_*` adds mode 0600;
  `remove_*` markers delete the corresponding `~/.X`.
- Files ending in `.tmpl` are Go templates rendered with chezmoi data
  (`{{ .name }}`, `{{ .email }}`, `{{ .signingKey }}`, `{{ .profile }}`).
- The Brewfile is split into three tiers: `Brewfile` (common, always),
  `brewfiles/Brewfile.personal`, `brewfiles/Brewfile.work`. The brew-bundle chezmoi script picks
  layers based on the `profile` value.
- Edit dotfiles via `chezmoi edit ~/.X` (opens the source). Editing the live
  `$HOME` file directly creates drift.
- For applying changes, use the `chez` zsh function (a wrapper around
  `chezmoi apply --force` with an upfront diff-preview prompt). This avoids
  prompt collisions between chezmoi's per-file conflict prompts and sudo's
  password prompt during macos-defaults.
- `docs/mapping.md` is the authoritative source-to-target table. Update it when
  adding/removing managed files.
