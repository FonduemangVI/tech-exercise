#!/usr/bin/env bash
# Prints a SHA-256 of what a saved Terraform plan will change: each
# resource's address, actions and planned values. Two plans with the same
# fingerprint make the same changes. The hash reveals no values, so it can
# pass between jobs as a plain output.
#
#   scripts/plan-fingerprint.sh <planfile>   (run from the Terraform directory)

set -euo pipefail

terraform show -json "${1:?plan file}" | jq -cS '
  [.resource_changes[]?
   | select(.change.actions != ["no-op"])
   | {address, actions: .change.actions, after: .change.after, unknown: .change.after_unknown}]' |
  sha256sum | cut -d' ' -f1
