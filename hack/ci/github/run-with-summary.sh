#!/usr/bin/env bash
# Keep the tail of a failed command visible in the check's annotations.
set -euo pipefail
log=$(mktemp)
trap 'rm -f "$log"' EXIT
if "$@" >"$log" 2>&1; then
  cat "$log"
else
  command_status=$?
  cat "$log"
  message=$(tail -n 20 "$log" | tail -c 3500)
  message=${message//'%'/'%25'}
  message=${message//$'\r'/'%0D'}
  message=${message//$'\n'/'%0A'}
  printf '::error title=CI command failed::%s\n' "$message"
  exit "$command_status"
fi
