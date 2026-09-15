# swift

Repo: [dotfiles](../../README.md) · The module contract:
[docs/modules.md](../../docs/modules.md)

Swift and iOS development from VS Code, without living in Xcode's editor.
Xcode itself still has to be on disk — its SDKs, simulators and codesigning are
not distributed any other way — but nothing here opens its window.

```mermaid
flowchart LR
  B["Brewfile<br/>mas · swiftlint · swiftformat · xcbeautify"] --> X["Xcode.app<br/>via mas, id 497799835"]
  B --> T["CLI tools<br/>on PATH"]
  A["apply.sh"] --> E["VS Code extension<br/>sswg.swift-lang"]
  X -. "sourcekit-lsp, xcodebuild,<br/>the simulator" .-> E
```

## Three things this cannot automate

Each needs an interactive prompt or `sudo`, so each stays a one-time step on a
new machine — `dot doctor` names the exact command for the two it can check.

1. **Sign into the App Store first.** `mas` has had no way to sign in
   non-interactively since Apple put sign-in behind 2FA. Without this, the
   `mas "Xcode"` line in the Brewfile fails and `dot apply` reports it —
   `swiftlint`, `swiftformat` and `xcbeautify` still install; only the VS Code
   extension waits, because `apply.sh` only runs once its module's *whole*
   Brewfile installs clean (the same rule `dev-cli` runs on for `mise`). Sign
   in, then `dot apply` again.
2. **Point the toolchain at Xcode, not the Command Line Tools:**
   `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
3. **Accept the licence:** `sudo xcodebuild -license accept`, or open
   Xcode.app once.

## What actually runs in VS Code

Once the three steps above are done:

- The **Swift** extension (`sswg.swift-lang`) drives `sourcekit-lsp` for
  autocomplete, diagnostics and go-to-definition, and can build, run and debug
  against the iOS simulator directly — no Xcode window involved.
- Pure Swift Package Manager projects (libraries, CLIs) need nothing from
  Xcode's editor at all.
- `xcodebuild`/`xcrun simctl` from the integrated terminal build, run and
  archive the same way Xcode's own toolbar buttons do; `xcbeautify` pipes their
  output into something readable.
- Storyboards and XIBs still need Interface Builder — a reason to leave a
  SwiftUI-only project as one.

## `doctor.sh`

Reads state, writes nothing:

| Check | How |
|---|---|
| Xcode installed | `-d /Applications/Xcode.app` |
| Selected | `xcode-select -p` equals Xcode's `Contents/Developer` |
| Licence accepted | `defaults read` compares the agreed and installed versions |
| VS Code extension | the extensions folder, not `code --list-extensions` |

The extension check reads `~/.vscode/extensions/` directly rather than running
`code --list-extensions`, which **creates** `~/.vscode` and
`~/Library/Application Support/Code` on a machine that has neither — the same
trap `colima status` (`containers`) and `mise ls` (`dev-cli`) set for a
`doctor.sh` that has to stay read-only.

## Removal

Xcode, `mas` and the CLI tools are Homebrew/mas packages: they stay, same as
every other module's (see [Configuration](../../docs/configuration.md#enabling-and-disabling),
"packages stay"). The VS Code extension is the one thing `apply.sh` puts
somewhere the uninstall sweep cannot see, and it is still not `remove.sh`'s to
delete unasked — it reports the extension and the one command that removes it.
