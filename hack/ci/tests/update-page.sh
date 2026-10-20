#!/usr/bin/env bash
# Exercise the real Pages updater against a local bare remote, without GitHub.
set -euo pipefail

updater=$(realpath "$(dirname "$0")/../github/steps/update-page.sh")
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME='Pages Test'
export GIT_AUTHOR_EMAIL='pages-test@example.com'
export GIT_COMMITTER_NAME=$GIT_AUTHOR_NAME
export GIT_COMMITTER_EMAIL=$GIT_AUTHOR_EMAIL

git init --bare "$fixture/remote.git"
git init -b gh-pages "$fixture/writer"
git -C "$fixture/writer" remote add origin "$fixture/remote.git"
printf 'initial\n' > "$fixture/writer/index.yaml"
git -C "$fixture/writer" add index.yaml
git -C "$fixture/writer" commit -m Initial
git -C "$fixture/writer" push origin gh-pages
git clone --branch gh-pages "$fixture/remote.git" "$fixture/runner"

# Advance the remote after checkout, as chart-releaser does.
printf 'released\n' > "$fixture/writer/index.yaml"
git -C "$fixture/writer" commit -am Release
git -C "$fixture/writer" push origin gh-pages

cd "$fixture/runner"
mkdir -p hack/sh
: > hack/sh/rc.sh
printf 'info() { echo "$@"; }\n' > hack/sh/_functions.sh
printf 'repository metadata\n' > cfi2017-charts-repo.yaml
cat > hack/update-readme.sh <<'GENERATOR'
#!/usr/bin/env bash
set -euo pipefail
# Simulate a second publisher pushing after the updater's initial fetch.
if [[ ${PAGES_TEST_RACE:-0} == 1 ]]; then
    git -C "$PAGES_TEST_WRITER" pull --ff-only origin gh-pages
    printf 'concurrent release\n' > "$PAGES_TEST_WRITER/index.yaml"
    git -C "$PAGES_TEST_WRITER" commit -am 'Concurrent release'
    git -C "$PAGES_TEST_WRITER" push origin gh-pages
fi
printf '%s\n' "$PAGES_TEST_CONTENT" > "$HELMCHARTS_GOMPLATE_OUTPUT"
GENERATOR
chmod +x hack/update-readme.sh
export PAGES_TEST_CONTENT='generated site'
export PAGES_TEST_WRITER="$fixture/writer"
bash "$updater"
[[ $(git --git-dir="$fixture/remote.git" show gh-pages:index.yaml) == released ]]
[[ $(git --git-dir="$fixture/remote.git" show gh-pages:index.md) == 'generated site' ]]

# An unchanged generated site must not add a commit.
before=$(git --git-dir="$fixture/remote.git" rev-parse gh-pages)
bash "$updater"
[[ $(git --git-dir="$fixture/remote.git" rev-parse gh-pages) == "$before" ]]

export PAGES_TEST_RACE=1
export PAGES_TEST_CONTENT='updated site'
bash "$updater"
[[ $(git --git-dir="$fixture/remote.git" show gh-pages:index.yaml) == 'concurrent release' ]]
[[ $(git --git-dir="$fixture/remote.git" show gh-pages:index.md) == 'updated site' ]]
[[ $(git worktree list --porcelain | awk '/^worktree / {count++} END {print count}') == 1 ]]
echo 'Pages updater: stale checkout, no-op, concurrent push and cleanup checks passed.'
