info () {
    echo "${1}" 1>&2
}

err () {
    echo "${1}" 1>&2
    exit 1
}

# Stream a release asset only after a successful download. Authenticated API
# downloads avoid gateway failures on GitHub's browser release URLs in CI.
github_release_asset () {
    local repository=$1 tag=$2 asset=$3 downloaded attempt
    downloaded=$(mktemp) || return
    if [[ -n "${GH_TOKEN:-}" ]] && command -v gh >/dev/null; then
        for attempt in 1 2 3; do
            if gh release download "$tag" --repo "$repository" --pattern "$asset" \
                --output "$downloaded" --clobber; then
                cat "$downloaded"
                rm -f "$downloaded"
                return 0
            fi
            sleep "$attempt"
        done
    elif curl --fail --location --retry 3 --retry-all-errors \
        --connect-timeout 15 --max-time 120 \
        "https://github.com/$repository/releases/download/$tag/$asset" -o "$downloaded"; then
        cat "$downloaded"
        rm -f "$downloaded"
        return 0
    fi
    rm -f "$downloaded"
    return 1
}
