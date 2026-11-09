#!/usr/bin/env bash
set -euo pipefail

# The v1.0.3 install hook uses curl without --fail or retries, so an HTTP error
# page is treated as a tarball. Download and verify the pinned Linux runner
# binary ourselves, then skip only the hook's download.
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
install_plugin() {
  local archive="$work_dir/helm-unittest.tgz"
  local url=https://github.com/helm-unittest/helm-unittest/releases/download/v1.0.3/helm-unittest-linux-amd64-1.0.3.tgz
  if [[ -n "${GH_TOKEN:-}" ]] && command -v gh >/dev/null; then
    # The authenticated asset API avoids cached failures on browser download URLs.
    gh release download v1.0.3 --repo helm-unittest/helm-unittest \
      --pattern helm-unittest-linux-amd64-1.0.3.tgz --output "$archive" || return
  else
    curl --fail --location --retry 3 --retry-all-errors \
      --connect-timeout 15 --max-time 120 --output "$archive" "$url" || return
  fi
  # Published in v1.0.3's helm-unittest-checksum.sha.
  printf '9761f23d9509c98770c026e019e743b524b57010f4bc29175f78d2582ace0633  %s\n' "$archive" \
    | sha256sum --check || return
  SKIP_BIN_INSTALL=1 helm plugin install https://github.com/helm-unittest/helm-unittest --version v1.0.3 || return
  tar -xzf "$archive" -C "$(helm env HELM_PLUGINS)/helm-unittest" || return
  helm unittest --help
}

if install_plugin >"$work_dir/install.log" 2>&1; then
  cat "$work_dir/install.log"
else
  cat "$work_dir/install.log"
  message=$(tail -n 20 "$work_dir/install.log")
  message=${message//'%'/'%25'}
  message=${message//$'\r'/'%0D'}
  message=${message//$'\n'/'%0A'}
  printf '::error title=helm-unittest installation failed::%s\n' "$message"
  exit 1
fi
