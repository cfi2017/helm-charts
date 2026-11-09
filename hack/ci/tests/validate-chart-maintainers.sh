#!/usr/bin/env bash
set -euo pipefail

# chart-testing probes github.com/<name>, whose browser endpoint can time out.
# Preserve account validation using the GitHub API, with the CI token when set.
maintainers=$(python - "$1/Chart.yaml" <<'PY'
import sys
import yaml
with open(sys.argv[1]) as stream:
    chart = yaml.safe_load(stream)
for maintainer in chart.get("maintainers", []):
    print(maintainer["name"])
PY
)
headers=(-H 'Accept: application/vnd.github+json')
if [[ -n "${GH_TOKEN:-}" ]]; then
  headers+=(-H "Authorization: Bearer $GH_TOKEN")
fi
while IFS= read -r maintainer; do
  [[ -n "$maintainer" ]] || continue
  if [[ ! "$maintainer" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,38}$ ]]; then
    printf 'Invalid GitHub maintainer name: %s\n' "$maintainer" >&2
    exit 1
  fi
  curl --fail --silent --show-error --retry 3 --retry-all-errors \
    --connect-timeout 15 --max-time 120 "${headers[@]}" \
    "https://api.github.com/users/$maintainer" --output /dev/null
  printf 'Verified GitHub maintainer: %s\n' "$maintainer"
done <<< "$maintainers"
