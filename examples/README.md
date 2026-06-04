# examples/

Drop-in starter files you can copy into a project to make use of the global
workstation tools (`mise`, `pre-commit`). Not chezmoi-managed — these are
references, not config that gets applied to `$HOME`.

## How to use

Copy the file you want into a project root, rename it (drop the `.example`),
and edit. The comments inside each file explain the choices.

```sh
# mise: per-project runtimes + env vars
cd /path/to/project
mise use java@temurin-21 gradle@latest node@lts   # creates/updates mise.toml
mise install                                       # download the pinned versions

# or start from the opinionated template
cp ~/Developer/personal/dotfiles/examples/mise/backend.mise.toml /path/to/project/mise.toml
cd /path/to/project && mise install

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

JDKs come from mise (`java = ["temurin-21", "temurin-25"]` in the global
`~/.config/mise/config.toml`), and a project pins its own version in its
`mise.toml`. mise installs to stable, version-named paths
(`~/.local/share/mise/installs/java/temurin-21/Contents/Home`) that don't move
on update, so VS Code's Java language server has a durable path to anchor to —
that's exactly what the `java.configuration.runtimes` entries in the managed
VS Code settings point at.

You still pin the Java *version* per project in the build tool, which is where
teammates and CI read it from anyway:

- **Gradle** — `java { toolchain { languageVersion = JavaLanguageVersion.of(21) } }`
  (or `kotlin { jvmToolchain(21) }`). Gradle auto-discovers the mise JDKs; no
  paths needed. VS Code follows automatically.
- **Maven** — `<maven.compiler.release>21</maven.compiler.release>`. Maven
  compiles on whatever JDK runs it; `mise activate` sets `JAVA_HOME` to the
  project's pinned JDK, or use `examples/maven/toolchains.xml.example`.

Add another major (e.g. 17) by adding it to the `java = [...]` list in the
global mise config and a matching entry to `java.configuration.runtimes` in the
VS Code settings.

Both tools are already wired into your shell — `pre-commit` lands via the
Brewfile, and `mise` lands via the Brewfile with its activation hook in
`.zshrc` and global defaults in `~/.config/mise/config.toml`. No further setup.

### Why per-project runtimes (mise) instead of just global versions?

A project's `mise.toml` lives in its own repo, gets committed, and travels with
the code. A teammate cloning the repo gets the exact same JDK/Node/Python
versions on first `cd` in (after `mise install` once). This dotfiles repo
deliberately doesn't carry project runtime pins — those belong to each project,
not to your personal machine config; the global mise config only provides
sensible *defaults* for a bare shell. The exceptions are deliberate:
account-level CLIs such as `az` and `gcloud` stay global (Homebrew) so auth and
project/subscription context are available before entering a project, and
database servers + project CLIs (kubectl, terraform) stay in Homebrew or run via
Docker — mise manages language runtimes, not everything.
