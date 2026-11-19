# PostHog resolve release GitHub Action

Create or find the PostHog error tracking release for a build, and output its ID.

Give the ID to your app as the `POSTHOG_RELEASE_ID` environment variable.
The SDK sends it as `$release_id` on every event, and error tracking uses it to link each exception to the release it came from.
The Python SDK reads `POSTHOG_RELEASE_ID` from version 7.59.0.

The action installs [hog](https://github.com/PostHog/posthog/tree/master/hog), the PostHog command line, at the version you pick, checks it against that version's manifest, and runs `hog error-tracking release`.
If a release with the same name and version already exists, for example because a source map upload created it, the action returns that release instead of creating a new one.

hog logs in with the job's OIDC token, so no PostHog key is stored in GitHub.
The job needs `permissions: id-token: write`, and PostHog has to trust the repository once: run `hog ci setup --scope error_tracking:write` in the repository and approve the request.
See [CI without a stored key](https://github.com/PostHog/posthog/tree/master/hog#ci-without-a-stored-key).

The action does not need a checkout. With one, it reads the project and host from `posthog.json`.

## Inputs

| **Name**          | **Required** | **Description**                                                                                                                                                                                  |
| ----------------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `hog-version`     | Yes          | The hog version to install, such as `0.1.0`. Pin a version you tested, so a new hog release never changes a build on its own                                                                     |
| `hog-sha256`      | No           | The SHA-256 of the hog archive for the runner, from the version's `manifest.json`. When set, the download must match it, which pins the exact binary                                            |
| `project-id`      | No           | PostHog project ID. Defaults to `projectId` in `posthog.json`, then `HOG_PROJECT_ID`                                                                                                            |
| `host`            | No           | PostHog host URL. Defaults to `host` in `posthog.json`, then `HOG_HOST`, then the US cloud. For the EU cloud, set `https://eu.posthog.com`                                                      |
| `release-name`    | No           | Release name. If not provided, the action uses the repository name                                                                                                                              |
| `release-version` | No           | Release version (e.g., `1.4.0` or a commit SHA). If not provided, the action uses the commit SHA, which on a pull request is the head commit of the pull request                                 |
| `build`           | No           | Build number (e.g., `42`). The release version becomes `<release-version>+<build>`, so each build number is a separate release. Without `release-version`, the build number alone is the version |

## Outputs

| **Name**          | **Description**                                                                                                      |
| ----------------- | -------------------------------------------------------------------------------------------------------------------- |
| `release-id`      | ID of the release. Give it to your app as `POSTHOG_RELEASE_ID`. Empty when no release was resolved                   |
| `release-name`    | Name of the release in PostHog                                                                                       |
| `release-version` | Version of the release in PostHog, including the build number when one was given                                    |
| `release`         | The whole release as JSON. Read a field with `fromJSON(steps.<step-id>.outputs.release).<field>`                      |
| `hog-path`        | Path to the hog binary the action installed, so later steps can run it, for example to upload source maps            |

## Example usage

Resolve the release, then bake its ID into a Docker image:

```yaml
name: Build

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-24.04
    permissions:
      id-token: write # lets hog get an OIDC token for PostHog
      contents: read
    steps:
      - uses: actions/checkout@v6

      - name: Resolve PostHog release
        id: release
        uses: PostHog/resolve-release@v2
        with:
          hog-version: 0.1.0
          # Without a posthog.json that names them
          # project-id: ${{ vars.POSTHOG_PROJECT_ID }}
          # host: https://eu.posthog.com

          # To name the release yourself instead of using the repository name and commit SHA
          # release-name: my-app
          # release-version: 1.4.0

      - name: Build image
        env:
          POSTHOG_RELEASE_ID: ${{ steps.release.outputs.release-id }}
        run: docker build --build-arg POSTHOG_RELEASE_ID="$POSTHOG_RELEASE_ID" --tag my-app .
```

In the Dockerfile, turn the build argument into an environment variable:

```dockerfile
ARG POSTHOG_RELEASE_ID
ENV POSTHOG_RELEASE_ID=$POSTHOG_RELEASE_ID
```

### Keep deploys going when PostHog can't be reached

The action fails the step when the hog download, the checksum, the OIDC exchange, or the PostHog API fails.
To deploy anyway, let the step fail without failing the job, and cap how long it can take:

```yaml
- name: Resolve PostHog release
  id: release
  continue-on-error: true
  timeout-minutes: 5
  uses: PostHog/resolve-release@v2
  with:
    hog-version: 0.1.0
```

The `release-id` output is then empty, and an empty `POSTHOG_RELEASE_ID` is safe to pass on: the SDK treats it as unset.

### Use one release in several jobs

Resolve the release in one job and pass the ID to the others through job outputs.
Two jobs that resolve the same new release at the same time can both try to create it, and one of them then fails.

```yaml
jobs:
  release:
    runs-on: ubuntu-24.04
    permissions:
      id-token: write
      contents: read
    outputs:
      release-id: ${{ steps.release.outputs.release-id }}
    steps:
      - uses: actions/checkout@v6
      - id: release
        uses: PostHog/resolve-release@v2
        with:
          hog-version: 0.1.0

  build:
    needs: release
    strategy:
      matrix:
        service: [web, worker]
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v6
      - env:
          POSTHOG_RELEASE_ID: ${{ needs.release.outputs.release-id }}
        run: docker build --build-arg POSTHOG_RELEASE_ID="$POSTHOG_RELEASE_ID" --tag "${{ matrix.service }}" .
```

## Upgrade from v1

- Set `hog-version` to the hog version to install, such as `0.1.0`.
- Remove `api-key`. v2 uses the job's OIDC token instead: add `permissions: id-token: write` to the job, and run `hog ci setup --scope error_tracking:write` in the repository once. Then delete the PostHog key secret.
- `project-id` is optional. Put `host` and `projectId` in `posthog.json`, or keep the inputs.

## Notes

- Pull requests from forks get no OIDC token. Without one, the action logs a warning, leaves every output empty, and passes.
- The action runs on Linux and macOS runners, on x64 or arm64. It needs `curl` and `jq`, which GitHub-hosted runners include.
- Pin the action to a major version (`@v2`) to get fixes, or to a full version (`@v2.0.0`) to control updates yourself. `hog-sha256` pins the exact hog binary on top of `hog-version`.
