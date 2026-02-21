# unmetered-code

[![CI/CD](https://github.com/ymortazavi/unmetered-code/actions/workflows/ci.yml/badge.svg)](https://github.com/ymortazavi/unmetered-code/actions/workflows/ci.yml)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/ymortazavi?logo=github)](https://github.com/sponsors/ymortazavi)

**Private AI coding agents. No rate limits. ~$1.50/hr.**

Run [Claude Code](https://github.com/anthropics/claude-code) and [OpenCode](https://github.com/anomalyco/opencode) backed by [MiniMax M2.5](https://huggingface.co/MiniMaxAI/MiniMax-M2.5) on rented GPUs — no API keys, no per-token billing, no usage caps.

> Requires a [Vast.ai](https://cloud.vast.ai/?ref_id=399895) account with credits loaded.

![Architecture diagram](assets/architecture.png)

- **Private** — model runs on your rented GPU, connected via encrypted SSH tunnel; no code or prompts sent to third-party APIs
- **Unmetered** — flat GPU cost (~$1.50/hr), ~50 tok/s single agent, ~20 tok/s per agent with 4 running in parallel; no rate limits
- **Web search** — [SearXNG](https://github.com/searxng/searxng) MCP pre-configured for both agents; no search API key required
- **Full dev stack** — Node.js 24, Python 3.13, Rust, C/C++, and standard tooling in every agent container

> If unmetered-code cuts your AI spend, please consider [sponsoring the project](https://github.com/sponsors/ymortazavi).

## Get started

```bash
curl -sSL https://raw.githubusercontent.com/ymortazavi/unmetered-code/main/install.sh | bash
```

Prompts for your Vast.ai API key, finds a GPU, provisions the instance, starts the tunnel, and launches Docker. Prints a destroy command at the end so you can stop billing when done.

For manual setup, prerequisites, and configuration options, see the **[Setup Guide](docs/setup.md)**.

## Usage

Once the stack is up, run an agent:

| Script | Description |
|--------|-------------|
| `./opencode.sh` | OpenCode — interactive TUI |
| `./claude.sh` | Claude Code — prompts for tool permissions |
| `./claude-yolo.sh` | Claude Code — skips all permission prompts |

Or attach VS Code directly to a container:

```bash
./open-vscode.sh --opencode   # OpenCode
./open-vscode.sh --claude     # Claude Code
./open-vscode.sh --both       # Both (default)
```

## Cost

GPU rental (~$1.50/hr, 2× RTX Pro 6000 on [Vast.ai](https://cloud.vast.ai/?ref_id=399895)) vs per-token APIs:

| | Input ($/M) | Output ($/M) | Rate limits |
|---|:---:|:---:|:---:|
| Claude Opus 4.6 | $5.00 | $25.00 | Yes |
| Claude Sonnet 4.6 | $3.00 | $15.00 | Yes |
| GPT-5.2 | $1.75 | $14.00 | Yes |
| MiniMax M2.5 API | $0.30 | $1.20 | Yes |
| MiniMax M2.5 highspeed | $0.60 | $2.40 | Yes |
| **unmetered-code** | included | ~$5.21* | **None** |

\* ~$1.50/hr ÷ 0.288M tok/hr (4 agents × 20 tok/s). Idle time raises effective cost.

## Teardown

```bash
docker compose down   # stop local containers
./destroy.sh          # terminate Vast.ai instance and stop billing
```

---

[Setup Guide](docs/setup.md) · [Troubleshooting](docs/troubleshooting.md) · [Sponsor](https://github.com/sponsors/ymortazavi)
