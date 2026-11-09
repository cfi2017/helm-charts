#/bin/bash

set -e

source hack/sh/_functions.sh

readonly helm_docs_target=$ADFINIS_CHARTS_TMP_BIN
readonly helm_docs_version=$ADFINIS_CHARTS_HELM_DOCS_VERSION
readonly helm_docs_bin=$helm_docs_target/helm-docs

readonly helm_docs_url="https://github.com/norwoodj/helm-docs/releases/download/v$helm_docs_version/helm-docs_${helm_docs_version}_Linux_x86_64.tar.gz"
readonly helm_docs_docs="https://github.com/norwoodj/helm-docs/"

env | grep helm

set +e

if [[ ! -x `which helm-docs` ]]; then
  github_release_asset norwoodj/helm-docs "v$helm_docs_version" "helm-docs_${helm_docs_version}_Linux_x86_64.tar.gz" | tar -C "$helm_docs_target" -zxf - || err "Could not download helm-docs."
  chmod +x $helm_docs_bin
  [[ ! -x $helm_docs_bin ]] && err "Could not install helm-docs binary. See $helm_docs_docs for info."
fi
