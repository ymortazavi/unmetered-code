#!/bin/bash
set -e

if [ ! -d "/workspace/.git" ]; then
  git init /workspace
  git -C /workspace commit --allow-empty -m "init"
fi

exec "$@"
