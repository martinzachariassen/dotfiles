#!/usr/bin/env bash
# Manifest for the setup feature — data only, no side effects. Sourced in a
# subshell by core/features.sh; see features/README.md for the contract.
# shellcheck disable=SC2034  # every variable here is read by the registry

FEATURE_NAME="setup"
FEATURE_TITLE="Setup wizard and saved answers"
FEATURE_MODULE=""
FEATURE_DOCTOR_ORDER=""
