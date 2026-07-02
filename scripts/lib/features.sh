#!/usr/bin/env bash
# features.sh — the single list of workstation feature toggles + their defaults.
#
# `FEATURE_KEYS` and `feature_default` were byte-identical in install.sh and
# dotfiles-config.sh; adding a feature meant editing both in lock-step. Now they
# live here: dotfiles-config.sh sources this, install.sh inlines the region
# between the @inline markers (see scripts/build-install.sh).
#
# To add a feature: append its key to FEATURE_KEYS and give it a default in
# feature_default. The chezmoi templates read `.features.<key>` via
# `dig "features" "<key>" <default> .`.
#
# FEATURE_KEYS is referenced by sourcing/inlining callers; feature_default is too.
# shellcheck disable=SC2034,SC2329

# Source guard kept OUTSIDE the @inline region (see chezmoi-data.sh for why).
[ -n "${__DOTFILES_FEATURES_SH:-}" ] && return 0
__DOTFILES_FEATURES_SH=1

# @inline-begin
# Every optional workstation feature toggle, in wizard/display order.
FEATURE_KEYS=(macApps)

# feature_default KEY — the default state for a feature absent from config.
# macApps defaults on (a fresh personal Mac wants the GUI/AI app layer); unknown
# keys default off so a newly-added toggle is opt-in until wired up.
feature_default() {
    case "$1" in
        macApps) printf 'true' ;;
        *) printf 'false' ;;
    esac
}
# @inline-end
