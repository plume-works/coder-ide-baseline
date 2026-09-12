# Docker-in-Docker workspace running on the Sysbox runtime.
# sysbox-runc must be installed on the Docker host; see README.md.

terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.18"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

variable "docker_socket" {
  default     = ""
  description = "(Optional) Docker socket URI"
  type        = string
}

provider "docker" {
  # Defaulting to null lets this stay optional without inventing a default.
  host = var.docker_socket != "" ? var.docker_socket : null
}

provider "coder" {}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  # The image bakes this user in; the home volume and apps must agree with it.
  username = "coder"
  home_dir = "/home/coder"

  # The image without any tag or digest, so the resolved digest can be
  # appended. The parameter is free-form, so it may already carry either.
  image_repo = replace(replace(data.coder_parameter.image.value, "/@[^@]+$/", ""), "/:[^:/]+$/", "")

  # Where the clone lands; the startup script and coder_devcontainer must agree.
  repo_dir  = replace(replace(data.coder_parameter.repo.value, "/^.*[\\/:]/", ""), "/\\.git$/", "")
  repo_path = "${local.home_dir}/${local.repo_dir}"
}

data "coder_parameter" "image" {
  name         = "image"
  display_name = "Base image"
  description  = "Base image to use for the workspace. Any image that ships the tooling and a passwordless-sudo coder user works."
  type         = "string"
  mutable      = true
  default      = "ghcr.io/plume-works/coder-ide-baseline:latest"
}

data "coder_parameter" "repo" {
  name         = "repo"
  display_name = "Repository URL"
  description  = "Optional repository to clone on first start, e.g. git@github.com:plume-works/coder-ide-baseline.git"
  type         = "string"
  mutable      = true
  default      = ""
}

resource "coder_agent" "dev" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  # Git identity comes from the Coder account rather than a template default.
  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
  }

  startup_script_behavior = "blocking"
  startup_script          = <<-EOT
    set -euo pipefail

    # The home directory is a fresh volume on first start; seed it from skel.
    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~ 2>/dev/null || true
      touch ~/.init_done
    fi

    # Nothing supervises the container, so the agent owns dockerd.
    if ! docker info >/dev/null 2>&1; then
      echo "Starting dockerd"
      sudo -n dockerd >/tmp/dockerd.log 2>&1 &
    fi

    echo "Waiting for Docker to become ready"
    for _ in $(seq 1 60); do
      if docker info >/dev/null 2>&1; then
        echo "Docker is ready"
        break
      fi
      sleep 2
    done
    docker info >/dev/null 2>&1 || echo "WARNING: Docker did not become ready; see /tmp/dockerd.log"

    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    ssh-keyscan -t ed25519 github.com gitlab.com >>~/.ssh/known_hosts 2>/dev/null || true

    REPO_URL="${data.coder_parameter.repo.value}"
    if [ -n "$REPO_URL" ] && [ ! -d "${local.repo_path}" ]; then
      echo "Cloning $REPO_URL"
      git clone "$REPO_URL" "${local.repo_path}" || echo "WARNING: clone failed"
    fi
  EOT

  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "2_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }
}

module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.dev.id
  folder   = local.home_dir
  order    = 1
}

# The agent autostarts this Dev Container and exposes it as its own sub-agent.
resource "coder_devcontainer" "repo" {
  count            = data.coder_parameter.repo.value != "" ? data.coder_workspace.me.start_count : 0
  agent_id         = coder_agent.dev.id
  workspace_folder = local.repo_path
}

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"

  # Keep the volume across attribute changes so home data is not discarded.
  lifecycle {
    ignore_changes = all
  }

  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

resource "docker_volume" "docker_lib" {
  name = "coder-${data.coder_workspace.me.id}-docker"

  lifecycle {
    ignore_changes = all
  }

  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

# Resolve the tag to a digest and run that digest. Naming the tag alone leaves
# a host that already cached the tag on a stale image indefinitely.
data "docker_registry_image" "base_image" {
  name = data.coder_parameter.image.value
}

resource "docker_image" "base_image" {
  name          = "${local.image_repo}@${data.docker_registry_image.base_image.sha256_digest}"
  pull_triggers = [data.docker_registry_image.base_image.sha256_digest]
  keep_locally  = true
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = docker_image.base_image.image_id
  # Uses lower() to avoid Docker restriction on container names.
  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = lower(data.coder_workspace.me.name)

  # The agent is the entrypoint and starts dockerd itself.
  entrypoint = ["sh", "-c", replace(coder_agent.dev.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.dev.token}"]

  # Sysbox gives the workspace a working, unprivileged Docker.
  runtime = "sysbox-runc"

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  volumes {
    container_path = local.home_dir
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }

  # Without this the inner image cache is discarded on every restart.
  volumes {
    container_path = "/var/lib/docker"
    volume_name    = docker_volume.docker_lib.name
    read_only      = false
  }

  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
}
