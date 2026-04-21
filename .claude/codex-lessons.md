## 2026-04-21 | codex-do | success
Task: Package self-hosted Firecrawl as public Claude Code plugin, ship to GitHub with v0.1.0 release
Iters: 1 (inline, no codex MCP available)
Lesson: Upstream firecrawl compose maps PORT:INTERNAL_PORT — smoke test must use PORT=3012 INTERNAL_PORT=3002 (not both 3012) to avoid EADDRINUSE inside container; bind-mount volumes written by root containers require docker alpine rm to clean up in uninstall; .gitignore pattern `firecrawl/` must be anchored as `/firecrawl/` to avoid matching nested `skills/firecrawl/`
