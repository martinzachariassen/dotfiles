#!/usr/bin/env bats
# The data that drives chez clean's reconciliation of $HOME and ~/.config.
#
# chez clean reads three lists from clean.toml: keepConfig, keepHome, and owners
# (keep an entry while its owning tool or extension is present). If any renders
# wrong, chez clean offers an in-use directory for removal — so these pin the
# render and the entries that must never be lost.

setup() {
    load '../../../core/testing/helper'
    CLEAN_DATA="$REPO_ROOT/src/.chezmoidata/clean.toml"
    skip_unless chezmoi
    chezmoi_stub_config
}

# The rendered tool-ownership map — the exact template chez clean reads: one
# "entry<TAB>package<TAB>binary<TAB>extension" row per cleanup.owners entry.
# dig-guarded so a missing map renders empty rather than erroring.
_render_owners() {
    chezmoi_render_str '{{ range $e, $m := (dig "cleanup" "owners" (dict) .) }}{{ $e }}{{ "\t" }}{{ dig "package" "" $m }}{{ "\t" }}{{ dig "binary" "" $m }}{{ "\t" }}{{ dig "extension" "" $m }}{{ "\n" }}{{ end }}'
}

# ─── keepConfig: the ~/.config keep-list chez clean spares ────────────────────

@test "the critical auth/state dirs are pinned in keepConfig (chezmoi first)" {
    chezmoi_stub_config
    local keep first
    keep="$(chezmoi_render_str '{{ range .cleanup.keepConfig }}{{ . }}{{ "\n" }}{{ end }}')"
    [ -n "$keep" ]
    # chezmoi's own config+state dir MUST come first — removing it breaks chezmoi.
    first="$(printf '%s\n' "$keep" | grep -m1 .)"
    [ "$first" = "chezmoi" ]
    local crit
    for crit in chezmoi op gh gcloud; do
        grep -qxF "$crit" <<<"$keep" || {
            echo "critical dir missing from keepConfig: $crit"
            return 1
        }
    done
}

@test "keepHome pins the structurally-required exceptions" {
    chezmoi_stub_config
    local keephome e
    keephome="$(chezmoi_render_str '{{ range .cleanup.keepHome }}{{ . }}{{ "\n" }}{{ end }}')"
    # .config stays whole here (children reconciled separately vs keepConfig);
    # .ssh holds keys; .storecode is installed by 05-storecode; .swiftpm is
    # SwiftPM state with no `swiftpm` binary for the stem heuristic to match, so
    # without the pin chez clean offers to delete it on every appleDev machine.
    for e in .storecode .config .ssh .swiftpm; do
        grep -qxF "$e" <<<"$keephome" || {
            echo "keepHome missing required entry: $e"
            return 1
        }
    done
}

# ─── cleanup.owners: the tool-ownership map chez clean reads ───────────────────
# If this renders wrong (a lost binary, an empty row) chez clean would offer
# in-use config for removal.

@test "cleanup.owners renders as entry→package/binary/extension rows" {
    chezmoi_stub_config
    local owners
    owners="$(_render_owners)"
    [ -n "$owners" ]
    grep -qxF $'.kube\tkubernetes-cli\tkubectl\t' <<<"$owners"
    # .m2 has no package (mise); the empty middle field must survive rendering
    # or the "mvn" binary would be lost.
    grep -qxF $'.m2\t\tmvn\t' <<<"$owners"
    # .sts4 is extension-only (empty package+binary, three tabs before the
    # ID) — a collapsed middle field would land the extension in the binary slot.
    grep -qxF $'.sts4\t\t\tvmware.vscode-spring-boot' <<<"$owners"
}

@test "at least one owners row maps a binary that differs from its dir stem (alias exercised)" {
    chezmoi_stub_config
    local owners
    owners="$(_render_owners)"
    # awk preserves empty fields (unlike read with a whitespace IFS).
    run awk -F'\t' '{ stem=$1; sub(/^\./,"",stem); sub(/\..*/,"",stem)
                      if ($3 != "" && $3 != stem) diverge++ }
                    END { exit (diverge > 0) ? 0 : 1 }' <<<"$owners"
    [ "$status" -eq 0 ]
}

@test "no owners row has package, binary AND extension all empty (every entry stays findable)" {
    chezmoi_stub_config
    local owners
    owners="$(_render_owners)"
    run awk -F'\t' '$2 == "" && $3 == "" && $4 == "" { print }' <<<"$owners"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "every extension-owned owners row carries an extension ID (chez clean's extension signal)" {
    chezmoi_stub_config
    local owners
    owners="$(_render_owners)"
    local dir
    for dir in .sts4 .lemminx; do
        awk -F'\t' -v d="$dir" '$1 == d && $4 != "" { found=1 } END { exit found ? 0 : 1 }' <<<"$owners" || {
            echo "extension-owned dir missing its extension ID: $dir"
            return 1
        }
    done
}
