# Contributing

## Development setup

```bash
git clone https://github.com/sannidhyas/fireclaude
cd fireclaude

# Bootstrap stack (first time ~10–15 min)
FIRECRAWL_INSTALL_DIR=$HOME/.firecrawl-dev PORT=3002 ./install.sh
```

## Running tests locally

```bash
# Requires a live stack at FIRECRAWL_URL
FIRECRAWL_URL=http://localhost:3002 bash skills/fireclaude/tests/test_fc.sh
```

All 9 tests must pass before opening a PR.

## Adding a new `fc` subcommand

1. Add `cmd_<name>()` function in `skills/fireclaude/scripts/fc`.
2. Wire it into the `main()` case statement.
3. Add a `--json` flag that returns the raw API response.
4. Add a test case in `skills/fireclaude/tests/test_fc.sh`.
5. Document in `README.md` and `CHANGELOG.md`.

## Patches

Patches live in `docker/patches/` and are applied against firecrawl SHA `0ae6387b762c7450190eb7d8f9f7b81b7adfcaab`.

To update or add a patch:

```bash
# Make changes in the firecrawl repo
cd $FIRECRAWL_INSTALL_DIR
# ... edit files ...
git diff HEAD -- apps/playwright-service-ts/src/playwright.ts \
  > /path/to/fireclaude/docker/patches/my-patch.ts.patch
```

Keep patches minimal. Comment each hunk to explain why the change is needed.

## Commit convention

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add fc extract subcommand
fix: handle empty markdown in fc changes
docs: update README with model swap examples
ci: add concurrency cancel-in-progress
test: add webhook-listen test case
```

Include co-author line on AI-assisted commits:
```
Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

## Pull requests

- Open against `main` (or `master`).
- Fill out the PR template.
- Ensure CI is green before requesting review.
- Keep PRs focused — one feature or fix per PR.

## Reporting bugs

Use the GitHub issue tracker. Fill out the bug report template fully — especially the Docker version and OS.
