# PostHog resolve release GitHub Action

Create or find the PostHog error tracking release for a build, and output its ID.

Give the ID to your app as the `POSTHOG_RELEASE_ID` environment variable.
The SDK sends it as `$release_id` on every event, and error tracking uses it to link each exception to the release it came from.
The Python SDK reads `POSTHOG_RELEASE_ID` from version 7.59.0.

The action installs a pinned, checksum-verified `posthog-cli` and runs [`posthog-cli release resolve`](https://github.com/PostHog/posthog/tree/master/cli#resolving-a-release).
If a release with the same name and version already exists, for example because a source map upload created it, the action returns that release instead of creating a new one.

The action does not need a checkout. It reads the repository, branch, and commit from the workflow run.

## Inputs

| **Name**          | **Required** | **Description**                                                                                                                                                                       |
| ----------------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `api-key`         | Yes          | PostHog personal API key with error tracking write scope. See [API key settings](https://app.posthog.com/settings/user-api-keys#variables). When empty, the action resolves no release |
| `project-id`      | Yes          | PostHog project ID. See [project settings](https://app.posthog.com/settings/project#variables)                                                                                        |
| `host`            | No           | PostHog host URL. If you use the US cloud, you don't need to set this. For the EU cloud, set `https://eu.posthog.com`                                                                 |
| `release-name`    | No           | Release name. If not provided, the action uses the repository name                                                                                                                   |
| `release-version` | No           | Release version (e.g., `1.4.0` or a commit SHA). If not provided, the action uses the commit SHA, which on a pull request is the head commit of the pull request                       |
| `build`           | No           | Build number (e.g., `42`). The release version becomes `<release-version>+<build>`, so each build number is a separate release. Without `release-version`, the build number alone is the version |

## Outputs

| **Name**          | **Description**                                                                                                      |
| ----------------- | -------------------------------------------------------------------------------------------------------------------- |
| `release-id`      | ID of the release. Give it to your app as `POSTHOG_RELEASE_ID`. Empty when no release was resolved                   |
| `release-name`    | Name of the release in PostHog                                                                                       |
| `release-version` | Version of the release in PostHog, including the build number when one was given                                    |
| `release`         | The whole release as JSON. Read a field with `fromJSON(steps.<step-id>.outputs.release).<field>`                      |

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
    steps:
      - uses: actions/checkout@v6

      - name: Resolve PostHog release
        id: release
        uses: PostHog/resolve-release@v1
        with:
          api-key: ${{ secrets.POSTHOG_CLI_API_KEY }}
          project-id: ${{ vars.POSTHOG_PROJECT_ID }}

          # If using the EU cloud, set the host explicitly
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

The action fails the step when the CLI download, the checksum, or the PostHog API fails.
To deploy anyway, let the step fail without failing the job, and cap how long it can take:

```yaml
- name: Resolve PostHog release
  id: release
  continue-on-error: true
  timeout-minutes: 5
  uses: PostHog/resolve-release@v1
  with:
    api-key: ${{ secrets.POSTHOG_CLI_API_KEY }}
    project-id: ${{ vars.POSTHOG_PROJECT_ID }}
```

The `release-id` output is then empty, and an empty `POSTHOG_RELEASE_ID` is safe to pass on: the SDK treats it as unset.

### Use one release in several jobs

Resolve the release in one job and pass the ID to the others through job outputs.
Two jobs that resolve the same new release at the same time can both try to create it, and one of them then fails.

```yaml
jobs:
  release:
    runs-on: ubuntu-24.04
    outputs:
      release-id: ${{ steps.release.outputs.release-id }}
    steps:
      - id: release
        uses: PostHog/resolve-release@v1
        with:
          api-key: ${{ secrets.POSTHOG_CLI_API_KEY }}
          project-id: ${{ vars.POSTHOG_PROJECT_ID }}

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

## Notes

- Pull requests from forks get no secrets. With an empty `api-key`, the action logs a warning, leaves every output empty, and passes.
- The action runs on Linux and macOS runners. It needs `curl` and `jq`, which GitHub-hosted runners include.
- Pin the action to a major version (`@v1`) to get fixes and CLI updates, or to a full version (`@v1.0.0`) to control updates yourself.
