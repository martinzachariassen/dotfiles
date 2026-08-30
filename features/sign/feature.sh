#!/usr/bin/env bash
# Manifest for the sign feature — data only, no side effects. Sourced in a
# subshell by core/features.sh; see features/README.md for the contract.
# shellcheck disable=SC2034  # every variable here is read by the registry

FEATURE_NAME="sign"
FEATURE_TITLE="Git commit signing"
FEATURE_MODULE=""
FEATURE_DOCTOR_ORDER="50"
