#!/usr/bin/env bash
set -euo pipefail

# hog trades the job's OIDC token for a PostHog token, which needs `permissions: id-token: write`.
# Pull requests from forks never get one, so they pass with empty outputs. Any other job without a
# token is missing the permission, and fails so the missing release doesn't go unnoticed.
if [ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ] || [ -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]; then
    if [ "${FORK_PULL_REQUEST:-}" = true ]; then
        echo "::warning title=No PostHog release::Pull requests from forks get no OIDC token, so no release was resolved and every output is empty."
        exit 0
    fi
    echo "::error title=No OIDC token::The job has no OIDC token. Add \`permissions: id-token: write\` to the job, and run \`hog ci setup\` once so PostHog trusts this repository."
    exit 1
fi

version="${HOG_VERSION#v}"
if [ -z "$version" ]; then
    echo "::error title=No hog version::Set the hog-version input to the hog version to install, such as 0.1.0."
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "::error title=jq not found::This action needs jq to read the release. Install jq on the runner. GitHub-hosted runners include it."
    exit 1
fi

case "$(uname -s)/$(uname -m)" in
    Linux/x86_64) target=linux-x64 ;;
    Linux/aarch64 | Linux/arm64) target=linux-arm64 ;;
    Darwin/arm64) target=darwin-arm64 ;;
    # A shell under Rosetta reports x86_64 on Apple silicon, where the native build is faster.
    Darwin/x86_64)
        if [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || true)" = 1 ]; then
            target=darwin-arm64
        else
            target=darwin-x64
        fi
        ;;
    *)
        echo "::error title=Unsupported runner::This action runs on Linux and macOS runners, on x64 or arm64. This runner is $(uname -s) on $(uname -m)."
        exit 1
        ;;
esac
# musl systems such as Alpine have a loader named ld-musl-<arch>.so.1, and glibc systems don't.
if [ "${target%%-*}" = linux ]; then
    for loader in /lib/ld-musl-* /usr/lib/ld-musl-*; do
        if [ -e "$loader" ]; then
            target="$target-musl"
            break
        fi
    done
fi

# The archive comes from releases.posthog.com, or from the GitHub release when that fails. Its
# checksum always comes from the GitHub release, so the two origins would both have to serve the
# same wrong file for a bad archive to pass.
file="hog-$target.tar.gz"
primary="https://releases.posthog.com/hog/v$version"
mirror="https://github.com/PostHog/posthog/releases/download/hog%2Fv$version"
dir="$RUNNER_TEMP/hog-$version"
mkdir -p "$dir"
fetch() {
    curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --connect-timeout 10 -o "$2" "$1"
}
if ! fetch "$mirror/SHA256SUMS" "$dir/SHA256SUMS"; then
    echo "::error title=No hog release::There is no hog $version release on GitHub. Check the hog-version input, such as 0.1.0."
    exit 1
fi
expected=$(awk -v file="$file" '$2 == file { print $1 }' "$dir/SHA256SUMS")
if [ -z "$expected" ]; then
    echo "::error title=No hog build::hog $version has no $target build."
    exit 1
fi
if ! fetch "$primary/$file" "$dir/$file"; then
    echo "Couldn't download $file from releases.posthog.com, so it comes from the GitHub release."
    fetch "$mirror/$file" "$dir/$file"
fi
if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$dir/$file" | awk '{ print $1 }')
else
    # macOS runners have shasum but not sha256sum.
    actual=$(shasum -a 256 "$dir/$file" | awk '{ print $1 }')
fi
if [ "$actual" != "$expected" ]; then
    echo "::error title=hog checksum mismatch::$file doesn't match the checksum in the hog $version GitHub release."
    exit 1
fi
# hog-sha256 lists one checksum per runner type the workflow uses, so a matrix can pin all of them.
if [ -n "${HOG_SHA256:-}" ] && ! tr '[:upper:]' '[:lower:]' <<<"$HOG_SHA256" | tr -s ' ,\n' '\n' | grep -qx "$actual"; then
    echo "::error title=hog checksum not pinned::$file of hog $version has the checksum $actual, which the hog-sha256 input doesn't list."
    exit 1
fi
tar -xzf "$dir/$file" -C "$dir" hog
hog="$dir/hog"

export HOG_NO_UPDATE_CHECK=1
if [ -n "${INPUT_PROJECT_ID:-}" ]; then
    export HOG_PROJECT_ID="$INPUT_PROJECT_ID"
fi
if [ -n "${INPUT_HOST:-}" ]; then
    export HOG_HOST="$INPUT_HOST"
fi

args=(error-tracking release -o json)
if [ -n "${INPUT_RELEASE_NAME:-}" ]; then
    args+=(--release-name "$INPUT_RELEASE_NAME")
fi
if [ -n "${INPUT_RELEASE_VERSION:-}" ]; then
    args+=(--release-version "$INPUT_RELEASE_VERSION")
fi
if [ -n "${INPUT_BUILD:-}" ]; then
    args+=(--build "$INPUT_BUILD")
fi

release="$("$hog" "${args[@]}")"

# hog prints null when neither the inputs nor the git metadata name a release.
if [ -z "$release" ] || [ "$release" = null ]; then
    echo "::warning title=No PostHog release::hog could not name a release. Set the release-name and release-version inputs."
    echo "hog-path=$hog" >>"$GITHUB_OUTPUT"
    exit 0
fi

# Multiline syntax, so a newline in a release name or version can't add an output of its own.
output() {
    local delimiter
    delimiter="EOF_$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
    printf '%s<<%s\n%s\n%s\n' "$1" "$delimiter" "$2" "$delimiter" >>"$GITHUB_OUTPUT"
}
output release-id "$(jq -r '.id' <<<"$release")"
output release-name "$(jq -r '.project' <<<"$release")"
output release-version "$(jq -r '.version' <<<"$release")"
output release "$(jq -c '.' <<<"$release")"
output hog-path "$hog"

echo "Resolved release $(jq -r '"\(.project)@\(.version) with id \(.id)"' <<<"$release")"
