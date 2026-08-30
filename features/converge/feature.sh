#!/usr/bin/env bash
# Manifest for the converge feature — data only, no side effects. Sourced in a
# subshell by core/features.sh; see features/README.md for the contract.
# shellcheck disable=SC2034  # every variable here is read by the registry

FEATURE_NAME="converge"
FEATURE_TITLE="Converge this Mac to the repo"
FEATURE_MODULE=""
# No section of its own: what a converge check would look at — chezmoi, its
# config, the source path — is not this feature's, it is chezmoi's, and lives
# in features/doctor/checks/15-chezmoi.sh.
FEATURE_DOCTOR_ORDER=""
