#!/bin/bash
set -e

git config --global user.name "claude"
git config --global user.email "claude@local"
git config --global init.defaultBranch main

if [ ! -d "/workspace/.git" ]; then
  git init /workspace
  git -C /workspace commit --allow-empty -m "init"
fi

exec "$@"
