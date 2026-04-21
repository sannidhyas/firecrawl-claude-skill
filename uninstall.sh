#!/usr/bin/env bash
# uninstall.sh — stop and remove the self-hosted Firecrawl stack
set -euo pipefail

FIRECRAWL_INSTALL_DIR="${FIRECRAWL_INSTALL_DIR:-$HOME/.firecrawl-claude-skill/firecrawl}"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-firecrawl}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[uninstall]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }

if [[ ! -d "$FIRECRAWL_INSTALL_DIR" ]]; then
  warn "Install dir not found: $FIRECRAWL_INSTALL_DIR — nothing to uninstall."
  exit 0
fi

# ── Step 1: docker compose down -v ────────────────────────────────────────────
info "Stopping containers and removing volumes (project: $COMPOSE_PROJECT_NAME)..."
(cd "$FIRECRAWL_INSTALL_DIR" && \
  COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" \
  docker compose --project-name "$COMPOSE_PROJECT_NAME" down -v --remove-orphans) || \
  warn "docker compose down failed — containers may already be stopped."

# ── Step 2: prompt to remove clone dir (default No) ──────────────────────────
echo ""
read -r -p "Remove clone directory $FIRECRAWL_INSTALL_DIR? [y/N] " _remove_clone
_remove_clone="${_remove_clone:-N}"
if [[ "$_remove_clone" =~ ^[Yy]$ ]]; then
  info "Removing $FIRECRAWL_INSTALL_DIR ..."
  # Ollama and searxng bind-mount dirs contain root-owned files written by
  # containers. Use a temporary alpine container to remove them cleanly.
  if [[ -d "$FIRECRAWL_INSTALL_DIR/self-host-extras" ]]; then
    docker run --rm -v "$FIRECRAWL_INSTALL_DIR/self-host-extras:/target" \
      alpine sh -c "rm -rf /target" 2>/dev/null || true
  fi
  rm -rf "$FIRECRAWL_INSTALL_DIR"
  info "Clone directory removed."
else
  info "Keeping clone directory at $FIRECRAWL_INSTALL_DIR."
fi

# ── Step 3: prompt to remove ollama-data volume (default No) ─────────────────
echo ""
_ollama_vol="${COMPOSE_PROJECT_NAME}_ollama-data"
if docker volume ls -q 2>/dev/null | grep -q "^${_ollama_vol}$"; then
  read -r -p "Remove ollama model cache volume '${_ollama_vol}'? [y/N] " _remove_ollama
  _remove_ollama="${_remove_ollama:-N}"
  if [[ "$_remove_ollama" =~ ^[Yy]$ ]]; then
    docker volume rm "$_ollama_vol" && info "Volume ${_ollama_vol} removed." || \
      warn "Could not remove volume ${_ollama_vol} — may still be in use."
  else
    info "Keeping ollama model cache volume '${_ollama_vol}' (saves re-downloading models)."
  fi
fi

echo ""
info "Uninstall complete."
