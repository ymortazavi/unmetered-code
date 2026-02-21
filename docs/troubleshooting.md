# Troubleshooting

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
The model is likely still downloading. Check progress with:

```bash
vastai logs <INSTANCE_ID>
```

**Out of VRAM:**
The model is too large for the GPU(s). Edit `config.env` to use a smaller quantization or a different model. See [VRAM Budget](setup.md#vram-budget).

**Build your own images:**
To build locally instead of pulling from GHCR (e.g. after changing Dockerfiles):

```bash
docker compose -f compose.yaml -f compose.build.yaml up -d --build
```

**Claude Code: `InputValidationError` (Write failed — `file_path` / `content` missing):**
This is a [known issue](https://github.com/anthropics/claude-code/issues/895) when using third-party APIs (LiteLLM + MiniMax) instead of the official Anthropic API. The model sometimes returns tool calls with parameter names Claude Code does not accept. Workarounds:

1. Retry the request — often the next attempt succeeds.
2. Ask the model to use Bash instead: "use a single bash command to write the file content".
3. Use the OpenCode agent (`umcode opencode` or `./opencode.sh`) for file-heavy tasks; it uses a different tool stack and is less affected.

> Note on [Claude Code Router (CCR)](https://github.com/musistudio/claude-code-router): CCR does not normalize Write tool parameter names (`path`→`file_path`, `contents`→`content`). Its `enhancetool`/`toolArgumentsParser` only repairs malformed JSON, not renames parameters. Using CCR in front of another provider does not fix this error; the same workarounds apply.

**VS Code: "Cannot attach to the container … it no longer exists":**
The container was recreated (e.g. after `docker compose down`/`up` or a rebuild). Click **Close Remote**, then run `umcode vscode --opencode` or `umcode vscode --claude` (or `./open-vscode.sh --opencode` / `--claude`) again to attach to the current container.

**SSH into the Vast.ai instance directly:**

```bash
vastai ssh-url <INSTANCE_ID>
```
