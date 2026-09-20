<!--
This repo is one person's machine setup, so a pull request here is usually a
self-review before main. Title it the way the commit is titled --
fix(ui): count what a hook reported. Drop any section with nothing to say.

Arrived here from a fork? Say which Mac you ran it on; the note about
profiles.toml in the README applies to you before anything else.
-->

## What and why

<!-- The title says what changed. Say why here, at whatever length the reason needs. -->

## How it was checked

<!-- `make check` is CI's job. This section is for the machine CI does not have. -->

- [ ] `dot apply --dry-run`, then the real run -- same words both times
- [ ] `dot doctor` clean afterwards, with the touched module enabled
- [ ] `bash uninstall.sh --dry-run` still accounts for what this adds
- [ ] A Brewfile changed, so `make brew-audit` ran
- [ ] Hand test on a clean Mac -- bootstrap changes only, where a hosted runner
      takes the "already installed" branch and `install-smoke` cannot follow

<details>
<summary>Output</summary>

```
Paste a real run, never a sketch: DOT_COLUMNS=76 dot doctor
```

</details>

## Docs in the same commit

<!-- The table in CLAUDE.md, as a list. contract.bats catches the four marked;
     the rest is a hand check, so tick them honestly. -->

- [ ] A module added, renamed or dropped -> the module tables in `README.md` *(tested)*
- [ ] A verb, or an option it takes -> `usage()` in `bin/dot`, the command list in `README.md` *(tested)*
- [ ] A verb count named in `docs/` prose *(tested)*
- [ ] What a run prints -> `docs/architecture.md`, and every sample block showing it
- [ ] A module's settings -> that module's `README.md`, and `docs/configuration.md` *(tested)*
- [ ] A rule the driver enforces -> the `CLAUDE.md` of the directory it lives in
- [ ] Sample output regenerated from a real run, not edited by hand

## Deliberate widening

<!-- Only if this touches tests/contract.bats. Name the limit -- lib/ files,
     dot verbs, module.toml fields, the hook and module-dir sets -- and why it
     moved. Widening one changes what the repo is; that friction is the point.
     Delete this section otherwise. -->
