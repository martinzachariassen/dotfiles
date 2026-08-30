#!/usr/bin/env bats
# Tests for core/ui.sh — the dependency-free terminal UI helpers shared
# by doctor.sh, chezup.sh, bootstrap-auth.sh, and macos-defaults.sh.
#
# log.sh runs on a fresh machine before any package is installed, so two
# invariants matter: never colorize non-TTY output, and glyphs must degrade to
# ASCII on a bare C/POSIX locale instead of emitting mojibake — both
# branch-on-environment, which `bash -n` can't see. Callers also rely on the
# init entry points staying idempotent and colour vars being defined even
# when empty (they run under `set -u`).

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    LOG="$REPO_ROOT/core/ui.sh"
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
    # __DOTFILES_UI_SH makes a second source a cheap no-op; load-bearing for
    # the tty.sh sibling that early-returns the same way.
    run src 'source "'"$LOG"'"; echo "${__DOTFILES_UI_SH:-unset}"'
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

# ─── ui_init_colors: colour only on a TTY, always defined under set -u ───────

@test "ui_init_colors emits NO escape codes when stdout is not a terminal" {
    # Under `run`, stdout is a pipe.
    run src 'ui_init_colors; printf "[%s][%s][%s]" "$GREEN" "$RED" "$RESET"'
    [ "$status" -eq 0 ]
    [ "$output" = "[][][]" ]
}

@test "colour vars are defined (empty) so callers under set -u never trip" {
    # If merely unset rather than empty, `set -u` would abort mid-run.
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
    [[ "${lines[0]}" == *"OK hello"* ]] || return 1
    [[ "${lines[1]}" == *"! careful"* ]] || return 1
    [[ "${lines[2]}" == *"X broke"* ]] || return 1
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
    [[ "${lines[0]}" == *"OK  good"* ]] || return 1
    [[ "${lines[1]}" == *"X  bad"* ]] || return 1
}
