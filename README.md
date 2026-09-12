# Coder Workspace Template for running Devcontainers

This repository contains all the required files to run a [Devcontainer](https://code.visualstudio.com/docs/remote/containers) in a [Coder](https://github.com/coder/coder) workspace. The devcontainer image supports both ARM64 and AMD64 architectures.

## Structure

The structure of this repository is as follows:

- `root-container`: Contains the container used by Coder as the base for your workspaces. It contains the minimal amount of software required to run Docker and VS Code.
- `template`: Contains the template used in Coder to create your workspaces.

## Image

The base image is published to the GitHub Container Registry:

```
ghcr.io/plume-works/coder-ide-baseline:latest
```

Pushes to `main` publish the `latest` tag, and published releases publish a tag named after the release. Pull requests build the image without publishing it. The workspace user inside the image is `coder` (uid 1000), with the home directory at `/home/coder`.

A GitHub Container Registry package is not public when it is first published.
Unless the Docker host running the workspaces authenticates to `ghcr.io`, set
the package visibility to public once, under
`Package settings -> Change visibility`; otherwise the workspace build fails to
pull the image with `unauthorized`.

To build the image locally for the current architecture:

```bash
./root-container/build.sh
```

## Docker-in-Docker

The Coder agent is the container entrypoint and starts `dockerd` on first
boot, so Docker is available inside the workspace.

The `Container runtime` parameter selects how that is isolated:

- **Default runtime (privileged)** runs the workspace as a privileged
  container. It works on any Docker host, and is the default.
- **Sysbox** runs the workspace unprivileged under `sysbox-runc`, which gives
  stronger isolation but must be
  [installed on the Docker host](https://coder.com/docs/v2/latest/templates/docker-in-workspaces#use-sysbox-in-docker-based-templates)
  first.

A privileged container can affect the host it runs on; prefer Sysbox on any
host shared between users.

## Usage

You'll need the Coder CLI on your local machine to create and push the template. You can find the installation instructions [here](https://coder.com/docs/v2/latest/templates#get-the-cli).

Once you have the CLI installed, run `./template/push.sh`. It creates the
template on the first run and pushes a new version on later runs. Set
`TEMPLATE_NAME` to use a name other than `docker-in-docker`.
