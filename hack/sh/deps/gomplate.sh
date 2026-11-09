#/bin/bash

set -e

source hack/sh/_functions.sh

readonly gomplate_target=$ADFINIS_CHARTS_TMP_BIN
readonly gomplate_version=$ADFINIS_CHARTS_GOMPLATE_VERSION
readonly gomplate_bin=$gomplate_target/gomplate

readonly gomplate_url="https://github.com/hairyhenderson/gomplate/releases/download/v$gomplate_version/gomplate_linux-amd64"
readonly gomplate_docs="https://gomplate_docs.gomplate.ca/installing/"

set +e

if [[ ! -x `which gomplate` ]]; then
    github_release_asset hairyhenderson/gomplate "v$gomplate_version" gomplate_linux-amd64 > "$gomplate_bin" || err "Could not download gomplate."
    chmod +x $gomplate_bin
    [[ ! -x $gomplate_bin ]] && err "Could not install gomplate binary. See $gomplate_docs for info."
fi
