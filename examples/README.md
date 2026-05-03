# examples/

Drop-in starter files you can copy into a project to make use of the tools the
Brewfile installs (`direnv`, `pre-commit`). Not chezmoi-managed — these are
references, not config that gets applied to `$HOME`.

## How to use

Copy the file you want into a project root, rename it (drop the `.example`),
and edit. Both files have the same shape every project would use; the comments
inside explain the choices.

```sh
# direnv: per-directory env vars + tool versions
cp ~/Dev/Personal/dotfiles/examples/envrc.example /path/to/project/.envrc
cd /path/to/project
direnv allow                   # one-time approval per project

# pre-commit: git hooks for lint/format/sanity-checks
cp ~/Dev/Personal/dotfiles/examples/pre-commit-config.yaml.example /path/to/project/.pre-commit-config.yaml
cd /path/to/project
pre-commit install             # writes .git/hooks/pre-commit; runs on every git commit
pre-commit run --all-files     # one-off: run all hooks against every tracked file
```

Both tools are already wired into your shell — `direnv` via the hook in `.zshrc`,
`pre-commit` via the brew install. No further setup.
