# unmetered-code

**Private AI coding agents. No rate limits. ~$1.50/hr.**

Run your favorite AI coders (currently supporting Claude Code and OpenCode)
with [MiniMax M2.5](https://huggingface.co/MiniMaxAI/MiniMax-M2.5) on rented GPUs —
no API keys, no per-token billing, no usage caps. Your code **never
leaves your machine**. The model runs on a
[Vast.ai](https://cloud.vast.ai/?ref_id=399895) GPU instance connected
through an encrypted SSH tunnel — no code, prompts, or outputs are sent
to any third-party API. Everything stays between your local Docker stack
and your rented GPU.

## Architecture

<!-- ![Architecture diagram](assets/architecture.png) -->
<img src="assets/architecture.png" width="50%" alt="Architecture" />


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

**Coding benchmarks** — M2.5 matches frontier closed models on code:

| Benchmark | [M2.5](https://huggingface.co/MiniMaxAI/MiniMax-M2.5) | Sonnet 4.6 | Opus 4.6 |
|-----------|:---:|:---:|:---:|
| SWE-Bench Verified | **80.2%** | 79.6% | **80.8%** |
| Multi-SWE-Bench | **51.3%** | — | — |
| Terminal-Bench 2 | 46.3% | 59.1% | **65.4%** |
| BrowseComp | 76.3% | — | **84.0%** |

**General reasoning** — competitive but trails Opus and GPT-5:

| Benchmark | [M2.5](https://huggingface.co/MiniMaxAI/MiniMax-M2.5) | Sonnet 4.5 | Opus 4.6 | GPT-5.2 |
|-----------|:---:|:---:|:---:|:---:|
| AIME 2025 | 86.3 | 88.0 | **95.6** | **98.0** |
| GPQA Diamond | 85.2 | 83.0 | **90.0** | **90.0** |
| SciCode | 44.4 | 45.0 | 52.0 | 52.0 |

Scores are self-reported by each vendor using their own agent scaffolds
(M2.5 coding benchmarks used Claude Code as the scaffold). See the
[model card](https://huggingface.co/MiniMaxAI/MiniMax-M2.5) for full
results and methodology.

**Bottom line:** M2.5 is at the Sonnet/Opus level on SWE-Bench — where
it matters most for a coding agent — while being fully open-weight and
self-hostable.

### Inference Performance

Measured on 2× RTX Pro 6000 (192 GB VRAM), UD-Q4_K_XL quantization:

| | 1 agent | 4 agents (parallel) |
|---|:---:|:---:|
| **Generation speed** | ~50 tok/s | ~20 tok/s per agent |
| **Context window** | 640K tokens | 160K tokens each |

| Metric | Value |
|--------|-------|
| GPU cost | ~$1.50/hr (varies by availability) |
| Time to first token | ~2–5s (depends on prompt length) |
| Quantization | UD-Q4_K_XL (~123 GB weights) |

Speed varies with prompt length, quantization, and GPU hardware. These
numbers are from informal testing, not rigorous benchmarks.

### Pre-installed Dev Toolchains

Both agent containers come with full development environments:

| Tool | Claude Code | OpenCode | Notes |
|------|:-----------:|:--------:|-------|
| Node.js | 24.x LTS | 22.x | npm included |
| Python | 3.13.x | 3.12.x | pip, venv, dev headers |
| Rust | stable | stable | installed via rustup, cargo included |
| C/C++ | gcc, g++ | gcc, g++ | make, cmake included |
| Utilities | git, ripgrep, fd, jq, vim, tree | same | standard dev tools |

OpenCode versions depend on its upstream Alpine base image. Both
containers share a `/workspace` volume, so files created by one agent
are immediately visible to the other.


## Prerequisites

### Required

- **Docker + Docker Compose** — needed to run the local service stack
  (LiteLLM, SSH tunnel, agents, SearXNG). Install via
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
vastai search offers 'gpu_name=RTX_Pro_6000 num_gpus>=2 reliability>0.9 inet_down>200'
```

This returns a table of offers. Note the **ID** in the first column of the
offer you want.

> **Tip:** For the default MiniMax-M2.5 model at `UD-Q4_K_XL` quantization,
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
next steps. Model download takes 10–30 minutes depending on size and
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
docker compose up -d --build
```

This starts five containers:

| Container | Role |
|-----------|------|
| `ssh-tunnel` | Encrypted tunnel to the Vast.ai llama-server |
| `litellm` | API proxy (OpenAI + Anthropic compatible) |
| `anthropic-proxy` | Translates Anthropic API format for Claude Code |
| `opencode` | OpenCode agent with shared `/workspace` |
| `claude` | Claude Code agent with shared `/workspace` |
| `searxng` | Local search engine on `http://localhost:8080` |

Docker Compose handles startup order automatically — each service waits for
its dependencies to be healthy before starting.

### 7. Verify everything is working

```bash
# Check the SSH tunnel is forwarding
docker exec ssh-tunnel-unmetered-code nc -z 127.0.0.1 8080

# Check LiteLLM can reach the backend
curl -s http://localhost:4000/health

# View tunnel logs if needed
docker logs ssh-tunnel-unmetered-code
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

```bash
docker exec -it opencode-unmetered-code opencode
docker exec -it claude-code-unmetered-code claude --model minimax-m2.5
```

**Option C — Claude Code YOLO mode** (skips all permission prompts):

```bash
./claude-yolo.sh
```

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
| UD-Q4_K_XL | ~123 GB | Yes | Default — good quality, ~50 tok/s |
| UD-Q3_K_XL | ~101 GB | Yes | Smaller, slight quality loss |
| Q8_0 | ~243 GB | No | Exceeds VRAM |

For MiniMax M2.5 (230B MoE), the default `UD-Q4_K_XL` quant fits
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
compose.yaml          Local services (ssh-tunnel, LiteLLM, OpenCode, Claude, SearXNG)
ssh-tunnel/           SSH tunnel container (Dockerfile + entrypoint)
litellm/config.yaml   LiteLLM proxy configuration
config/opencode.json  OpenCode agent configuration
opencode/             OpenCode container (Dockerfile + entrypoint)
claude/               Claude Code container (Dockerfile + entrypoint)
searxng/settings.yml  SearXNG search engine configuration
open-vscode.sh        Attach VS Code to agent containers
claude-yolo.sh        Run Claude Code with --dangerously-skip-permissions
bench.py              Benchmark script
```

## Troubleshooting

**SSH tunnel not connecting:**
```bash
# Check tunnel container logs
docker logs ssh-tunnel-unmetered-code

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
