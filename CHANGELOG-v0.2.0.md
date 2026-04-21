# v0.2.0 — agentic CLI + marketplace + CI (2026-04-21)

## New features

- **`fc extract <url> --schema <file.json> [--prompt STR] [--json]`** — structured JSON extraction via local Ollama using a JSON Schema file.
- **`fc model list/pull/swap/current`** — manage Ollama models from the CLI. `swap` rewrites `.env` and hot-reloads the API container.
- **`fc changes <url> [--diff] [--json]`** — content change tracking backed by SQLite at `~/.fireclaude/changes.db`. Returns hash comparison and optional unified diff.
- **`fc webhook-listen [--port N] [--json]`** — ephemeral HTTP receiver that emits one JSON line per incoming POST. Useful for testing Firecrawl webhook callbacks.
- **`--json` flag** on all existing subcommands (`scrape`, `search`, `map`, `crawl`, `batch`) — returns full raw API response for agent-friendly piping.

## Infrastructure

- **`marketplace.json`** — `/plugin marketplace add sannidhyas/fireclaude` now works.
- **`package.json`** — `npm install -g fireclaude` installs the `fc` binary globally.
- **GitHub Actions CI** — `ubuntu-latest`, installs stack, runs `test_fc.sh` (9 tests), tears down. Concurrency cancel-in-progress per branch.
- **9-test skill harness** at `skills/fireclaude/tests/test_fc.sh` covering all subcommands.

## Optional / disabled by default

- **Turnstile solver patch** (`docker/patches/playwright-turnstile.ts.patch`) — supports CapMonster and 2captcha. Enable with `TURNSTILE_SOLVER` + `TURNSTILE_SOLVER_API_KEY` env vars.
- **`env.example` additions** — residential proxy block, Turnstile solver block, change tracking path, webhook URL/HMAC.

## Backward compatibility

All changes are additive. Default output for existing subcommands is unchanged when `--json` is absent. v0.1.0 install scripts continue to work.
