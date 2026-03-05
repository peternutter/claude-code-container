# Claude Code Container

A little tool I built for myself to run Claude Code **unhinged** with relative safety.

The goal: let Claude run long-running processes -- building, testing, debugging, iterating -- with zero intervention. Walk away, come back, and your code is done (or at least thoroughly attempted).

Claude runs with `--dangerously-skip-permissions` (no confirmation prompts), but inside a Docker container that isolates it from your host system. The container can only access the project directory you mount -- so Claude can go wild without nuking your machine.

> **DO NOT DEPLOY THIS TO PRODUCTION. DO NOT RUN THIS IN THE CLOUD.**
>
> This tool is designed for **local development machines only**. It runs an AI agent with full autonomous permissions inside a container. The isolation is "good enough" for a dev laptop where the blast radius is limited to one project. It is absolutely not hardened for any environment where security matters.
>
> Seriously: local dev only. Your laptop. Not a server. Not AWS. Not your company's Kubernetes cluster.

> **Platform**: Only tested on macOS. Should work on Linux but is untested. Windows/WSL is not supported.

## Why Use This?

- **Hands-off**: Let Claude build, test, fix, and iterate without you clicking "approve" every 10 seconds
- **Unhinged**: Claude runs with `--dangerously-skip-permissions`, auto-approving all actions
- **Isolated**: Container has no access to your host filesystem except the mounted project
- **Safe-ish**: The combination means Claude can work freely without destroying your system

## What's Installed

- Ubuntu 24.04
- Node.js 22.x (LTS)
- Python 3.12, uv, ruff, mypy, pytest, ipython
- Claude Code CLI
- GitHub CLI (`gh`), AWS CLI
- git, curl, build-essential, jq, ripgrep, fd-find
- wandb, huggingface-cli

## Prerequisites

1. **Docker Desktop** - Install and start Docker Desktop
2. **Claude Code CLI** - Run once outside the container to create `~/.claude`:
   ```bash
   npx @anthropic-ai/claude-code
   ```

## Installation

```bash
git clone https://github.com/todd-working/claude-code-container.git
cd claude-code-container
make install
source ~/.zshrc  # or open a new terminal
```

This will:
1. Build the Docker image
2. Install `claude-sandbox` script to `~/.claude/bin/`
3. Add `~/.claude/bin` to your PATH

Your `~/.claude` directory is mounted directly into the container, so authentication and settings sync bidirectionally between host and container.

## Usage

```bash
# Current directory
claude-sandbox

# Specific project
claude-sandbox ~/projects/my-app

# Resume a previous conversation
claude-sandbox . --resume

# Resume a specific session with model override
claude-sandbox . --resume abc123 --model opus

# Override the container workspace path (for session cross-linking)
claude-sandbox --as /home/claude/workspaces/old-name .
```

All unrecognized flags are forwarded to the `claude` CLI inside the container. Use `--` for explicit separation: `claude-sandbox . -- --verbose`.

The `--as <path>` flag overrides the container workspace path. This is useful when you need to resume sessions that were created under a different path (e.g., after renaming a project directory).

## Git & GitHub Authentication

Git authentication uses **HTTPS with a GitHub token** (SSH is not supported inside the container due to UID mapping constraints).

1. Create a [personal access token](https://github.com/settings/tokens) with `repo` scope
2. Add it to a `.env` file:

```
GH_TOKEN=ghp_your_token_here
```

Place the `.env` in your project root or in `~/.claude/.env` (global). Both files are loaded if present — global first, then project-specific. Project values override global ones for the same key, while global-only keys (like `GH_TOKEN`) are always available. The token is automatically configured for both `gh` and `git push/pull` via HTTPS.

Add `.env` to your `.gitignore` to avoid committing secrets.

## AWS Authentication

AWS credentials can be provided in two ways:

1. **Config files**: If `~/.aws` exists on the host, it's mounted read-only into the container
2. **Environment variables**: Add `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, etc. to your `.env` file

## Skills & Commands

Claude Code custom [skills](https://code.claude.com/docs/en/skills) and [slash commands](https://code.claude.com/docs/en/slash-commands) in `~/.claude/skills/` and `~/.claude/commands/` are available inside the sandbox via the `~/.claude` bind mount.

**Important:** These directories must contain real files, not symlinks pointing outside `~/.claude`. Symlinks to host paths (e.g., `~/Developer/dotfiles/...`) break inside the container because those paths don't exist there.

If you manage skills in a dotfiles repo, use the included `sync-skills` script to hard-link files between your dotfiles and `~/.claude/skills/`:

```bash
# Initial setup (and after git pull, or creating new skills)
sync-skills ~/path/to/dotfiles/claude/skills
```

Hard links keep both locations in sync — edits in either place are reflected instantly. Run `sync-skills` again after `git pull` (which may break links) or after creating new skills inside the sandbox.

## Updating

```bash
make update    # Rebuild with latest Claude Code CLI and tools
```

## Persistent Storage

### Home Directory Volume

A `claude-home` volume is mounted at `/home/claude` to persist Claude Code's onboarding state (theme, login) across container runs. Without this, you'd have to complete setup every time.

Your host's `~/.claude` directory is bind-mounted on top at `/home/claude/.claude`, so credentials and settings sync from your machine.

### Cache Volumes

| Volume | Purpose |
|--------|---------|
| `claude-home` | Home directory, onboarding state |
| `claude-uv-cache` | Python package cache |
| `claude-python-bin` | Installed Python tools |

Tools installed via `uv tool install` persist across sessions.

## Uninstall

```bash
make uninstall
```

This removes the Docker image, volumes, and the `~/.claude/bin/claude-sandbox` script.

To also remove the PATH entry, edit your `~/.zshrc` and remove the line:
```bash
export PATH="$HOME/.claude/bin:$PATH"
```

## Security Notes

- **Container isolation**: Only the mounted project directory and `~/.claude` are accessible to Claude Code
- **Bidirectional auth sync**: Credentials from `~/.claude` are shared between host and container
- **Ephemeral containers**: The `--rm` flag ensures containers are destroyed on exit
- **`--dangerously-skip-permissions`**: Safe here because the container provides the isolation boundary
- **UID matching**: Container runs as your host UID, so file permissions work correctly

## Sandbox System Prompt

Every session automatically injects environment-specific instructions into Claude's system prompt via `--append-system-prompt`. This tells Claude about available tools, git auth, package management, filesystem constraints, and safety rules (e.g., don't modify `~/.claude`, don't deploy to production).

To customize what Claude knows about the sandbox, edit the `sandbox_prompt` heredoc in `bin/claude-sandbox` (around line 362) and run `make install` to apply.

You can also create a `CLAUDE.md` in your project root (or `.claude/CLAUDE.md`) for project-specific instructions. Run `/init` inside Claude to generate one interactively.
