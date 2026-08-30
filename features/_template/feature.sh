#!/usr/bin/env bash
# Manifest for the <name> feature — data only, no side effects. Sourced in a
# subshell by core/features.sh; see features/README.md for the contract.
# shellcheck disable=SC2034  # every variable here is read by the registry

FEATURE_NAME="<name>"         # must match this directory's name
FEATURE_TITLE="<Human title>" # heading chezdoctor prints for its section
FEATURE_MODULE=""             # module that gates the whole feature; empty = always on
FEATURE_DOCTOR_ORDER=""       # position in chezdoctor; empty = contributes no checks
