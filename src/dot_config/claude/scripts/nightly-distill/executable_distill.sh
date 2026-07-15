#!/usr/bin/env bash
# Nightly distill: turn a day's Claude Code conversations into memory + a dated
# Obsidian digest. Runs unattended at 01:00 via launchd, or by hand.
#
#   distill.sh                 process yesterday, write real memory + digest
#   distill.sh --date 2026-07-15
#   distill.sh --dry-run       process into a throwaway sandbox, touch nothing real
#   distill.sh --read          open the latest digest in bat
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config/claude"
PROJECTS_ROOT="$CONFIG_DIR/projects"
# Claude Code slugs a project by its absolute path with '/' → '-'; the "global"
# memory lives under the home-dir project. Derive it from $HOME so this works on
# any machine/username, not just /Users/martin.
GLOBAL_MEM="$PROJECTS_ROOT/${HOME//\//-}/memory"
VAULT="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/The Archive"
DIGEST_DIR="$VAULT/Claude Digests"
MODEL="claude-sonnet-5"
LOG="$SCRIPT_DIR/run.log"
PYTHON="${PYTHON:-/usr/bin/python3}"   # stdlib-only; system python is fine and always present

# macOS Keychain item holding the long-lived headless token (see setup notes).
KEYCHAIN_SERVICE="claude-nightly-distill"

# Project slugs to skip entirely (space-separated). e.g. DENY="-Users-martin-Developer-work-foo"
DENY=""

DATE=""
DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --date) DATE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --model) MODEL="$2"; shift 2 ;;
    --read)
      latest="$(ls -1 "$DIGEST_DIR"/*.md 2>/dev/null | sort | tail -1 || true)"
      [[ -z "$latest" ]] && { echo "No digests yet in $DIGEST_DIR"; exit 0; }
      exec bat "$latest" ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Default: the calendar day that just ended (yesterday, local).
[[ -z "$DATE" ]] && DATE="$(date -v-1d +%F)"

log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" | tee -a "$LOG" >&2; }

# --- Auth --------------------------------------------------------------------
# Interactive runs inherit auth from the session env. Unattended (launchd) runs
# don't, so pull the long-lived token from Keychain. If neither is available and
# we're not on a TTY, fail loudly instead of letting claude hang on /login.
if [[ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
  tok="$(security find-generic-password -s "$KEYCHAIN_SERVICE" -w 2>/dev/null || true)"
  [[ -n "$tok" ]] && export CLAUDE_CODE_OAUTH_TOKEN="$tok"
fi
if [[ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" && ! -t 1 ]]; then
  echo "$(date '+%FT%T') ERROR: no auth. Set Keychain item '$KEYCHAIN_SERVICE' (see README). Aborting." >> "$LOG"
  exit 3
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

log "distill start date=$DATE dry_run=$DRY_RUN model=$MODEL"

# --- Step 1: collect the day's turns ------------------------------------------
$PYTHON "$SCRIPT_DIR/collect.py" --date "$DATE" --out "$WORK" \
  --projects-root "$PROJECTS_ROOT" ${DENY:+--deny $DENY} > "$WORK/collect.json"

RECORDS="$($PYTHON -c 'import json,sys;print(json.load(open(sys.argv[1]))["records"])' "$WORK/collect.json")"
if [[ "$RECORDS" -eq 0 ]]; then
  log "no conversation activity on $DATE — nothing to do"
  exit 0
fi
log "collected records=$RECORDS chars=$($PYTHON -c 'import json,sys;print(json.load(open(sys.argv[1]))["chars"])' "$WORK/collect.json")"

# --- Decide target paths (real vs sandbox) ------------------------------------
if [[ "$DRY_RUN" -eq 1 ]]; then
  SANDBOX="$WORK/sandbox"
  mkdir -p "$SANDBOX"
  TARGET_GLOBAL_MEM="$SANDBOX/global-memory"
  TARGET_DIGEST_DIR="$SANDBOX/digest"
  mkdir -p "$TARGET_GLOBAL_MEM" "$TARGET_DIGEST_DIR"
  # seed sandbox with a copy of real global memory so dedup/supersede is exercised
  [[ -d "$GLOBAL_MEM" ]] && cp -R "$GLOBAL_MEM/." "$TARGET_GLOBAL_MEM/" 2>/dev/null || true
  MODE_NOTE="## DRY RUN — write ONLY inside $SANDBOX. Use the project memory dirs exactly as given in the table below; they already point into the sandbox. Do not touch anything outside $SANDBOX."
else
  TARGET_GLOBAL_MEM="$GLOBAL_MEM"
  TARGET_DIGEST_DIR="$DIGEST_DIR"
  mkdir -p "$TARGET_GLOBAL_MEM" "$TARGET_DIGEST_DIR"
  MODE_NOTE=""
fi
DIGEST_FILE="$TARGET_DIGEST_DIR/$DATE.md"

# --- Build the project routing table (rewriting mem dirs to sandbox if dry) ---
PROJECT_TABLE="$($PYTHON - "$WORK/manifest.json" "$DRY_RUN" "${SANDBOX:-}" <<'PY'
import json, sys
manifest = json.load(open(sys.argv[1]))
dry = sys.argv[2] == "1"
sandbox = sys.argv[3]
rows = []
for p in manifest["projects"]:
    mem = p["memory_dir"]
    if dry:
        mem = f"{sandbox}/proj/{p['slug']}/memory"
    rows.append(f"- `{p['slug']}` (path: {p['cwd']}) → memory dir: `{mem}`")
print("\n".join(rows))
PY
)"

# In dry-run, seed each project's sandbox memory dir from the real one.
if [[ "$DRY_RUN" -eq 1 ]]; then
  while IFS= read -r slug realmem; do
    dst="$SANDBOX/proj/$slug/memory"
    mkdir -p "$dst"
    [[ -d "$realmem" ]] && cp -R "$realmem/." "$dst/" 2>/dev/null || true
  done < <($PYTHON -c '
import json,sys
for p in json.load(open(sys.argv[1]))["projects"]:
    print(p["slug"], p["memory_dir"])
' "$WORK/manifest.json")
fi

# --- Step 2: compose the prompt -----------------------------------------------
PROMPT="$(sed \
  -e "s|{{DATE}}|$DATE|g" \
  -e "s|{{INPUT_FILE}}|$WORK/digest-input.md|g" \
  -e "s|{{GLOBAL_MEMORY_DIR}}|$TARGET_GLOBAL_MEM|g" \
  -e "s|{{DIGEST_FILE}}|$DIGEST_FILE|g" \
  "$SCRIPT_DIR/prompt.md")"
# Table and mode note may contain slashes/newlines — substitute via awk-safe replace.
PROMPT="${PROMPT//\{\{PROJECT_TABLE\}\}/$PROJECT_TABLE}"
PROMPT="${PROMPT//\{\{MODE_NOTE\}\}/$MODE_NOTE}"

# --- Step 3: run the distiller ------------------------------------------------
# acceptEdits so file writes proceed unattended; tools limited to file + search.
# add-dir grants access to the memory tree, the work dir, and the digest target.
ADD_DIRS=(--add-dir "$PROJECTS_ROOT" --add-dir "$WORK")
if [[ "$DRY_RUN" -eq 1 ]]; then ADD_DIRS+=(--add-dir "$SANDBOX"); else ADD_DIRS+=(--add-dir "$DIGEST_DIR"); fi

log "invoking claude ($MODEL) → digest=$DIGEST_FILE"
set +e
printf '%s' "$PROMPT" | claude -p \
  --model "$MODEL" \
  --permission-mode acceptEdits \
  --allowedTools "Read" "Write" "Edit" "Glob" "Grep" \
  "${ADD_DIRS[@]}" \
  2>>"$LOG" | tee -a "$LOG"
rc=$?
set -e

log "claude exit=$rc"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo
  echo "=== DRY RUN complete. Inspect the sandbox: ==="
  echo "  digest:  $DIGEST_FILE"
  echo "  memory:  $SANDBOX"
  echo "Sandbox is deleted on exit — copying it out so you can review:"
  KEEP="$SCRIPT_DIR/last-dry-run"
  rm -rf "$KEEP"; mkdir -p "$KEEP"
  cp -R "$SANDBOX/." "$KEEP/" 2>/dev/null || true
  cp "$WORK/digest-input.md" "$KEEP/_conversation-input.md" 2>/dev/null || true
  echo "  kept at: $KEEP"
fi

# --- Step 4: sync global memory to its private git remote (best-effort) --------
# The global memory dir is its own git repo (private remote) so distilled memory
# follows between machines. Only real runs sync; commit unsigned (machine-
# generated, and the 1Password signing agent isn't present in the bare 01:00
# launchd env) and never fail the run on a git problem — an offline night simply
# catches up on the next run. Per-machine setup (repo clone + deploy key) is in
# the README; if the dir isn't a git repo or has no remote, this is a silent no-op.
if [[ "$DRY_RUN" -eq 0 && -d "$GLOBAL_MEM/.git" ]] \
   && git -C "$GLOBAL_MEM" remote get-url origin >/dev/null 2>&1; then
  git -C "$GLOBAL_MEM" add -A
  if git -C "$GLOBAL_MEM" diff --cached --quiet; then
    log "memory unchanged — nothing to sync"
  elif git -C "$GLOBAL_MEM" -c commit.gpgsign=false commit -q -m "distill $DATE"; then
    if git -C "$GLOBAL_MEM" push -q; then
      log "memory synced (committed + pushed)"
    else
      log "memory committed but push failed (offline?) — will catch up next run"
    fi
  else
    log "memory commit failed"
  fi
fi

log "distill done date=$DATE"
