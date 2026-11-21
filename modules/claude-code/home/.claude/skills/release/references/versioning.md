# Versioning and changelog

## Commit type to changelog section

| Commit | Bump (>= 1.0.0) | Bump (0.x) | Changelog section |
|---|---|---|---|
| `type!:` or `BREAKING CHANGE:` footer | major | minor | **Breaking changes** (first, with a migration note) |
| `feat` | minor | patch | Added |
| `fix` | patch | patch | Fixed |
| `perf` | patch | patch | Changed |
| `revert` | patch | patch | the section of what it reverts, or Fixed |
| deprecation mentioned in the body | minor | patch | Deprecated |
| removal of a public feature | major | minor | Removed |
| security fix | patch | patch | Security |
| `docs`, `test`, `chore`, `ci`, `build`, `style`, `refactor` | none | none | omit, unless a user would notice |

The whole release takes the **highest** bump of any change in it.

Pre-releases: `<next>-rc.1`, then `-rc.2`; the final release drops the
suffix. Follow the repo's existing suffix (`-beta.N`, `-alpha.N`) if it has
one.

## Keep a Changelog shape

Use this only when the repo has no `CHANGELOG.md` format of its own. Newest
release on top; an `Unreleased` section only if the repo keeps one.

```markdown
# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
uses [Semantic Versioning](https://semver.org/).

## [1.4.0] - 2026-11-13

### Breaking changes

- `--output` now takes a directory, not a file. Pass `--output dist/`
  instead of `--output dist/out.json`. (#58)

### Added

- `--watch` re-runs on file changes. (#55)

### Fixed

- Paths with spaces no longer break the config loader. (#57)

[1.4.0]: https://github.com/<owner>/<repo>/compare/v1.3.2...v1.4.0
```

## Writing entries

- One line per change a user would notice, in the imperative or plain past
  tense -- match the existing file.
- Say the effect, not the implementation: "Paths with spaces no longer break
  the config loader", not "fix(config): quote path in loader".
- Link the PR or issue number when there is one. Group several commits for
  one change into one line.
- Breaking changes say what the user must do, not only what changed.
- Dates are ISO 8601 (`YYYY-MM-DD`).
