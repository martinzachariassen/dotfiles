# storecode

The one place in the repo that installs software from outside Homebrew.
`storecode` is a security tool that ships its own installer, so it cannot be a
Brewfile package — and because Homebrew does not know about it, `chez mirror`
and `chez clean` have to be told to leave it alone.

| Piece | Where |
|---|---|
| Apply engine | [`hook.sh`](hook.sh), run by `run_onchange_after_05-storecode` |
| Installer command | [`src/.chezmoidata/storecode.toml`](../../src/.chezmoidata/storecode.toml) |
| Cleanup exemption | `.storecode` on `keepHome` in [`src/.chezmoidata/clean.toml`](../../src/.chezmoidata/clean.toml) |

## The contract

**Never add it to a Brewfile.** It is not in Homebrew; a `brew "storecode"` line
would fail `brew bundle` on every machine.

**Never offer `~/.storecode` for cleanup.** Nothing installed it that
[`clean`](../clean) can recognise, so without the `keepHome` entry every
`chez clean` run would offer to delete a working security tool. The entry is
permanent, not a deprecation waiting to be tidied — both halves are pinned by
[`tests/storecode.bats`](tests/storecode.bats) so neither can drift out from
under the other.

## How the install works

The template decides the two things only a render can: whether this is macOS,
and what the installer command is. It passes the destination home and that
command to `hook.sh`, which installs only when `storecode` is neither on `PATH`
nor already unpacked at `~/.storecode`.

**The installer command is the only gate.** It used to be `profile == "work"`;
v1.0 retired the profile and the gate became the data instead of moving to a
tick-box. That removes a gate rather than relocating one — `installCmd` is empty
in the committed data, because the real installer URL is internal and this repo
is public, so an extra to enable it would do nothing for everybody who can read
this. With it empty the hook prints where to set it and exits 0: the machine
converges cleanly and simply arrives without the tool. A hard failure would
abort the apply and cost the user hook 99's "Next moves" block. Set it locally
to a one-liner (a `curl -fsSL … | bash`, say) and the next `chez up` installs it.

The command runs through `eval`, so it may be a pipeline. One consequence worth
knowing: an installer one-liner containing a bare `exit` ends the hook rather
than being reported as a failure.

## Why the hook is hashed against its engine

`run_onchange_` re-fires when the rendered template changes. With the body moved
here, the template stops changing on an engine edit — so it hashes `hook.sh`
too. Forget that and chezmoi keeps matching the recorded hash and the hook never
runs again: no error, no output, and storecode quietly never installs.
`tests/chezmoi-scripts.bats` enforces the pair for every delegating hook.
