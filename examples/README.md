# examples/

Drop-in starter files you can copy into a project to make use of the tools the
Brewfile installs (`devbox`, `direnv`, `pre-commit`). Not chezmoi-managed —
these are references, not config that gets applied to `$HOME`.

## How to use

Copy the file you want into a project root, rename it (drop the `.example`),
and edit. The comments inside each file explain the choices.

```sh
# devbox + direnv: per-project runtimes + env vars
cp ~/Dev/Personal/dotfiles/examples/envrc.example /path/to/project/.envrc
cd /path/to/project
devbox init                                       # creates devbox.json
devbox add jdk21 kotlin postgresql_16 gradle      # pin your toolchain
# direnv allow                                     # only if the dir isn't under ~/Dev (the whitelisted root)

# pre-commit: git hooks for lint/format/sanity-checks
cp ~/Dev/Personal/dotfiles/examples/pre-commit-config.yaml.example /path/to/project/.pre-commit-config.yaml
cd /path/to/project
pre-commit install             # writes .git/hooks/pre-commit; runs on every git commit
pre-commit run --all-files     # one-off: run all hooks against every tracked file
```

All three tools are already wired into your shell — `direnv` and `pre-commit`
land via the Brewfile (`direnv` also has its hook in `.zshrc` and the `~/Dev`
whitelist in `~/.config/direnv/direnv.toml`), and `devbox` is installed via
Jetify's official curl-installer by `.chezmoiscripts/run_onchange_before_01b-install-devbox.sh.tmpl`
on first `chezmoi apply` (devbox isn't in homebrew). No further setup.

### Why per-project runtimes (devbox) instead of a global manager?

`devbox.json` lives in the project's own repo, gets committed, and travels with
the code. A teammate cloning the repo gets the exact same JDK/Postgres/Node
versions on first `cd` in (after `devbox install` once). This dotfiles repo
deliberately doesn't carry runtime pins — those belong to each project, not to
your personal machine config. See the project README for the rationale.
