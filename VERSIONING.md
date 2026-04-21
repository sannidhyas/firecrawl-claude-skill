# Versioning

fireclaude follows SemVer.

- **0.x.y** — pre-stable. Breaking changes allowed between any release.
- **1.0.0** — stable public API. Breaking changes only on major bumps.

## Stability checklist before 1.0.0 (historical)

- [x] API surface frozen: subcommands, env vars, skill format.
- [x] Install verified on Linux (Fedora). macOS branches exercised locally;
      continuous CI is Linux-only at 1.0.
- [x] CI green on master at 1.0 tag.
- [x] README polished, known limits documented honestly in CHANGELOG.
- [x] Migration guide from 0.x written: [MIGRATION-0.x-to-1.0.md](./MIGRATION-0.x-to-1.0.md).

## Current state (1.0.0)

Stable. Public API is frozen:

- Binary name, subcommands, flags, env vars, skill layout, and JSON shapes
  documented in [CHANGELOG.md](./CHANGELOG.md#100--2026-04-21--stable).
- Additive changes land on minor bumps (1.1.0, 1.2.0, …).
- Breaking changes require a major bump (2.0.0) with a migration guide.
