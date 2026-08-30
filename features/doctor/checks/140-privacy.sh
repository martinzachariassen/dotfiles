#!/usr/bin/env bash
# A sourced fragment, not a script: it defines doctor_check_privacy() and nothing else.
# features/doctor/cli.sh sources it and calls it, so it can use that runner's
# pass/warn/note/fail helpers and keep the tallies in one process.
#
# The one section that checks nothing. macOS refuses to let a script read
# Privacy permissions, so this prints the list to verify by hand — which is
# still better than the permissions being invisible.

doctor_check_privacy() {
    section "Privacy permissions (manual check)"
    echo "  ${DIM}macOS won't let scripts inspect Privacy permissions. Verify manually:${RESET}"
    echo "  ${DIM}  System Settings ${ARROW_MARK} Privacy & Security ${ARROW_MARK}${RESET}"
    echo "  ${DIM}    ${NOTE} Full Disk Access:    Ghostty (for protected-dir scans)${RESET}"
    echo "  ${DIM}    ${NOTE} Accessibility:       Rectangle, Raycast, Karabiner (if used)${RESET}"
    echo "  ${DIM}    ${NOTE} Screen Recording:    Raycast / screenshot tools${RESET}"
    echo "  ${DIM}    ${NOTE} Input Monitoring:    Karabiner (if used)${RESET}"
    echo "  ${DIM}    ${NOTE} Developer Tools:     your terminal (avoids Gatekeeper friction)${RESET}"
}
