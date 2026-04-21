---
name: firecrawl
description: "Scrape web pages, batch-scrape URL lists, search the web, map sites, crawl documentation, and extract structured JSON via a self-hosted Firecrawl — with local SearxNG for web search and local Ollama (llama3.2:3b) for LLM extract. Use when the user needs to fetch live web content as markdown, convert URLs to a dataset, build a research corpus from websites, extract structured data matching a JSON schema, discover pages on a site, or run a web search without external API keys. Also triggers on: 'scrape this URL', 'build dataset from these sites', 'crawl docs', 'search the web', 'get markdown of X', 'extract these fields from a page'. No external API key, no rate limits."
allowed-tools: ["Bash", "Read", "Write"]
---

# Firecrawl (self-hosted — full local parity)

Local Firecrawl API at `http://localhost:3002` (default; override with `FIRECRAWL_URL`).
No auth. Stack managed via `docker compose` in `$FIRECRAWL_INSTALL_DIR` (default `$HOME/.fireclaude/firecrawl`).

Stack (8 containers):

| Service | Role |
|---|---|
| `api` | Firecrawl REST API |
| `playwright-service` | JS rendering (playwright-extra + stealth) |
| `redis`, `rabbitmq`, `nuq-postgres` | queue / state |
| **`searxng`** | Local web search → `/v2/search` |
| **`ollama`** | Local LLM (`llama3.2:3b`) → JSON schema extract |

## Capability parity vs Firecrawl Cloud

| Feature | Cloud | This self-host |
|---|---|---|
| `/v2/scrape` markdown/html/links/screenshot | ✅ | ✅ |
| `/v2/batch/scrape` | ✅ | ✅ |
| `/v2/crawl` / `/v2/map` | ✅ | ✅ |
| `/v2/search` | via managed search | ✅ via SearxNG |
| JSON-schema extract (`formats:[{type:"json",schema}]`) | GPT-4o | ✅ via Ollama `llama3.2:3b` |
| Actions (click, wait, scroll) | ✅ | ✅ (Playwright) |
| Fire-engine anti-bot bypass | ✅ | ❌ (cloud-only) |
| Change Tracking / Deep Research | ✅ | ❌ (cloud-only) |
| Webhooks (`SELF_HOSTED_WEBHOOK_URL`) | ✅ | ✅ |

## Commands

Wrapper script at `${CLAUDE_PLUGIN_ROOT}/skills/fireclaude/scripts/fc` (invoked via the `fireclaude` npm binary after install).

| Action | Command |
|---|---|
| Single scrape | `fireclaude scrape <url> [--format markdown\|html\|links\|screenshot]` |
| Batch scrape | `fireclaude batch <urls.txt> [--out dataset.jsonl]` |
| Search web (SearxNG) | `fireclaude search "<query>" [--limit N]` |
| Map site URLs | `fireclaude map <url>` |
| Crawl site | `fireclaude crawl <url> [--limit N] [--out dir]` |
| Health | `fireclaude health` |
| Stack status | `fireclaude status` |
| Stack logs | `fireclaude logs [api\|playwright-service\|searxng\|ollama]` |

## Dataset pipeline

```
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fireclaude/scripts/batch-dataset.py \
    --urls urls.txt --out dataset.jsonl --format markdown --only-main
```

JSONL per line: `{url, title, markdown, status, fetched_at, ...}`.

## JSON-schema extract (local Ollama)

```bash
curl -sS -X POST http://localhost:3002/v2/scrape \
  -H 'Content-Type: application/json' \
  -d '{
    "url": "https://news.ycombinator.com",
    "formats": [{
      "type": "json",
      "schema": {
        "type": "object",
        "properties": {
          "top_story_title": {"type": "string"},
          "top_story_url":   {"type": "string"},
          "point_count":     {"type": "integer"}
        },
        "required": ["top_story_title"]
      },
      "prompt": "Extract the top story on the page."
    }]
  }' | jq .data.json
```

Extract routes through Ollama because `apps/api/src/lib/generic-ai.ts` is patched to force provider → ollama whenever `OLLAMA_BASE_URL` is set.

Swap model: set `MODEL_NAME=qwen2.5:7b` (or anything in `docker exec firecrawl-ollama-1 ollama list`) in `.env`, then:
```bash
cd $FIRECRAWL_INSTALL_DIR && docker compose up -d --force-recreate api
```

Pull more models:
```bash
docker exec firecrawl-ollama-1 ollama pull qwen2.5:7b
docker exec firecrawl-ollama-1 ollama pull nomic-embed-text
```

## Endpoints (raw, v2)

```
POST /v2/scrape         {url, formats, onlyMainContent, waitFor, actions}
POST /v2/batch/scrape   {urls, formats} → {id}
GET  /v2/batch/scrape/{id}
POST /v2/crawl          {url, limit, scrapeOptions}
GET  /v2/crawl/{id}
POST /v2/search         {query, limit}
POST /v2/map            {url}
```

## Cloudflare / antibot

Self-host has no Fire-engine. Per-site success rate on Cloudflare sites ~40–50%. Mitigations (all free):

1. **Retry**: Cloudflare returns `SCRAPE_RETRY_LIMIT` → `document_antibot` intermittently; same URL on 2nd-3rd try often succeeds.
2. **waitFor + actions**: `{waitFor: 5000, actions: [{type:"wait", milliseconds:3000}, {type:"scrape"}]}`.
3. **Custom proxy**: set `PROXY_SERVER=socks5://your-proxy:1080` in `.env`, then `docker compose up -d --force-recreate playwright-service`. For IP rotation, bring your own proxy — integrated Tor was trialled and dropped due to unreliable bootstrap on many networks and Cloudflare pre-blocking most exit nodes.

## Stack control

```bash
cd $FIRECRAWL_INSTALL_DIR
docker compose up -d                              # start all
docker compose up -d --force-recreate api         # pick up env changes
docker compose down                               # stop
docker compose logs -f api                        # tail
```

Files layered on top of upstream repo:

```
$FIRECRAWL_INSTALL_DIR/
├── .env                                  # tunables, MODEL_NAME, PROXY_SERVER
├── docker-compose.yaml                   # upstream (do not edit)
├── docker-compose.override.yaml          # self-host extras: searxng, ollama
└── self-host-extras/
    ├── searxng/settings.yml              # JSON output enabled
    └── ollama-data/                      # model cache volume
```

Source patches are in `${CLAUDE_PLUGIN_ROOT}/docker/patches/`. Applied at install time via `git apply --3way`.

## When to invoke

Activate on any request that reads live web content: "scrape", "crawl", "fetch page", "build dataset from these sites", "search the web", "get markdown of docs", "extract fields from page", "convert URLs to training data". Prefer this over ad-hoc `curl` + HTML parsing.
