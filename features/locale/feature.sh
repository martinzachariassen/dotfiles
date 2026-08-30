#!/usr/bin/env bash
# Manifest for the locale feature — data only, no side effects. Sourced in a
# subshell by core/features.sh; see features/README.md for the contract.
# shellcheck disable=SC2034  # every variable here is read by the registry

FEATURE_NAME="locale"
FEATURE_TITLE="Spelling and locale"
FEATURE_MODULE="locale"
FEATURE_DOCTOR_ORDER=""
