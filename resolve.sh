#!/usr/bin/env bash
set -euo pipefail

# hog trades the job's OIDC token for a PostHog token, which needs `permissions: id-token: write`.
# Pull requests from forks never get one, so exiting zero here keeps those runs green.
if [ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]; then
    echo "::warning title=No PostHog release::The job has no OIDC token, so no release was resolved and every output is empty. Add \`permissions: id-token: write\` to the job, and run \`hog ci setup\` once so PostHog trusts this repository."
    exit 0
fi

if [ -z "${HOG_VERSION:-}" ]; then
    echo "::error title=No hog version::Set the hog-version input to the hog version to install, such as 0.1.0."
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "::error title=jq not found::This action needs jq to read the release. Install jq on the runner. GitHub-hosted runners include it."
    exit 1
fi

case "${RUNNER_OS:-}/$(uname -m)" in
    Linux/x86_64) target=linux-x64 ;;
    Linux/aarch64 | Linux/arm64) target=linux-arm64 ;;
    macOS/arm64) target=darwin-arm64 ;;
    macOS/x86_64) target=darwin-x64 ;;
    *)
        echo "::error title=Unsupported runner::This action runs on Linux and macOS runners, on x64 or arm64. This runner is '${RUNNER_OS:-unknown}' on '$(uname -m)'."
        exit 1
        ;;
esac
# Alpine and other musl-based containers need the musl build.
if [ "$RUNNER_OS" = Linux ] && ldd --version 2>&1 | grep -qi musl; then
    target="$target-musl"
fi

download() {
    curl --proto '=https' --tlsv1.2 -fsSL --retry 5 --retry-all-errors --retry-max-time 60 --connect-timeout 10 \
        -o "$2" "$1"
}

# Files under a hog version never change, so the version's manifest names the archive for this runner
# and its checksum.
base="https://releases.posthog.com/hog/v$HOG_VERSION"
dir="$RUNNER_TEMP/hog-$HOG_VERSION"
mkdir -p "$dir"
download "$base/manifest.json" "$dir/manifest.json"
file=$(jq -r --arg target "$target" '.artifacts[$target].file // empty' "$dir/manifest.json")
sha256=$(jq -r --arg target "$target" '.artifacts[$target].sha256 // empty' "$dir/manifest.json")
if [ -z "$file" ] || [ -z "$sha256" ]; then
    echo "::error title=No hog build::hog $HOG_VERSION has no $target build. Check the hog-version input."
    exit 1
fi
if [ -n "${HOG_SHA256:-}" ] && [ "$HOG_SHA256" != "$sha256" ]; then
    echo "::error title=hog checksum mismatch::The hog-sha256 input doesn't match the $target archive of hog $HOG_VERSION."
    exit 1
fi
download "$base/$file" "$dir/$file"
# macOS runners have shasum but not sha256sum.
if command -v sha256sum >/dev/null 2>&1; then
    echo "$sha256  $dir/$file" | sha256sum -c -
else
    echo "$sha256  $dir/$file" | shasum -a 256 -c -
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

release_id="$(jq -r '.id' <<<"$release")"
release_name="$(jq -r '.project' <<<"$release")"
release_version="$(jq -r '.version' <<<"$release")"
release_json="$(jq -c '.' <<<"$release")"

{
    echo "release-id=$release_id"
    echo "release-name=$release_name"
    echo "release-version=$release_version"
    echo "release=$release_json"
    echo "hog-path=$hog"
} >>"$GITHUB_OUTPUT"

echo "Resolved release $release_name@$release_version with id $release_id"
