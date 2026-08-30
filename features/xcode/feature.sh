#!/usr/bin/env bash
# Manifest for the xcode feature — data only, no side effects. Sourced in a
# subshell by core/features.sh; see features/README.md for the contract.
# shellcheck disable=SC2034  # every variable here is read by the registry

FEATURE_NAME="xcode"
FEATURE_TITLE="Xcode and iOS"
FEATURE_MODULE="appleDev"
FEATURE_DOCTOR_ORDER="90"
