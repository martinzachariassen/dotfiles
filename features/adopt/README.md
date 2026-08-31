# Adopted packages and files

`chez adopt` records something this Mac already has, so the repo stops calling
it drift. It is the counterpart of the removal verbs: adopting is how a package
stops being offered for uninstall, and deleting the line again is how it starts
being offered.

## Verbs

- `chez adopt` — Declare an installed package or existing file so it stops counting as drift.

## How it works

Three shapes, chosen by what the argument is rather than by a flag:

| You type | What happens |
|---|---|
| `chez adopt ffmpeg` | `brew "ffmpeg"` is appended to `features/brew/Brewfile` — every Mac gets it |
| `chez adopt --local ffmpeg` | the same line goes to `~/.config/chez/Brewfile.local` — only this Mac keeps it |
| `chez adopt ~/.foorc` | `chezmoi add ~/.foorc` |

An argument that exists on disk is treated as a path; anything else is treated
as a package name. The slash cannot be the test, because a tap-qualified formula
(`azure/kubelogin/kubelogin`) has slashes too — and the two never collide in
practice, because there is no `./azure/kubelogin/kubelogin` to be found.

### Why the overlay is a real Brewfile

`~/.config/chez/Brewfile.local` is emitted by `brew_active_files` as one more
tier, last, after every repo tier. That is the entire mechanism, and it is worth
being precise about what it buys:

- **`chez doctor`** stops reporting the package as untracked.
- **The removal verbs** never offer it, because they compare against the same
  resolver — the invariant `features/brew/README.md` documents as "install and
  removal cannot disagree".
- **`chez up`** installs it if it goes missing. The apply hook appends the
  overlay to its own file list at run time, because the path comes from
  `XDG_CONFIG_HOME` and a template render cannot know it. Without that the
  overlay would be half a mechanism — declared enough to be spared, never
  declared enough to be installed.

It is emitted *last* so it can only ever add to the declared set: it cannot
reorder a repo tier, and `brew bundle` applies tiers in the order it is given.
It is emitted as an *absolute* path, because it lives outside the checkout —
`brew_resolve_file` is the one place that knows the difference, so no caller has
to special-case it and none can get the rule half-right.

The file is seeded from `features/brew/Brewfile.local.template` on the first
apply, before anyone needs it — commented throughout, declaring nothing, so
seeding cannot change what the Mac installs. A hatch nobody knows about is not a
hatch, and a file that explains itself where you would look for it beats a
paragraph in a repo you have to already know about. Seeding never rewrites an
overlay that exists; it runs on every apply, and discarding adopted packages
once a release would be worse than not shipping the hatch at all.

### Why it is not `brew bundle add`

Homebrew has a `brew bundle add`, and it is the obvious thing to delegate to.
Three behaviours ruled it out:

1. **It does not deduplicate.** Running it twice with the same name writes the
   entry twice. Two `brew "jq"` lines in one Brewfile is drift that looks like
   configuration.
2. **It injects a description comment** above every entry, which does not match
   this repo's `brew "name"  # why` style.
3. **It always appends at the end**, ignoring the section headings the Brewfile
   is organised under — so the placement needs a human either way.

Writing the line directly keeps the file in the repo's own style and makes
adopting the same thing twice a no-op, which is the detect-then-act rule the
rest of the repo follows.

## Gotchas

- **Adopt captures reality; it does not place orders.** A package that is not
  installed is refused. Accepting it would let a typo into the repo Brewfile,
  where it breaks `brew bundle install` on every *other* machine and not on the
  one that made the mistake.
- **A name installed as both a formula and a cask is refused** until you pass
  `--formula` or `--cask`. `docker` is the live example. They are separate
  Homebrew namespaces, so guessing would declare one and leave the other
  permanently untracked — the same trap `brew_untracked_of_kind` exists to
  avoid.
- **"Already declared" is checked against every active tier**, not just the file
  being written to. Adopting locally something the repo already declares is a
  no-op with a note, not a second copy.
- The comparison is on the **bare, lowercased name** (`brew_bare_names`), so a
  tap-qualified declaration counts as a declaration.
