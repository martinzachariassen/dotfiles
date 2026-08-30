# GitHub and cloud sign-in

The post-install walkthrough: gh, az, gcloud, their auth plugins, and a real
signed commit as a smoke test. Informational in doctor — never fails a run.

## Verbs

- `chez auth` — Sign in to gh and the cloud CLIs after a fresh install.

## Where its code lives today

This feature has not been moved yet. Until it is, these are its parts:

- `scripts/bin/bootstrap-auth.sh`
- `tests/bootstrap-auth.bats`
- `docs/install.md`

Moving them here — code, tests and this document — is what turns this stub into
the dossier. See [docs/architecture.md](../../docs/architecture.md).
