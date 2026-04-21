#!/usr/bin/env python3
"""fc-changes.py — change tracking helper for fc changes <url>"""
import argparse
import hashlib
import json
import os
import sqlite3
import sys
import time
import urllib.request
import difflib

DB_SCHEMA = """
CREATE TABLE IF NOT EXISTS changes (
    url TEXT NOT NULL,
    scraped_at INTEGER NOT NULL,
    content_hash TEXT NOT NULL,
    markdown TEXT NOT NULL,
    PRIMARY KEY (url, scraped_at)
);
"""


def get_db(path: str) -> sqlite3.Connection:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    conn = sqlite3.connect(path)
    conn.execute(DB_SCHEMA)
    conn.commit()
    return conn


def scrape(firecrawl_url: str, url: str) -> str:
    payload = json.dumps({
        "url": url,
        "formats": ["markdown"],
        "onlyMainContent": True,
    }).encode()
    req = urllib.request.Request(
        f"{firecrawl_url}/v2/scrape",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read())
    except Exception as e:
        print(json.dumps({"error": str(e)}), file=sys.stderr)
        sys.exit(1)
    markdown = (data.get("data") or {}).get("markdown") or ""
    if not markdown:
        print(json.dumps({"error": "no markdown in response", "raw": data}), file=sys.stderr)
        sys.exit(1)
    return markdown


def sha256(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def last_row(conn: sqlite3.Connection, url: str):
    cur = conn.execute(
        "SELECT scraped_at, content_hash, markdown FROM changes WHERE url=? ORDER BY scraped_at DESC LIMIT 1",
        (url,),
    )
    return cur.fetchone()


def main():
    parser = argparse.ArgumentParser(description="Track content changes for a URL")
    parser.add_argument("--url", required=True)
    parser.add_argument("--db", required=True)
    parser.add_argument("--firecrawl-url", default="http://localhost:3002")
    parser.add_argument("--diff", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    conn = get_db(args.db)
    markdown = scrape(args.firecrawl_url, args.url)
    current_hash = sha256(markdown)
    now = int(time.time())

    prev = last_row(conn, args.url)
    previous_hash = prev[1] if prev else None
    previous_markdown = prev[2] if prev else None
    changed = previous_hash != current_hash if previous_hash else True

    # Always store current scrape
    conn.execute(
        "INSERT OR REPLACE INTO changes (url, scraped_at, content_hash, markdown) VALUES (?,?,?,?)",
        (args.url, now, current_hash, markdown),
    )
    conn.commit()

    diff_bytes = 0
    diff_text = ""
    if previous_markdown and changed:
        diff_lines = list(difflib.unified_diff(
            previous_markdown.splitlines(keepends=True),
            markdown.splitlines(keepends=True),
            fromfile="previous",
            tofile="current",
        ))
        diff_text = "".join(diff_lines)
        diff_bytes = len(diff_text.encode())

    result = {
        "url": args.url,
        "changed": changed,
        "previous_hash": previous_hash,
        "current_hash": current_hash,
        "diff_bytes": diff_bytes,
        "scraped_at": now,
    }

    if args.json:
        print(json.dumps(result))
    else:
        status = "changed" if changed else "unchanged"
        print(f"{args.url}: {status}")
        if args.diff and diff_text:
            print(diff_text)


if __name__ == "__main__":
    main()
