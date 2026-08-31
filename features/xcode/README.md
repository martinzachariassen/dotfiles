# Xcode and iOS

`chez xcode` (today: `chez xcode`) brings a Mac from "has the Command Line Tools"
to "can build and run an iOS app", in five idempotent steps: install Xcode.app,
point `xcode-select` at it, accept the licence, run `xcodebuild -runFirstLaunch`,
and download an iOS simulator runtime.

Gated by the `appleDev` module.

## Why an apply cannot do this

Three reasons, all of them hard.

`install.sh` deliberately installs only the Command Line Tools, because that is
all Homebrew needs. `xcodes install` authenticates against an Apple ID with 2FA,
so it cannot run unattended inside a hook. And the two downloads come to roughly
40 GB.

So this is a verb you run once, by hand, and everything about it is built around
that: nothing in `install.sh` or an apply ever invokes it, each large download is
confirmed separately, and declining either exits cleanly having changed nothing.

## The two states it exists to catch

Both look healthy from the outside, which is the point.

The **Command Line Tools satisfying `xcode-select -p`** while `xcodebuild` has no
iOS SDK behind it. Everything reports a developer directory; nothing can build
for a device.

**A complete Xcode with no simulator runtime.** Runtimes have been separate
downloads since Xcode 16, so a fresh install shows every iOS simulator as
"Unavailable" with no obvious cause.

`probe.sh` holds the read-only checks for both, and `chez doctor` runs exactly the
same functions. That sharing is deliberate: a report that disagreed with the verb
about whether the machine is ready would be worse than no report.

## Why the `xcodes` CLI is not a Brewfile entry

Circular. The only tap formula builds from source, and that build needs a full
Xcode.app — which is the thing it exists to install. On a fresh Mac it could
never succeed.

`xcodes-cli.sh` fetches upstream's signed prebuilt binary into `~/.local/bin`
instead, verified against the sha256 pinned in
[`src/.chezmoidata/xcode.toml`](../../src/.chezmoidata/xcode.toml). The fetch
happens only *after* you accept the Xcode download, so declining still leaves the
machine untouched.

## Gotchas

It requires a TTY for the confirm gate. With no terminal it refuses rather than
starting a 40 GB download unasked; `YES=1` is the deliberate way past that.
`DRY_RUN=1` previews every step and works headless, `SKIP_RUNTIME=1` takes Xcode
without the simulator runtime, and `XCODE_VERSION=26.6` pins a version instead of
`--latest`.

Signing stays manual — Xcode → Settings → Accounts, then the team on a target's
Signing & Capabilities tab. Automating it would mean handling an Apple ID
credential, which this repo does not do.

`probe.sh` and `xcodes-cli.sh` used to be `scripts/lib/xcode.sh` and
`scripts/lib/xcodes.sh` — one letter apart, opposite jobs, both sourced by the
same script. The names now say which is the read-only probe and which reaches the
network.
