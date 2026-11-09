#!/usr/bin/env bash
set -euo pipefail

log=$(mktemp)
trap 'rm -f "$log"' EXIT
if helm plugin install https://github.com/helm-unittest/helm-unittest --version v1.0.3 >"$log" 2>&1; then
  cat "$log"
else
  cat "$log"
  message=$(tail -n 20 "$log")
  message=${message//'%'/'%25'}
  message=${message//$'\r'/'%0D'}
  message=${message//$'\n'/'%0A'}
  printf '::error title=helm-unittest installation failed::%s\n' "$message"
  exit 1
fi
