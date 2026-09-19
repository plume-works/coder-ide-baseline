FROM ubuntu:resolute@sha256:da6fc2be547864451aa253836dd926da33623312df4a9a243e35dc877c378a78

SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

# Install the Docker apt repository
RUN apt-get update && \
    apt-get upgrade --yes --no-install-recommends --no-install-suggests && \
    apt-get install --yes --no-install-recommends --no-install-suggests \
    ca-certificates && \
    rm -rf /var/lib/apt/lists/*
COPY docker-archive-keyring.gpg /usr/share/keyrings/docker-archive-keyring.gpg
COPY docker.list /etc/apt/sources.list.d/docker.list

# Install baseline packages
RUN apt-get update && \
    apt-get install --yes --no-install-recommends --no-install-suggests \
    bash \
    build-essential \
    containerd.io \
    curl \
    docker-ce \
    docker-ce-cli \
    docker-buildx-plugin \
    docker-compose-plugin \
    htop \
    jq \
    locales \
    man \
    pipx \
    python3 \
    python3-pip \
    software-properties-common \
    sudo \
    systemd \
    systemd-sysv \
    unzip \
    vim \
    wget \
    rsync && \
    # Install latest Git using their official PPA
    add-apt-repository ppa:git-core/ppa && \
    apt-get install --yes git \
    && rm -rf /var/lib/apt/lists/*

# Enables Docker starting with systemd
RUN systemctl enable docker

# Create a symlink for standalone docker-compose usage
RUN ln -s /usr/libexec/docker/cli-plugins/docker-compose /usr/bin/docker-compose

# Generate the desired locale (en_US.UTF-8)
RUN locale-gen en_US.UTF-8

# Make typing unicode characters in the terminal work.
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Remove the `ubuntu` user and add a user `coder` so that you are not developing as the `root` user
RUN userdel -r ubuntu && \
    useradd coder \
    --create-home \
    --shell=/bin/bash \
    --groups=docker \
    --uid=1000 \
    --user-group && \
    echo "coder ALL=(ALL) NOPASSWD:ALL" >>/etc/sudoers.d/nopasswd

# Node lives outside /home/coder because that path is a volume mount at
# runtime, which would otherwise mask it. /opt/node-bin is a stable symlink so
# PATH does not name a Node version.
ENV NVM_DIR=/opt/nvm
# renovate: datasource=github-tags depName=nvm-sh/nvm
ARG NVM_VERSION=v0.39.7
# renovate: datasource=npm depName=@devcontainers/cli
ARG DEVCONTAINERS_CLI_VERSION=0.89.0
RUN mkdir -p "$NVM_DIR" && \
    curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash && \
    . "$NVM_DIR/nvm.sh" && \
    nvm install --lts && \
    nvm alias default lts/* && \
    nvm cache clear && \
    # devcontainers cli for prebuilding devcontainers
    npm install -g "@devcontainers/cli@${DEVCONTAINERS_CLI_VERSION}" && \
    ln -sfn "$(dirname "$(command -v node)")" /opt/node-bin && \
    chown -R coder:coder "$NVM_DIR"

# On PATH for non-interactive shells too, which is how the agent runs scripts.
ENV PATH=/opt/node-bin:$PATH:/home/coder/.local/bin

# The home directory is a volume mount at runtime, which masks anything
# baked into it; /etc/skel seeds it on first start instead.
COPY bashrc /etc/skel/.bashrc
COPY --chown=coder:coder bashrc /home/coder/.bashrc

# systemd runs as PID 1 and must be root; the template drops to `coder` for
# the agent.
USER root

# Links the published package to this repository. Without the link a push
# from Actions is denied `write_package`, whatever the workflow permissions
# say, because an unlinked org package inherits no repository access.
LABEL org.opencontainers.image.source=https://github.com/plume-works/coder-ide-baseline
