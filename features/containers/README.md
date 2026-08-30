# Containers (colima)

The colima VM, its login agent, and the docker CLI plugin symlinks Homebrew
installs outside the CLI's search path.

## Where its code lives today

This feature has not been moved yet. Until it is, these are its parts:

- `src/.chezmoiscripts/run_onchange_after_07-colima.sh.tmpl`
- `src/Library/LaunchAgents/no.mlz.colima.plist.tmpl`
- `src/dot_config/colima/_templates/default.yaml`
- `src/dot_docker/cli-plugins/`
- `docs/shell.md (colima section)`

Moving them here — code, tests and this document — is what turns this stub into
the dossier. See [docs/architecture.md](../../docs/architecture.md).
