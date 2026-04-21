#!/usr/bin/env bash
# install.sh — bootstrap self-hosted Firecrawl Claude Code plugin
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIRECRAWL_INSTALL_DIR="${FIRECRAWL_INSTALL_DIR:-$HOME/.firecrawl-claude-skill/firecrawl}"
FIRECRAWL_UPSTREAM="https://github.com/firecrawl/firecrawl.git"
PINNED_SHA="0ae6387b762c7450190eb7d8f9f7b81b7adfcaab"
PORT="${PORT:-3002}"
MODEL_NAME="${MODEL_NAME:-llama3.2:3b}"

# Docker Compose project name — override to avoid collisions with an existing
# stack running on a different port (e.g. smoke tests use firecrawl-smoke).
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-firecrawl}"
export COMPOSE_PROJECT_NAME

# Helper: run docker compose inside the install dir, inheriting project name.
dc() { COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" docker compose --project-name "$COMPOSE_PROJECT_NAME" -f "$FIRECRAWL_INSTALL_DIR/docker-compose.yaml" "$@"; }

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
  command -v "$dep" >/dev/null 2>&1 || die "Missing required tool: $dep. Please install it first."
done
docker compose version >/dev/null 2>&1 || \
  die "docker compose (v2 plugin) not found. Install Docker Desktop or the compose plugin."
info "All dependencies present."

# ── Step 2: clone firecrawl ───────────────────────────────────────────────────
if [[ -d "$FIRECRAWL_INSTALL_DIR/.git" ]]; then
  warn "Firecrawl repo already exists at $FIRECRAWL_INSTALL_DIR — skipping clone."
else
  info "Cloning firecrawl into $FIRECRAWL_INSTALL_DIR ..."
  mkdir -p "$(dirname "$FIRECRAWL_INSTALL_DIR")"
  git clone "$FIRECRAWL_UPSTREAM" "$FIRECRAWL_INSTALL_DIR"
fi

# ── Step 3: pin to known-good SHA ─────────────────────────────────────────────
info "Pinning to SHA $PINNED_SHA ..."
git -C "$FIRECRAWL_INSTALL_DIR" fetch --quiet origin
git -C "$FIRECRAWL_INSTALL_DIR" checkout --quiet "$PINNED_SHA" || \
  die "Could not checkout $PINNED_SHA. Try: git -C $FIRECRAWL_INSTALL_DIR fetch --all"

# ── Step 4: apply patches ─────────────────────────────────────────────────────
info "Applying patches..."
for patch in "$PLUGIN_ROOT/docker/patches/"*.patch; do
  pname=$(basename "$patch")
  info "  applying $pname ..."
  # Skip if already applied (idempotent re-runs)
  if git -C "$FIRECRAWL_INSTALL_DIR" apply --check "$patch" >/dev/null 2>&1; then
    git -C "$FIRECRAWL_INSTALL_DIR" apply --3way "$patch" 2>&1 || {
      REJECT=$(find "$FIRECRAWL_INSTALL_DIR" -name "*.rej" 2>/dev/null | head -5 | tr '\n' ' ')
      die "Patch $pname failed. Reject files: ${REJECT:-none found}. Check for upstream conflicts."
    }
  else
    # --check failed: patch may already be applied or have a real conflict.
    # Try reverse-check to detect already-applied case.
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

# ── Step 6: write default .env ────────────────────────────────────────────────
ENV_FILE="$FIRECRAWL_INSTALL_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
  warn ".env already exists — not overwriting. Edit $ENV_FILE manually if needed."
else
  info "Writing default .env ..."
  cat > "$ENV_FILE" <<EOF
PORT=${PORT}
INTERNAL_PORT=${PORT}
HOST=0.0.0.0
USE_DB_AUTHENTICATION=false

# concurrency
NUM_WORKERS_PER_QUEUE=8
CRAWL_CONCURRENT_REQUESTS=16
MAX_CONCURRENT_JOBS=6
BROWSER_POOL_SIZE=6

BULL_AUTH_KEY=localdev
LOGGING_LEVEL=INFO
ALLOW_LOCAL_WEBHOOKS=true

# --- local LLM (ollama) ---
MODEL_NAME=${MODEL_NAME}
MODEL_EMBEDDING_NAME=nomic-embed-text

# --- Cloudflare-mitigation proxy (tor) ---
# Leave blank by default — flip to socks5://tor:9050 to route Playwright through Tor.
PROXY_SERVER=
PROXY_USERNAME=
PROXY_PASSWORD=
EOF
fi

# ── Step 7: docker build + up ─────────────────────────────────────────────────
info "Building images (cache ok, this may take a few minutes on first run)..."
(cd "$FIRECRAWL_INSTALL_DIR" && COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" \
  docker compose --project-name "$COMPOSE_PROJECT_NAME" build)

info "Starting stack..."
(cd "$FIRECRAWL_INSTALL_DIR" && COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" \
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
  die "API did not respond within 180s. Check logs: cd $FIRECRAWL_INSTALL_DIR && docker compose --project-name $COMPOSE_PROJECT_NAME logs api"
fi

# ── Step 9: pull ollama models ────────────────────────────────────────────────
info "Pulling Ollama model $MODEL_NAME (~2 GB on first run, cached after)..."
docker exec "$OLLAMA_CONTAINER" ollama pull "$MODEL_NAME" || \
  warn "Ollama pull for $MODEL_NAME failed. Run: docker exec $OLLAMA_CONTAINER ollama pull $MODEL_NAME"

info "Pulling nomic-embed-text embedding model..."
docker exec "$OLLAMA_CONTAINER" ollama pull nomic-embed-text || \
  warn "nomic-embed-text pull failed. Run: docker exec $OLLAMA_CONTAINER ollama pull nomic-embed-text"

# ── Step 10: smoke tests ──────────────────────────────────────────────────────
info "Running smoke tests..."
ALL_PASS=true

# health
HC=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$API_URL/v2/scrape" \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com","formats":["markdown"]}' 2>/dev/null || echo "000")
if [[ "$HC" =~ ^(200|408|500)$ ]]; then
  pass "health (POST /v2/scrape -> HTTP $HC)"
else
  fail_msg "health (POST /v2/scrape -> HTTP $HC)"
  ALL_PASS=false
fi

# scrape
SCRAPE_RESP=$(curl -sS -X POST "$API_URL/v2/scrape" \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com","formats":["markdown"]}' 2>/dev/null || echo '{}')
SCRAPE_OK=$(echo "$SCRAPE_RESP" | jq -r '.success // false')
if [[ "$SCRAPE_OK" == "true" ]]; then
  pass "scrape (example.com markdown)"
else
  fail_msg "scrape (example.com) — $(echo "$SCRAPE_RESP" | jq -r '.error // "unknown error"')"
  ALL_PASS=false
fi

# search
SEARCH_RESP=$(curl -sS -X POST "$API_URL/v2/search" \
  -H 'Content-Type: application/json' \
  -d '{"query":"test query","limit":3}' 2>/dev/null || echo '{}')
SEARCH_OK=$(echo "$SEARCH_RESP" | jq -r '.success // false')
if [[ "$SEARCH_OK" == "true" ]]; then
  pass "search (/v2/search SearxNG)"
else
  fail_msg "search (/v2/search) — $(echo "$SEARCH_RESP" | jq -r '.error // "unknown error"')"
  ALL_PASS=false
fi

# JSON extract (Ollama must be loaded; first request cold-starts the model)
EXTRACT_RESP=$(curl -sS --max-time 120 -X POST "$API_URL/v2/scrape" \
  -H 'Content-Type: application/json' \
  -d '{
    "url": "https://example.com",
    "formats": [{
      "type": "json",
      "schema": {
        "type": "object",
        "properties": { "title": {"type": "string"} },
        "required": ["title"]
      },
      "prompt": "Extract the page title."
    }]
  }' 2>/dev/null || echo '{}')
EXTRACT_OK=$(echo "$EXTRACT_RESP" | jq -r '.success // false')
EXTRACT_JSON=$(echo "$EXTRACT_RESP" | jq -r '.data.json // null')
if [[ "$EXTRACT_OK" == "true" && "$EXTRACT_JSON" != "null" ]]; then
  pass "JSON extract (Ollama)"
else
  fail_msg "JSON extract — success=$EXTRACT_OK json=$EXTRACT_JSON"
  ALL_PASS=false
fi

# ── Step 11: summary ──────────────────────────────────────────────────────────
echo ""
echo "========================================"
if $ALL_PASS; then
  echo -e "${GREEN}install complete${NC} — all smoke tests passed"
else
  echo -e "${YELLOW}install complete${NC} — some smoke tests failed (see above)"
fi
echo ""
echo "API:       $API_URL"
echo "Stack dir: $FIRECRAWL_INSTALL_DIR"
echo "Project:   $COMPOSE_PROJECT_NAME"
echo ""
echo "Usage:"
echo "  fc scrape https://example.com"
echo "  fc search \"openai gpt-5\""
echo "  fc crawl https://docs.example.com --limit 20"
echo "  FIRECRAWL_REPO=$FIRECRAWL_INSTALL_DIR fc status"
echo ""
echo "Skill scripts: $PLUGIN_ROOT/skills/firecrawl/scripts/"
echo "========================================"
