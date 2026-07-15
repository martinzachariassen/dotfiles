#!/usr/bin/env bash
# Nightly distill: turn each day's Claude Code conversations into memory + a
# dated Obsidian digest, keep the global memory repo synced, and periodically
# roll up + garden what has accumulated. Runs unattended at 01:00 via launchd,
# or by hand.
#
#   distill.sh                   scheduled run: catch up every missed day since
#                                state/last-success, then weekly / memory-GC
#                                passes when due
#   distill.sh --date 2026-07-14 backfill one specific day (no state changes)
#   distill.sh --week [2026-W28] weekly rollup only (default: last full week)
#   distill.sh --gc              memory-gardening pass over global memory
#   distill.sh --dry-run         any of the above into a sandbox, touch nothing
#   distill.sh --status          agent / auth / memory-repo / last-run health
#   distill.sh --setup           guided one-time machine setup (token, deploy
#                                key, memory repo) — idempotent
#   distill.sh --read            open the latest digest in bat
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
LAUNCHD_LOG="$SCRIPT_DIR/launchd.log"
STATE_DIR="$SCRIPT_DIR/state"          # runtime-only, never committed
STATE_FILE="$STATE_DIR/last-success"   # last date fully distilled by a scheduled run
PYTHON="${PYTHON:-/usr/bin/python3}"   # stdlib-only; system python is fine and always present

LABEL="com.martin.claude-nightly-distill"
# macOS Keychain item holding the long-lived headless token (see --setup).
KEYCHAIN_SERVICE="claude-nightly-distill"
# Private repo the global memory syncs to, over the dedicated deploy-key host
# alias in ~/.ssh/config (chezmoi-managed) — the 1Password agent isn't around
# at 01:00, so the alias pins a plain machine-local key instead.
MEMORY_REMOTE="git@github-claude-memory:martinzachariassen/claude-memory.git"
MEMORY_KEY="$HOME/.ssh/claude_memory_ed25519"

# A scheduled run catches up at most this many missed days (a machine that was
# off longer can still backfill older days one at a time via --date).
CATCHUP_CAP=7
MAX_LOG_LINES=500

# Project slugs to skip entirely (space-separated). e.g. DENY="-Users-martin-Developer-work-foo"
DENY=""

# --- Args ----------------------------------------------------------------------
DATE=""
DRY_RUN=0
DO_WEEK=0
WEEK_ID=""
DO_GC=0
MODE="run"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --date) DATE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --model) MODEL="$2"; shift 2 ;;
    --week)
      DO_WEEK=1
      if [[ "${2:-}" =~ ^[0-9]{4}-W[0-9]{2}$ ]]; then WEEK_ID="$2"; shift; fi
      shift ;;
    --gc) DO_GC=1; shift ;;
    --status) MODE="status"; shift ;;
    --setup) MODE="setup"; shift ;;
    --read) MODE="read"; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
if [[ -n "$DATE" && ( "$DO_WEEK" -eq 1 || "$DO_GC" -eq 1 ) ]]; then
  echo "--date cannot be combined with --week/--gc" >&2
  exit 2
fi

# --- Small helpers ---------------------------------------------------------------
log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" | tee -a "$LOG" >&2; }

# Failure visibility for unattended runs; never let notifying break the run.
notify() {
  [[ -t 1 ]] && return 0
  osascript -e "display notification \"$1\" with title \"nightly distill\"" >/dev/null 2>&1 || true
}

# In-place truncation (tail into a temp file, cat back) so launchd's open
# append-mode fd on launchd.log stays valid across rotation.
rotate_log() {
  local f="$1" tmp
  [[ -f "$f" ]] || return 0
  [[ "$(wc -l < "$f")" -le "$MAX_LOG_LINES" ]] && return 0
  tmp="$(mktemp)"
  tail -n "$MAX_LOG_LINES" "$f" > "$tmp" && cat "$tmp" > "$f"
  rm -f "$tmp"
}

# ISO date/week arithmetic — python beats BSD-date gymnastics for week math.
dateutil() {
  $PYTHON - "$@" <<'PY'
import sys, datetime as dt
cmd, *a = sys.argv[1:]
D = dt.date.fromisoformat
if cmd == "add":
    print(D(a[0]) + dt.timedelta(days=int(a[1])))
elif cmd == "range":  # inclusive, one date per line
    d, end = D(a[0]), D(a[1])
    while d <= end:
        print(d)
        d += dt.timedelta(days=1)
elif cmd == "span":   # inclusive day count
    print((D(a[1]) - D(a[0])).days + 1)
elif cmd == "dow":    # ISO weekday: Mon=1 … Sun=7
    print(D(a[0]).isoweekday())
elif cmd == "dom":
    print(D(a[0]).day)
elif cmd == "week-id":
    y, w, _ = D(a[0]).isocalendar()
    print(f"{y}-W{w:02d}")
elif cmd == "week-days":  # a[0] like 2026-W28 → its 7 dates
    y, w = a[0].split("-W")
    for i in range(1, 8):
        print(dt.date.fromisocalendar(int(y), int(w), i))
elif cmd == "last-week":  # most recently COMPLETED ISO week
    t = dt.date.today()
    monday = t - dt.timedelta(days=t.isoweekday() - 1)
    y, w, _ = (monday - dt.timedelta(days=1)).isocalendar()
    print(f"{y}-W{w:02d}")
PY
}

# run_claude <prompt> <claude args…> — returns claude's exit code (not tee's).
run_claude() {
  local prompt="$1"
  shift
  local rc
  set +e
  printf '%s' "$prompt" | claude -p \
    --model "$MODEL" \
    --permission-mode acceptEdits \
    "$@" \
    2>>"$LOG" | tee -a "$LOG"
  rc="${PIPESTATUS[0]}"
  set -e
  return "$rc"
}

# --- Memory repo plumbing ----------------------------------------------------------
memory_git_ready() {
  [[ "$DRY_RUN" -eq 0 && -d "$GLOBAL_MEM/.git" ]] \
    && git -C "$GLOBAL_MEM" remote get-url origin >/dev/null 2>&1
}

# Reconcile against what other machines pushed before distilling on top of it.
memory_pull() {
  memory_git_ready || return 0
  if git -C "$GLOBAL_MEM" pull --rebase --autostash -q 2>>"$LOG"; then
    log "memory pulled — up to date with remote"
  else
    git -C "$GLOBAL_MEM" rebase --abort >/dev/null 2>&1 || true
    log "memory pull failed (offline? no upstream yet?) — continuing with local state"
  fi
}

# Commit + push whatever the run wrote. Unsigned (machine-generated, and the
# 1Password signing agent isn't present in the bare launchd env) and never
# fatal — an offline night simply catches up on the next run.
sync_memory() {
  local msg="$1"
  memory_git_ready || return 0
  git -C "$GLOBAL_MEM" add -A
  if git -C "$GLOBAL_MEM" diff --cached --quiet; then
    log "memory unchanged — nothing to sync"
    return 0
  fi
  if ! git -C "$GLOBAL_MEM" -c commit.gpgsign=false commit -q -m "$msg"; then
    log "memory commit failed"
    return 0
  fi
  # Rebase onto anything another machine pushed since our pre-run pull, so the
  # push isn't rejected. Abort quietly on conflict and let the push report it.
  git -C "$GLOBAL_MEM" pull --rebase -q 2>>"$LOG" \
    || git -C "$GLOBAL_MEM" rebase --abort >/dev/null 2>&1 || true
  if git -C "$GLOBAL_MEM" push -q 2>>"$LOG"; then
    log "memory synced (committed + pushed)"
  else
    log "memory committed but push failed (offline?) — will catch up next run"
  fi
}

# --- Modes that need no LLM ---------------------------------------------------------
do_read() {
  local latest
  latest="$(ls -1 "$DIGEST_DIR"/*.md 2>/dev/null | sort | tail -1 || true)"
  [[ -z "$latest" ]] && { echo "No digests yet in $DIGEST_DIR"; exit 0; }
  exec bat "$latest"
}

do_status() {
  local domain latest lastexit
  domain="gui/$(id -u)"
  echo "nightly-distill — status"
  echo
  printf '  last scheduled success : %s\n' "$(cat "$STATE_FILE" 2>/dev/null || echo '(none yet)')"
  if launchctl print "$domain/$LABEL" >/dev/null 2>&1; then
    lastexit="$(launchctl print "$domain/$LABEL" 2>/dev/null | awk -F'= ' '/last exit code/ {print $2; exit}')"
    printf '  launchd agent          : loaded (last exit code %s)\n' "${lastexit:-?}"
  else
    printf '  launchd agent          : NOT loaded — chezmoi apply, or: launchctl bootstrap %s ~/Library/LaunchAgents/%s.plist\n' "$domain" "$LABEL"
  fi
  if security find-generic-password -s "$KEYCHAIN_SERVICE" -w >/dev/null 2>&1; then
    printf '  keychain token         : present\n'
  else
    printf '  keychain token         : MISSING — run distill.sh --setup\n'
  fi
  if [[ -d "$GLOBAL_MEM/.git" ]]; then
    printf '  memory last commit     : %s\n' "$(git -C "$GLOBAL_MEM" log -1 --format='%h %cs %s' 2>/dev/null || echo '(no commits yet)')"
    printf '  memory sync state      : %s\n' "$(git -C "$GLOBAL_MEM" status -sb 2>/dev/null | head -1)"
  else
    printf '  memory repo            : not wired — run distill.sh --setup\n'
  fi
  latest="$(ls -1 "$DIGEST_DIR"/*.md 2>/dev/null | sort | tail -1 || true)"
  printf '  latest digest          : %s\n' "${latest:-(none)}"
  if [[ -f "$LOG" ]]; then
    echo
    echo "  recent log:"
    tail -n 8 "$LOG" | sed 's/^/    /'
  fi
}

confirm() {
  local a
  read -r -p "$1 [y/N] " a
  [[ "$a" == y* || "$a" == Y* ]]
}

# One guided pass over everything a fresh machine needs. Idempotent: detects
# what's in place and only offers what's missing. The two secrets (token,
# deploy key) are created here, interactively, and never leave the machine.
do_setup() {
  if [[ ! -t 0 ]]; then
    echo "--setup is interactive; run it from a terminal" >&2
    exit 2
  fi
  echo "nightly-distill — one-time machine setup (safe to re-run any time)"
  echo

  # 1/4 Headless auth token
  if security find-generic-password -s "$KEYCHAIN_SERVICE" -w >/dev/null 2>&1; then
    echo "[ok] 1/4 Keychain token present ($KEYCHAIN_SERVICE)"
  else
    echo "[..] 1/4 No Keychain token. 'claude setup-token' opens a browser flow and"
    echo "     prints a long-lived token; you'll then be prompted to paste it into"
    echo "     the new Keychain item (input hidden)."
    if confirm "     Run it now?"; then
      claude setup-token
      security add-generic-password -s "$KEYCHAIN_SERVICE" -a "$USER" -w
      echo "[ok] 1/4 token stored"
    else
      echo "[!!] 1/4 skipped — nightly runs will abort until the token exists"
    fi
  fi

  # 2/4 Memory deploy key
  if [[ -f "$MEMORY_KEY" ]]; then
    echo "[ok] 2/4 deploy key present ($MEMORY_KEY)"
  else
    echo "[..] 2/4 No deploy key. A dedicated passphrase-less ed25519 key lets the"
    echo "     01:00 job push memory without the 1Password agent. It stays machine-local."
    if confirm "     Generate it and register it on the claude-memory repo now?"; then
      ssh-keygen -t ed25519 -N '' -C "claude-memory deploy ($(hostname -s))" -f "$MEMORY_KEY"
      if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        gh repo deploy-key add "$MEMORY_KEY.pub" \
          --repo martinzachariassen/claude-memory --allow-write \
          --title "claude-memory $(hostname -s)"
        echo "[ok] 2/4 key generated + registered as a write deploy key"
      else
        echo "[!!] gh unavailable/unauthenticated — add this public key manually with"
        echo "     WRITE access at https://github.com/martinzachariassen/claude-memory/settings/keys :"
        cat "$MEMORY_KEY.pub"
      fi
    else
      echo "[!!] 2/4 skipped — memory will stay local-only on this machine"
    fi
  fi

  # 3/4 Memory repo wired into place
  if [[ -d "$GLOBAL_MEM/.git" ]] && git -C "$GLOBAL_MEM" remote get-url origin >/dev/null 2>&1; then
    if git -C "$GLOBAL_MEM" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
      echo "[ok] 3/4 memory repo wired ($GLOBAL_MEM)"
    else
      echo "[..] 3/4 memory repo has a remote but no upstream — pushing initial state"
      if git -C "$GLOBAL_MEM" push -u origin main; then
        echo "[ok] 3/4 upstream set"
      else
        echo "[!!] 3/4 push failed — check step 2, then: git -C \"$GLOBAL_MEM\" push -u origin main"
      fi
    fi
  elif [[ -e "$GLOBAL_MEM" && -n "$(ls -A "$GLOBAL_MEM" 2>/dev/null)" ]]; then
    echo "[..] 3/4 memory dir exists but isn't wired to the private repo"
    if confirm "     Initialise it and push to $MEMORY_REMOTE?"; then
      git -C "$GLOBAL_MEM" init -b main 2>/dev/null || git -C "$GLOBAL_MEM" init
      git -C "$GLOBAL_MEM" remote get-url origin >/dev/null 2>&1 \
        || git -C "$GLOBAL_MEM" remote add origin "$MEMORY_REMOTE"
      git -C "$GLOBAL_MEM" add -A
      git -C "$GLOBAL_MEM" diff --cached --quiet \
        || git -C "$GLOBAL_MEM" -c commit.gpgsign=false commit -q -m "chore: seed global Claude memory"
      if git -C "$GLOBAL_MEM" push -u origin main; then
        echo "[ok] 3/4 memory repo wired + pushed"
      else
        echo "[!!] 3/4 push failed — fix auth, then: git -C \"$GLOBAL_MEM\" push -u origin main"
      fi
    fi
  else
    echo "[..] 3/4 no memory dir yet — it should be cloned from the shared private repo"
    if confirm "     Clone $MEMORY_REMOTE into place?"; then
      mkdir -p "$(dirname "$GLOBAL_MEM")"
      git clone "$MEMORY_REMOTE" "$GLOBAL_MEM" && echo "[ok] 3/4 memory cloned" || echo "[!!] 3/4 clone failed"
    fi
  fi

  # 4/4 Verify — also seeds known_hosts so the first headless run can't stall
  # on an interactive host-key prompt.
  if grep -qs "Host github-claude-memory" "$HOME/.ssh/config"; then
    if git ls-remote "$MEMORY_REMOTE" >/dev/null 2>&1; then
      echo "[ok] 4/4 remote reachable over the deploy key"
    else
      echo "[!!] 4/4 cannot reach $MEMORY_REMOTE — key registered (2/4)? repo exists?"
    fi
  else
    echo "[!!] 4/4 ~/.ssh/config lacks the github-claude-memory host alias — run chezmoi apply"
  fi

  echo
  echo "Done. Check overall health any time with: distill.sh --status"
}

case "$MODE" in
  read)   do_read ;;             # execs bat, never returns
  status) do_status; exit 0 ;;
  setup)  do_setup;  exit 0 ;;
esac

# --- Auth ------------------------------------------------------------------------
# Interactive runs inherit auth from the session env. Unattended (launchd) runs
# don't, so pull the long-lived token from Keychain. If neither is available and
# we're not on a TTY, fail loudly instead of letting claude hang on /login.
if [[ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
  tok="$(security find-generic-password -s "$KEYCHAIN_SERVICE" -w 2>/dev/null || true)"
  [[ -n "$tok" ]] && export CLAUDE_CODE_OAUTH_TOKEN="$tok"
fi
if [[ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" && ! -t 1 ]]; then
  echo "$(date '+%FT%T') ERROR: no auth. Run distill.sh --setup (Keychain item '$KEYCHAIN_SERVICE'). Aborting." >> "$LOG"
  notify "no auth token — run distill.sh --setup"
  exit 3
fi

rotate_log "$LOG"
rotate_log "$LAUNCHD_LOG"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
KEEP="$SCRIPT_DIR/last-dry-run"
if [[ "$DRY_RUN" -eq 1 ]]; then
  rm -rf "$KEEP"
  mkdir -p "$KEEP"
fi

# --- One day's distillation ---------------------------------------------------------
run_day() {
  local d="$1"
  local day_dir="$WORK/$d"
  mkdir -p "$day_dir"

  # Step 1: collect the day's turns.
  $PYTHON "$SCRIPT_DIR/collect.py" --date "$d" --out "$day_dir" \
    --projects-root "$PROJECTS_ROOT" ${DENY:+--deny $DENY} > "$day_dir/collect.json"

  local records
  records="$($PYTHON -c 'import json,sys;print(json.load(open(sys.argv[1]))["records"])' "$day_dir/collect.json")"
  if [[ "$records" -eq 0 ]]; then
    log "day=$d no conversation activity — nothing to do"
    return 0
  fi
  log "day=$d collected records=$records chars=$($PYTHON -c 'import json,sys;print(json.load(open(sys.argv[1]))["chars"])' "$day_dir/collect.json")"
  if [[ "$($PYTHON -c 'import json,sys;print(json.load(open(sys.argv[1])).get("truncated",False))' "$day_dir/collect.json")" == "True" ]]; then
    log "day=$d input exceeded the size budget — longest sessions were trimmed (see manifest.json)"
  fi

  # Decide target paths (real vs sandbox).
  local sandbox="" target_global_mem target_digest_dir mode_note=""
  if [[ "$DRY_RUN" -eq 1 ]]; then
    sandbox="$day_dir/sandbox"
    target_global_mem="$sandbox/global-memory"
    target_digest_dir="$sandbox/digest"
    mkdir -p "$target_global_mem" "$target_digest_dir"
    # seed sandbox with a copy of real global memory so dedup/supersede is exercised
    [[ -d "$GLOBAL_MEM" ]] && cp -R "$GLOBAL_MEM/." "$target_global_mem/" 2>/dev/null || true
    mode_note="## DRY RUN — write ONLY inside $sandbox. Use the project memory dirs exactly as given in the table below; they already point into the sandbox. Do not touch anything outside $sandbox."
  else
    target_global_mem="$GLOBAL_MEM"
    target_digest_dir="$DIGEST_DIR"
    mkdir -p "$target_global_mem" "$target_digest_dir"
  fi
  local digest_file="$target_digest_dir/$d.md"

  # Previous digest, for open-thread continuity. Dry runs get a copy inside the
  # work dir so the real vault never has to be granted to a sandboxed run.
  local prev prev_digest="(none)"
  prev="$(dateutil add "$d" -1)"
  if [[ -f "$DIGEST_DIR/$prev.md" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      cp "$DIGEST_DIR/$prev.md" "$day_dir/prev-digest.md"
      prev_digest="$day_dir/prev-digest.md"
    else
      prev_digest="$DIGEST_DIR/$prev.md"
    fi
  fi

  # Build the project routing table (rewriting mem dirs to sandbox if dry).
  local project_table
  project_table="$($PYTHON - "$day_dir/manifest.json" "$DRY_RUN" "$sandbox" <<'PY'
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
    local slug realmem dst
    while IFS=' ' read -r slug realmem; do
      dst="$sandbox/proj/$slug/memory"
      mkdir -p "$dst"
      [[ -d "$realmem" ]] && cp -R "$realmem/." "$dst/" 2>/dev/null || true
    done < <($PYTHON -c '
import json,sys
for p in json.load(open(sys.argv[1]))["projects"]:
    print(p["slug"], p["memory_dir"])
' "$day_dir/manifest.json")
  fi

  # Step 2: compose the prompt.
  local prompt
  prompt="$(sed \
    -e "s|{{DATE}}|$d|g" \
    -e "s|{{INPUT_FILE}}|$day_dir/digest-input.md|g" \
    -e "s|{{GLOBAL_MEMORY_DIR}}|$target_global_mem|g" \
    -e "s|{{DIGEST_FILE}}|$digest_file|g" \
    -e "s|{{PREV_DIGEST}}|$prev_digest|g" \
    "$SCRIPT_DIR/prompt.md")"
  # Table and mode note may contain slashes/newlines — substitute via bash instead.
  prompt="${prompt//\{\{PROJECT_TABLE\}\}/$project_table}"
  prompt="${prompt//\{\{MODE_NOTE\}\}/$mode_note}"

  # Step 3: run the distiller. acceptEdits so file writes proceed unattended;
  # tools limited to file + search. add-dir grants the memory tree, the work
  # dir, and (real runs only) the digest target.
  local add_dirs=(--add-dir "$PROJECTS_ROOT" --add-dir "$WORK")
  [[ "$DRY_RUN" -eq 0 ]] && add_dirs+=(--add-dir "$DIGEST_DIR")

  log "day=$d invoking claude ($MODEL) → digest=$digest_file"
  local rc=0
  run_claude "$prompt" --allowedTools "Read" "Write" "Edit" "Glob" "Grep" "${add_dirs[@]}" || rc=$?
  log "day=$d claude exit=$rc"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    mkdir -p "$KEEP/$d"
    cp -R "$sandbox/." "$KEEP/$d/" 2>/dev/null || true
    cp "$day_dir/digest-input.md" "$KEEP/$d/_conversation-input.md" 2>/dev/null || true
    log "day=$d dry-run sandbox kept at $KEEP/$d"
  fi
  return "$rc"
}

# --- Weekly rollup -------------------------------------------------------------------
run_week() {
  local week="$1"
  local week_dir="$WORK/week-$week"
  mkdir -p "$week_dir"
  local input="$week_dir/week-input.md"

  # Gather that ISO week's daily digests (via bash — claude only needs $WORK).
  local d found=0
  echo "# Daily digests — $week" > "$input"
  while IFS= read -r d; do
    if [[ -f "$DIGEST_DIR/$d.md" ]]; then
      { echo; echo "<!-- $d -->"; cat "$DIGEST_DIR/$d.md"; } >> "$input"
      found=$((found + 1))
    fi
  done < <(dateutil week-days "$week")
  if [[ "$found" -eq 0 ]]; then
    log "week=$week no daily digests found — skipping rollup"
    return 0
  fi

  local target_digest_dir="$DIGEST_DIR"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    target_digest_dir="$week_dir/sandbox"
    mkdir -p "$target_digest_dir"
  fi
  local digest_file="$target_digest_dir/$week Weekly.md"

  local prompt
  prompt="$(sed \
    -e "s|{{WEEK}}|$week|g" \
    -e "s|{{INPUT_FILE}}|$input|g" \
    -e "s|{{DIGEST_FILE}}|$digest_file|g" \
    "$SCRIPT_DIR/prompt-weekly.md")"

  local add_dirs=(--add-dir "$WORK")
  [[ "$DRY_RUN" -eq 0 ]] && add_dirs+=(--add-dir "$DIGEST_DIR")

  log "week=$week rollup from $found daily digests → $digest_file"
  local rc=0
  run_claude "$prompt" --allowedTools "Read" "Write" "${add_dirs[@]}" || rc=$?
  log "week=$week claude exit=$rc"

  if [[ "$DRY_RUN" -eq 1 && -f "$digest_file" ]]; then
    cp "$digest_file" "$KEEP/" 2>/dev/null || true
    log "week=$week dry-run rollup kept at $KEEP"
  fi
  return "$rc"
}

# --- Monthly memory-GC -----------------------------------------------------------------
run_gc() {
  local target_mem="$GLOBAL_MEM"
  local add_dirs=(--add-dir "$PROJECTS_ROOT")
  if [[ "$DRY_RUN" -eq 1 ]]; then
    target_mem="$WORK/gc-sandbox/global-memory"
    mkdir -p "$target_mem"
    [[ -d "$GLOBAL_MEM" ]] && cp -R "$GLOBAL_MEM/." "$target_mem/" 2>/dev/null || true
    add_dirs=(--add-dir "$WORK")
  fi
  if [[ ! -f "$target_mem/MEMORY.md" ]]; then
    log "gc: no global memory yet — skipping"
    return 0
  fi

  local month prompt
  month="$(date +%Y-%m)"
  prompt="$(sed \
    -e "s|{{GLOBAL_MEMORY_DIR}}|$target_mem|g" \
    -e "s|{{MONTH}}|$month|g" \
    "$SCRIPT_DIR/prompt-gc.md")"

  log "gc: gardening global memory ($target_mem)"
  local rc=0
  run_claude "$prompt" --allowedTools "Read" "Write" "Edit" "Glob" "Grep" "${add_dirs[@]}" || rc=$?
  log "gc: claude exit=$rc"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    mkdir -p "$KEEP/gc"
    cp -R "$target_mem/." "$KEEP/gc/" 2>/dev/null || true
    log "gc: dry-run result kept at $KEEP/gc"
  fi
  return "$rc"
}

# --- Main flow --------------------------------------------------------------------------
FAILED=0
LAST_OK=""

if [[ "$DO_WEEK" -eq 1 ]]; then
  [[ -z "$WEEK_ID" ]] && WEEK_ID="$(dateutil last-week)"
  log "distill start mode=week week=$WEEK_ID dry_run=$DRY_RUN model=$MODEL"
  run_week "$WEEK_ID" || FAILED=1
elif [[ "$DO_GC" -eq 1 ]]; then
  log "distill start mode=gc dry_run=$DRY_RUN model=$MODEL"
  memory_pull
  run_gc || FAILED=1
  sync_memory "distill: memory gc $(date +%Y-%m)"
elif [[ -n "$DATE" ]]; then
  log "distill start mode=backfill date=$DATE dry_run=$DRY_RUN model=$MODEL"
  memory_pull
  run_day "$DATE" || FAILED=1
  sync_memory "distill $DATE"
else
  # Scheduled: catch up every day from last-success+1 through yesterday (launchd
  # coalesces sleep-skipped firings, but powered-off nights are simply gone),
  # then run the periodic passes that came due along the way.
  YESTERDAY="$(date -v-1d +%F)"
  LAST="$(cat "$STATE_FILE" 2>/dev/null || true)"
  [[ "$LAST" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || LAST="$(dateutil add "$YESTERDAY" -1)"
  START="$(dateutil add "$LAST" 1)"
  log "distill start mode=scheduled window=$START..$YESTERDAY dry_run=$DRY_RUN model=$MODEL"

  if [[ "$START" > "$YESTERDAY" ]]; then
    log "nothing to catch up (last success $LAST)"
  else
    SPAN="$(dateutil span "$START" "$YESTERDAY")"
    if [[ "$SPAN" -gt "$CATCHUP_CAP" ]]; then
      log "gap of $SPAN days exceeds cap ($CATCHUP_CAP) — older days need manual --date backfill"
      START="$(dateutil add "$YESTERDAY" "-$((CATCHUP_CAP - 1))")"
    fi
    memory_pull
    while IFS= read -r DAY; do
      if run_day "$DAY"; then
        LAST_OK="$DAY"
        if [[ "$DRY_RUN" -eq 0 ]]; then
          mkdir -p "$STATE_DIR"
          printf '%s\n' "$DAY" > "$STATE_FILE"
        fi
        # Periodic passes ride the scheduled run: a Sunday closes its ISO week;
        # the 1st of a month opens with a gardening pass over global memory.
        if [[ "$(dateutil dow "$DAY")" -eq 7 ]]; then
          run_week "$(dateutil week-id "$DAY")" || FAILED=1
        fi
        if [[ "$(dateutil dom "$DAY")" -eq 1 ]]; then
          run_gc || FAILED=1
        fi
      else
        FAILED=1
        log "day=$DAY failed — stopping catch-up (state stays at ${LAST_OK:-$LAST})"
        break
      fi
    done < <(dateutil range "$START" "$YESTERDAY")
  fi
  sync_memory "distill ${LAST_OK:-$YESTERDAY}"
fi

if [[ "$FAILED" -ne 0 ]]; then
  log "distill finished WITH FAILURES"
  notify "nightly distill failed — check run.log"
  exit 1
fi
log "distill done"
