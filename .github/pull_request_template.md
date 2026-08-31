## Summary

<!-- What does this PR change, in one or two lines? -->

## Motivation

<!-- Why is this change needed? What problem does it solve or what does it enable? -->

## Changes

<!-- The notable changes, as a short list. -->
-

## Type of change

<!-- Match the Conventional Commit type of the PR title. -->
- [ ] feat — new capability
- [ ] fix — bug fix
- [ ] docs — documentation only
- [ ] refactor — no behavior change
- [ ] chore / build / ci — tooling, packages, pipelines
- [ ] style / perf / test

## How tested

<!-- The exact commands you ran, and the machine state. Delete lines that don't apply. -->
- [ ] `pre-commit run --all-files`
- [ ] `bats tests/`
- [ ] `chezmoi apply --dry-run` (or `scripts/ci/render-check.sh`) is clean
- [ ] Applied on a real machine with `chez apply` / `chez up`

## Screenshots

<!-- Only for visible changes (theme, prompt, terminal, editor UI). Delete otherwise. -->

## Risk & rollout

<!-- Blast radius: does this touch bootstrap (install.sh), hooks (.chezmoiscripts),
     macOS defaults, or secrets/signing? Anything to do after merge + apply? -->

## Checklist

- [ ] PR title is a Conventional Commit (`type(scope): subject`, ≤ 72 chars)
- [ ] Edited chezmoi **sources** under `src/`, not rendered files in `$HOME`
- [ ] Preserved chezmoi attribute prefixes / `.tmpl` semantics
- [ ] No secrets, tokens, keys, or personal data committed
- [ ] Docs updated (`docs/`, `README.md`) if behavior or commands changed
- [ ] CI is green
