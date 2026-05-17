# Personal Claude Code — global config

This file is loaded automatically into every personal Claude Code session.
Project-specific overrides go in `<project>/CLAUDE.md` and merge on top of this
one. Project instructions win when they are more specific.

---

## About me

Senior backend developer on macOS (Apple Silicon).

**Primary stack:** Java (21 or 25) + Kotlin with Spring Boot. Reach for
Node/TypeScript when the situation calls for it.

**Cloud / infra:** Kubernetes, Azure, GCP. **Terraform** for IaC — I'm still
building intuition here, so briefly explaining the *why* behind Terraform
suggestions is welcome. For my main stack (Java/Kotlin/Spring Boot), don't
over-explain fundamentals.

---

## Communication style

- **Concise, direct.** Skip preambles like "Certainly!", "Great question!", or
  restating my question before answering.
- **Prose over bullets** for explanations. Reach for bullet lists only when
  enumerating genuinely parallel items, not as a default format.
- **Show tradeoffs, not just answers.** When recommending one approach, briefly
  name what it costs and what alternative I'd reach for if the situation
  flipped.
- **Don't repeat code I just wrote** in a follow-up. Assume I can scroll up.
- **Don't pad** with summaries of what you just did unless I asked for one.

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
  `~/.config/1Password`, `~/.claude`, `~/.claude.json`, and local `.env` files
  as sensitive unless I explicitly say otherwise.
- Prefer `.env.example`, documented placeholders, or secret-manager references
  over real values.

---

## What I use

This machine is set up via my chezmoi-managed dotfiles repo at
`~/Developer/personal/dotfiles`. The following are assumed available — when
suggesting alternatives, default to these unless a specific project uses
something else.

**Runtimes & version management**

- **`devbox`** (Jetify, Nix-backed) for per-project runtimes — Java/Kotlin/
  Postgres/Node/etc. Each project's repo carries its own `devbox.json`
  (committed) and `.envrc` (with `eval "$(devbox generate direnv --print-envrc)"`);
  on `cd` direnv activates the pinned toolchain for that project only. Two
  services on different JDK majors coexist without PATH gymnastics.
- For a new Spring Boot service the scaffold is:
  ```sh
  devbox init
  devbox add jdk21 kotlin gradle postgresql_16 flyway
  # writes devbox.json + devbox.lock — both committed
  ```
  Common nixpkgs for my stack: `jdk21` / `temurin-bin-21`, `kotlin`, `gradle`,
  `maven`, `postgresql_16`, `redis`, `flyway`. Search at
  <https://search.nixos.org/packages>.
- **`direnv`** for project env vars + auto-activating devbox. The hook lives
  in `~/.config/zsh/.zshrc`; the whitelist in `~/.config/direnv/direnv.toml`
  trusts `~/Developer` automatically, so no per-project `direnv allow` is needed
  for projects under there.
- **No global runtime manager** (no mise, asdf, nvm, jenv, pyenv, sdkman, …).
  If I genuinely need a fallback JDK or Node outside any project, it's
  `devbox global add jdk21 kotlin nodejs@lts` — but default to per-project.

**Shell & terminal**

- zsh, XDG layout (`ZDOTDIR=~/.config/zsh`), `fzf` for fuzzy history search
  (`Ctrl-R`) backed by `fd` instead of `find`.
- `zsh-autosuggestions` for fish-like type-ahead from history;
  `zsh-syntax-highlighting` for inline syntax coloring; `zsh-completions` for
  extra completions.
- Terminal: **Ghostty** | Multiplexer: **Zellij** | Prompt: **Starship**.
- `k` is aliased to `kubectl`.

**Editors**

- VS Code (GUI). Neovim with LazyVim (terminal). For Java/Kotlin work I
  often reach for IntelliJ separately when the project is non-trivial.

**Git & ops**

- Signed commits via 1Password's `op-ssh-sign`; `delta` as the diff pager.
- `lazygit` for interactive git ops; `pre-commit` for hook frameworks.

**Databases**

- `pgcli` (Postgres) and `redis-cli` available globally via Brewfile. For
  servers (Postgres 16, Redis, …) prefer per-project pinning via
  `devbox add postgresql_16 redis` rather than a global brew install.

**HTTP / RPC**

- `httpie`, `grpcurl`, `mkcert` for local TLS.

**Kubernetes**

- `kubectl`, `kubectx`/`kubens`, `k9s`, `stern`, `helm`.
- AKS auth: `kubelogin` (Brewfile).
- GKE auth: `gke-gcloud-auth-plugin` (installed via
  `gcloud components install gke-gcloud-auth-plugin` after `gcloud auth login`).

**Cloud CLIs**

- `az` (Azure), `gcloud` (GCP). My cloud stack is Azure + GCP.

**Infrastructure-as-Code**

- **Terraform** from HashiCorp's official tap (`hashicorp/tap/terraform`),
  plus `tflint` and `terraform-docs`. I'm still building intuition with
  Terraform — briefly explaining the *why* behind suggestions is welcome.

**Containers**

- Docker Desktop, `dive` for image introspection.

---

## Code style preferences

### General principles

- **Readability over cleverness.** Code is read more often than written.
- Apply language and framework best practices, but don't reach for advanced
  features just because they exist. Modern syntax should clarify, not show off.
- Don't add new dependencies unless they remove real complexity, match existing
  project patterns, or are clearly justified by the problem.
- **Comments explain *why*, not *what*.** Comment surprising decisions,
  non-obvious algorithms, workarounds, and topics that might confuse a future
  reader. Skip obvious-comment noise (`// increment counter`).

### Java (target 21, ready for 25)

- Records for immutable data carriers; sealed interfaces/classes for closed
  hierarchies.
- `var` only when the type is self-evident from the right-hand side.
- Pattern matching + switch expressions over `if/instanceof` chains.
- Use Lombok in projects that already use it, and for new Spring Boot Java
  services unless there is a concrete reason not to. Prefer
  `@RequiredArgsConstructor` for injection, `@Slf4j` for the logger, and
  `@Value`/`@Data`/`@Builder` where they earn their keep. Avoid field-level
  `@Autowired`.

### Kotlin

- `data class` for value types; `sealed interface` for closed hierarchies.
- Immutable by default (`val`, `List`, `Map`).
- Scope functions (`let`, `apply`, `also`, `run`, `with`) only where they
  genuinely improve readability — not because they exist.
- Extension functions over utility classes.
- Lean on null safety; avoid `!!` outside truly unreachable paths.
- Constructor injection is implicit — no annotation needed for primary
  constructor params.

### Spring Boot

- I work with **both 3.x and 4.x**. New projects target 4+; ongoing
  maintenance projects stay on whatever they're already on. Don't force-upgrade
  APIs unless I ask.
- **Constructor injection always** (Lombok `@RequiredArgsConstructor` in Java;
  implicit primary constructor in Kotlin).
- Thin controllers, services for business logic, repositories for persistence.
- `@ConfigurationProperties` (typed) over scattered `@Value`.
- Jakarta Bean Validation (`@Valid`, `@NotNull`, etc.) at boundaries.
- **Logging via SLF4J**, accessed through Lombok's `@Slf4j` (puts `log` in
  scope). Always parameterized:
  `log.debug("user {} requested {}", userId, resource)` — never string
  concatenation, never `log.debug("..." + x)`.
- Tests: JUnit 5 + AssertJ; MockMvc/WebTestClient for the HTTP layer;
  Testcontainers for anything touching a real database or queue.

### Build tools

- **Maven and Gradle are both fine.** Match whatever the project already uses;
  don't suggest converting.

### Database

- **Postgres-first.**
- **Always UUIDs for primary keys** — no serial/bigint surrogates.
- Migrations via **Flyway**.

### API

- **REST + OpenAPI** as the default. Use `springdoc-openapi` to generate the
  spec from controllers; treat the generated spec as the source of truth for
  consumers.

---

## What to suggest

- Modern replacements for legacy CLI tools (`eza` over `ls`, `ripgrep` over
  `grep`, `fd` over `find`, `bat` over `cat`, `dust` over `du`).
- Declarative / idempotent approaches over imperative one-shots — easier to
  re-run safely.
- For shell scripts that mutate state: detect-then-act patterns so re-runs are
  cheap (e.g., `if ! brew list foo &>/dev/null; then brew install foo; fi`).
- Catch obvious correctness issues — error handling, race conditions, unbounded
  resource use, missing transaction boundaries, missing tests for changed
  behavior — before style nits.

---

## Commit conventions

- **Conventional Commits** format: `<type>(<scope>): <subject>`.
- Common types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `perf`,
  `build`, `ci`, `style`.
- Subject in imperative mood (`add`, not `added` or `adds`); ≤ 72 chars.
- Body, when needed, explains the *why*, separated from subject by a blank
  line.
- Breaking changes: append `!` to the type (`feat(api)!: drop /v1 endpoints`)
  and add a `BREAKING CHANGE:` footer.
- **Author attribution: commits are authored by me only, unless I explicitly
  ask otherwise.** Never add `Co-authored-by:`, "🤖 Generated with…", or any
  AI-generated attribution. Hard rule.

Examples:

```
feat(auth): add JWT refresh endpoint
fix: handle null user-agent in middleware
chore(deps): bump spring-boot to 3.4
refactor(api)!: rename /users → /accounts (drops backward compat)
```

---

## Tooling conventions (positive defaults)

- **Always assume `devbox` + `direnv`** for per-project runtimes (JDK, Kotlin,
  Node, Postgres, Redis, etc.). Don't suggest `mise`, `nvm`, `jenv`, `pyenv`,
  `rbenv`, `asdf`, `volta`, `sdkman`, or installing language runtimes via
  `brew` directly.
- **For new projects, propose a committed `devbox.json` + `.envrc`** with
  `eval "$(devbox generate direnv --print-envrc)"`. The toolchain travels with
  the project repo, so onboarding is `git clone && cd` and direnv handles the
  rest.
- **For Node, prefer `pnpm`** (add it via `devbox add nodejs pnpm` per project).
- **For installing dev CLIs globally** (things you want available outside any
  project — `kubectl`, `terraform`, etc.), add them to my Brewfile rather than
  language-specific installers (`npm install -g`, `pip install --user`).
- **For zsh customization**, add things to my managed `.zshrc` rather than
  introducing a framework (oh-my-zsh, prezto, zinit). My setup is plain zsh +
  brew `zsh-completions` + `zsh-syntax-highlighting`.

## Behavioral rules

- **Don't apologize** when correcting yourself — just state the correction.
- **Don't surface "this might not work in older versions" caveats** for
  tools I have installed. Trust my devbox/Brewfile versions; if compatibility
  genuinely matters for a snippet, say so once and move on.
- **Default cloud examples to Azure or GCP.** AWS is fine when I explicitly
  ask or when the topic is cloud-agnostic and AWS is the most-recognizable
  baseline; otherwise lead with Azure or GCP.

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
  `chezmoi apply --force` with an upfront diff-preview prompt). Avoids
  prompt collisions between chezmoi's per-file conflict prompts and sudo's
  password prompt during macos-defaults.
- `docs/mapping.md` is the authoritative source-to-target table. Update it when
  adding/removing managed files.
