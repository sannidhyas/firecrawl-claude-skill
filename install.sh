#!/usr/bin/env bash
# install.sh — bootstrap self-hosted Firecrawl Claude Code plugin
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIRECRAWL_INSTALL_DIR="${FIRECRAWL_INSTALL_DIR:-$HOME/.firecrawl-claude-skill/firecrawl}"
FIRECRAWL_UPSTREAM="https://github.com/firecrawl/firecrawl.git"
FIRECRAWL_PINNED_SHA="0ae6387b762c7450190eb7d8f9f7b81b7adfcaab"
PORT="${PORT:-3002}"
MODEL_NAME="${MODEL_NAME:-llama3.2:3b}"

# Docker Compose project name — override to avoid collisions with an existing
# stack running on a different port (e.g. smoke tests use COMPOSE_PROJECT_NAME=firecrawl-smoke).
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-firecrawl}"
export COMPOSE_PROJECT_NAME

# Container name prefix follows the compose project name.
OLLAMA_CONTAINER="${COMPOSE_PROJECT_NAME}-ollama-1"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[install]${NC} $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC} $*"; }
die()     { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }
pass()    { echo -e "${GREEN}PASS${NC} $1"; }
fail_msg(){ echo -e "${RED}FAIL${NC} $1"; }

# ── Step 1: dependency check ──────────────────────────────────────────────────
info "Checking dependencies..."
for dep in docker git curl jq python3; do
  command -v "$dep" >/dev/null 2>&1 || \
    die "Missing required tool: $dep. Please install it first (e.g. brew install $dep / apt install $dep)."
done
docker compose version >/dev/null 2>&1 || \
  die "docker compose (v2 plugin) not found. Install Docker Desktop or 'apt install docker-compose-plugin'."
info "All dependencies present."

# ── Step 1b: create data dir for change tracking ─────────────────────────────
CHANGES_DB_DIR="${CHANGES_DB_PATH:-$HOME/.firecrawl-claude-skill/changes.db}"
CHANGES_DB_DIR="$(dirname "$CHANGES_DB_DIR")"
mkdir -p "$CHANGES_DB_DIR"
info "Change-tracking DB dir: $CHANGES_DB_DIR"

# ── Step 2: clone firecrawl ───────────────────────────────────────────────────
if [[ -d "$FIRECRAWL_INSTALL_DIR/.git" ]]; then
  warn "Firecrawl repo already exists at $FIRECRAWL_INSTALL_DIR — skipping clone."
else
  info "Cloning firecrawl into $FIRECRAWL_INSTALL_DIR ..."
  mkdir -p "$(dirname "$FIRECRAWL_INSTALL_DIR")"
  git clone "$FIRECRAWL_UPSTREAM" "$FIRECRAWL_INSTALL_DIR"
fi

# ── Step 3: pin to known-good SHA ─────────────────────────────────────────────
info "Pinning to SHA $FIRECRAWL_PINNED_SHA ..."
git -C "$FIRECRAWL_INSTALL_DIR" fetch --quiet origin
git -C "$FIRECRAWL_INSTALL_DIR" checkout --quiet "$FIRECRAWL_PINNED_SHA" || \
  die "Could not checkout $FIRECRAWL_PINNED_SHA. Try: git -C $FIRECRAWL_INSTALL_DIR fetch --all"

# ── Step 4: apply patches ─────────────────────────────────────────────────────
info "Applying patches..."
for patch in "$PLUGIN_ROOT/docker/patches/"*.patch; do
  pname=$(basename "$patch")
  # playwright-turnstile.ts.patch is optional (disabled unless TURNSTILE_SOLVER env is set).
  # Skip it gracefully if it doesn't apply cleanly so a missing/different target file
  # does not block the core install.
  if [[ "$pname" == "playwright-turnstile.ts.patch" ]]; then
    if git -C "$FIRECRAWL_INSTALL_DIR" apply --check "$patch" >/dev/null 2>&1; then
      info "  applying $pname (optional Turnstile solver) ..."
      git -C "$FIRECRAWL_INSTALL_DIR" apply --3way "$patch" 2>&1 || \
        warn "  $pname failed to apply — Turnstile solver disabled. Set TURNSTILE_SOLVER to enable."
    elif git -C "$FIRECRAWL_INSTALL_DIR" apply --check --reverse "$patch" >/dev/null 2>&1; then
      warn "  $pname already applied — skipping."
    else
      warn "  $pname cannot be applied (target file may differ) — Turnstile solver disabled."
    fi
    continue
  fi
  info "  applying $pname ..."
  # Try forward apply first
  if git -C "$FIRECRAWL_INSTALL_DIR" apply --check "$patch" >/dev/null 2>&1; then
    git -C "$FIRECRAWL_INSTALL_DIR" apply --3way "$patch" 2>&1 || {
      REJECT=$(find "$FIRECRAWL_INSTALL_DIR" -name "*.rej" 2>/dev/null | head -5 | tr '\n' ' ')
      die "Patch $pname failed. Reject files: ${REJECT:-none found}. Check for upstream conflicts."
    }
  else
    # --check failed: may already be applied — confirm via reverse check
    if git -C "$FIRECRAWL_INSTALL_DIR" apply --check --reverse "$patch" >/dev/null 2>&1; then
      warn "  $pname already applied — skipping."
    else
      die "Patch $pname cannot be applied and is not already applied. Check for upstream conflicts."
    fi
  fi
done
info "All patches applied."

# ── Step 5: copy overlay files ────────────────────────────────────────────────
info "Copying docker-compose.override.yaml ..."
cp "$PLUGIN_ROOT/docker/docker-compose.override.yaml" "$FIRECRAWL_INSTALL_DIR/docker-compose.override.yaml"

info "Copying searxng settings ..."
mkdir -p "$FIRECRAWL_INSTALL_DIR/self-host-extras/searxng"
cp "$PLUGIN_ROOT/docker/searxng-settings.yml" \
   "$FIRECRAWL_INSTALL_DIR/self-host-extras/searxng/settings.yml"

# ── Step 6: write default .env (from env.example, if absent) ─────────────────
ENV_FILE="$FIRECRAWL_INSTALL_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
  warn ".env already exists — not overwriting. Edit $ENV_FILE manually if needed."
else
  info "Writing default .env from docker/env.example ..."
  cp "$PLUGIN_ROOT/docker/env.example" "$ENV_FILE"
  # Stamp in runtime values for PORT and MODEL_NAME
  sed -i "s/^PORT=.*/PORT=${PORT}/" "$ENV_FILE"
  sed -i "s/^INTERNAL_PORT=.*/INTERNAL_PORT=${PORT}/" "$ENV_FILE"
  sed -i "s/^MODEL_NAME=.*/MODEL_NAME=${MODEL_NAME}/" "$ENV_FILE"
fi

# ── Step 7: docker build + up ─────────────────────────────────────────────────
info "Building images (cache ok — may take a few minutes on first run)..."
(cd "$FIRECRAWL_INSTALL_DIR" && \
  COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" \
  docker compose --project-name "$COMPOSE_PROJECT_NAME" build api playwright-service)

info "Starting stack..."
(cd "$FIRECRAWL_INSTALL_DIR" && \
  COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" \
  docker compose --project-name "$COMPOSE_PROJECT_NAME" up -d)

# ── Step 8: wait for API ──────────────────────────────────────────────────────
API_URL="http://localhost:${PORT}"
info "Waiting for Firecrawl API at $API_URL (up to 180s)..."
DEADLINE=$((SECONDS + 180))
while [[ $SECONDS -lt $DEADLINE ]]; do
  HTTP_CODE=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$API_URL/v2/scrape" \
    -H 'Content-Type: application/json' \
    -d '{"url":"https://example.com","formats":["markdown"]}' 2>/dev/null || echo "000")
  if [[ "$HTTP_CODE" =~ ^(200|408|500)$ ]]; then
    info "API reachable (HTTP $HTTP_CODE)."
    break
  fi
  echo -n "."
  sleep 3
done
echo ""
if [[ $SECONDS -ge $DEADLINE ]]; then
  die "API did not respond within 180s. Check: cd $FIRECRAWL_INSTALL_DIR && docker compose --project-name $COMPOSE_PROJECT_NAME logs api"
fi

# ── Step 9: pull ollama models ────────────────────────────────────────────────
info "Pulling Ollama model $MODEL_NAME (~2 GB on first run, cached after)..."
docker exec "$OLLAMA_CONTAINER" ollama pull "$MODEL_NAME" || \
  warn "Ollama pull for $MODEL_NAME failed. Run manually: docker exec $OLLAMA_CONTAINER ollama pull $MODEL_NAME"

info "Pulling nomic-embed-text embedding model..."
docker exec "$OLLAMA_CONTAINER" ollama pull nomic-embed-text || \
  warn "nomic-embed-text pull failed. Run: docker exec $OLLAMA_CONTAINER ollama pull nomic-embed-text"

# ── Step 10: smoke tests ──────────────────────────────────────────────────────
info "Running smoke tests..."
ALL_PASS=true

# 1. scrape
SCRAPE_RESP=$(curl -sS -X POST "$API_URL/v2/scrape" \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com","formats":["markdown"]}' 2>/dev/null || echo '{}')
SCRAPE_OK=$(echo "$SCRAPE_RESP" | jq -r '.success // false')
SCRAPE_LEN=$(echo "$SCRAPE_RESP" | jq -r '.data.markdown // "" | length')
if [[ "$SCRAPE_OK" == "true" && "$SCRAPE_LEN" -gt 50 ]]; then
  pass "scrape (/v2/scrape example.com markdown len=$SCRAPE_LEN)"
else
  fail_msg "scrape — success=$SCRAPE_OK markdown_len=$SCRAPE_LEN"
  ALL_PASS=false
fi

# 2. search
SEARCH_RESP=$(curl -sS -X POST "$API_URL/v2/search" \
  -H 'Content-Type: application/json' \
  -d '{"query":"test query","limit":3}' 2>/dev/null || echo '{}')
SEARCH_OK=$(echo "$SEARCH_RESP" | jq -r '.success // false')
SEARCH_LEN=$(echo "$SEARCH_RESP" | jq -r 'if .data then (.data | length) elif .data.web then (.data.web | length) else 0 end')
if [[ "$SEARCH_OK" == "true" ]]; then
  pass "search (/v2/search SearxNG results=$SEARCH_LEN)"
else
  fail_msg "search — success=$SEARCH_OK error=$(echo "$SEARCH_RESP" | jq -r '.error // "unknown"')"
  ALL_PASS=false
fi

# 3. JSON extract via Ollama (cold-start may take up to 60s)
EXTRACT_RESP=$(curl -sS --max-time 120 -X POST "$API_URL/v2/scrape" \
  -H 'Content-Type: application/json' \
  -d '{
    "url": "https://example.com",
    "formats": [{
      "type": "json",
      "schema": {
        "type": "object",
        "properties": { "page_title": {"type": "string"} },
        "required": ["page_title"]
      },
      "prompt": "Extract the page title."
    }]
  }' 2>/dev/null || echo '{}')
EXTRACT_OK=$(echo "$EXTRACT_RESP" | jq -r '.success // false')
EXTRACT_JSON=$(echo "$EXTRACT_RESP" | jq -r '.data.json // null')
if [[ "$EXTRACT_OK" == "true" && "$EXTRACT_JSON" != "null" ]]; then
  pass "JSON extract (Ollama $MODEL_NAME)"
else
  fail_msg "JSON extract — success=$EXTRACT_OK json=$EXTRACT_JSON"
  ALL_PASS=false
fi

# ── Step 11: summary ──────────────────────────────────────────────────────────
echo ""
echo "========================================"
if $ALL_PASS; then
  echo -e "${GREEN}install complete — 3/3 smoke tests passed${NC}"
else
  echo -e "${YELLOW}install complete — some smoke tests failed (see above)${NC}"
fi
echo ""
echo "API:       $API_URL"
echo "Stack dir: $FIRECRAWL_INSTALL_DIR"
echo "Project:   $COMPOSE_PROJECT_NAME"
echo ""
echo "Next steps:"
echo "  Add skill to Claude Code: /plugin add $PLUGIN_ROOT"
echo "  Skill scripts: $PLUGIN_ROOT/skills/firecrawl/scripts/fc"
echo "  Quick test: PATH=\"$PLUGIN_ROOT/skills/firecrawl/scripts:\$PATH\" fc scrape https://example.com"
echo "========================================"
