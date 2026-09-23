# Contributing

## Release a new version

- Change the version in `VERSION` (for example `1.0.1`) in the same pull request as your change.
- Merge the pull request into `main`.
- The release workflow creates the `v1.0.1` tag and a GitHub release, and moves the `v1` tag to it.

A push to `main` that keeps `VERSION` unchanged releases nothing.

## Update the CLI

The CLI version and the checksum of its installer are pinned in `action.yml`.
To upgrade, set `POSTHOG_CLI_VERSION` and recompute the checksum:

```bash
curl -LsSf "https://github.com/PostHog/posthog/releases/download/posthog-cli%2Fv<X.Y.Z>/posthog-cli-installer.sh" | shasum -a 256
```

Release a new minor version after a CLI upgrade.

## Tests

The test workflow runs the action on Linux and macOS runners.
The job that resolves a real release needs these settings in the repository.
Without the secret, the job is skipped and the run shows a notice.

- Secret `POSTHOG_CLI_API_KEY`: a personal API key with error tracking write scope.
- Variable `POSTHOG_CLI_PROJECT_ID`: the ID of the project that holds the test releases.
- Variable `POSTHOG_CLI_HOST` (optional): the PostHog host, when it is not the US cloud.

To run the script outside GitHub Actions, set the variables that `action.yml` passes to it, plus `RUNNER_OS`, `RUNNER_TEMP`, and `GITHUB_OUTPUT`, then run `bash resolve.sh`.
