# Coder Workspace Template for running Devcontainers

This repository contains all the required files to run a [Devcontainer](https://code.visualstudio.com/docs/devcontainers/containers) in a [Coder](https://github.com/coder/coder) workspace. The devcontainer image supports both ARM64 and AMD64 architectures.

## Structure

The structure of this repository is as follows:

- `root-container`: Contains the container used by Coder as the base for your workspaces. It contains the minimal amount of software required to run Docker and VS Code.
- `template`: Contains the template used in Coder to create your workspaces.

## Image

The base image is published to the GitHub Container Registry:

```
ghcr.io/plume-works/coder-ide-baseline:latest
```

Pushes to `main` publish the `latest` tag, published releases publish a tag
named after the release, and a pull request publishes `pr-<number>` so its
image can be pulled and tested before merge. Each architecture builds on its
own native runner and the two are joined into one manifest list. The workspace
user inside the image is `coder` (uid 1000), with the home directory at
`/home/coder`.

A pull request from a fork builds both architectures but publishes nothing: a
fork's `GITHUB_TOKEN` is read-only no matter what the workflow declares. The
checks still run and still gate the merge, so the build stays a useful signal.
The run records that nothing was published in a warning and its job summary.

Two package settings gate publishing and pulling, and they are independent.
Both live under `Package settings` on the package page.

- **Actions access** decides whether this repository's workflow may push at
  all. The package must appear under `Manage Actions access` with the `Write`
  role; otherwise the push fails with `denied: permission_denied:
  write_package`. A package that Actions created is linked and granted this
  automatically -- one first pushed by hand from a personal token is not.
- **Visibility** decides whether the Docker host may pull. A package is
  private when first published, so unless that host authenticates to
  `ghcr.io`, set visibility to public once under `Change visibility`;
  otherwise the workspace build fails to pull with `unauthorized`.

To build the image locally for the current architecture:

```bash
./root-container/build.sh
```

## Docker-in-Docker

Workspaces run on the [Sysbox](https://github.com/nestybox/sysbox) runtime,
which gives each workspace a working Docker daemon without a privileged
container. `sysbox-runc` must be installed on the Docker host that runs the
workspaces; see the
[Sysbox installation guide](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/install.md)
and Coder's
[Docker-in-workspaces guide](https://coder.com/docs/admin/templates/extending-templates/docker-in-workspaces#use-sysbox-in-docker-based-templates).

Without it, workspace builds fail with
`unknown or invalid runtime name: sysbox-runc`.

systemd runs as PID 1 in the workspace and `docker.service` supervises
`dockerd`; the Coder agent starts alongside it as the `coder` user.

## Dev Containers

The `repo` parameter clones that repository into the home directory and
registers it as a Dev Container, defaulting to `agent-devcontainer`. The agent
runs `devcontainer up` on it and Coder exposes the running container as a
sub-agent, so an editor attaches to the Dev Container itself rather than to the
workspace around it:

```bash
coder ssh <workspace>.<repo-name>
```

Clearing `repo` gives a plain workspace with no Dev Container.

`second_repo` clones a second repository *inside* that Dev Container, at
`/workspaces/<name>` alongside the first, once the agent has brought it up. It
is empty by default and ignored when `repo` is empty, since there is then no
Dev Container to clone into. That path is in the Dev Container's own filesystem
rather than on the home volume, so the second clone is recreated whenever the
Dev Container is rebuilt.

## Usage

You'll need the Coder CLI on your local machine to create and push the template. You can find the installation instructions [here](https://coder.com/docs/install/cli).

Once you have the CLI installed, run `./template/push.sh`. It creates the
template on the first run and pushes a new version on later runs. Set
`TEMPLATE_NAME` to use a name other than `docker-in-docker`.
