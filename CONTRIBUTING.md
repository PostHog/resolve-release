# Contributing

## Release a new version

- Change the version in `VERSION` (for example `1.0.1`) in the same pull request as your change.
- Merge the pull request into `main`.
- The release workflow creates the `v1.0.1` tag and a GitHub release, and moves the `v1` tag to it.

A push to `main` that keeps `VERSION` unchanged releases nothing.

## Update hog

Callers pick the hog version with the required `hog-version` input, so a hog release needs no release of the action.
Raise the version the tests use in `.github/workflows/test.yml` to check the action against a new hog.

## Tests

The test workflow runs the action on Linux and macOS runners.
The job that resolves a real release logs in with its OIDC token, so the repository needs:

- Variable `POSTHOG_PROJECT_ID`: the ID of the project that holds the test releases.
- Variable `POSTHOG_HOST` (optional): the PostHog host, when it is not the US cloud.
- A trust policy for this repository in that project, for pull requests and pushes to `main`, with the `error_tracking:write` scope. Run `hog ci setup --scope error_tracking:write` in a clone of the repository to request it.

Without the variable, the job is skipped and the run shows a notice.

To run the script outside GitHub Actions, set the variables that `action.yml` passes to it, plus `RUNNER_OS`, `RUNNER_TEMP`, `GITHUB_OUTPUT`, and the job's `ACTIONS_ID_TOKEN_REQUEST_URL` and `ACTIONS_ID_TOKEN_REQUEST_TOKEN`, then run `bash resolve.sh`.
