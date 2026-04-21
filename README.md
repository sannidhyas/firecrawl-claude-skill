# firecrawl-claude-skill

Self-hosted [Firecrawl](https://github.com/firecrawl/firecrawl) packaged as a Claude Code skill. Scrape, crawl, search, batch-dataset, JSON-schema extract, change tracking, webhook testing — all local, no API keys, no paid tiers.

Stack: Firecrawl API + Playwright (stealth) + SearxNG (search) + Ollama (llama3.2:3b, JSON extract).

## TL;DR install

```bash
# one-liner (pinned release)
curl -sSL https://raw.githubusercontent.com/sannidhyas/firecrawl-claude-skill/v0.2.0/install.sh | bash

# or clone first
git clone https://github.com/sannidhyas/firecrawl-claude-skill
cd firecrawl-claude-skill && ./install.sh
```

Install takes 5–15 min on first run (Docker build + model download). The running stack uses ~4 GB RAM and ~8 GB disk.

Override install location:
```bash
FIRECRAWL_INSTALL_DIR=/opt/firecrawl ./install.sh
```

## Marketplace install

```
/plugin marketplace add sannidhyas/firecrawl-claude-skill
```

## npm install

```bash
npm install -g firecrawl-claude-skill
# then run: install.sh   (bootstraps the Docker stack)
```

## Claude Code local plugin install

```
/plugin add ./firecrawl-claude-skill
```

The skill activates automatically when you ask Claude to scrape, crawl, search the web, or extract structured data from pages.

## What works

| Feature | Command |
|---|---|
| Scrape single URL → markdown/html/links | `fc scrape <url>` |
| Batch scrape URL list → JSONL dataset | `fc batch urls.txt --out dataset.jsonl` |
| Web search via SearxNG | `fc search "query" --limit 10` |
| Map all URLs on a site | `fc map https://docs.example.com` |
| Crawl site → markdown files | `fc crawl https://docs.example.com --limit 50 --out ./docs` |
| JSON-schema extract via Ollama | `fc extract <url> --schema schema.json` |
| Change tracking | `fc changes <url> [--diff]` |
| Webhook receiver | `fc webhook-listen [--port N]` |
| Manage Ollama models | `fc model list/pull/swap/current` |
| Stack health check | `fc health` |
| Stack status | `fc status` |
| Tail logs | `fc logs [api\|playwright-service\|ollama\|searxng]` |

## Agentic use

All subcommands accept `--json` to return the full API response as machine-readable JSON:

```bash
# Scrape and pipe to jq
fc scrape https://example.com --json | jq '.data.markdown'

# Search — get raw results
fc search "rust async runtime" --limit 5 --json | jq '.data[].url'

# Map a site
fc map https://docs.anthropic.com --json | jq '.links | length'

# Extract structured data
fc extract https://news.ycombinator.com \
  --schema schema.json \
  --prompt "Extract the top 3 story titles and URLs" \
  --json | jq '.data.json'

# Change tracking — agent-friendly
fc changes https://example.com --json
# → {"url":"...","changed":false,"current_hash":"...","diff_bytes":0,"scraped_at":1714521600}
```

### JSON-schema extract

```bash
cat > schema.json <<'EOF'
{
  "type": "object",
  "properties": {
    "top_story_title": {"type": "string"},
    "top_story_url":   {"type": "string"},
    "point_count":     {"type": "integer"}
  },
  "required": ["top_story_title"]
}
EOF

fc extract https://news.ycombinator.com \
  --schema schema.json \
  --prompt "Extract the top story." \
  --json | jq '.data.json'
```

Routes through the `ollama` container (llama3.2:3b by default). First request cold-starts the model (~5–10s).

## Model swap

Swap the active Ollama model without restarting the whole stack:

```bash
# List available models
fc model list
# → ["llama3.2:3b","nomic-embed-text:latest"]

# Pull a new model
fc model pull qwen2.5:7b

# Swap active model (updates .env, recreates API container)
fc model swap qwen2.5:7b

# Check current model
fc model current
# → qwen2.5:7b
```

Manual alternative — edit `$FIRECRAWL_INSTALL_DIR/.env`:
```
MODEL_NAME=qwen2.5:7b
```
Then: `docker exec firecrawl-ollama-1 ollama pull qwen2.5:7b && docker compose up -d --force-recreate api`

## Change tracking

Track whether a page's content has changed since last check:

```bash
# First run — always "changed" (no baseline)
fc changes https://example.com
# → https://example.com: changed

# Second run — compare against stored hash
fc changes https://example.com
# → https://example.com: unchanged

# Show diff
fc changes https://example.com --diff

# JSON output for agents
fc changes https://example.com --json
# → {"url":"...","changed":false,"previous_hash":"abc...","current_hash":"abc...","diff_bytes":0,"scraped_at":1714521600}
```

Change history stored in SQLite at `~/.firecrawl-claude-skill/changes.db` (override with `CHANGES_DB_PATH`).

## Webhook testing

Spin up an ephemeral HTTP receiver to capture Firecrawl webhook callbacks:

```bash
# Start listener (default port 4321)
fc webhook-listen --json &

# Configure Firecrawl to POST webhooks to this receiver
# SELF_HOSTED_WEBHOOK_URL=http://host.docker.internal:4321/webhook

# Each POST emits a JSON line:
# {"timestamp":"2026-04-21T10:00:00Z","method":"POST","path":"/webhook","headers":{...},"body":{...}}

# Custom port
fc webhook-listen --port 9999
```

## Turnstile / CAPTCHA solver (optional)

Add to your `.env` (disabled by default):

```env
TURNSTILE_SOLVER=capmonster       # or: 2captcha
TURNSTILE_SOLVER_API_KEY=your_key
```

Then apply the patch during install: the patch is at `docker/patches/playwright-turnstile.ts.patch` and is applied automatically by `install.sh`.

## Honest limits

| Limit | Detail |
|---|---|
| Cloudflare 403 | No Fire-engine; CF IP reputation blocks ~50–60% of CF-protected pages. Retries help. Use `waitFor` + `actions` for JS-challenge pages. |
| No Fire-engine | Cloud-only antibot bypass not available self-hosted. |
| IP rotation | Bring your own proxy via `PROXY_SERVER` env. |
| LLM quality | llama3.2:3b extracts simple schemas well; complex multi-field extraction may need qwen2.5:7b or larger. |
| First model pull | ~2 GB download on first install. Subsequent starts are instant. |

## How patches work

Six `git diff` patches in `docker/patches/` are applied against firecrawl SHA `0ae6387b762c7450190eb7d8f9f7b81b7adfcaab` at install time:

| Patch | What it does |
|---|---|
| `generic-ai.ts.patch` | Routes all LLM calls through Ollama via OpenAI-compat `/v1` |
| `config.ts.patch` | Adds `SELF_HOST_ANTIBOT_RETRIES` + `SELF_HOST_ANTIBOT_WAIT_MS` env vars |
| `scrapeURL-index.ts.patch` | Retry loop + `waitFor` honored on antibot retries |
| `engines-index.ts.patch` | Marks playwright engine as `stealthProxy`-capable |
| `playwright-api.ts.patch` | Adds playwright-extra + stealth plugin |
| `playwright-package.json.patch` | Adds stealth plugin deps |
| `playwright-turnstile.ts.patch` | Optional Turnstile solver (disabled unless env vars set) |

## Uninstall

```bash
./uninstall.sh

# to also delete install dir and all data:
rm -rf ~/.firecrawl-claude-skill
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Security

See [SECURITY.md](SECURITY.md).

## License

MIT — see [LICENSE](LICENSE).
