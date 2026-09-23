#!/usr/bin/env bash
set -euo pipefail

# Pull requests from forks get no secrets. Exiting zero here keeps those runs green.
if [ -z "${POSTHOG_CLI_API_KEY:-}" ]; then
    echo "::warning title=No PostHog release::The api-key input is empty, so no release was resolved and every output is empty."
    exit 0
fi

case "${RUNNER_OS:-}" in
    Linux | macOS) ;;
    *)
        echo "::error title=Unsupported runner::This action runs on Linux and macOS runners only. The runner OS is '${RUNNER_OS:-unknown}'."
        exit 1
        ;;
esac

if ! command -v jq >/dev/null 2>&1; then
    echo "::error title=jq not found::This action needs jq to read the release. Install jq on the runner. GitHub-hosted runners include it."
    exit 1
fi

installer="$RUNNER_TEMP/posthog-cli-installer-$POSTHOG_CLI_VERSION.sh"
curl --proto '=https' --tlsv1.2 -fsSL --retry 5 --retry-all-errors --retry-max-time 60 --connect-timeout 10 \
    -o "$installer" \
    "https://github.com/PostHog/posthog/releases/download/posthog-cli%2Fv${POSTHOG_CLI_VERSION}/posthog-cli-installer.sh"
# macOS runners have shasum but not sha256sum.
if command -v sha256sum >/dev/null 2>&1; then
    echo "$POSTHOG_CLI_INSTALLER_SHA256  $installer" | sha256sum -c -
else
    echo "$POSTHOG_CLI_INSTALLER_SHA256  $installer" | shasum -a 256 -c -
fi
sh "$installer"

# The CLI treats an empty POSTHOG_CLI_HOST as a host, so export it only when the input has a value.
if [ -n "${INPUT_HOST:-}" ]; then
    export POSTHOG_CLI_HOST="$INPUT_HOST"
fi

args=(release resolve --json)
if [ -n "${INPUT_RELEASE_NAME:-}" ]; then
    args+=(--release-name "$INPUT_RELEASE_NAME")
fi
if [ -n "${INPUT_RELEASE_VERSION:-}" ]; then
    args+=(--release-version "$INPUT_RELEASE_VERSION")
fi
if [ -n "${INPUT_BUILD:-}" ]; then
    args+=(--build "$INPUT_BUILD")
fi

release="$("$POSTHOG_CLI_INSTALL_DIR/posthog-cli" "${args[@]}")"

# The CLI prints null and exits zero when neither the inputs nor the git metadata name a release.
if [ -z "$release" ] || [ "$release" = "null" ]; then
    echo "::warning title=No PostHog release::The CLI could not identify a release. Set the release-name and release-version inputs."
    exit 0
fi

release_id="$(jq -r '.id' <<<"$release")"
release_name="$(jq -r '.project' <<<"$release")"
release_version="$(jq -r '.version' <<<"$release")"
release_json="$(jq -c '.' <<<"$release")"

{
    echo "release-id=$release_id"
    echo "release-name=$release_name"
    echo "release-version=$release_version"
    echo "release=$release_json"
} >>"$GITHUB_OUTPUT"

echo "Resolved release $release_name@$release_version with id $release_id"
