# Setup Guide

## Prerequisites

### Required

- **Docker + Docker Compose** — install via [Docker Desktop](https://docs.docker.com/get-docker/) (macOS/Windows) or [Docker Engine](https://docs.docker.com/engine/install/) (Linux). Compose v2 is included with modern Docker installs.
- **Python 3** — used by provisioning scripts to parse Vast.ai API responses. Pre-installed on macOS and most Linux distros.
- **Vast.ai account** — [sign up](https://cloud.vast.ai/?ref_id=399895) and load funds. GPU rental is billed per hour.
- **Vast.ai CLI**:

  ```bash
  pip install vastai
  ```

- **SSH key pair in `~/.ssh/`** — the tunnel container bind-mounts your `~/.ssh` directory and uses any `id_*` key to authenticate with the Vast.ai instance. Generate one if needed:

  ```bash
  ssh-keygen -t ed25519 -C "your_email@example.com"
  vastai set ssh-key "$(cat ~/.ssh/id_ed25519.pub)"
  vastai show ssh-keys   # verify
  ```

### Optional

- **HuggingFace token** — only needed for gated/private models. The default model ([unsloth/MiniMax-M2.5-GGUF](https://huggingface.co/unsloth/MiniMax-M2.5-GGUF)) is public. A token can also give faster downloads. Set `HF_TOKEN` in `config.env` if needed.
- **VS Code** with the [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension — required only for `./open-vscode.sh`.

---

## Manual Setup

### 1. Clone the repo

```bash
git clone https://github.com/ymortazavi/unmetered-code.git
cd unmetered-code
```

### 2. Configure `config.env`

Open `config.env` and set your Vast.ai API key:

```bash
VAST_API_KEY="your_vast_api_key_here"
```

**HuggingFace token (optional):** Uncomment and set `HF_TOKEN` if your model is gated or you want faster downloads:

```bash
HF_TOKEN="your_hf_token_here"
```

If unset or `"none"`, HuggingFace authentication is skipped — the default public model works without it.

### 3. Find a GPU offer

```bash
vastai search offers 'gpu_name in [RTX_PRO_6000_S,RTX_PRO_6000_WS] num_gpus==2 reliability>0.9' -o dph
```

The **ID** column is what you pass to `provision.sh`. For the default MiniMax M2.5 at UD-Q4_K_XL quantization, you need at least **192 GB VRAM** (e.g. 2× RTX Pro 6000). See [VRAM Budget](#vram-budget) below.

### 4. Provision the remote instance

```bash
./provision.sh <OFFER_ID>
```

Creates a Vast.ai instance that downloads the model and starts `llama-server`. The script waits for the instance to reach `running` state, then prints next steps. Model download takes 5–10 minutes.

> The llama port is not exposed publicly — it is only reachable through the SSH tunnel.

### 5. Connect the SSH tunnel

```bash
./connect.sh
```

Fetches the instance's public IP and SSH port, tests the connection, and writes a `.env` file with tunnel parameters for Docker Compose. If SSH isn't ready yet, re-run after a minute or two.

### 6. Start local services

```bash
docker compose up -d
```

Pulls prebuilt images from GHCR (linux/amd64 and linux/arm64) and starts the stack. To build your own images instead:

```bash
docker compose -f compose.yaml -f compose.build.yaml up -d --build
```

| Container | Role |
|-----------|------|
| `ssh-tunnel` | Encrypted tunnel to the Vast.ai llama-server |
| `litellm` | API proxy (OpenAI + Anthropic compatible) |
| `anthropic-proxy` | Translates Anthropic API format for Claude Code |
| `opencode` | OpenCode agent with shared `/workspace` |
| `claude` | Claude Code agent with shared `/workspace` |
| `searxng` | Free web search at `http://localhost:8080` |

Docker Compose handles startup order via health checks.

### 7. Verify

```bash
# Check the SSH tunnel is forwarding
docker compose exec ssh-tunnel nc -z 127.0.0.1 8080

# Check LiteLLM can reach the backend
curl -s http://localhost:4000/health

# View tunnel logs if needed
docker compose logs ssh-tunnel
```

**Optional — compare agent latency:**

```bash
./bench-agents.sh "hi"                                              # sequential
./bench-agents.sh -p "hi"                                           # parallel
./bench-agents.sh -p "build a simple terminal snake app in Python"  # tool calls
./bench-agents.sh -p "report high/low/open/close for SPY today"     # web search
```

### 8. Tear down

```bash
docker compose down   # stop local containers
./destroy.sh          # terminate Vast.ai instance and stop billing
```

---

## VRAM Budget

2× RTX Pro 6000 = **192 GB VRAM total**.

| Quant | ~Size | Fits? | Notes |
|-------|-------|-------|-------|
| [UD-Q4_K_XL](https://huggingface.co/unsloth/MiniMax-M2.5-GGUF) | ~123 GB | Yes | Default — good quality, ~50 tok/s |
| [UD-Q3_K_XL](https://huggingface.co/unsloth/MiniMax-M2.5-GGUF) | ~101 GB | Yes | Smaller, slight quality loss |
| Q8_0 | ~243 GB | No | Exceeds VRAM |

Adjust `HF_REPO`, `HF_INCLUDE`, and `HF_QUANT` in `config.env` to use a different model or quantization. Smaller models like Qwen2.5-72B-Instruct fit easily at Q4_K_M (~42 GB).

---

## Model: MiniMax M2.5

[MiniMax M2.5](https://huggingface.co/MiniMaxAI/MiniMax-M2.5) is a 230B-parameter Mixture-of-Experts model (10B active per token), trained with RL across 200K+ real-world coding environments in 10+ languages.

- Open-weight (Modified MIT license)
- Full-stack — Web, Android, iOS, Windows
- Architect-mode — decomposes and plans features before writing code
- ~50 tok/s single agent, ~20 tok/s per agent with 4 parallel agents (2× RTX Pro 6000, UD-Q4_K_XL)

### Dev toolchains in agent containers

| Tool | Claude Code | OpenCode | Notes |
|------|:-----------:|:--------:|-------|
| Node.js | 24.x LTS | 24.x LTS | npm included |
| Python | 3.13.x | 3.13.x | pip, venv, dev headers |
| Rust | stable | stable | rustup, cargo |
| C/C++ | gcc, g++ | gcc, g++ | make, cmake |
| Utilities | git, ripgrep, fd, jq, vim, tree | same | — |

Both containers share a `/workspace` volume — files created by one agent are immediately visible to the other.

---

## Files

```
install.sh            One-shot installer (curl | bash): clone, configure, provision, connect
config.env            Configuration (API key, model, server settings)
provision.sh          Create Vast.ai instance
connect.sh            Fetch SSH endpoint, write .env
destroy.sh            Destroy Vast.ai instance
compose.yaml          Local services (ssh-tunnel, LiteLLM, OpenCode, Claude, SearXNG)
ssh-tunnel/           SSH tunnel container (Dockerfile + entrypoint)
litellm/config.yaml   LiteLLM proxy configuration
config/opencode.json  OpenCode agent configuration
opencode/             OpenCode container (Dockerfile + entrypoint)
claude/               Claude Code container (Dockerfile + entrypoint)
searxng/settings.yml  SearXNG config (free web search for agents)
open-vscode.sh        Attach VS Code to agent containers
opencode.sh           Run OpenCode agent in terminal
claude.sh             Run Claude Code in terminal
claude-yolo.sh        Run Claude Code with --dangerously-skip-permissions
bench-agents.sh       Compare OpenCode vs Claude Code latency (use -p for parallel)
bench.py              Benchmark script
```
