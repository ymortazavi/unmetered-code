#!/bin/bash
set -e

git config --global user.name "claude"
git config --global user.email "claude@local"
git config --global init.defaultBranch main

# Install default MCP config (SearXNG) into home and workspace if missing (volumes shadow image content)
if [ ! -f /home/node/.claude.json ]; then
  cp /opt/claude-defaults/.claude.json /home/node/.claude.json
fi
if [ ! -f /workspace/.mcp.json ]; then
  cp /opt/claude-defaults/.mcp.json /workspace/.mcp.json
fi

if [ ! -d "/workspace/.git" ]; then
  git init /workspace
  git -C /workspace commit --allow-empty -m "init"
fi

exec "$@"
