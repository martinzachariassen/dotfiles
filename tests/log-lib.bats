#!/usr/bin/env bats
# Tests for scripts/lib/log.sh — the dependency-free terminal UI helpers shared
# by doctor.sh, chezup.sh, bootstrap-auth.sh, setup-ollama.sh, and the obsidian
# apply hook.
#
# Why this exists:
#   log.sh runs on a FRESH machine before any package is installed, so its two
#   invariants matter: (1) it must never colorize non-TTY output (piped/CI logs
#   would fill with escape codes), and (2) its glyphs must degrade to ASCII on a
#   bare C/POSIX locale instead of emitting mojibake. Both are branch-on-
#   environment, which `bash -n` can't see. Every other sourcing script also
#   relies on the four init entry points staying idempotent and on the colour
#   vars being defined even when empty (callers run under `set -u`). These lock
#   that contract down so a refactor of the shared lib can't silently regress it.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    LOG="$REPO_ROOT/scripts/lib/log.sh"
    [ -r "$LOG" ] || skip "log.sh not found at $LOG"
}

# src EXPR — source log.sh in a clean bash and evaluate EXPR. stdout is a pipe
# here (not a tty), so this is exactly the non-interactive path CI/scripts hit.
src() { bash -c "source '$LOG'; $1"; }

# ─── Entry points + source guard ────────────────────────────────────────────

@test "log.sh defines all four init entry points" {
    run src 'declare -F ui_init_colors ui_init_glyphs ui_init_logging ui_init_status >/dev/null && echo ok'
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "log.sh sets its source guard and is safe to re-source" {
    # The guard (__DOTFILES_LOG_SH) makes a second source a cheap no-op. A
    # regression that dropped it would re-run everything (harmless today, but the
    # guard is load-bearing for the tty.sh sibling that early-returns the same way).
    run src 'source "'"$LOG"'"; echo "${__DOTFILES_LOG_SH:-unset}"'
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

# ─── ui_init_colors: colour only on a TTY, always defined under set -u ───────

@test "ui_init_colors emits NO escape codes when stdout is not a terminal" {
    # The whole point: piped output stays plain. Under `run`, stdout is a pipe.
    run src 'ui_init_colors; printf "[%s][%s][%s]" "$GREEN" "$RED" "$RESET"'
    [ "$status" -eq 0 ]
    [ "$output" = "[][][]" ]
}

@test "colour vars are defined (empty) so callers under set -u never trip" {
    # Callers use $GREEN/$RESET unconditionally; if they were merely unset rather
    # than empty, `set -u` would abort a fresh-machine script mid-run.
    run bash -c "set -u; source '$LOG'; ui_init_colors; printf '%s' \"ok:\${BOLD}\${DIM}\${GREEN}\${YELLOW}\${BLUE}\${RED}\${CYAN}\${RESET}\""
    [ "$status" -eq 0 ]
    [ "$output" = "ok:" ]
}

# ─── ui_init_glyphs: Unicode on UTF-8, ASCII fallback otherwise ─────────────

@test "ui_init_glyphs uses Unicode line-drawing under a UTF-8 locale" {
    run bash -c "export LC_ALL=en_US.UTF-8; source '$LOG'; ui_init_glyphs; printf '%s %s %s' \"\$OK_MARK\" \"\$FAIL_MARK\" \"\$BAR\""
    [ "$status" -eq 0 ]
    [ "$output" = "✓ ✗ │" ]
}

@test "ui_init_glyphs falls back to ASCII on a bare C locale" {
    # Prevents mojibake on POSIX/C — the state a minimal first-boot shell is in.
    run bash -c "export LC_ALL=C LC_CTYPE=C LANG=C; source '$LOG'; ui_init_glyphs; printf '%s %s %s %s' \"\$OK_MARK\" \"\$FAIL_MARK\" \"\$BAR\" \"\$NODE\""
    [ "$status" -eq 0 ]
    [ "$output" = "OK X | *" ]
}

# ─── ui_init_logging: the rail-style helpers ────────────────────────────────

@test "ui_init_logging defines the rail-style helper set" {
    run src 'ui_init_logging; declare -F line_prefix say ok info warn fail dim hr >/dev/null && echo ok'
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "ok/warn/fail print their message with the expected glyph" {
    run bash -c "export LC_ALL=C; source '$LOG'; ui_init_logging; ok hello; warn careful; fail broke"
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == *"OK hello"* ]]
    [[ "${lines[1]}" == *"! careful"* ]]
    [[ "${lines[2]}" == *"X broke"* ]]
}

# ─── ui_init_status: the flat report-style helpers ──────────────────────────

@test "ui_init_status defines the flat status helper set" {
    run src 'ui_init_status; declare -F s_pass s_warn s_note s_fail s_info s_section >/dev/null && echo ok'
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "s_pass/s_fail render an indented glyph + message" {
    run bash -c "export LC_ALL=C; source '$LOG'; ui_init_status; s_pass good; s_fail bad"
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == *"OK  good"* ]]
    [[ "${lines[1]}" == *"X  bad"* ]]
}
