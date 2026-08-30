# Health check

The read-only report. Also the host for every other feature's checks: once the
registry lands, `doctor.sh` runs `features/*/doctor.sh` in declared order.

## Verbs

- `chez doctor` — Read-only health check (repo, brew, auth, mise, shell).

## Where its code lives today

This feature has not been moved yet. Until it is, these are its parts:

- `scripts/bin/doctor.sh`
- `core/semver.sh`
- `tests/doctor.bats`
- `docs/commands.md`

Moving them here — code, tests and this document — is what turns this stub into
the dossier. See [docs/architecture.md](../../docs/architecture.md).
