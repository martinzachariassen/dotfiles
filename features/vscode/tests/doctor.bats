#!/usr/bin/env bats
# The cSpell personal dictionary, checked by the VS Code section.
#
# ~/.config/cspell/personal.txt is the only managed path that is a symlink into
# this repo, so it is the one thing a repo-side file move can break for a
# machine that pulls without applying. cSpell fails silently when the target is
# gone — it just stops knowing the words — so the health report is the only
# place that can ever say so.

setup() {
    load '../../../core/testing/helper'
    load '../../../core/testing/doctor'
    doctor_iso_setup
}

@test "a dictionary that resolves passes" {
    mkdir -p "$ISO_HOME/.config/cspell"
    printf 'chezmoi\n' >"$ISO_REPO/words.txt"
    ln -s "$ISO_REPO/words.txt" "$ISO_HOME/.config/cspell/personal.txt"
    doctor_run
    [[ "$output" == *"cSpell personal dictionary resolves"* ]] || return 1
}

@test "a dangling symlink is a failure, because cSpell would not say so" {
    mkdir -p "$ISO_HOME/.config/cspell"
    ln -s "$ISO_REPO/gone.txt" "$ISO_HOME/.config/cspell/personal.txt"
    doctor_run
    [ "$status" -eq 1 ]
    [[ "$output" == *"dangling symlink"* ]] || return 1
}

@test "never deployed is a note, not a failure" {
    doctor_run
    [[ "$output" == *"cSpell personal dictionary not deployed yet"* ]] || return 1
    [[ "$output" != *"dangling symlink"* ]] || return 1
}
