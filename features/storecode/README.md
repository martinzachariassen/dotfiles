# storecode (work profile)

The work-only exception, and the one place in the repo that installs software
from outside Homebrew. `storecode` is a work security tool that ships its own
installer, so it cannot be a Brewfile package — and because Homebrew does not
know about it, `chezmirror` and `chezclean` have to be told to leave it alone.

| Piece | Where |
|---|---|
| Apply engine | [`hook.sh`](hook.sh), run by `run_onchange_after_05-storecode` |
| Installer command | [`src/.chezmoidata/storecode.toml`](../../src/.chezmoidata/storecode.toml) |
| Cleanup exemption | `.storecode` on `keepHome` in [`src/.chezmoidata/clean.toml`](../../src/.chezmoidata/clean.toml) |

## The contract

**Never add it to a Brewfile.** It is not in Homebrew; a `brew "storecode"` line
would fail `brew bundle` for every work machine and do nothing for anyone else.

**Never offer `~/.storecode` for cleanup.** Nothing installed it that
[`clean`](../clean) can recognise, so without the `keepHome` entry every
`chezclean` run would offer to delete a working security tool. The entry is
permanent, not a deprecation waiting to be tidied — both halves are pinned by
[`tests/storecode.bats`](tests/storecode.bats) so neither can drift out from
under the other.

## How the install works

The template decides the two things only a render can: whether this is macOS and
the work profile, and what the installer command is. It passes the destination
home and that command to `hook.sh`, which installs only when `storecode` is
neither on `PATH` nor already unpacked at `~/.storecode`.

`installCmd` is empty in the committed data, because the real installer URL is
work-internal and this repo is public. With it empty the hook prints where to
set it and exits 0, so a work machine converges cleanly and simply arrives
without the tool — the alternative, a hard failure, would abort the apply and
cost the user hook 99's "Next moves" block. Set it locally to a one-liner (a
`curl -fsSL … | bash`, say) and the next `chezup` installs it.

The command runs through `eval`, so it may be a pipeline. One consequence worth
knowing: an installer one-liner containing a bare `exit` ends the hook rather
than being reported as a failure.

## Why the hook is hashed against its engine

`run_onchange_` re-fires when the rendered template changes. With the body moved
here, the template stops changing on an engine edit — so it hashes `hook.sh`
too. Forget that and chezmoi keeps matching the recorded hash and the hook never
runs again: no error, no output, and storecode quietly never installs.
`tests/chezmoi-scripts.bats` enforces the pair for every delegating hook.
