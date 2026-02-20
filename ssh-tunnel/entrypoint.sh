#!/bin/sh
set -e

mkdir -p /root/.ssh
chmod 700 /root/.ssh

# Copy mounted keys with correct permissions (Docker on macOS
# bind-mounts don't preserve Unix permissions, which makes
# OpenSSH refuse the key files).
if [ -d /ssh-keys ]; then
  for f in /ssh-keys/id_* /ssh-keys/config; do
    [ -f "$f" ] && cp "$f" /root/.ssh/
  done
  chmod 600 /root/.ssh/id_* 2>/dev/null || true
fi

export AUTOSSH_GATETIME=0

exec autossh -M 0 -N \
  -o "StrictHostKeyChecking=accept-new" \
  -o "UserKnownHostsFile=/tmp/known_hosts" \
  -o "ServerAliveInterval=15" \
  -o "ServerAliveCountMax=3" \
  -o "ExitOnForwardFailure=yes" \
  -p "${SSH_PORT}" \
  -L "0.0.0.0:${LOCAL_PORT:-8080}:localhost:${REMOTE_PORT:-8080}" \
  "${SSH_USER:-root}@${SSH_HOST}"
