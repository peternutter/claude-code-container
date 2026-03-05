.PHONY: build install uninstall update help

IMAGE := claude-sandbox

help:
	@echo "Usage:"
	@echo "  make install   - Build image and install claude-sandbox command"
	@echo "  make uninstall - Remove image, volumes, and claude-sandbox script"
	@echo "  make build     - Build the Docker image"
	@echo "  make update    - Rebuild with latest Claude Code CLI and tools"

build:
	docker build -t $(IMAGE) -f dockerfiles/base.Dockerfile .

install: build
	@./install.sh

update:
	@echo "Rebuilding image with latest versions..."
	docker build --no-cache -t $(IMAGE) -f dockerfiles/base.Dockerfile .
	@echo "Done."

uninstall:
	docker rmi $(IMAGE) 2>/dev/null || true
	docker volume rm claude-home claude-uv-cache claude-python-bin 2>/dev/null || true
	rm -f $(HOME)/.claude/bin/claude-sandbox $(HOME)/.claude/bin/sync-skills
	@echo "Removed: Docker image, volumes, and ~/.claude/bin scripts"
