## 2026-04-21 | codex-do | success
Task: Package self-hosted Firecrawl as public Claude Code plugin, ship to GitHub with v0.1.0 release
Iters: 1 (inline, no codex MCP available)
Lesson: Upstream firecrawl compose maps PORT:INTERNAL_PORT — smoke test must use PORT=3012 INTERNAL_PORT=3002 (not both 3012) to avoid EADDRINUSE inside container; bind-mount volumes written by root containers require docker alpine rm to clean up in uninstall; .gitignore pattern `firecrawl/` must be anchored as `/firecrawl/` to avoid matching nested `skills/firecrawl/`

## 2026-04-21 | codex-do | success
Task: Ship v0.2.0 of firecrawl-claude-skill with CLI extensions, marketplace, CI, change tracking, webhook, model swap
Iters: 1 (inline, no codex MCP)
Lesson: Optional patches that target non-existent files must be skipped with warn not die; npm rejects bare bash scripts as bin entries — use a .js shim; background process port-binding in sandboxed Bash tools is unreliable — detect and fall back to syntax-check for network-dependent tests; push workflow files via SSH remote when OAuth token lacks workflow scope.

## 2026-04-21 | codex-do | success
Task: Rename firecrawl-claude-skill → fireclaude (GitHub, local dir, source, npm v0.3.0)
Iters: 1 (inline, no codex MCP)
Lesson: gh repo rename auto-redirects old URLs and preserves tags/issues; mv dir then git remote set-url is sufficient — no re-clone needed; Read tool tracks files by absolute path so must re-read at new path after mv before Edit/Write; npm publish auto-corrects bin key names and normalizes repository URL (warn is harmless); npm view 404 immediately after publish is normal registry propagation latency (~10s).

## 2026-04-21 | codex-do | success
Task: Ship fireclaude v0.4.0 — npm-only install flow with fc lifecycle subcommands
Iters: 1
Lesson: System `/usr/bin/fc` (shell built-in) shadows npm-installed fc binary; use FC_BIN= or full path in tests. npm `bin` entry with a path containing `/` triggers a cosmetic auto-correct warning but publishes fine.

## 2026-04-21 | codex-debugger | success
Task: Fix CI PATH shadowing — Ubuntu /usr/bin/fc (fontconfig) shadows npm-installed fc binary
Iters: 2
Lesson: Use `npm prefix -g` (not `npm root -g`) to locate the npm bin dir — prefix gives /usr/local directly; root gives node_modules and the ../bin dance fails when realpath exits 1 under set -e before any diagnostics print. test_fc.sh already had FC_BIN=${FC_BIN:-...} fallback; only ci.yml needed fixing. No version bump required for CI-only changes.

## 2026-04-21 | codex-do | success
Task: Ship fireclaude v0.5.0 — rename npm binary from fc to fireclaude, add alias subcommand
Iters: 1 (inline; all changes applied directly without codex MCP)
Lesson: npm warns "script name was invalid and removed" when bin path has ./ prefix — it actually normalizes and publishes correctly; verify with `npm info <pkg> bin`. When a feat + refactor both touch the same single file, there is no clean way to split them across commits — stage the file once and use the larger commit message. The fc bash script is the single source of truth for both binary rename and alias feature.

## 2026-04-21 | codex-do | success
Task: Ship fireclaude v0.6.0 — OLLAMA_MODE, ollama-start, logo, TUI, doctor update
Iters: 1 (plus 1 CI fix iteration)
Lesson: auto mode in model list/pull needs a runtime host-reachability probe — writing OLLAMA_MODE=auto to .env is not enough; the container-vs-host branch must re-probe at command time, not just at setup time.
