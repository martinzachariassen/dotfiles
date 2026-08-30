#!/usr/bin/env bash
# Manifest for the doctor feature — data only, no side effects. Sourced in a
# subshell by core/features.sh; see features/README.md for the contract.
# shellcheck disable=SC2034  # every variable here is read by the registry

FEATURE_NAME="doctor"
FEATURE_TITLE="Health check"
FEATURE_MODULE=""
# Empty on purpose: this feature has no single section. Its checks live in
# checks/NN-*.sh and each carries its own order in its filename, on the same
# numeric scale as every FEATURE_DOCTOR_ORDER.
FEATURE_DOCTOR_ORDER=""
