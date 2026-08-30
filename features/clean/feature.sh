#!/usr/bin/env bash
# Manifest for the clean feature — data only, no side effects. Sourced in a
# subshell by core/features.sh; see features/README.md for the contract.
# shellcheck disable=SC2034  # every variable here is read by the registry

FEATURE_NAME="clean"
FEATURE_TITLE="Untracked dotfiles"
FEATURE_MODULE=""
FEATURE_DOCTOR_ORDER=""
