# unmetered-code

[![CI/CD](https://github.com/ymortazavi/unmetered-code/actions/workflows/ci.yml/badge.svg)](https://github.com/ymortazavi/unmetered-code/actions/workflows/ci.yml)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/ymortazavi?logo=github)](https://github.com/sponsors/ymortazavi)

**Private AI coding agents. No rate limits. ~$1.50/hr.**

Run your favorite AI coders (currently supporting [Claude Code](https://github.com/anthropics/claude-code) and [OpenCode](https://github.com/anomalyco/opencode))
with [MiniMax M2.5](https://huggingface.co/MiniMaxAI/MiniMax-M2.5) on rented GPUs —
no API keys, no per-token billing, no usage caps. Your code **never
leaves your machine**. The model runs on a
[Vast.ai](https://cloud.vast.ai/?ref_id=399895) GPU instance connected
through an encrypted SSH tunnel — no code, prompts, or outputs are sent
to any third-party API. Everything stays between your local Docker stack
and your rented GPU. Agents can use **[SearXNG](https://github.com/searxng/searxng)** for free web search (no search API key required).


> **If unmetered-code cuts your AI spend, please consider [sponsoring the project](https://github.com/sponsors/ymortazavi) to keep it updated.**

## Architecture

![Architecture diagram](assets/architecture.png)

### Why MiniMax M2.5

This repo runs [MiniMax M2.5](https://huggingface.co/MiniMaxAI/MiniMax-M2.5)
by default — a 230B-parameter Mixture-of-Experts model (10B active per
token), trained with RL across 200K+ real-world coding environments in
10+ languages (Python, Go, C++, TypeScript, Rust, Java, and more).

- **Open-weight** (Modified MIT license) — run it locally, no API keys
- **Full-stack** — trained across Web, Android, iOS, and Windows projects
- **Architect-mode** — decomposes and plans features before writing code
- **Fast** — completes SWE-Bench tasks 37% faster than its predecessor,
  matching Claude Opus 4.6 in wall-clock time

### Inference Performance

Measured on 2× RTX Pro 6000 (192 GB VRAM), [UD-Q4_K_XL](https://unsloth.ai/docs/basics/unsloth-dynamic-2.0-ggufs) quantization:

| | 1 agent | 4 agents (parallel) |
|---|:---:|:---:|
| **Generation speed** | ~50 tok/s | ~20 tok/s per agent |
| **Context window** | 160K tokens | 160K tokens each |

| Metric | Value |
|--------|-------|
| GPU cost | ~$1.50/hr (varies by availability) |
| Time to first token | ~2–5s (depends on prompt length) |
| Quantization | [UD-Q4_K_XL](https://unsloth.ai/docs/basics/unsloth-dynamic-2.0-ggufs) (~123 GB weights) |

Speed varies with prompt length, quantization, and GPU hardware. These
numbers are from informal testing, not rigorous benchmarks.

### Pre-installed Dev Toolchains

Both agent containers come with full development environments:

| Tool | Claude Code | OpenCode | Notes |
|------|:-----------:|:--------:|-------|
| Node.js | 24.x LTS | 24.x LTS | npm included |
| Python | 3.13.x | 3.13.x | pip, venv, dev headers |
| Rust | stable | stable | installed via rustup, cargo included |
| C/C++ | gcc, g++ | gcc, g++ | make, cmake included |
| Utilities | git, ripgrep, fd, jq, vim, tree | same | standard dev tools |

Both agent containers use the same Debian-based dev stack. They share a
`/workspace` volume, so files created by one agent are immediately
visible to the other.


## Prerequisites

### Required

- **Docker + Docker Compose** — needed to run the local service stack
  (LiteLLM, SSH tunnel, agents, [SearXNG](https://github.com/searxng/searxng) for free web search). Install via
  [Docker Desktop](https://docs.docker.com/get-docker/) (macOS / Windows)
  or [Docker Engine](https://docs.docker.com/engine/install/) (Linux).
  Compose v2 is included with modern Docker installs.

- **Python 3** — used by the provisioning scripts to parse JSON responses
  from the Vast.ai API. Pre-installed on macOS and most Linux distros.

- **Vast.ai account** — [sign up here](https://cloud.vast.ai/?ref_id=399895)
  and load funds. GPU rental is billed per hour; the scripts create and
  destroy instances on demand.

- **Vast.ai CLI** — install with pip, then set your API key:

  ```bash
  pip install vastai
  ```

- **SSH key pair in `~/.ssh/`** — the SSH tunnel container bind-mounts
  your `~/.ssh` directory (read-only) and copies any `id_*` key files
  into the container. It uses these to authenticate with the Vast.ai
  instance. If you don't have a key pair yet:

  ```bash
  ssh-keygen -t ed25519 -C "your_email@example.com"
  ```

  Press Enter to accept the default path (`~/.ssh/id_ed25519`). A
  passphrase is optional.

  Then register the public key with Vast.ai:

  ```bash
  vastai set ssh-key "$(cat ~/.ssh/id_ed25519.pub)"
  ```

  Verify it was registered:

  ```bash
  vastai show ssh-keys
  ```

### Optional

- **HuggingFace account + token** — only needed if you want to download
  gated or private models (e.g. Llama, Mistral). The default model
  (`unsloth/MiniMax-M2.5-GGUF`) is public and downloads without
  authentication. Having a HuggingFace token can also give you **faster
  downloads** from the HuggingFace CDN compared to anonymous access.
  See [Step 2](#2-configure-configenv) for how to set it up.

- **VS Code** — needed only if you want to use `./open-vscode.sh` to
  attach VS Code directly to the agent containers. The
  [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
  extension is required.

## Quick Start

### 1. Get your Vast.ai API key

[Sign up on Vast.ai](https://cloud.vast.ai/?ref_id=399895), add credits,
then go to [Account](https://cloud.vast.ai/account/) to generate an API
key and copy it. You'll paste it into `config.env` in the next step.

### 2. Configure `config.env`

Open `config.env` and set your Vast.ai API key:

```bash
VAST_API_KEY="your_vast_api_key_here"
```

**HuggingFace token (optional):** If your model is gated/private, or you
want faster downloads, uncomment the `HF_TOKEN` line and set it:

1. Create a token at [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens) (read access is sufficient)
2. Accept the model's license agreement on its HuggingFace page
3. Uncomment and set the token in `config.env`:

```bash
HF_TOKEN="hf_your_token_here"
```

If the line is commented out or set to `"none"`, HuggingFace authentication
is skipped entirely — the default public model works fine without it.

### 3. Find a GPU offer

Search for available machines on Vast.ai:

```bash
vastai search offers 'gpu_name in [RTX_PRO_6000_S,RTX_PRO_6000_WS] num_gpus==2 reliability>0.9' -o dph
```

This returns a table of offers (sorted by price, cheapest first). The **ID** is
in the first column; **dph** is $/hour. Omit `-o dph` to use the default sort.

> **Tip:** For the default MiniMax-M2.5 model at [UD-Q4_K_XL](https://unsloth.ai/docs/basics/unsloth-dynamic-2.0-ggufs) quantization,
> you need at least **192 GB VRAM** (e.g. 2x RTX Pro 6000). See the
> [VRAM Budget](#vram-budget) section for details on what fits.

### 4. Provision the remote instance

```bash
./provision.sh <OFFER_ID>
```

This creates a Vast.ai instance that downloads the model and starts
`llama-server`. The llama port is **not** exposed publicly — it is only
reachable through the SSH tunnel.

The script waits for the instance to enter `running` state, then prints
next steps. Model download takes 5–10 minutes depending on size and
network speed.

### 5. Connect the SSH tunnel

```bash
./connect.sh
```

This fetches the instance's public IP and SSH port, tests the SSH
connection, and writes a `.env` file with the tunnel parameters for Docker
Compose.

If SSH isn't ready yet (the instance is still booting), re-run after a
minute or two.

### 6. Start local services

```bash
docker compose up -d
```

This pulls the prebuilt images from GHCR (linux/amd64) and starts the stack.
On **Apple Silicon (arm64)** there are no prebuilt images; build from source:

```bash
docker compose -f compose.yaml -f compose.build.yaml up -d --build
```

> **Note:** The first run can take several minutes (often 2–5+ min) while the four custom images are built. Later runs reuse the images.

On x86_64 you can also build from source with the same command.

| Container | Role |
|-----------|------|
| `ssh-tunnel` | Encrypted tunnel to the Vast.ai llama-server |
| `litellm` | API proxy (OpenAI + Anthropic compatible) |
| `anthropic-proxy` | Translates Anthropic API format for Claude Code |
| `opencode` | OpenCode agent with shared `/workspace` |
| `claude` | Claude Code agent with shared `/workspace` |
| `searxng` | Free web search for agents ([SearXNG](https://github.com/searxng/searxng)) at `http://localhost:8080` |

Docker Compose handles startup order automatically — each service waits for
its dependencies to be healthy before starting. Both agents have [SearXNG](https://github.com/searxng/searxng) MCP preconfigured for web search at no extra cost.

### 7. Verify everything is working

```bash
# Check the SSH tunnel is forwarding
docker compose exec ssh-tunnel nc -z 127.0.0.1 8080

# Check LiteLLM can reach the backend
curl -s http://localhost:4000/health

# View tunnel logs if needed
docker compose logs ssh-tunnel
```

**Optional — compare agent latency:** Run a prompt through both agents and see timing (helps confirm the stack is responsive). Use `-p` to run both in parallel:

```bash
# sequential
./bench-agents.sh "hi"
# parallel (faster wall-clock)
./bench-agents.sh -p "hi"
# test tool calls
./bench-agents.sh -p "build a simple terminal snake app in Python with a unique name" 
# test web search (MCP)
./bench-agents.sh -p "report high/low/open/close for S&P 500 ETF SPY in the last trading session"
```

### 8. Use the agents

**Option A — VS Code (recommended):**

```bash
./open-vscode.sh --opencode   # OpenCode only
./open-vscode.sh --claude     # Claude Code only
./open-vscode.sh --both       # Both (default)
```

This attaches VS Code to the running container. Use the integrated terminal
to launch the agent.

**Option B — Direct terminal:**

Three scripts run the agents in your terminal (each ensures the stack is up and `workspace` exists, then attaches to the container with `/workspace` as the working directory):

| Script | What it does |
|--------|----------------|
| **`./opencode.sh`** | Starts the OpenCode agent. Interactive TUI; use for general coding tasks. |
| **`./claude.sh`** | Starts Claude Code with MiniMax M2.5. Asks for permission when using tools (e.g. run commands, edit files). |
| **`./claude-yolo.sh`** | Same as `claude.sh` but skips all permission prompts (`--dangerously-skip-permissions`). Faster for trusted use. |

```bash
./opencode.sh
./claude.sh
./claude-yolo.sh
```

You can pass extra arguments (e.g. `./claude.sh --verbose`); they are forwarded to the agent. Run from the repo root so `docker compose` finds the project.

> Claude Code expects a model name registered in `litellm/config.yaml`.
> The default config maps `claude-sonnet-4-6` to the llama-server
> backend. Add more aliases there if Claude updates its default model name.

### 9. Tear down

When you're done, stop the local containers and destroy the Vast.ai
instance to stop billing:

```bash
docker compose down      # stop local containers
./destroy.sh             # terminate the Vast.ai instance and clean up
```

## VRAM Budget

2× RTX Pro 6000 = **192 GB VRAM total** (96 GB each).

| Quant | ~Size | Fits? | Notes |
|-------|-------|-------|-------|
| [UD-Q4_K_XL](https://unsloth.ai/docs/basics/unsloth-dynamic-2.0-ggufs) | ~123 GB | Yes | Default — good quality, ~50 tok/s |
| UD-Q3_K_XL | ~101 GB | Yes | Smaller, slight quality loss |
| Q8_0 | ~243 GB | No | Exceeds VRAM |

For MiniMax M2.5 (230B MoE), the default [UD-Q4_K_XL](https://unsloth.ai/docs/basics/unsloth-dynamic-2.0-ggufs) quant fits
comfortably in 192 GB with room for KV cache. Adjust `HF_REPO`,
`HF_INCLUDE`, and `HF_QUANT` in `config.env` to use a different model
or quantization.

Smaller models like Qwen2.5-72B-Instruct fit easily at Q4_K_M (~42 GB).

## Files

```
config.env            Configuration (API key, model, server settings)
provision.sh          Create Vast.ai instance
connect.sh            Fetch SSH endpoint, write .env
destroy.sh            Destroy Vast.ai instance
compose.yaml          Local services (ssh-tunnel, LiteLLM, OpenCode, Claude, [SearXNG](https://github.com/searxng/searxng))
ssh-tunnel/           SSH tunnel container (Dockerfile + entrypoint)
litellm/config.yaml   LiteLLM proxy configuration
config/opencode.json  OpenCode agent configuration
opencode/             OpenCode container (Dockerfile + entrypoint)
claude/               Claude Code container (Dockerfile + entrypoint)
searxng/settings.yml  [SearXNG](https://github.com/searxng/searxng) config (free web search for agents)
open-vscode.sh        Attach VS Code to agent containers
opencode.sh           Run OpenCode agent in terminal
claude.sh             Run Claude Code in terminal
claude-yolo.sh        Run Claude Code with --dangerously-skip-permissions
bench-agents.sh       Compare OpenCode vs Claude Code latency (use -p for parallel)
bench.py              Benchmark script
```

## Troubleshooting

**No matching manifest for linux/arm64 (Apple Silicon):**  
Prebuilt GHCR images are amd64 only. Build from source (first run may take several minutes):
```bash
docker compose -f compose.yaml -f compose.build.yaml up -d --build
```

**SSH tunnel not connecting:**
```bash
# Check tunnel container logs
docker compose logs ssh-tunnel

# Verify SSH access manually
ssh -p <SSH_PORT> root@<PUBLIC_IP>

# Check if your SSH key is registered with Vast.ai
vastai show ssh-keys
```

**Server not responding after provision:**
The model is likely still downloading. Check with:
```bash
vastai logs <INSTANCE_ID>
```

**Out of VRAM:**
The model is too large for the GPU(s). Edit `config.env` to use a smaller
quantization or a different model.

**SSH into instance:**
```bash
vastai ssh-url <INSTANCE_ID>
```

## Cost Comparison

Per-token API pricing (as of Feb 2026):

| | Input ($/M tokens) | Output ($/M tokens) | Rate limits |
|---|:---:|:---:|:---:|
| **Claude Sonnet 4.6** | $3.00 | $15.00 | Yes |
| **GPT-4o** | $2.50 | $10.00 | Yes |
| **[MiniMax M2.5 API](https://platform.minimax.io/)** | $0.30 | $1.10 | Yes |
| **unmetered-code** | included\* | ~$5.48\* | **None** |

\*Effective cost at ~$1.50/hr GPU rental sustaining ~76 tok/s aggregate
output (4 agents × ~20 tok/s). $1.50 / 0.274M tokens = ~$5.48/M. Input
processing is included — prompt eval runs at hundreds of tok/s and
doesn't reduce output throughput. Actual cost per token depends on GPU
utilization; idle time raises the effective rate.

Prices from [Anthropic](https://docs.anthropic.com/en/docs/about-claude/pricing),
[OpenAI](https://platform.openai.com/docs/pricing), and
[MiniMax](https://platform.minimax.io/docs/pricing/pay-as-you-go).

With unmetered-code you pay a flat GPU rental regardless of how many
tokens you use. Whether that's cheaper than the MiniMax API depends on
how heavily you use it — the break-even point is roughly 1–2M output
tokens per hour. The main advantages over any API are zero rate limits,
4 parallel agents, and full privacy (your code never leaves your network or the vast.ai host).
