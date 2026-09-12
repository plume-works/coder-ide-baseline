#!/usr/bin/env bash
# Materialise the container environment for coder-agent.service.
#
# The agent bootstrap is multi-line, which systemd's EnvironmentFile parser
# cannot represent, so it is written to its own script file instead.
set -euo pipefail

ENV_OUT=/etc/coder-agent.env
SCRIPT_OUT=/usr/local/bin/coder-agent-init.sh

: >"$ENV_OUT"
chmod 600 "$ENV_OUT"
: >"$SCRIPT_OUT"
chmod 700 "$SCRIPT_OUT"

# PID 1 holds the environment Docker passed to the container.
while IFS= read -r -d '' entry; do
  case "$entry" in
    CODER_AGENT_INIT_SCRIPT=*)
      printf '%s\n' "${entry#CODER_AGENT_INIT_SCRIPT=}" >"$SCRIPT_OUT"
      ;;
    CODER_AGENT_TOKEN=*|CODER_AGENT_URL=*)
      printf '%s\n' "$entry" >>"$ENV_OUT"
      ;;
  esac
done </proc/1/environ

chown coder:coder "$SCRIPT_OUT"
