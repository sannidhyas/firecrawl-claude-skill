# Migration guide: fireclaude 0.x → 1.0

This guide covers every breaking change between the first public `0.1.0` and
`1.0.0`. If you are already on `0.6.x` most items are no-ops; they are listed
for completeness.

> `1.0.0-rc1` is currently published to npm under the `next` dist-tag. Promote
> with `npm install -g fireclaude@next`. Final `1.0.0` is published to `latest`
> once the [promotion checklist](./CHANGELOG.md#promotion-checklist-must-all-pass-before-100-final)
> in CHANGELOG.md is fully ticked.

---

## tl;dr upgrade for most users

```bash
npm uninstall -g firecrawl-claude 2>/dev/null || true   # old name, if ever installed
npm install -g fireclaude@next
fireclaude alias install                                 # optional: restore `fc`
fireclaude upgrade                                       # pulls latest firecrawl + rebuilds
fireclaude doctor                                        # verify
```

That's it for standard installs. Read on if you customised env vars, scripts,
or skill paths.

---

## 1. Binary rename: `fc` → `fireclaude`  *(breaking, since 0.5.0)*

`fc` collides with the bash builtin `fc` (fix-command history editor) and the
fontconfig binary at `/usr/bin/fc` on Linux. We renamed the npm-provided
binary to `fireclaude`.

**Migration:**

- Replace `fc <cmd>` with `fireclaude <cmd>` in scripts, CI, docs.
- If you want muscle memory back: `fireclaude alias install` writes
  `alias fc='fireclaude'` into `~/.bashrc` / `~/.zshrc` (idempotent).
  Remove with `fireclaude alias uninstall`.
- The on-disk bash script is still at `skills/fireclaude/scripts/fc` — this is
  internal and not part of the public API.

## 2. Env var rename: `FC_BIN` → `FIRECLAUDE_BIN`  *(breaking, since 0.5.0)*

Only relevant if you referenced `FC_BIN` in CI or test harness glue. Replace
with `FIRECLAUDE_BIN`. The resolved path is typically
`$(npm prefix -g)/bin/fireclaude`.

## 3. `OLLAMA_MODE` env var added  *(non-breaking default, since 0.6.0)*

New env var controls where the Ollama daemon runs:

| Value | Behaviour |
|-------|-----------|
| `auto` *(default)* | Probe host daemon at `http://localhost:11434`. Use host if reachable, else bundled container. |
| `host` | Fail setup if host daemon unreachable. |
| `container` | Force the bundled container (pre-0.6.0 behaviour). |

**Migration:** set `OLLAMA_MODE=container` if you relied on the container
always running (e.g. GPU pass-through on a host that also has ollama idle).

## 4. Install flow is now npm-only  *(breaking, since 0.4.0)*

The `curl | bash` script still works for bootstrapping, but the authoritative
install is:

```bash
npm install -g fireclaude
fireclaude setup
```

`fireclaude setup` resolves `install.sh` from (in order):
`$FIRECLAUDE_INSTALL_SH` → npm global root → git repo root → download fallback.

If you hand-rolled a wrapper around the raw bash script, switch to the npm
binary — it is the supported surface going forward.

## 5. Plugin / marketplace schema change  *(breaking, since 0.6.3)*

`.claude-plugin/marketplace.json` was rewritten to match the Claude Code
marketplace schema (`owner` object, `plugins` array). If you forked the repo
and maintain your own marketplace entry, mirror the shape in
[`marketplace.json`](./.claude-plugin/marketplace.json).

## 6. Skill path unchanged

`skills/fireclaude/` layout is stable and frozen at 1.0. New skill assets
(scripts, templates) are additive; file removals or renames within this tree
require a major bump post-1.0.

---

## Known limits at 1.0.0

Shipped honestly, not hidden:

- Tested on Linux (Fedora 42) and, as of rc1 soak, Ubuntu 22.04. macOS works
  in principle (install script has macOS branches) but is not continuously
  verified in CI.
- GPU acceleration requires host Ollama (`OLLAMA_MODE=host` or `auto` resolved
  to host). The bundled container is CPU-only.
- `searxng` settings file copy requires that the target path is either absent
  or writable by the invoking user — if it is owned by the searxng container
  UID we warn and continue without overwriting.
- Firecrawl upstream pin is a git SHA; bumping it is a deliberate
  `fireclaude upgrade --sha <SHA>` operation, not automatic.

Report issues: https://github.com/sannidhyas/fireclaude/issues
