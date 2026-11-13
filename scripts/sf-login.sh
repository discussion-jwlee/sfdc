#!/usr/bin/env bash
# Authenticate the Salesforce CLI to the dev sandbox from an SFDX auth URL
# stored in the SFDX_AUTH_URL environment variable (never commit the URL).
#   Get it on a machine already logged in:  sf org display -o <alias> --verbose --json
#   (field: result.sfdxAuthUrl)
set -euo pipefail
ALIAS="${SF_ORG_ALIAS:-so-dev}"
if [[ -z "${SFDX_AUTH_URL:-}" ]]; then
  echo "SFDX_AUTH_URL is not set" >&2
  exit 1
fi
umask 077
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
printf '%s' "$SFDX_AUTH_URL" > "$tmp"
sf org login sfdx-url --sfdx-url-file "$tmp" --alias "$ALIAS" --set-default
sf org display --target-org "$ALIAS"
