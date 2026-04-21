# Fireclaude

Self-hosted [Firecrawl](https://github.com/firecrawl/firecrawl) packaged as a Claude Code skill. Scrape, crawl, search, batch-dataset, JSON-schema extract, change tracking, webhook testing — all local, no API keys, no paid tiers.

Stack: Firecrawl API + Playwright (stealth) + SearxNG (search) + Ollama (llama3.2:3b, JSON extract).

## Install

```bash
npm install -g fireclaude
fireclaude setup
```

`fireclaude setup` clones firecrawl, applies patches, builds Docker images, pulls the Ollama model, and runs smoke tests. Takes 5–15 min on first run. The running stack uses ~4 GB RAM and ~8 GB disk.

Override install location or model:
```bash
fireclaude setup --install-dir /opt/firecrawl --model qwen2.5:7b
```

**Optional short alias:** if you prefer typing `fc`, run:
```bash
fireclaude alias install
```
This writes `alias fc='fireclaude'` to `~/.bashrc` / `~/.zshrc`. Remove with `fireclaude alias uninstall`.

## Claude Code plugin install

```
/plugin marketplace add sannidhyas/fireclaude
```

Or from a local checkout:
```
/plugin add ./fireclaude
```

The skill activates automatically when you ask Claude to scrape, crawl, search the web, or extract structured data.

## CLI reference

### Lifecycle

| Command | Description |
|---|---|
| `fireclaude setup [--install-dir PATH] [--model NAME]` | First-run bootstrap — clone, patch, build, start stack |
| `fireclaude start` | Start stopped containers |
| `fireclaude stop` | Stop running containers |
| `fireclaude status [--json]` | Container status. `--json` → array of `{service, state}` |
| `fireclaude teardown [--purge]` | Stop + remove stack. `--purge` auto-answers yes to all prompts |
| `fireclaude upgrade [--sha GIT_SHA]` | Pull latest fireclaude npm, optionally pin firecrawl to SHA, rebuild, restart |
| `fireclaude version` | fireclaude version + installed firecrawl SHA + ollama models |
| `fireclaude doctor [--json]` | Dep check + container health + model presence. `--json` for agent use |
| `fireclaude alias install [--yes]` | Write `alias fc='fireclaude'` to `~/.bashrc` / `~/.zshrc` |
| `fireclaude alias uninstall [--yes]` | Remove the alias from shell rc files |

### Data

| Command | Description |
|---|---|
| `fireclaude scrape <url> [--format markdown\|html\|links\|screenshot] [--raw] [--json]` | Scrape single URL |
| `fireclaude batch <urls.txt> [--out dataset.jsonl] [--format markdown] [--json]` | Batch scrape URL list → JSONL |
| `fireclaude search "<query>" [--limit N] [--json]` | Web search via SearxNG |
| `fireclaude map <url> [--json]` | Map all URLs on a site |
| `fireclaude crawl <url> [--limit N] [--out dir] [--json]` | Crawl site → markdown files |
| `fireclaude extract <url> --schema <file.json> [--prompt STR] [--json]` | JSON-schema extract via Ollama |
| `fireclaude changes <url> [--diff] [--json]` | Change tracking against SQLite baseline |
| `fireclaude webhook-listen [--port N] [--json]` | Ephemeral HTTP receiver, logs POSTs as JSON lines |
| `fireclaude model list\|pull\|swap\|current` | Manage Ollama models |
| `fireclaude health` | API reachability check |
| `fireclaude logs [service]` | Tail container logs |

## Agentic use

Agent-safe JSON endpoints:

```bash
# Dep + health check — returns {deps, containers, models}
fireclaude doctor --json | jq '.deps.docker'

# Container status — returns [{service, state}, ...]
fireclaude status --json | jq 'length'

# Scrape
fireclaude scrape https://example.com --json | jq '.data.markdown'

# Search
fireclaude search "rust async runtime" --limit 5 --json | jq '.data[].url'

# Map a site
fireclaude map https://docs.anthropic.com --json | jq '.links | length'

# Extract structured data
fireclaude extract https://news.ycombinator.com \
  --schema schema.json \
  --prompt "Extract the top 3 story titles and URLs" \
  --json | jq '.data.json'

# Change tracking
fireclaude changes https://example.com --json
# → {"url":"...","changed":false,"current_hash":"...","diff_bytes":0,"scraped_at":...}
```

## JSON-schema extract

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

fireclaude extract https://news.ycombinator.com \
  --schema schema.json \
  --prompt "Extract the top story." \
  --json | jq '.data.json'
```

Routes through the `ollama` container (llama3.2:3b by default). First request cold-starts the model (~5–10s).

## Model swap

```bash
fireclaude model list
fireclaude model pull qwen2.5:7b
fireclaude model swap qwen2.5:7b
fireclaude model current
```

## Change tracking

```bash
fireclaude changes https://example.com          # first run → changed
fireclaude changes https://example.com          # second run → unchanged
fireclaude changes https://example.com --diff   # show unified diff
fireclaude changes https://example.com --json   # agent-friendly output
```

Change history stored in SQLite at `~/.fireclaude/changes.db` (override with `CHANGES_DB_PATH`).

## Webhook testing

```bash
fireclaude webhook-listen --json &
# Each POST to :4321/webhook emits a JSON line:
# {"timestamp":"...","method":"POST","path":"/webhook","headers":{...},"body":{...}}

fireclaude webhook-listen --port 9999
```

## Turnstile / CAPTCHA solver (optional)

Add to your `.env` (disabled by default):

```env
TURNSTILE_SOLVER=capmonster       # or: 2captcha
TURNSTILE_SOLVER_API_KEY=your_key
```

## Honest limits

| Limit | Detail |
|---|---|
| Cloudflare 403 | No Fire-engine; CF IP reputation blocks ~50–60% of CF-protected pages. |
| No Fire-engine | Cloud-only antibot bypass not available self-hosted. |
| IP rotation | Bring your own proxy via `PROXY_SERVER` env. |
| LLM quality | llama3.2:3b extracts simple schemas well; complex extraction may need qwen2.5:7b. |
| First model pull | ~2 GB download on first install. Subsequent starts are instant. |

## How patches work

Six `git diff` patches in `docker/patches/` are applied against firecrawl SHA `0ae6387b762c7450190eb7d8f9f7b81b7adfcaab`:

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
fireclaude teardown           # stop + prompt to remove clone + volumes
fireclaude teardown --purge   # stop + remove everything without prompts
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Security

See [SECURITY.md](SECURITY.md).

## License

MIT — see [LICENSE](LICENSE).

---

<details>
<summary>Alternative install (no Node.js)</summary>

If you don't have Node.js / npm:

```bash
# pinned release
curl -sSL https://raw.githubusercontent.com/sannidhyas/fireclaude/v0.5.0/install.sh | bash

# or clone first
git clone https://github.com/sannidhyas/fireclaude
cd fireclaude && ./install.sh
```

Override install location:
```bash
FIRECRAWL_INSTALL_DIR=/opt/firecrawl ./install.sh
```

</details>
