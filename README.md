# firecrawl-claude-skill

Self-hosted [Firecrawl](https://github.com/firecrawl/firecrawl) packaged as a Claude Code skill. Scrape, crawl, search, batch-dataset, and JSON-schema extract — all local, no API keys, no paid tiers.

Stack: Firecrawl API + Playwright (stealth) + SearxNG (search) + Ollama (llama3.2:3b, JSON extract).

## TL;DR install

```bash
# one-liner (pinned release)
curl -sSL https://raw.githubusercontent.com/sannidhyas/firecrawl-claude-skill/v0.1.0/install.sh | bash

# or clone first
git clone https://github.com/sannidhyas/firecrawl-claude-skill
cd firecrawl-claude-skill && ./install.sh
```

Install takes 5–15 min on first run (Docker build + model download). The running stack uses ~4 GB RAM and ~8 GB disk.

Override install location:
```bash
FIRECRAWL_INSTALL_DIR=/opt/firecrawl ./install.sh
```

## Claude Code plugin install

```
/plugin marketplace add sannidhyas/firecrawl-claude-skill
```

Or local-dir install (after cloning):
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
| JSON-schema extract via Ollama | see below |
| Stack health check | `fc health` |
| Stack status | `fc status` |
| Tail logs | `fc logs [api\|playwright-service\|ollama\|searxng]` |

### JSON-schema extract

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

Routes through `ollama` container (llama3.2:3b by default). First request cold-starts the model (~5–10s).

## Honest limits

| Limit | Detail |
|---|---|
| Cloudflare 403 | No Fire-engine; CF IP reputation blocks ~50–60% of CF-protected pages. Retries help (~40–50% success on retry). Use `waitFor` + `actions` for JS-challenge pages. |
| No Fire-engine | Cloud-only antibot bypass not available self-hosted. |
| No Change Tracking | Cloud-only feature. |
| No Deep Research | Cloud-only feature. |
| IP rotation | For datacenter IPs blocked by Cloudflare, bring your own proxy via `PROXY_SERVER` env. Integrated Tor was trialled and dropped due to unreliable bootstrap on many networks and Cloudflare pre-blocking most exit nodes. |
| LLM quality | llama3.2:3b (3B params) extracts simple schemas well; complex multi-field structured extraction may need qwen2.5:7b or larger. |
| First model pull | ~2 GB download on first install. Subsequent starts are instant (models cached in docker volume). |

## Swap Ollama model

Edit `$FIRECRAWL_INSTALL_DIR/.env`:
```
MODEL_NAME=qwen2.5:7b
```

Then restart the API:
```bash
cd $FIRECRAWL_INSTALL_DIR
docker exec firecrawl-ollama-1 ollama pull qwen2.5:7b   # pull first
docker compose up -d --force-recreate api
```

List available models:
```bash
docker exec firecrawl-ollama-1 ollama list
```

## Uninstall

```bash
./uninstall.sh

# to also delete install dir and all data:
rm -rf ~/.firecrawl-claude-skill
```

## How patches work

Six `git diff` patches in `docker/patches/` are applied against firecrawl SHA `0ae6387b762c7450190eb7d8f9f7b81b7adfcaab` at install time:

| Patch | What it does |
|---|---|
| `generic-ai.ts.patch` | Routes all LLM calls through Ollama via OpenAI-compat `/v1` (fixes AI SDK v2 incompatibility with `ollama-ai-provider`) |
| `config.ts.patch` | Adds `SELF_HOST_ANTIBOT_RETRIES` + `SELF_HOST_ANTIBOT_WAIT_MS` env vars |
| `scrapeURL-index.ts.patch` | Retry loop + `waitFor` honored on antibot retries |
| `engines-index.ts.patch` | Marks playwright engine as `stealthProxy`-capable; guards pdf/document engines from spurious selection |
| `playwright-api.ts.patch` | Adds playwright-extra + stealth plugin + `--disable-blink-features=AutomationControlled` + `networkidle` wait strategy |
| `playwright-package.json.patch` | Adds `playwright-extra` + `puppeteer-extra-plugin-stealth` deps |

If firecrawl upstream changes break a patch, run `git apply --3way` from the install dir and resolve conflicts manually.

## Contributing

PRs welcome. Keep patches minimal and comment why each hunk is needed. Test with the smoke test in `install.sh` before opening a PR.

Pin SHA updates: update `PINNED_SHA` in `install.sh` and regenerate patches with `git diff <new-sha> HEAD -- <file> > docker/patches/<name>.patch`.

## License

MIT — see [LICENSE](LICENSE).
