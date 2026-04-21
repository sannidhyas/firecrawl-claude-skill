# Changelog

All notable changes to this project will be documented in this file.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.4.0] — 2026-04-21 — npm-only install flow

### Added

- **`fc setup [--install-dir PATH] [--model NAME]`** — first-run bootstrap. Resolves install.sh from: `$FIRECLAUDE_INSTALL_SH` env → npm global root → git repo root → URL download fallback.
- **`fc start`** — start stopped containers (`docker compose up -d`).
- **`fc stop`** — stop running containers (`docker compose stop`).
- **`fc teardown [--purge]`** — stop + remove stack. `--purge` auto-answers yes to all prompts.
- **`fc upgrade [--sha GIT_SHA]`** — pull latest fireclaude npm, optionally pin firecrawl to a new SHA, re-apply patches, rebuild api + playwright-service, restart.
- **`fc version`** — print fireclaude version + installed firecrawl SHA + ollama models.
- **`fc doctor [--json]`** — dep check (docker, compose, git, curl, jq, python3, node) + container health + model presence. `--json` returns `{deps, containers, models}` for agent consumption.
- **`fc status --json`** — existing status command gains `--json` flag returning `[{service, state}]` array.
- **Install dir fallback chain** — `fc` now auto-locates install dir via `FIRECRAWL_INSTALL_DIR` → `FIRECLAUDE_INSTALL_DIR` → `~/.fireclaude/firecrawl`. Applies to start/stop/status/teardown/upgrade/logs/model.
- **README rewrite** — primary install is now `npm install -g fireclaude && fc setup`. curl-bash moved to collapsed `<details>` appendix. New CLI reference table. Agentic use section.
- **CI update** — bootstrap step uses `npm install -g ./ && fc setup --install-dir /tmp/fc-ci --model llama3.2:3b` instead of direct `./install.sh`.
- **Tests 10–12** — `fc version` semver check, `fc doctor --json` shape check, `fc status --json` shape check.

### Backward compatible

- `install.sh` still exists and is directly callable (curl-bash and git-clone flows preserved).
- `FIRECRAWL_INSTALL_DIR` continues to work unchanged.
- All v0.3.0 `fc` subcommands unchanged.

---

## [0.3.0] — 2026-04-21 — rename to Fireclaude

### Changed

- Project renamed from `firecrawl-claude-skill` to `fireclaude` (portmanteau of Firecrawl + Claude).
- GitHub repo moved to `sannidhyas/fireclaude` (old URL redirects automatically).
- npm package is now `fireclaude`; old `firecrawl-claude-skill` deprecated (still on registry for existing installs).
- Skill directory: `skills/firecrawl/` → `skills/fireclaude/`.
- Install dir default: `~/.firecrawl-claude-skill/` → `~/.fireclaude/`.
- No behavior changes. All v0.2.0 features carry forward.

---

## [0.2.0] — 2026-04-21

### Added

- **`fc extract <url> --schema <file.json> [--prompt STR] [--json]`** — POST /v2/scrape with JSON schema extraction via local Ollama. Schema is a standard JSON Schema file.
- **`fc model list`** — list Ollama models in container as JSON array.
- **`fc model pull <name>`** — pull a model into the ollama container.
- **`fc model swap <name>`** — pull model, rewrite `MODEL_NAME` in `.env`, recreate API container, wait for health.
- **`fc model current`** — print the effective `MODEL_NAME` from `.env`.
- **`fc changes <url> [--diff] [--json]`** — scrape + compare content hash against last known value in SQLite (`~/.fireclaude/changes.db`). `--diff` shows unified diff. `--json` returns structured result.
- **`fc webhook-listen [--port N] [--json]`** — ephemeral HTTP server that logs each incoming POST as a JSON line on stdout. Default port 4321. Ctrl+C to stop.
- **`--json` flag** on all existing subcommands (`scrape`, `search`, `map`, `crawl`, `batch`) — returns full API response as JSON instead of extracted human-friendly output.
- **`fc-changes.py`** — Python helper for change tracking with SQLite backend.
- **`fc-webhook-listen.py`** — Python webhook receiver using `http.server`.
- **`docker/patches/playwright-turnstile.ts.patch`** — optional Turnstile/CAPTCHA solver patch. Disabled by default; enabled by setting `TURNSTILE_SOLVER` + `TURNSTILE_SOLVER_API_KEY` env vars. Supports CapMonster and 2captcha backends.
- **`docker/env.example`** additions: residential proxy block, Turnstile solver block, change tracking DB path, webhook URL + HMAC secret.
- **`skills/fireclaude/tests/test_fc.sh`** — bash test harness: 9 test cases covering all new and existing subcommands.
- **`skills/fireclaude/tests/fixtures/example-schema.json`** — fixture JSON schema for extract tests.
- **`.claude-plugin/marketplace.json`** — Claude Code marketplace metadata so `/plugin marketplace add sannidhyas/fireclaude` works.
- **`package.json`** at repo root — npm package `fireclaude` exposing `fc` binary globally.
- **`.github/workflows/ci.yml`** — GitHub Actions CI: install stack on ubuntu-latest, run `test_fc.sh`, tear down. Concurrency cancel-in-progress per ref.
- **`CONTRIBUTING.md`**, **`SECURITY.md`**, GitHub issue templates, PR template.

### Changed

- `fc` usage text updated to list all new subcommands.
- `install.sh` creates `$HOME/.fireclaude/` dir for changes DB.
- `README.md` — new sections: Agentic use, Model swap (fc CLI), Change tracking, Webhook testing, Marketplace install, npm install.

### Backward compatible

All new features are additive. Default output for existing subcommands is unchanged when `--json` is absent.

---

## [0.1.0] — 2026-04-01

### Added

- Initial release: self-hosted Firecrawl packaged as a Claude Code skill.
- Docker stack: Firecrawl API + Playwright (stealth) + SearxNG + Ollama (llama3.2:3b).
- `fc` CLI: `scrape`, `batch`, `search`, `map`, `crawl`, `health`, `status`, `logs`.
- Six `git diff` patches applied at install time against pinned upstream SHA.
- `install.sh` with smoke tests (scrape, search, JSON extract).
- `uninstall.sh`.
- `SELF_HOST_ANTIBOT_RETRIES` / `SELF_HOST_ANTIBOT_WAIT_MS` antibot tuning env vars.
- `PROXY_SERVER` / `PROXY_USERNAME` / `PROXY_PASSWORD` proxy support.
- MIT license.
