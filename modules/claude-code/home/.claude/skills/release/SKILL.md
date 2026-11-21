---
name: release
description: Cuts a release from the commits since the last tag -- proposes the next semantic version from Conventional Commits (fix = patch, feat = minor, breaking = major), writes the changelog entry and release notes, bumps the version where the project keeps it, and after approval tags, pushes and publishes a GitHub release. Defers to release tooling the repo already uses (release-please, changesets, semantic-release, goreleaser). Use when the user says "cut a release", "release this", "bump the version", "write the changelog", "tag a new version", "lag en release", or asks what the next version should be.
argument-hint: "[major|minor|patch|<version>] [--draft] [--prerelease]"
allowed-tools: Bash(git status:*), Bash(git log:*), Bash(git describe:*), Bash(git tag --list:*), Bash(git tag -l:*), Bash(git rev-parse:*), Bash(git branch:*), Bash(gh repo view:*), Bash(gh release list:*), Bash(gh release view:*), Bash(gh pr list:*)
---

# release

Turns "the commits since the last tag" into a versioned release: a version
number that means something, a changelog a user can read, a tag and a GitHub
release. The version comes from what changed, not from what feels right.

**Language:** changelog, release notes, commit and tag are **English**,
whatever language the conversation is in.

**Arguments:** `$ARGUMENTS`
- `major`, `minor`, `patch` or an exact version (`2.1.0`) overrides the
  proposed bump -- still shown in the plan.
- `--draft` creates the GitHub release as a draft.
- `--prerelease` makes a pre-release (`-rc.1`, `-beta.1`, following the
  repo's existing pattern).

## Current state

- Branch: !`git branch --show-current 2>&1 || true`
- Status: !`git status --short 2>&1 | head -20 || true`
- Last tag: !`git describe --tags --abbrev=0 2>&1 || true`

## Workflow

```
- [ ] 1. Check the repo can release
- [ ] 2. Defer to existing release tooling
- [ ] 3. Collect the changes
- [ ] 4. Decide the version
- [ ] 5. Write the changelog and bump
- [ ] 6. Run the checks
- [ ] 7. Show the plan, wait for approval
- [ ] 8. Release PR, then tag and publish
```

### 1. Check the repo can release

**Stop** and say why if any of these fail:

- On the default branch (or the branch `$ARGUMENTS` / the repo's release
  docs name), clean working tree, and up to date with the remote
  (`git fetch` then compare with `origin/<branch>`).
- There are commits since the last tag. None: nothing to release.
- CI on HEAD is green (`gh run list --branch <branch> --limit 1`). Red or
  pending: say so; releasing a red commit needs the user's explicit word.

### 2. Defer to existing release tooling

If the repo already automates releases, **don't** do it by hand -- that
creates a second, conflicting source of truth:

| Found | What to do instead |
|---|---|
| `release-please-config.json`, `.release-please-manifest.json`, a release-please workflow | merge its open release PR (`gh pr list --label "autorelease: pending"`) |
| `.changeset/` | `npx changeset` for missing entries; the changesets action does the rest |
| `.releaserc*`, `release.config.*`, `semantic-release` in `package.json` | releases happen on merge; nothing to cut by hand |
| `.goreleaser.y*ml` | only push the tag; goreleaser builds and publishes |
| a release workflow triggered `on: push: tags` | create and push the tag only; let the workflow make the release |
| `RELEASING.md` or a release section in `CONTRIBUTING.md` | follow it |

Explain what you found and what that means, then do only the part that is
left to a human.

### 3. Collect the changes

- Range: `<last-tag>..HEAD`. No tag at all: this is the first release --
  ask what version to start at (`0.1.0` for something still settling,
  `1.0.0` if people already depend on it).
- `git log <range> --format='%H%x09%s%x09%b'`, and for merged PRs
  `gh pr list --state merged --base <branch> --search "merged:>=<tag-date>"`
  to link PR numbers and authors.
- Sort each commit by its Conventional Commit type; details in
  [references/versioning.md](references/versioning.md). Commits that don't
  follow the convention: read the diff and classify them by hand, don't drop
  them.

### 4. Decide the version

Apply SemVer to the collected changes -- the highest bump wins:

- any breaking change (`!` after the type, or a `BREAKING CHANGE:` footer)
  -> **major**
- any `feat` -> **minor**
- otherwise `fix`, `perf` and anything user-visible -> **patch**
- only `docs`, `test`, `chore`, `ci`, `style`, `refactor` -> nothing
  user-visible changed; say so and ask whether to release at all

Below `1.0.0`, a breaking change bumps the **minor** and a feature the
patch -- name this in the plan. Match the tag format already in use
(`v1.2.3` or `1.2.3`, check `git tag --list`).

### 5. Write the changelog and bump

- **Changelog**: if `CHANGELOG.md` exists, follow its existing format. If
  not, create it in the Keep a Changelog shape from
  [references/versioning.md](references/versioning.md) -- but ask first in a
  repo that never had one. Written for users: what changed for them, not
  commit subjects pasted as-is. Breaking changes first, with what to do
  about them.
- **Version bump**: only where the project already keeps a version --
  `package.json`, `pyproject.toml`, `Cargo.toml` (and `Cargo.lock`),
  `version.go`, a `VERSION` file, `Chart.yaml`. Go modules and many tools
  take the version from the tag alone; then there is nothing to bump. Use
  the ecosystem's own command where one exists (`npm version --no-git-tag-version`,
  `cargo set-version`), so lockfiles follow.

### 6. Run the checks

The project's check command (as `ship` finds it), run through the
`check-runner` agent when it is available, so only the failures come back.
Red: stop and show it.

### 7. Show the plan, wait for approval

Show: the current and next version and **why** (which commits forced the
bump), the changelog entry in full, the files bumped, the tag name, and the
release PR it goes through. Then **stop and wait for an explicit go-ahead**
-- a published tag is public and practically permanent.

### 8. Release PR, then tag and publish

The release commit reaches the default branch through a pull request, never
a direct push (a local `git-guard` hook refuses that push anyway):

```sh
git switch -c release/<version>
git commit -m "chore(release): <version>"   # repo's own convention if it differs
git push -u origin release/<version>
gh pr create --title "chore(release): <version>" --body-file - <<'EOF'
<the changelog entry>
EOF
```

Report the PR URL and stop. Once the user says it is merged:

```sh
git switch <default> && git pull --ff-only
git log -1 --format=%s                       # must be the release commit
git tag -a <tag> -m "<tag>"                  # -s if the repo signs tags
git push origin <tag>
gh release create <tag> --title "<tag>" --notes-file - [--draft] [--prerelease] <<'EOF'
<the changelog entry>
EOF
```

- A squash merge rewrites the subject (`... (#42)`): check that HEAD is the
  merged release PR before tagging, never tag an unrelated commit.
- A tag-triggered workflow publishes the release (step 2): push the tag
  and skip `gh release create`.
- Report the release URL.

## Boundaries

- Never move, delete or re-push an existing tag. A bad release gets a new
  patch version.
- Never publish to a package registry (`npm publish`, `cargo publish`,
  `twine upload`) unless the user asks in this run -- that is usually CI's
  job, and it cannot be undone.
- Never invent changelog entries, or credit someone the log does not show.
- In a **public** repo, keep internal ticket links and hostnames out of the
  release notes.
