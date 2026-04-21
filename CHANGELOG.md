# Changelog

All notable changes to this project will be documented in this file.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] — 2026-04-21 — stable

First stable release. Public API frozen. Breaking changes from this point
require a major bump.

### Promoted from 1.0.0-rc1

Identical codebase to `1.0.0-rc1`. Published to npm `latest` dist-tag.

### Public API (frozen)

- **Binary:** `fireclaude` (optional `fc` alias via `fireclaude alias install`)
- **Subcommands:** `setup`, `start`, `stop`, `teardown`, `upgrade`, `version`,
  `doctor`, `status`, `model list|pull`, `ollama-start`, `alias install|uninstall`
- **Env vars:** `OLLAMA_MODE` (`auto`|`host`|`container`), `FIRECLAUDE_INSTALL_SH`,
  `FIRECLAUDE_BIN`, `NO_COLOR`
- **Skill layout:** `skills/fireclaude/`
- **JSON shapes:** `doctor --json`, `status --json` (documented in README)

### Install

```bash
npm install -g fireclaude
fireclaude setup
```

### Upgrade from 0.x

See [MIGRATION-0.x-to-1.0.md](./MIGRATION-0.x-to-1.0.md).

### Known limits shipped honestly

- CI-verified on Linux only. macOS branches in `install.sh` are exercised in
  local smoke but not continuously in CI.
- GPU acceleration requires host Ollama (`OLLAMA_MODE=host` or `auto`-resolved
  to host). Bundled container is CPU-only.
- Firecrawl upstream is pinned to a git SHA; bumping is a deliberate
  `fireclaude upgrade --sha <SHA>` op.

---

## [1.0.0-rc1] — 2026-04-21 — release candidate

First release candidate for 1.0.0 stable. No new features vs 0.6.3. Gate this at
npm dist-tag `next` for soak testing.

### Promotion checklist (must all pass before `1.0.0` final)

- [ ] CI green on master for ≥3 consecutive runs after this tag
- [ ] `fireclaude setup` verified on fresh Fedora and one other OS (Ubuntu or macOS)
- [ ] No P1 issues reported against rc1 during soak window
- [ ] `MIGRATION-0.x-to-1.0.md` reviewed by at least one external user

### Public API frozen at this point

- Binary name: `fireclaude` (with optional `fc` alias via `fireclaude alias install`)
- Subcommands: `setup`, `start`, `stop`, `teardown`, `upgrade`, `version`, `doctor`,
  `status`, `model list|pull`, `ollama-start`, `alias install|uninstall`
- Env vars: `OLLAMA_MODE` (`auto`|`host`|`container`), `FIRECLAUDE_INSTALL_SH`,
  `FIRECLAUDE_BIN`, `NO_COLOR`
- Skill format: `skills/fireclaude/` layout
- JSON shapes: `doctor --json`, `status --json` (documented in README)

Breaking changes post-1.0 require a major bump.

### Install

```bash
npm install -g fireclaude@next
# or, when promoted:
npm install -g fireclaude
```

See [MIGRATION-0.x-to-1.0.md](./MIGRATION-0.x-to-1.0.md) for upgrade from 0.x.

---

## [0.6.3] — 2026-04-21 — fix: valid marketplace schema + robust searxng copy

- Rewrite `.claude-plugin/marketplace.json` to match Claude Code marketplace
  schema (`owner` object + `plugins` array). Previous shape (`skills[]` /
  `author` / `install`) failed `/plugin marketplace add` with
  `owner: expected object, received undefined, plugins: expected array, received undefined`.
- `install.sh` now skips searxng settings copy when content is identical and
  warns + continues when target is owned by the searxng container UID, instead
  of aborting with `Permission denied`.
- Version bumps: `package.json`, `plugin.json`, `package-lock.json` → 0.6.3.

No API changes.

---

## [0.6.2] — 2026-04-21 — chore: sync marketplace + version alignment

- Align `.claude-plugin/marketplace.json`, `.claude-plugin/plugin.json`,
  `package.json`, `package-lock.json` all at 0.6.2. Marketplace was stuck at
  0.3.0 while npm/plugin shipped 0.6.1.
- Refresh marketplace description to match current scope.

No API changes.

---

## [0.6.1] — 2026-04-21 — fix: ora/chalk ESM crash

- Downgrade `ora` → 5.4.1 + `chalk` → 4.1.2 (last CJS versions) to fix TypeError on `fireclaude setup`.
- No API changes.

---

## [0.6.0] — 2026-04-21 — ollama host mode + logo + TUI

- **OLLAMA_MODE** env (`auto`|`host`|`container`). `auto` (default) probes host daemon at `http://localhost:11434`; skips the bundled container when reachable. `host` fails setup if unreachable. `container` preserves previous behaviour.
- **`fireclaude ollama-start`** — launch host ollama via `systemctl --user` (Linux) or `brew services` / `launchctl` (macOS). Falls back to `nohup ollama serve` when no service manager entry found.
- **Logo**: `assets/logo.svg` (512×512 SVG, flame + purple wordmark) + `assets/logo-ascii.txt`. README header updated.
- **CLI animations**: `ora` spinner on long ops (`setup`, `start`, `upgrade`). `gradient-string` fire gradient on ASCII splash. `chalk` for colour. Degrades to plain text when `!process.stdout.isTTY`, `NO_COLOR=1`, or `--no-animate`.
- **`fireclaude doctor --json`** now includes `.ollama = { mode, endpoint, reachable, models, gpu: { detected, name } }`.
- **`fireclaude model list|pull`** route to host daemon when `OLLAMA_MODE` is `host` or `auto` (resolved to host).
- **VERSIONING.md** — documents 0.x → 1.0.0 stability path.

No breaking changes from 0.5.0.

---

## [0.5.0] — 2026-04-21 — rename binary to `fireclaude`

**Breaking:** the `fc` binary shipped by npm is renamed to `fireclaude` to avoid
collision with the bash builtin `fc` (fix-command history editor) and fontconfig
`/usr/bin/fc` on Linux.

### Changed

- `package.json` `bin` entry: `fc` → `fireclaude` (points to renamed shim `fireclaude-bin.js`).
- All user-facing CLI usage text updated from `fc <cmd>` to `fireclaude <cmd>`.
- CI workflow: `FC_BIN` variable renamed to `FIRECLAUDE_BIN`; resolved via `$(npm prefix -g)/bin/fireclaude`.
- Test harness: `skills/fireclaude/tests/test_fc.sh` → `test_fireclaude.sh`; internal `FC_BIN` → `FIRECLAUDE_BIN`.
- `package.json` and `.claude-plugin/plugin.json` version bumped to `0.5.0`.

### Added

- **`fireclaude alias install [--yes]`** — writes `alias fc='fireclaude'` to `~/.bashrc` and `~/.zshrc` if present. Prompts before writing; `--yes` auto-confirms. Idempotent.
- **`fireclaude alias uninstall [--yes]`** — removes the alias lines written by `alias install`.

### Migration

```bash
npm install -g fireclaude@0.5.0
# The binary is now `fireclaude`. To keep the short `fc` muscle memory:
fireclaude alias install
source ~/.bashrc   # or open a new shell
fc setup           # works via alias
```

If you had `fc setup` in scripts, replace with `fireclaude setup`.

### Backward compatible

- `install.sh` curl-bash flow unchanged.
- All subcommands and flags identical; only the top-level binary name changes.
- The underlying bash script remains at `skills/fireclaude/scripts/fc` (on-disk name unchanged).

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
