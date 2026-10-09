#!/usr/bin/env bash
# Preserve the real exit status while giving CI compact, colorful groups.
set -euo pipefail
label=$1
shift
printf '\033[1;36m▶ %s\033[0m\n' "$label"
printf '::group::%s\n' "$label"
if "$@"; then
  printf '::endgroup::\n\033[1;32m✅ %s\033[0m\n' "$label"
else
  code=$?
  printf '::endgroup::\n\033[1;31m❌ %s (exit %s)\033[0m\n' "$label" "$code" >&2
  exit "$code"
fi
