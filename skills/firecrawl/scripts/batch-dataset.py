#!/usr/bin/env python3
"""Batch-scrape URLs through self-hosted Firecrawl, write a JSONL research dataset."""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

FC_URL = os.environ.get("FIRECRAWL_URL", "http://localhost:3002")


def post(path: str, payload: dict) -> dict:
    req = urllib.request.Request(
        f"{FC_URL}{path}",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read())


def get(path: str) -> dict:
    with urllib.request.urlopen(f"{FC_URL}{path}", timeout=60) as r:
        return json.loads(r.read())


def kick_off(urls: list[str], fmt: str, only_main: bool) -> str:
    resp = post(
        "/v2/batch/scrape",
        {"urls": urls, "formats": [fmt], "onlyMainContent": only_main},
    )
    job_id = resp.get("id") or resp.get("jobId")
    if not job_id:
        raise RuntimeError(f"no job id in batch response: {resp}")
    return job_id


def poll(job_id: str, interval: float, timeout: float) -> dict:
    deadline = time.time() + timeout
    last_completed = -1
    while time.time() < deadline:
        resp = get(f"/v2/batch/scrape/{job_id}")
        status = resp.get("status")
        completed = resp.get("completed", 0)
        total = resp.get("total", "?")
        if completed != last_completed:
            print(f"  {status}: {completed}/{total}", file=sys.stderr)
            last_completed = completed
        if status in ("completed", "failed", "cancelled"):
            return resp
        time.sleep(interval)
    raise TimeoutError(f"batch {job_id} not done within {timeout}s")


def to_record(item: dict, fmt: str) -> dict:
    meta = item.get("metadata", {}) or {}
    return {
        "url": meta.get("url") or meta.get("sourceURL") or item.get("url"),
        "title": meta.get("title"),
        "description": meta.get("description"),
        "status_code": meta.get("statusCode"),
        fmt: item.get(fmt),
        "status": "ok" if item.get(fmt) else "error",
        "error": item.get("error"),
        "fetched_at": datetime.now(timezone.utc).isoformat(),
    }


def run(
    urls_path: str,
    out_path: str,
    fmt: str,
    only_main: bool,
    chunk: int,
    poll_interval: float,
    timeout: float,
) -> None:
    urls = [u.strip() for u in open(urls_path) if u.strip() and not u.strip().startswith("#")]
    if not urls:
        raise SystemExit("no urls in input file")
    print(f"batching {len(urls)} urls in chunks of {chunk} -> {out_path}", file=sys.stderr)

    ok = err = 0
    with open(out_path, "w") as out:
        for i in range(0, len(urls), chunk):
            batch = urls[i : i + chunk]
            print(f"chunk {i // chunk + 1}: {len(batch)} urls", file=sys.stderr)
            try:
                job_id = kick_off(batch, fmt, only_main)
                print(f"  job id: {job_id}", file=sys.stderr)
                resp = poll(job_id, poll_interval, timeout)
            except (urllib.error.URLError, RuntimeError, TimeoutError) as e:
                print(f"  chunk failed: {e}", file=sys.stderr)
                for u in batch:
                    rec = {
                        "url": u,
                        "status": "error",
                        "error": str(e),
                        "fetched_at": datetime.now(timezone.utc).isoformat(),
                    }
                    out.write(json.dumps(rec, ensure_ascii=False) + "\n")
                    err += 1
                continue

            for item in resp.get("data", []) or []:
                rec = to_record(item, fmt)
                out.write(json.dumps(rec, ensure_ascii=False) + "\n")
                if rec["status"] == "ok":
                    ok += 1
                else:
                    err += 1

    print(f"done: {ok} ok, {err} error -> {out_path}", file=sys.stderr)


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--urls", required=True, help="file with one URL per line")
    p.add_argument("--out", default="dataset.jsonl")
    p.add_argument("--format", default="markdown", choices=["markdown", "html", "links", "rawHtml"])
    p.add_argument("--only-main", action="store_true", default=False)
    p.add_argument("--chunk", type=int, default=10, help="URLs per batch job")
    p.add_argument("--poll-interval", type=float, default=2.0)
    p.add_argument("--timeout", type=float, default=600.0, help="per-chunk timeout in seconds")
    args = p.parse_args()
    run(args.urls, args.out, args.format, args.only_main, args.chunk, args.poll_interval, args.timeout)


if __name__ == "__main__":
    main()
