#!/usr/bin/env bash
set -euo pipefail
source hack/sh/_functions.sh

# Versions and signature policy match chart-testing-action v2.9.0.
version=3.15.0
target="$RUNNER_TEMP/chart-testing"
mkdir -p "$target"
archive="chart-testing_${version}_linux_amd64.tar.gz"
github_release_asset helm/chart-testing "v$version" "$archive" > "$target/ct.tar.gz"
github_release_asset helm/chart-testing "v$version" "$archive.sigstore.json" > "$target/ct.sigstore.json"
cosign verify-blob --bundle "$target/ct.sigstore.json" \
  --certificate-identity 'https://github.com/helm/chart-testing/.github/workflows/release.yaml@refs/heads/main' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' "$target/ct.tar.gz"
tar -xzf "$target/ct.tar.gz" -C "$target"
python -m venv "$target/venv"
"$target/venv/bin/pip" install yamllint==1.33.0 yamale==6.0.0
printf '%s\n' "$target" "$target/venv/bin" >> "$GITHUB_PATH"
printf 'CT_CONFIG_DIR=%s/etc\n' "$target" >> "$GITHUB_ENV"
"$target/ct" version
