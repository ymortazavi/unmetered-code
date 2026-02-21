#!/usr/bin/env bash
# All-in-one installer for umcode.
# Run: curl -sSL https://raw.githubusercontent.com/ymortazavi/umcode/main/install.sh | bash
#
# This script: clones the repo, asks for config (Vast API key, etc.), provisions
# a Vast.ai instance, connects the SSH tunnel, and starts Docker. Before exiting
# it prints clear instructions on how to DESTROY the Vast instance to stop billing.

set -euo pipefail

REPO_URL="${UNMETERED_CODE_REPO:-https://github.com/ymortazavi/umcode.git}"
# Use $HOME (not /$HOME); expand once so we never pass a literal $HOME path to git
DEFAULT_DIR="${UNMETERED_CODE_DIR:-$HOME/umcode}"

info()  { printf '\033[1;34m→ %s\033[0m\n' "$*"; }
ok()    { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33m⚠ %s\033[0m\n' "$*"; }
fail()  { printf '\033[1;31m✗ %s\033[0m\n' "$*"; exit 1; }

prompt() {
  local var="$1" prompt_text="$2" default="${3:-}"
  if [[ -n "$default" ]]; then
    printf '\033[1;36m%s\033[0m [%s]: ' "$prompt_text" "$default"
    read -r "${var?}" < /dev/tty
    if [[ -z "${!var}" ]]; then
      printf -v "$var" '%s' "$default"
    fi
  else
    printf '\033[1;36m%s\033[0m: ' "$prompt_text"
    read -r "${var?}" < /dev/tty
  fi
}

yesno() {
  local prompt_text="$1" default="${2:-n}"
  local y="y/N"
  [[ "$default" =~ ^[yY] ]] && y="Y/n"
  printf '\033[1;36m%s\033[0m [%s]: ' "$prompt_text" "$y"
  read -r ans < /dev/tty
  case "${ans:-$default}" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  umcode — Unmetered private AI on Vast.ai (~\$1.50/hr)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# ─── Dependency checks ─────────────────────────────────

missing=""
command -v git &>/dev/null        || missing+=" git"
command -v docker &>/dev/null    || missing+=" docker"
command -v python3 &>/dev/null   || missing+=" python3"
docker compose version &>/dev/null 2>&1 || docker-compose version &>/dev/null 2>&1 || missing+=" docker-compose"
if [[ -n "$missing" ]]; then
  fail "Missing:${missing}. See https://github.com/ymortazavi/umcode#prerequisites"
fi
ok "git  docker  python3"

# ─── Install directory ────────────────────────────────

INSTALL_DIR=""
prompt INSTALL_DIR "Install directory" "$DEFAULT_DIR"
INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"
# Reject bogus paths (e.g. from stdin being script when run as curl|bash); use $HOME not /$HOME
if [[ -z "$INSTALL_DIR" || "$INSTALL_DIR" == *'$HOME'* || "$INSTALL_DIR" == /\$HOME* ]]; then
  INSTALL_DIR="$DEFAULT_DIR"
fi
INSTALL_DIR="$(cd -P "$(dirname "$INSTALL_DIR")" 2>/dev/null && pwd)/$(basename "$INSTALL_DIR")" || true
if [[ -z "$INSTALL_DIR" || "$INSTALL_DIR" == *'$HOME'* ]]; then
  INSTALL_DIR="$DEFAULT_DIR"
fi

if [[ -d "$INSTALL_DIR" && -f "$INSTALL_DIR/provision.sh" ]]; then
  if ! yesno "Directory $INSTALL_DIR already exists and looks like umcode. Use it and only configure/run?" "y"; then
    fail "Aborted. Choose a different directory or remove $INSTALL_DIR and re-run."
  fi
  ok "Using existing repo at $INSTALL_DIR"
else
  if [[ -d "$INSTALL_DIR" ]]; then
    fail "Directory $INSTALL_DIR exists but is not an umcode clone. Remove it or choose another path."
  fi
  info "Cloning into $INSTALL_DIR ..."
  git clone --depth 1 --quiet "$REPO_URL" "$INSTALL_DIR" || fail "git clone failed"
  ok "Cloned"
fi

cd "$INSTALL_DIR"

# ─── Config: VAST_API_KEY ──────────────────────────────

if [[ -f config.env ]] && grep -q '^VAST_API_KEY="[^"]*"' config.env 2>/dev/null; then
  current_key="$(grep '^VAST_API_KEY=' config.env 2>/dev/null | sed 's/^VAST_API_KEY="\(.*\)"$/\1/' || true)"
  if [[ -n "$current_key" && "$current_key" != "your_vast_api_key_here" ]]; then
    if yesno "config.env already has VAST_API_KEY set. Use it and skip key prompt?" "y"; then
      VAST_API_KEY="$current_key"
    fi
  fi
fi
if [[ -z "${VAST_API_KEY:-}" ]]; then
  echo "API key: https://cloud.vast.ai/manage-keys/"
  prompt VAST_API_KEY "Vast.ai API key" ""
  [[ -z "${VAST_API_KEY:-}" ]] && fail "VAST_API_KEY is required"
fi

# ─── Config: HF_TOKEN (optional) ──────────────────────

HF_TOKEN=""
if yesno "HuggingFace token (optional, for gated models)?" "n"; then
  prompt HF_TOKEN "HuggingFace token" ""
fi

# ─── Write config.env ─────────────────────────────────

info "Writing config.env ..."
cat > config.env <<CONFIG
# ─── Vast.ai ───────────────────────────────────────────
VAST_API_KEY="${VAST_API_KEY}"

# ─── HuggingFace (optional) ────────────────────────────
CONFIG
if [[ -n "${HF_TOKEN:-}" ]]; then
  echo "HF_TOKEN=\"${HF_TOKEN}\"" >> config.env
else
  echo "# HF_TOKEN=\"your_hf_token_here\"" >> config.env
fi
cat >> config.env <<'CONFIG_TAIL'

# ─── Model (HuggingFace GGUF) ─────────────────────────
HF_REPO="unsloth/MiniMax-M2.5-GGUF"
HF_QUANT="UD-Q4_K_XL"
HF_INCLUDE="UD-Q4_K_XL/*"
MODEL_ALIAS="minimax-m2.5"

# ─── llama-server ──────────────────────────────────────
LLAMA_PORT=8080
CTX_SIZE=163840
GPU_LAYERS=-1
PARALLEL=4
KV_CACHE_TYPE="q4_0"
BATCH_SIZE=4096
UBATCH_SIZE=4096

# ─── Vast.ai Instance ─────────────────────────────────
IMAGE="vastai/llama-cpp:b8054-cuda-12.9"
DISK_GB=150
CONFIG_TAIL
ok "config.env written"

# ─── vastai CLI ────────────────────────────────────────

if ! command -v vastai &>/dev/null; then
  info "Installing vastai CLI (pip install vastai) ..."
  python3 -m pip install --user vastai 2>/dev/null || pip install vastai 2>/dev/null || fail "Could not install vastai. Run: pip install vastai"
  ok "vastai installed"
fi
vastai set api-key "$VAST_API_KEY" >/dev/null 2>&1
ok "Vast.ai API key configured"

# ─── SSH key (optional) ────────────────────────────────

if yesno "Register SSH key with Vast.ai (for tunnel)?" "y"; then
  for key in ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub; do
    if [[ -f "${key/#\~/$HOME}" ]]; then
      vastai set ssh-key "$(cat "${key/#\~/$HOME}")" 2>/dev/null && ok "SSH key registered" && break
    fi
  done
  vastai show ssh-keys &>/dev/null || warn "No key registered. Run: ssh-keygen -t ed25519 && vastai set ssh-key \"\$(cat ~/.ssh/id_ed25519.pub)\""
fi

# ─── GPU offer & provision ─────────────────────────────

echo
info "GPU offers (2× RTX Pro 6000)..."
./scripts/select-offer.sh || fail "Offer selection failed"
OFFER_ID=$(cat .selected_offer 2>/dev/null)
rm -f .selected_offer
[[ -z "${OFFER_ID:-}" ]] && fail "No offer selected."

info "Provisioning Vast.ai instance (this may take a few minutes)..."
./provision.sh "$OFFER_ID" || fail "provision.sh failed"

INSTANCE_ID="$(cat .instance_id 2>/dev/null || true)"
[[ -z "$INSTANCE_ID" ]] && fail "No .instance_id after provision"
ok "Instance ${INSTANCE_ID} created. View it at: https://cloud.vast.ai/instances/"

# ─── Connect (SSH tunnel + wait for model) ──────────────

info "Connecting SSH tunnel and waiting for model (5–10 min first time)..."
./connect.sh || fail "connect.sh failed"

# ─── Docker Compose ────────────────────────────────────

echo
echo "Start stack:  1) Pre-built images  2) Build from source (Apple Silicon / custom)"
prompt BUILD_CHOICE "Choose [1/2]" "1"
case "${BUILD_CHOICE}" in
  2) info "Building..." ; docker compose -f compose.yaml -f compose.build.yaml up -d --build || fail "docker compose build failed" ;;
  *) info "Starting..." ; docker compose up -d || fail "docker compose up failed" ;;
esac
ok "Stack is up"

# ─── Launch agent ─────────────────────────────────────

echo
echo "Launch agent:  1) opencode  2) claude  3) claude --yolo  4–6) VS Code  7) Skip"
prompt AGENT_CHOICE "Choose [1-7]" "7"

# ─── Add umcode to PATH (optional) ─────────────────────

if yesno "Add umcode to PATH (~/.local/bin)?" "y"; then
  LOCAL_BIN="${HOME}/.local/bin"
  mkdir -p "$LOCAL_BIN"
  if ln -sf "${INSTALL_DIR}/umcode" "${LOCAL_BIN}/umcode" 2>/dev/null; then
    ok "Symlinked umcode to ${LOCAL_BIN}/umcode"
    if ! echo ":$PATH:" | grep -q ":${LOCAL_BIN}:"; then
      echo ""
      echo "  Add to your shell config (~/.bashrc or ~/.zshrc):"
      echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
      echo ""
      echo "  Then run:  exec \$SHELL   (or open a new terminal)"
    fi
  else
    warn "Could not create symlink. Add manually:  ln -sf \"${INSTALL_DIR}/umcode\" ~/.local/bin/umcode"
  fi
fi

# ─── Success + DESTROY reminder ────────────────────────

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok "Setup complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
printf '\033[1;31m'
echo "  Stop billing when done:  umcode destroy   (instance ${INSTANCE_ID})"
printf '\033[0m'
echo

case "${AGENT_CHOICE}" in
  1) exec ./opencode.sh ;;
  2) exec ./claude.sh ;;
  3) exec ./claude-yolo.sh ;;
  4) exec ./open-vscode.sh --opencode ;;
  5) exec ./open-vscode.sh --claude ;;
  6) exec ./open-vscode.sh --both ;;
  *) echo "Run agents anytime:  ./umcode opencode  ./umcode claude  ./umcode vscode --both" ;;
esac
