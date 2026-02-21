# umcode

[![CI/CD](https://github.com/ymortazavi/umcode/actions/workflows/ci.yml/badge.svg)](https://github.com/ymortazavi/umcode/actions/workflows/ci.yml)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/ymortazavi?logo=github)](https://github.com/sponsors/ymortazavi)

**Unmetered Private AI coding agents. No rate limits. ~$1.50/hr.**

Run [Claude Code](https://github.com/anthropics/claude-code) and [OpenCode](https://github.com/anomalyco/opencode) backed by [MiniMax M2.5](https://huggingface.co/MiniMaxAI/MiniMax-M2.5) on rented GPUs — no API keys, no per-token billing, no usage caps.

> Requires a [Vast.ai](https://cloud.vast.ai/?ref_id=399895) account with credits loaded.

![Architecture diagram](assets/architecture.png)

- **Private** — model runs on your rented GPU, connected via encrypted SSH tunnel; no code or prompts sent to third-party APIs
- **Unmetered** — flat GPU cost (~$1.50/hr), ~50 tok/s single agent, ~20 tok/s per agent with 4 running in parallel; no rate limits
- **Web search** — [SearXNG](https://github.com/searxng/searxng) MCP pre-configured for both agents; no search API key required
- **Full dev stack** — Node.js 24, Python 3.13, Rust, C/C++, and standard tooling in every agent container

> If umcode cuts your AI spend, please consider [sponsoring the project](https://github.com/sponsors/ymortazavi).

## Get started

**First-time (clone and configure):**

```bash
curl -sSL https://raw.githubusercontent.com/ymortazavi/umcode/main/install.sh | bash
```

**Life cycle:** After the repo is on your machine (and `config.env` has your [Vast.ai](https://cloud.vast.ai/?ref_id=399895) API key), use two commands:

- **`umcode start`** — Rent a GPU, provision the instance, connect the SSH tunnel, and start the local stack. Does everything needed to get agents running.
- **`umcode destroy`** — Destroy the Vast.ai instance and stop billing. Run when you’re done.

For manual setup, prerequisites, and configuration options, see the **[Setup Guide](docs/setup.md)**.

**Run `umcode` from anywhere:** Add the CLI to your PATH so you can run `umcode start`, `umcode destroy`, etc. from any directory:

```bash
mkdir -p ~/.local/bin
ln -sf "$(pwd)/umcode" ~/.local/bin/umcode
```

Then ensure `~/.local/bin` is in your PATH. For bash, add to `~/.bashrc`; for zsh, add to `~/.zshrc`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Reload your shell (`exec $SHELL`) or open a new terminal. Verify with `umcode --help`.

## Usage

Once the stack is up, run an agent (workspace is in the install directory under `workspace/`). All commands are available via the **`umcode`** CLI ([full list](docs/setup.md#files)). You can run `umcode` from any directory.

```bash
umcode opencode        # OpenCode — interactive TUI
umcode claude          # Claude Code — prompts for tool permissions
umcode claude --yolo   # Claude Code — skips all permission prompts
```

Or attach [VS Code](https://github.com/microsoft/vscode) directly to a container:

```bash
umcode vscode --opencode   # OpenCode
umcode vscode --claude     # Claude Code
umcode vscode --both       # Both (default)
```

You can also run the scripts directly from the install directory: `opencode.sh`, `claude.sh`, `open-vscode.sh`, etc.

Install the official extensions for a richer experience: [OpenCode](https://marketplace.visualstudio.com/items?itemName=sst-dev.opencode) · [Claude Code](https://marketplace.visualstudio.com/items?itemName=Anthropic.claude-code)

## Cost

GPU rental (~$1.50/hr, 2× RTX Pro 6000 on [Vast.ai](https://cloud.vast.ai/?ref_id=399895)) vs per-token APIs:

| | Input ($/M) | Output ($/M) | Rate limits |
|---|:---:|:---:|:---:|
| Claude Opus 4.6 | $5.00 | $25.00 | Yes |
| Claude Sonnet 4.6 | $3.00 | $15.00 | Yes |
| GPT-5.2 | $1.75 | $14.00 | Yes |
| MiniMax M2.5 API | $0.30 | $1.20 | Yes |
| MiniMax M2.5 highspeed | $0.60 | $2.40 | Yes |
| **umcode** | included | ~$5.21* | **None** |

\* ~$1.50/hr ÷ 0.288M tok/hr (4 agents × 20 tok/s). Idle time raises effective cost.

## Teardown

```bash
docker compose down   # stop local containers
umcode destroy        # terminate Vast.ai instance and stop billing
# or: destroy.sh (from install directory)
```

---

[Setup Guide](docs/setup.md) · [Troubleshooting](docs/troubleshooting.md) · [Sponsor](https://github.com/sponsors/ymortazavi)
