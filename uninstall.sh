#!/usr/bin/env bash
# uninstall.sh — stop and remove the self-hosted Firecrawl stack
set -euo pipefail

FIRECRAWL_INSTALL_DIR="${FIRECRAWL_INSTALL_DIR:-$HOME/.firecrawl-claude-skill/firecrawl}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[uninstall]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }

if [[ ! -d "$FIRECRAWL_INSTALL_DIR" ]]; then
  warn "Install dir not found: $FIRECRAWL_INSTALL_DIR — nothing to uninstall."
  exit 0
fi

info "Stopping and removing containers..."
(cd "$FIRECRAWL_INSTALL_DIR" && docker compose down --remove-orphans) || \
  warn "docker compose down failed — containers may already be stopped."

echo ""
echo "Containers removed. Data volumes (ollama models, redis, postgres) are preserved."
echo ""
echo "To also remove volumes:"
echo "  cd $FIRECRAWL_INSTALL_DIR && docker compose down -v"
echo ""
echo "To fully remove the install directory:"
echo "  rm -rf $FIRECRAWL_INSTALL_DIR"
echo ""
info "Uninstall complete."
