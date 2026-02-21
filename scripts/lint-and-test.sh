#!/usr/bin/env bash
# Run linters and smoke tests (same as CI where possible).
# Usage: ./scripts/lint-and-test.sh   or from repo root: bash scripts/lint-and-test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

FAILED=0

# Minimal config.env so scripts that source it don't fail shellcheck (SC1091)
if [[ ! -f config.env ]]; then
  echo 'VAST_API_KEY=""' > config.env
fi

# --- Shellcheck (if installed) ---
if command -v shellcheck &>/dev/null; then
  echo "→ Running shellcheck..."
  if shellcheck --severity=warning \
    umcode install.sh start.sh provision.sh connect.sh destroy.sh \
    opencode.sh claude.sh claude-yolo.sh open-vscode.sh bench-agents.sh \
    scripts/select-offer.sh \
    ssh-tunnel/entrypoint.sh opencode/entrypoint.sh claude/entrypoint.sh 2>&1; then
    echo "  shellcheck OK"
  else
    FAILED=1
  fi
else
  echo "→ shellcheck not installed (skip). Install: brew install shellcheck"
fi

# --- Ruff (Python lint + format) ---
echo "→ Running ruff check..."
if command -v ruff &>/dev/null; then
  ruff check anthropic-proxy/proxy.py bench.py && echo "  ruff check OK" || FAILED=1
  echo "→ Running ruff format --check..."
  ruff format --check anthropic-proxy/proxy.py bench.py && echo "  ruff format OK" || FAILED=1
elif [[ -d .venv ]] && [[ -f .venv/bin/ruff ]]; then
  .venv/bin/ruff check anthropic-proxy/proxy.py bench.py && echo "  ruff check OK" || FAILED=1
  .venv/bin/ruff format --check anthropic-proxy/proxy.py bench.py && echo "  ruff format OK" || FAILED=1
else
  echo "  ruff not found. Install: pip install ruff  or  uv sync --extra dev"
fi

# --- Docker Compose config ---
echo "→ Validating docker compose config..."
if command -v docker &>/dev/null; then
  if [[ ! -f .env ]]; then
    printf 'SSH_HOST=ci\nSSH_PORT=22\nREMOTE_PORT=8080\nLLAMA_API_BASE=http://localhost:8080/v1\n' > .env
  fi
  if docker compose config --quiet 2>/dev/null; then
    echo "  compose config OK"
  else
    FAILED=1
  fi
else
  echo "  docker not found (skip)"
fi

# --- umcode CLI smoke tests ---
echo "→ umcode CLI smoke tests..."
if ./umcode --help &>/dev/null; then
  echo "  umcode --help OK"
else
  FAILED=1
fi
UNKNOWN_OUT=$(./umcode unknown 2>&1) || true
if echo "$UNKNOWN_OUT" | grep -q "unknown subcommand"; then
  echo "  umcode unknown (exit 1) OK"
else
  FAILED=1
fi
START_OUT=$(./umcode start 2>&1) || true
if echo "$START_OUT" | grep -q "VAST_API_KEY"; then
  echo "  umcode start (fails without key) OK"
else
  FAILED=1
fi

echo
if [[ $FAILED -eq 0 ]]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks failed."
  exit 1
fi
