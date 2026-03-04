FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TERM=xterm-256color
ENV LANG=en_US.UTF-8

# Install Node.js 22.x from NodeSource
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
       | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
       > /etc/apt/sources.list.d/nodesource.list

# Add GitHub CLI repository
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list

# Install all packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    nodejs \
    git \
    gh \
    openssh-client \
    build-essential \
    curl \
    wget \
    jq \
    ripgrep \
    fd-find \
    locales \
    ncurses-base \
    sudo \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/* \
    && locale-gen en_US.UTF-8 \
    && echo "ALL ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/nopasswd \
    && chmod 440 /etc/sudoers.d/nopasswd

# Install Python 3.12 from deadsnakes PPA
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
    && add-apt-repository -y ppa:deadsnakes/ppa \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    python3-pip \
    && rm -rf /var/lib/apt/lists/* \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.12 1 \
    && pip install --break-system-packages uv

# Install Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# Create non-root user with UID 1000 (delete ubuntu user first if it exists)
# Make home directory world-writable so container can run as any UID (via --user flag)
RUN userdel -r ubuntu 2>/dev/null || true \
    && useradd -m -s /bin/bash -u 1000 claude \
    && chmod 777 /home/claude \
    && chmod 666 /etc/passwd

# Install Python tools via uv
USER claude
ENV PATH="/home/claude/.local/bin:${PATH}"
RUN uv tool install ruff \
    && uv tool install mypy \
    && uv tool install pytest \
    && uv tool install ipython \
    && uv tool install wandb \
    && uv tool install 'huggingface_hub[cli]' \
    && uv tool install awscli \
    && chmod -R 777 /home/claude/.local /home/claude/.cache

# Create entrypoint script
USER root
RUN mkdir -p /opt/claude-container
COPY --chmod=755 <<'SCRIPT' /opt/claude-container/entrypoint.sh
#!/bin/bash

# Verify mount points are accessible (output to stderr to not interfere with commands)
verify_mounts() {
    local failed=false
    local ws="$(pwd)"

    # Check ~/.claude is writable
    if ! touch ~/.claude/.mount-test 2>/dev/null; then
        echo "⚠ Warning: ~/.claude is not writable" >&2
        failed=true
    else
        rm -f ~/.claude/.mount-test
    fi

    # Check workspace is writable
    if ! touch "$ws/.mount-test" 2>/dev/null; then
        echo "⚠ Warning: $ws is not writable" >&2
        failed=true
    else
        rm -f "$ws/.mount-test"
    fi

    # Check for CLAUDE.md files (informational)
    if [ -f ~/.claude/CLAUDE.md ]; then
        echo "✓ Global CLAUDE.md found" >&2
    else
        echo "○ No global ~/.claude/CLAUDE.md" >&2
    fi

    if [ -f "$ws/CLAUDE.md" ]; then
        echo "✓ Project CLAUDE.md found (root)" >&2
    elif [ -f "$ws/.claude/CLAUDE.md" ]; then
        echo "✓ Project CLAUDE.md found (.claude/)" >&2
    else
        echo "○ No project CLAUDE.md (run /init to create)" >&2
    fi

    if $failed; then
        echo "" >&2
        echo "Mount verification failed. Check your docker run command." >&2
        echo "Expected: -v claude-home:/home/claude" >&2
        echo "          -v \"\$HOME/.claude\":/home/claude/.claude" >&2
        echo "          -v \"\$PROJECT\":\$PWD (set via -w)" >&2
    fi
}

# Ensure current UID has a passwd entry (needed for git, ssh, and other tools)
if ! getent passwd "$(id -u)" >/dev/null 2>&1; then
    echo "claude:x:$(id -u):$(id -g):Claude:/home/claude:/bin/bash" >> /etc/passwd
fi

# Configure git to use GH_TOKEN for HTTPS auth when available
if [ -n "${GH_TOKEN:-}" ] || [ -n "${GITHUB_TOKEN:-}" ]; then
    gh auth setup-git 2>/dev/null || true
fi

verify_mounts

# Check for Claude Code CLI updates (background, non-blocking)
check_claude_update() {
    # Wait for Claude to start before printing anything to avoid output interleaving
    sleep 3
    local installed=$(claude --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    # Timeout after 5 seconds to avoid hanging on slow/unreachable registry
    local latest=$(timeout 5 npm show @anthropic-ai/claude-code version 2>/dev/null)
    if [ -n "$installed" ] && [ -n "$latest" ] && [ "$installed" != "$latest" ]; then
        echo "" >&2
        echo "╔════════════════════════════════════════════════════════════╗" >&2
        echo "║  Claude Code update available: $installed → $latest" >&2
        echo "║  Run 'make update' on host to rebuild image" >&2
        echo "╚════════════════════════════════════════════════════════════╝" >&2
        echo "" >&2
    fi
}
check_claude_update &

exec "$@"
SCRIPT

USER claude

ENTRYPOINT ["/opt/claude-container/entrypoint.sh"]
# Launch Claude Code with full permissions (safe since container is isolated)
CMD ["claude", "--dangerously-skip-permissions"]
