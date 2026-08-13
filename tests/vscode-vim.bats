#!/usr/bin/env bats
# VSCodeVim setup: the leader-map table is hand-maintained JSON inside a Go
# template, and three of its failure modes are silent — nothing surfaces them at
# apply time, they just make the editor subtly wrong.
#
# Pinned here: (1) the theme-gated EasyMotion palette must not leave a stray
# comma behind when `theme` is off (render-check only runs bash/zsh syntax
# checks, so it never parses this file); (2) relative line numbers are a pair of
# settings across two sections that are wrong alone; (3) no leader sequence may
# be a strict prefix of another, which would stall the shorter one for
# `vim.timeout` ms on every press.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SRC_DIR="$REPO_ROOT/src"
    SETTINGS="$SRC_DIR/Library/Application Support/Code/User/settings.json.tmpl"

    HAS_CHEZMOI=0
    command -v chezmoi >/dev/null 2>&1 && HAS_CHEZMOI=1
}

# $1 is a TOML array literal of selected modules, e.g. '["theme"]'.
_stub_config() {
    STUB="$BATS_TEST_TMPDIR/home"
    mkdir -p "$STUB/.config/chezmoi" "$BATS_TEST_TMPDIR/dst"
    cat > "$STUB/.config/chezmoi/chezmoi.toml" <<EOF
sourceDir = "$SRC_DIR"

[data]
    name           = "CI"
    email          = "ci@example.com"
    modules        = $1
    signingKey     = "ssh-ed25519 AAAAplaceholder"
    profile        = "personal"
    useOnePassword = false

    [data.features]
        macApps = true
EOF
}

_render_settings() {
    HOME="$STUB" XDG_CONFIG_HOME="$STUB/.config" \
        chezmoi execute-template \
            --config="$STUB/.config/chezmoi/chezmoi.toml" \
            --source="$SRC_DIR" \
            --destination="$BATS_TEST_TMPDIR/dst" \
            --file "$SETTINGS"
}

# Strip the VS Code JSONC dialect (// and /* */ comments, trailing commas) down
# to strict JSON on stdout. Mirrors scripts/ci/lint-config.sh's validator.
_jsonc_to_json() {
    python3 - "$1" <<'PY'
import json, re, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    s = fh.read()

def strip(s):
    out, i, n = [], 0, len(s)
    while i < n:
        c = s[i]
        if c == '"':
            j = i + 1
            while j < n:
                if s[j] == "\\" and j + 1 < n:
                    j += 2; continue
                if s[j] == '"':
                    j += 1; break
                j += 1
            out.append(s[i:j]); i = j
        elif c == "/" and i + 1 < n and s[i + 1] == "/":
            j = s.find("\n", i); i = n if j == -1 else j
        elif c == "/" and i + 1 < n and s[i + 1] == "*":
            j = s.find("*/", i + 2); i = n if j == -1 else j + 2
        else:
            out.append(c); i += 1
    return "".join(out)

src = re.sub(r",(\s*[\]}])", r"\1", strip(s))
json.dump(json.loads(src), sys.stdout)
PY
}

# Render with modules $1 into $BATS_TEST_TMPDIR/settings.json, asserting the
# rendered JSONC parses. Leaves the strict-JSON form in $JSON for later checks.
_render_ok() {
    _stub_config "$1"
    run _render_settings
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" > "$BATS_TEST_TMPDIR/rendered.jsonc"
    JSON="$BATS_TEST_TMPDIR/settings.json"
    _jsonc_to_json "$BATS_TEST_TMPDIR/rendered.jsonc" > "$JSON"
}

# ─── theme gating of the EasyMotion palette ─────────────────────────────────────

@test "theme on: EasyMotion markers use the Catppuccin palette" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _render_ok '["theme"]'
    grep -q '"vim.easymotionMarkerForegroundColorOneChar"' "$BATS_TEST_TMPDIR/rendered.jsonc"
    grep -q '"vim.easymotionDimColor"' "$BATS_TEST_TMPDIR/rendered.jsonc"
}

@test "theme off: no EasyMotion palette, and the file is still valid JSONC" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    # _render_ok already fails on a stray comma left by the gated block.
    _render_ok '[]'
    ! grep -q 'easymotionMarker' "$BATS_TEST_TMPDIR/rendered.jsonc"
    # EasyMotion itself is a motion, not a colour — it survives theme being off.
    grep -q '"vim.easymotion": true' "$BATS_TEST_TMPDIR/rendered.jsonc"
}

# ─── save participants ──────────────────────────────────────────────────────────

@test "files.autoSave does not disable format/fix on save" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _render_ok '["theme"]'
    # VS Code skips save participants when files.autoSave is "afterDelay", so
    # that one value silently voids editor.formatOnSave and every
    # codeActionsOnSave in the file. Nothing reports it — saves just stop
    # formatting. This shipped broken until 2026-08.
    python3 - "$JSON" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
auto = s.get("files.autoSave")
assert auto != "afterDelay", "files.autoSave=afterDelay disables all save participants"
assert s.get("editor.formatOnSave") is True, s.get("editor.formatOnSave")
PY
}

@test "language-scoped codeActionsOnSave keep the global organizeImports" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _render_ok '["theme"]'
    # A language block *replaces* the global editor.codeActionsOnSave instead of
    # merging into it, so any language that sets its own must repeat every
    # global action it still wants. Swift opts out on purpose with {}.
    python3 - "$JSON" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
glob = set(s.get("editor.codeActionsOnSave") or {})
opted_out = {"[swift]"}
bad = []
for key, val in s.items():
    if not (key.startswith("[") and isinstance(val, dict)):
        continue
    if key in opted_out:
        continue
    local = val.get("editor.codeActionsOnSave")
    if not local:          # absent -> inherits the global, which is fine
        continue
    for action in glob:
        # Ruff supplies its own source.organizeImports.ruff variant.
        if action == "source.organizeImports" and any(
            a.startswith("source.organizeImports") for a in local
        ):
            continue
        if action not in local:
            bad.append(f"{key} drops {action}")
if bad:
    raise SystemExit("\n".join(sorted(bad)))
PY
}

# ─── settings that are only correct in pairs ────────────────────────────────────

@test "relative line numbers are configured on both the editor and vim sides" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _render_ok '["theme"]'
    # editor.lineNumbers alone leaves insert mode relative too; smartRelativeLine
    # alone does nothing, because VS Code is still rendering absolute numbers.
    python3 - "$JSON" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
assert s.get("editor.lineNumbers") == "relative", s.get("editor.lineNumbers")
assert s.get("vim.smartRelativeLine") is True, s.get("vim.smartRelativeLine")
PY
}

@test "VSCodeVim gets its own extension host via affinity" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _render_ok '["theme"]'
    python3 - "$JSON" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
assert s.get("extensions.experimental.affinity", {}).get("vscodevim.vim") == 1
PY
}

# ─── leader-map structure ───────────────────────────────────────────────────────

@test "no key sequence is a strict prefix of another in the same mode" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _render_ok '["theme"]'
    # A shorter sequence that prefixes a longer one can't fire until vim.timeout
    # (1s) elapses — e.g. adding <leader>ee would make <leader>e feel broken.
    python3 - "$JSON" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
bad = []
for mode in ("normal", "visual", "insert"):
    for suffix in ("KeyBindings", "KeyBindingsNonRecursive"):
        maps = s.get(f"vim.{mode}Mode{suffix}") or []
        seqs = ["\x00".join(m["before"]) for m in maps]
        dupes = {q for q in seqs if seqs.count(q) > 1}
        bad += [f"{mode}: duplicate {q.split(chr(0))}" for q in sorted(dupes)]
        for a in seqs:
            for b in seqs:
                if a != b and b.startswith(a + "\x00"):
                    bad.append(f"{mode}: {a.split(chr(0))} prefixes {b.split(chr(0))}")
if bad:
    raise SystemExit("\n".join(sorted(set(bad))))
PY
}

@test "no map shadows a sequence an enabled emulated plugin already owns" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _render_ok '["theme"]'
    # The prefix test above only compares explicit maps against each other, so
    # it can't see the bindings the emulated plugins claim implicitly. Both of
    # these shipped broken once: <leader><space> is <space><space>, which is
    # EasyMotion's whole prefix, and replaceWithRegister owns `gr` — the same
    # `gr` LazyVim uses for Goto References. Neither prefix is configurable, so
    # enabling the plugin and mapping the sequence is always a silent conflict.
    python3 - "$JSON" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
leader = s.get("vim.leader", "\\")

# (setting, sequences that setting claims) — only checked when the setting is on.
claims = {
    "vim.easymotion": [[leader, leader]],
    "vim.replaceWithRegister": [["g", "r"]],
    "vim.sneak": [["s"], ["S"]],
    "vim.camelCaseMotion.enable": [[leader, "w"], [leader, "b"], [leader, "e"]],
}
bad = []
for setting, sequences in claims.items():
    if not s.get(setting):
        continue
    for owned in sequences:
        for mode in ("normal", "visual", "operatorPending"):
            for m in s.get(f"vim.{mode}ModeKeyBindingsNonRecursive") or []:
                before = m["before"]
                # Exact match, or the map sits under the sequence as a prefix.
                if before[: len(owned)] == owned:
                    bad.append(f"{mode}: {before} shadows {owned} from {setting}")
if bad:
    raise SystemExit("\n".join(bad))
PY
}

@test "no leader map re-binds a motion VSCodeVim already emulates natively" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _render_ok '["theme"]'
    # gd (definition) and gc/gC (vim-commentary) ship with the extension; a
    # leader alias for them is a second way to do the same thing that then has
    # to be kept in sync with LazyVim for no benefit.
    python3 - "$JSON" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
native = {"editor.action.commentLine", "editor.action.revealDefinition"}
bad = []
for mode in ("normal", "visual"):
    for m in s.get(f"vim.{mode}ModeKeyBindingsNonRecursive") or []:
        hit = native.intersection(m.get("commands") or [])
        if hit and m["before"] != ["g", "d"]:
            bad.append(f"{mode}: {m['before']} -> {sorted(hit)}")
if bad:
    raise SystemExit("\n".join(bad))
PY
}
