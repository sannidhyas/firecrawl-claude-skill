# Security Policy

## Supported versions

| Version | Supported |
|---------|-----------|
| 0.2.x   | Yes       |
| 0.1.x   | No        |

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Email: **shrutiatulit@gmail.com** with subject line `[firecrawl-claude-skill] Security Disclosure`.

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Any suggested fix (optional)

You will receive an acknowledgement within 72 hours and a resolution timeline within 7 days.

## Scope

- `fc` CLI scripts and Python helpers
- `install.sh` / `uninstall.sh`
- Docker patches that modify Firecrawl/Playwright behavior
- Secrets handling (`.env`, API keys)

## Out of scope

- Vulnerabilities in upstream Firecrawl, Ollama, SearxNG, or Playwright itself — report those to their respective projects.
- Issues requiring physical access to the host machine.

## Notes

- `.env` files are excluded from git by `.gitignore`. Never commit secrets.
- The `TURNSTILE_SOLVER_API_KEY` and `PROXY_PASSWORD` values should be stored only in `.env`, never in code or issue comments.
