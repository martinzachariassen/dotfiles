# GitHub and cloud sign-in

`chez auth` walks through the credentials a fresh Mac needs and cannot get from
an apply: `gh`, Azure, Google Cloud, their auth plugins, and a signed-commit
smoke test.

## Why it is a separate step

An apply installs tools; it cannot log you in. Every one of these opens a browser
or asks for a second factor, so none of it can run unattended inside a hook —
which is why the completion hook *prints* this command rather than running it.

It never had a verb before this move: the README and the completion hook both
told you to run a full path. `chez auth` replaces that.

## What it checks

Each step is skipped when its CLI is absent, so the walkthrough is safe on a
machine that does not have the cloud tooling. The Azure and Google steps also
check for `kubelogin` and `gke-gcloud-auth-plugin`, because an authenticated CLI
without its cluster auth plugin fails only later, at the point you try to reach a
cluster.

The `cloudAuth` module gates the Azure and Google steps. Note the asymmetry: the
CLIs themselves come from the **work profile's** Brewfile, not from a module, so
on a personal machine `cloudAuth` gates steps for tools that were never
installed. Harmless — they skip — but worth knowing before you go looking for the
bug.

## Gotchas

The signing smoke test is borrowed from `features/sign/lib.sh` rather than
duplicated, so both features verify signing the same way.
