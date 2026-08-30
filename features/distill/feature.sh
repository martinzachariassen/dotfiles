#!/usr/bin/env bash
# Manifest for the distill feature — data only, no side effects. Sourced in a
# subshell by core/features.sh; see features/README.md for the contract.
# shellcheck disable=SC2034  # every variable here is read by the registry

FEATURE_NAME="distill"
FEATURE_TITLE="The nightly distiller"
FEATURE_MODULE="claudeDistiller"
FEATURE_DOCTOR_ORDER="100"
