#!/usr/bin/env bash
# install.sh — bootstrap self-hosted Firecrawl Claude Code plugin
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIRECRAWL_INSTALL_DIR="${FIRECRAWL_INSTALL_DIR:-$HOME/.fireclaude/firecrawl}"
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

# OLLAMA_MODE: auto (default) | host | container
OLLAMA_MODE="${OLLAMA_MODE:-auto}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[install]${NC} $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC} $*"; }
die()     { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }
pass()    { echo -e "${GREEN}PASS${NC} $1"; }
fail_msg(){ echo -e "${RED}FAIL${NC} $1"; }
# @stage: protocol — consumed by fireclaude-bin.js ora wrapper
stage()   { echo "@stage: $*" >&2; }

# ── Step 0: print splash ──────────────────────────────────────────────────────
LOGO_ASCII="${PLUGIN_ROOT}/assets/logo-ascii.txt"
if [[ -f "$LOGO_ASCII" ]]; then
  cat "$LOGO_ASCII"
  echo ""
fi
info "fireclaude setup — version $(node -e "try{process.stdout.write(require('${PLUGIN_ROOT}/package.json').version)}catch(e){process.stdout.write('?')}" 2>/dev/null || echo '?')"
echo ""

# ── Step 1: dependency check ──────────────────────────────────────────────────
stage "deps-check"
info "Checking dependencies..."
for dep in docker git curl jq python3; do
  command -v "$dep" >/dev/null 2>&1 || \
    die "Missing required tool: $dep. Please install it first (e.g. brew install $dep / apt install $dep)."
done
docker compose version >/dev/null 2>&1 || \
  die "docker compose (v2 plugin) not found. Install Docker Desktop or 'apt install docker-compose-plugin'."
info "All dependencies present."

# ── Step 1b: create data dir for change tracking ─────────────────────────────
CHANGES_DB_DIR="${CHANGES_DB_PATH:-$HOME/.fireclaude/changes.db}"
CHANGES_DB_DIR="$(dirname "$CHANGES_DB_DIR")"
mkdir -p "$CHANGES_DB_DIR"
info "Change-tracking DB dir: $CHANGES_DB_DIR"

# ── Step 1c: resolve ollama mode ──────────────────────────────────────────────
stage "ollama-mode"
_host_ollama_reachable() {
  curl -sf --max-time 3 http://localhost:11434/api/tags >/dev/null 2>&1
}

EFFECTIVE_OLLAMA_MODE="container"
OLLAMA_BASE_URL_OVERRIDE=""

case "$OLLAMA_MODE" in
  host)
    info "OLLAMA_MODE=host — checking host daemon at http://localhost:11434 ..."
    if _host_ollama_reachable; then
      info "Host ollama reachable. Using host daemon."
      EFFECTIVE_OLLAMA_MODE="host"
      OLLAMA_BASE_URL_OVERRIDE="http://host.docker.internal:11434/api"
    else
      die "OLLAMA_MODE=host but host ollama is unreachable at http://localhost:11434. Start it with: fireclaude ollama-start"
    fi
    ;;
  auto)
    info "OLLAMA_MODE=auto — probing host daemon at http://localhost:11434 ..."
    if _host_ollama_reachable; then
      info "Host ollama reachable. Skipping container — using host daemon (mode: host)."
      EFFECTIVE_OLLAMA_MODE="host"
      OLLAMA_BASE_URL_OVERRIDE="http://host.docker.internal:11434/api"
    else
      info "Host ollama not reachable. Falling back to container mode."
      EFFECTIVE_OLLAMA_MODE="container"
    fi
    ;;
  container)
    info "OLLAMA_MODE=container — will start bundled ollama container."
    EFFECTIVE_OLLAMA_MODE="container"
    ;;
  *)
    die "Unknown OLLAMA_MODE='$OLLAMA_MODE'. Valid values: auto | host | container"
    ;;
esac

info "Effective ollama mode: $EFFECTIVE_OLLAMA_MODE"

# ── Step 2: clone firecrawl ───────────────────────────────────────────────────
stage "clone"
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
stage "patches"
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
SEARXNG_SRC="$PLUGIN_ROOT/docker/searxng-settings.yml"
SEARXNG_DST="$FIRECRAWL_INSTALL_DIR/self-host-extras/searxng/settings.yml"
if [[ -f "$SEARXNG_DST" ]] && cmp -s "$SEARXNG_SRC" "$SEARXNG_DST"; then
  info "  searxng settings unchanged — skipping copy"
elif [[ ! -e "$SEARXNG_DST" ]] || [[ -w "$SEARXNG_DST" ]]; then
  cp "$SEARXNG_SRC" "$SEARXNG_DST"
else
  warn "  $SEARXNG_DST owned by another user (likely searxng container UID)"
  warn "  fix: sudo chown \$(id -u):\$(id -g) $SEARXNG_DST && fireclaude setup"
  warn "  skipping searxng settings update — continuing with existing file"
fi

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

# In host / auto-resolved-host mode, set OLLAMA_BASE_URL so the api container
# reaches the host daemon via host.docker.internal.
if [[ "$EFFECTIVE_OLLAMA_MODE" == "host" ]]; then
  if grep -q '^OLLAMA_BASE_URL=' "$ENV_FILE" 2>/dev/null; then
    sed -i "s|^OLLAMA_BASE_URL=.*|OLLAMA_BASE_URL=${OLLAMA_BASE_URL_OVERRIDE}|" "$ENV_FILE"
  else
    echo "OLLAMA_BASE_URL=${OLLAMA_BASE_URL_OVERRIDE}" >> "$ENV_FILE"
  fi
  # Persist mode for doctor / fc to read
  if grep -q '^OLLAMA_MODE=' "$ENV_FILE" 2>/dev/null; then
    sed -i "s/^OLLAMA_MODE=.*/OLLAMA_MODE=host/" "$ENV_FILE"
  else
    echo "OLLAMA_MODE=host" >> "$ENV_FILE"
  fi
  info "OLLAMA_BASE_URL set to $OLLAMA_BASE_URL_OVERRIDE in $ENV_FILE"
fi

# ── Step 7: docker build + up ─────────────────────────────────────────────────
stage "build"
info "Building images (cache ok — may take a few minutes on first run)..."
(cd "$FIRECRAWL_INSTALL_DIR" && \
  COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" \
  docker compose --project-name "$COMPOSE_PROJECT_NAME" build api playwright-service)

stage "up"
info "Starting stack..."
if [[ "$EFFECTIVE_OLLAMA_MODE" == "container" ]]; then
  (cd "$FIRECRAWL_INSTALL_DIR" && \
    COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" \
    COMPOSE_PROFILES="container-ollama" \
    docker compose --project-name "$COMPOSE_PROJECT_NAME" --profile container-ollama up -d)
else
  # Host mode — no ollama container needed
  (cd "$FIRECRAWL_INSTALL_DIR" && \
    COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" \
    docker compose --project-name "$COMPOSE_PROJECT_NAME" up -d)
fi

# ── Step 8: wait for API ──────────────────────────────────────────────────────
stage "health"
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
stage "pull"
if [[ "$EFFECTIVE_OLLAMA_MODE" == "container" ]]; then
  info "Pulling Ollama model $MODEL_NAME (~2 GB on first run, cached after)..."
  docker exec "$OLLAMA_CONTAINER" ollama pull "$MODEL_NAME" || \
    warn "Ollama pull for $MODEL_NAME failed. Run manually: docker exec $OLLAMA_CONTAINER ollama pull $MODEL_NAME"

  info "Pulling nomic-embed-text embedding model..."
  docker exec "$OLLAMA_CONTAINER" ollama pull nomic-embed-text || \
    warn "nomic-embed-text pull failed. Run: docker exec $OLLAMA_CONTAINER ollama pull nomic-embed-text"
else
  # Host mode — pull via HTTP API on the host daemon
  _OLLAMA_HOST_URL="http://localhost:11434"
  info "Pulling $MODEL_NAME via host ollama at $_OLLAMA_HOST_URL ..."
  curl -sS -X POST "$_OLLAMA_HOST_URL/api/pull" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"$MODEL_NAME\"}" | tail -1 || \
    warn "Host ollama pull for $MODEL_NAME may have failed. Run: ollama pull $MODEL_NAME"

  info "Pulling nomic-embed-text via host ollama ..."
  curl -sS -X POST "$_OLLAMA_HOST_URL/api/pull" \
    -H 'Content-Type: application/json' \
    -d '{"name":"nomic-embed-text"}' | tail -1 || \
    warn "Host ollama pull for nomic-embed-text may have failed."
fi

# ── Step 10: smoke tests ──────────────────────────────────────────────────────
stage "smoke"
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
echo "API:          $API_URL"
echo "Stack dir:    $FIRECRAWL_INSTALL_DIR"
echo "Project:      $COMPOSE_PROJECT_NAME"
echo "Ollama mode:  $EFFECTIVE_OLLAMA_MODE"
echo ""
echo "Next steps:"
echo "  Add skill to Claude Code: /plugin add $PLUGIN_ROOT"
echo "  Skill scripts: $PLUGIN_ROOT/skills/fireclaude/scripts/fc"
echo "  Quick test (npm install): fireclaude scrape https://example.com"
echo "  Optional short alias:     fireclaude alias install"
echo "========================================"
