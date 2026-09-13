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

  # The second clone is a sibling of the first inside the Dev Container, which
  # mounts the first at /workspaces/<name>.
  second_repo_dir  = replace(replace(data.coder_parameter.second_repo.value, "/^.*[\\/:]/", ""), "/\\.git$/", "")
  second_repo_path = "/workspaces/${local.second_repo_dir}"

  # Without the first repository there is no Dev Container to clone into.
  second_repo_enabled = data.coder_parameter.second_repo.value != "" && data.coder_parameter.repo.value != ""

  # systemd hands units its own PATH rather than the image's, so the directory
  # the image puts Node and the devcontainer CLI on has to be named again here.
  agent_unit = <<-EOT
    [Unit]
    Description=Coder Agent
    Wants=network-online.target
    After=network-online.target

    [Service]
    Type=exec
    User=${local.username}
    Environment=PATH=/opt/node-bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    EnvironmentFile=/etc/coder/agent.env
    ExecStart=/bin/bash /etc/coder/agent-init.sh
    Restart=on-failure
    RestartSec=5

    [Install]
    WantedBy=multi-user.target
  EOT
}

data "coder_parameter" "image" {
  name         = "image"
  display_name = "Base image"
  description  = "Base image to use for the workspace. It must run as root and provide systemd at /sbin/init, plus the tooling and a passwordless-sudo coder user."
  type         = "string"
  mutable      = true
  default      = "ghcr.io/plume-works/coder-ide-baseline:latest"
}

data "coder_parameter" "repo" {
  name         = "repo"
  display_name = "Repository URL"
  description  = "Repository to clone on first start and bring up as the workspace's Dev Container. Leave empty for a plain workspace with no Dev Container."
  type         = "string"
  mutable      = true
  default      = "https://github.com/plume-works/agent-devcontainer.git"
}

data "coder_parameter" "second_repo" {
  name         = "second_repo"
  display_name = "Second repository URL"
  description  = "Optional second repository, cloned inside the Dev Container at /workspaces/<name> as a sibling of the first. Ignored when Repository URL is empty."
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

    # systemd owns dockerd through docker.service; wait for it to come up.
    echo "Waiting for Docker to become ready"
    for _ in $(seq 1 60); do
      if docker info >/dev/null 2>&1; then
        echo "Docker is ready"
        break
      fi
      sleep 2
    done
    docker info >/dev/null 2>&1 ||
      echo "WARNING: Docker did not become ready; check 'systemctl status docker'"

    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    ssh-keyscan -t ed25519 github.com gitlab.com >>~/.ssh/known_hosts 2>/dev/null || true

    REPO_URL="${data.coder_parameter.repo.value}"
    if [ -n "$REPO_URL" ]; then
      if [ ! -d "${local.repo_path}" ]; then
        echo "Cloning $REPO_URL"
        git clone "$REPO_URL" "${local.repo_path}" || echo "WARNING: clone failed"
      fi

      # Docker creates a missing bind-mount source as root, so bringing a Dev
      # Container up can leave the checkout owned by another uid. Git then
      # refuses to read it, and a devcontainer.json initializeCommand that asks
      # git anything fails before the container is built.
      git config --global --get-all safe.directory 2>/dev/null |
        grep -qx "${local.repo_path}" ||
        git config --global --add safe.directory "${local.repo_path}"
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

# The agent starts declared Dev Containers only once its start scripts have all
# finished, so this waits in a detached process: waiting in the foreground would
# hold back the very container it is waiting for. `devcontainer exec` only
# attaches to a container that already exists, so polling it cannot race the
# agent's own `devcontainer up`.
resource "coder_script" "second_repo" {
  count              = local.second_repo_enabled ? data.coder_workspace.me.start_count : 0
  agent_id           = coder_agent.dev.id
  display_name       = "Clone second repository"
  icon               = "/icon/git.svg"
  run_on_start       = true
  start_blocks_login = false
  script             = <<-EOT
    set -euo pipefail

    LOG=/tmp/coder-second-repo.log
    WORKER=/tmp/coder-second-repo.sh

    # The worker runs from a file with stdin closed: fed on stdin instead, the
    # `devcontainer exec` below would consume the rest of it as its own input.
    cat >"$WORKER" <<'SCRIPT'
    folder=$1
    target=$2
    url=$3

    # A first Dev Container build pulls and builds everything the image needs,
    # which for a large one runs well past the twenty minutes this first allowed.
    deadline=$(( $(date +%s) + 3600 ))
    until devcontainer exec --workspace-folder "$folder" -- true >/dev/null 2>&1; do
      if [ "$(date +%s)" -ge "$deadline" ]; then
        echo "WARNING: the Dev Container did not come up within an hour; $target was not cloned"
        exit 0
      fi
      sleep 5
    done

    echo "Cloning $url into $target"
    devcontainer exec --workspace-folder "$folder" -- bash -c '
      if [ -e "$1" ]; then
        echo "$1 already exists; leaving it alone"
      else
        git clone "$2" "$1"
      fi
    ' _ "$target" "$url"
    SCRIPT

    echo "Waiting for the Dev Container in the background; progress in $LOG"
    setsid bash "$WORKER" "${local.repo_path}" "${local.second_repo_path}" "${data.coder_parameter.second_repo.value}" >"$LOG" 2>&1 </dev/null &
  EOT
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

  # Sysbox sets a container up for systemd only when its first argument is
  # exactly `/sbin/init`, so systemd cannot be reached through a wrapper shell.
  # The agent is a unit instead; docker.service supervises dockerd.
  entrypoint = ["/sbin/init"]
  command    = []

  # The agent must run as `coder`: devcontainer up maps the inner user to the
  # invoking uid.
  # Root-owned and not executable: systemd names the interpreter, so `coder`
  # needs only to read what systemd runs as it.
  upload {
    file    = "/etc/coder/agent-init.sh"
    content = <<-EOT
      ${replace(coder_agent.dev.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")}
    EOT
  }

  upload {
    file    = "/etc/coder/agent.env"
    content = "CODER_AGENT_TOKEN=${coder_agent.dev.token}\n"
  }

  upload {
    file    = "/etc/systemd/system/coder-agent.service"
    content = local.agent_unit
  }

  # `systemctl enable` cannot run before systemd does, and systemd ignores a
  # plain file dropped in a wants directory, where it expects a symlink. A
  # target drop-in pulls the unit in without one.
  upload {
    file    = "/etc/systemd/system/multi-user.target.d/10-coder-agent.conf"
    content = <<-EOT
      [Unit]
      Wants=coder-agent.service
    EOT
  }

  # systemd as PID 1 reads SIGTERM as daemon-reexec, so a stop would end in
  # SIGKILL with dockerd still writing to /var/lib/docker. SIGRTMIN+3 is its
  # shutdown signal, and the grace period is what gives the stop time to run.
  stop_signal           = "SIGRTMIN+3"
  destroy_grace_seconds = 30

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
