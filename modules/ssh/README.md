# ssh

Repo: [dotfiles](../../README.md) · The module contract:
[docs/modules.md](../../docs/modules.md)

There are no private keys on this machine. 1Password holds them and exposes an
agent socket; `ssh` asks that agent to sign, and the key never leaves the
vault. This module is the one line of config that points at it:

```
Host *
  IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
```

That path is the same on every Mac — `2BUA8C4S2C` is AgileBits' Apple team ID,
not something per-user — which is why it can be tracked rather than generated.
The machine-local override `~/.ssh/config.local` is `Include`d **first**, so
anything in it wins: ssh takes the first value it obtains for each keyword.

Which keys the agent offers is a second file, `~/.config/1Password/ssh/agent.toml`,
also tracked here:

```toml
[[ssh-keys]]
vault = "Development"
```

Without it the agent offers only keys in the built-in Personal/Private vault.
Naming a vault **replaces** that default, so the key has to live in the vault
the file names. Move the key to another vault and the agent still answers, with
no keys — pushes fail with `Permission denied (publickey)` and every commit
signature fails, while nothing else looks wrong. `dot doctor` reports it as
"holds no keys".

Commit signing rides on the same agent and is set up by
[`modules/git`](../git/README.md).

One step cannot be automated: **1Password → Settings → Developer → "Use the SSH
agent"**. Until it is ticked the socket does not exist, and the failure never
mentions SSH config — `git push` reports `Permission denied (publickey)`, which
reads as a key problem and sends you hunting through a key directory that is
empty on purpose. `doctor.sh` checks the socket, so `dot doctor` says so
plainly instead.
