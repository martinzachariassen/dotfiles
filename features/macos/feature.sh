#!/usr/bin/env bash
# Manifest for the macos feature — data only, no side effects. Sourced in a
# subshell by core/features.sh; see features/README.md for the contract.
# shellcheck disable=SC2034  # every variable here is read by the registry

FEATURE_NAME="macos"
FEATURE_TITLE="macOS system defaults"
FEATURE_MODULE="macosDefaults"
FEATURE_DOCTOR_ORDER=""
