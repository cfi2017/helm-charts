#!/bin/bash

set -e

source hack/sh/rc.sh
source hack/sh/_functions.sh

info 'Updating charts repo site...'

# Chart-releaser may have pushed since checkout. Start from the remote tip,
# without relying on (or modifying) a potentially stale local gh-pages branch.
git fetch origin gh-pages
gh_pages_worktree=$(mktemp -d)
trap 'git worktree remove --force "$gh_pages_worktree"' EXIT
git worktree add --detach "$gh_pages_worktree" FETCH_HEAD

HELMCHARTS_GOMPLATE_OUTPUT="$gh_pages_worktree/index.md" \
HELMCHARTS_GOMPLATE_NAME=indexpage \
hack/update-readme.sh

cp --force cfi2017-charts-repo.yaml "$gh_pages_worktree/cfi2017-charts-repo.yaml"

git -C "$gh_pages_worktree" add index.md cfi2017-charts-repo.yaml
if git -C "$gh_pages_worktree" diff --cached --quiet; then
    exit 0
fi
git -C "$gh_pages_worktree" commit --message="Update site" --signoff

# Use checkout's authenticated remote rather than putting a token in the URL.
# Preserve a concurrent index.yaml update by rebasing before retrying the push.
for attempt in 1 2 3; do
    if git -C "$gh_pages_worktree" push origin HEAD:refs/heads/gh-pages; then
        exit 0
    fi
    if [[ "$attempt" -lt 3 ]]; then
        git -C "$gh_pages_worktree" fetch origin gh-pages
        git -C "$gh_pages_worktree" rebase FETCH_HEAD
    fi
done

echo 'Unable to push the Pages update after three attempts.' >&2
exit 1
