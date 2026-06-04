# examples/

Drop-in starter files you can copy into a project to make use of the global
workstation tools (`devbox`, `direnv`, `pre-commit`). Not chezmoi-managed —
these are references, not config that gets applied to `$HOME`.

## How to use

Copy the file you want into a project root, rename it (drop the `.example`),
and edit. The comments inside each file explain the choices.

```sh
# devbox + direnv: per-project runtimes + env vars
cd /path/to/project
devbox init                                       # creates devbox.json
devbox add gradle postgresql_16                   # pin per-project tools (NOT the JDK — see below)
devbox generate direnv                            # creates .envrc
# direnv allow                                     # only if the dir isn't under ~/Developer (the whitelisted root)

# or start from one of the opinionated templates
cp ~/Developer/personal/dotfiles/examples/devbox/backend-devbox.json /path/to/project/devbox.json
cp ~/Developer/personal/dotfiles/examples/devbox/kubernetes-devbox.json /path/to/project/devbox.json
cp ~/Developer/personal/dotfiles/examples/devbox/terraform-devbox.json /path/to/project/devbox.json
cp ~/Developer/personal/dotfiles/examples/devbox/opentofu-devbox.json /path/to/project/devbox.json
cd /path/to/project
devbox generate direnv

# pre-commit: git hooks for lint/format/sanity-checks
cp ~/Developer/personal/dotfiles/examples/pre-commit-config.yaml.example /path/to/project/.pre-commit-config.yaml
cd /path/to/project
pre-commit install             # writes .git/hooks/pre-commit; runs on every git commit
pre-commit run --all-files     # one-off: run all hooks against every tracked file

# maven toolchains (optional): pin a JDK per Maven build, independent of JAVA_HOME
cp ~/Developer/personal/dotfiles/examples/maven/toolchains.xml.example ~/.m2/toolchains.xml

# formatting: identical results across editors/teammates
cp ~/Developer/personal/dotfiles/examples/.editorconfig.example /path/to/project/.editorconfig
cp ~/Developer/personal/dotfiles/examples/.prettierrc.example   /path/to/project/.prettierrc
```

### Consistent formatting

VS Code is set to format on save with a pinned formatter per language, so the
*editor* is deterministic. To make results identical for everyone — other
editors, CI, teammates — commit these two files to the project root:

- **`.editorconfig`** — the cross-editor baseline (indent, charset, EOL,
  final newline). Honored by VS Code, IntelliJ, Vim, and formatters like
  Prettier and `shfmt`. Start from `examples/.editorconfig.example`.
- **`.prettierrc`** — pins Prettier options (print width, quotes, trailing
  commas, prose wrap) for JS/TS/JSON/YAML/Markdown. Start from
  `examples/.prettierrc.example`. When present it overrides the editor's
  Prettier fallbacks, so everyone gets the same output.

### Java / Kotlin JDKs

JDKs are the one runtime that does **not** come from devbox here — they're
installed globally via Homebrew Temurin (`Brewfile`: `temurin@21`, `temurin@25`).
The reason is VS Code: the Java language server caches the JDK's absolute path,
and devbox's content-hashed `/nix/store` paths move on every update/GC, which
forces constant "reload Java projects". A stable Homebrew path fixes that.

You still pin the Java *version* per project — just in the build tool, which is
where teammates and CI read it from anyway:

- **Gradle** — `java { toolchain { languageVersion = JavaLanguageVersion.of(21) } }`
  (or `kotlin { jvmToolchain(21) }`). Gradle auto-discovers the Temurin JDKs; no
  paths, no `JAVA_HOME`. VS Code follows automatically.
- **Maven** — `<maven.compiler.release>21</maven.compiler.release>`. Maven compiles
  on whatever JDK runs it, so also set `JAVA_HOME` (one line in `.envrc`, see
  `envrc.example`) or use `examples/maven/toolchains.xml.example`.

Add another major (e.g. 17) by adding `cask "temurin@17"` to the `Brewfile` and a
matching entry to `java.configuration.runtimes` in the VS Code settings.

All three tools are already wired into your shell — `direnv` and `pre-commit`
land via the Brewfile (`direnv` also has its hook in `.zshrc` and the `~/Developer`
whitelist in `~/.config/direnv/direnv.toml`), and `devbox` is installed via
Jetify's official curl-installer by `.chezmoiscripts/run_onchange_before_01b-install-devbox.sh.tmpl`
on first `chezmoi apply` (devbox isn't in homebrew). No further setup.

`examples/envrc.example` is still useful when you want a documented `.envrc`
with extra project environment variables, `PATH_add ./bin`, or `.envrc.local`
support. For the common case, prefer `devbox generate direnv`.

### Why per-project runtimes (devbox) instead of a global manager?

`devbox.json` lives in the project's own repo, gets committed, and travels with
the code. A teammate cloning the repo gets the exact same JDK/Postgres/Node,
Terraform/OpenTofu, or Kubernetes tool versions on first `cd` in (after
`devbox install` once). This dotfiles repo deliberately doesn't carry runtime
or project CLI pins in Homebrew — those belong to each project, not to your
personal machine config. The exceptions are deliberate: account-level CLIs such
as `az` and `gcloud` stay global so authentication and project/subscription
context are available before entering a project shell, and the **JDK** stays
global (Homebrew Temurin) so VS Code's Java server has a stable path to anchor to
(see "Java / Kotlin JDKs" above). The project's Java *version* is still pinned in
its own repo — via the Gradle/Maven toolchain, not Homebrew.
