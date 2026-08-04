#!/usr/bin/env python3
"""Flash sale load test.

Fires N concurrent reservation requests at a single flash sale and reports
success/sold-out counts plus latency percentiles. Uses only the standard
library so there is nothing to pip install.

Usage:
    docker-compose up -d          # app + sidekiq + redis + postgres
    python3 loadtest/load_test.py --requests 500 --concurrency 150

    # Or against a specific sale / host:
    python3 loadtest/load_test.py --sale-id 3 --base-url http://localhost:3000

The pass condition printed at the end checks the one property that matters:
successes never exceed the inventory that was live when the test started.
"""

import argparse
import json
import statistics
import sys
import time
import urllib.error
import urllib.request
import uuid
from concurrent.futures import ThreadPoolExecutor


def fetch_dashboard(base_url):
    with urllib.request.urlopen(f"{base_url}/dashboard", timeout=10) as resp:
        return json.loads(resp.read())


def resolve_sale(base_url, sale_id):
    """Pick the target sale and its live inventory from the dashboard."""
    dashboard = fetch_dashboard(base_url)
    sales = dashboard.get("active_flash_sales", [])
    if not sales:
        sys.exit("No active flash sales found. Run `docker-compose up` (seeds a demo sale) first.")

    if sale_id is None:
        sale = sales[0]
    else:
        matches = [s for s in sales if s["id"] == sale_id]
        if not matches:
            sys.exit(f"Flash sale {sale_id} is not active. Active ids: {[s['id'] for s in sales]}")
        sale = matches[0]

    return sale["id"], sale["live_inventory"]


def reserve(base_url, sale_id, buyer_id):
    """One reservation attempt. Returns (outcome, latency_seconds)."""
    body = json.dumps({"buyer_id": buyer_id}).encode()
    req = urllib.request.Request(
        f"{base_url}/api/flash_sales/{sale_id}/reserve",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    start = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            payload = json.loads(resp.read())
            outcome = "reserved" if payload.get("reserved") else payload.get("reason", "unknown")
    except urllib.error.HTTPError as e:
        try:
            payload = json.loads(e.read())
            outcome = payload.get("reason", f"http_{e.code}")
        except (json.JSONDecodeError, ValueError):
            outcome = f"http_{e.code}"
    except (urllib.error.URLError, TimeoutError):
        outcome = "connection_error"
    return outcome, time.perf_counter() - start


def percentile(sorted_values, pct):
    if not sorted_values:
        return 0.0
    index = min(len(sorted_values) - 1, round(pct / 100 * (len(sorted_values) - 1)))
    return sorted_values[index]


def main():
    parser = argparse.ArgumentParser(description="Concurrent flash sale reservation load test")
    parser.add_argument("--base-url", default="http://localhost:3000")
    parser.add_argument("--sale-id", type=int, default=None, help="defaults to the first active sale")
    parser.add_argument("--requests", type=int, default=500, help="total reservation attempts")
    parser.add_argument("--concurrency", type=int, default=150, help="worker threads")
    args = parser.parse_args()

    sale_id, starting_inventory = resolve_sale(args.base_url, args.sale_id)
    run_tag = uuid.uuid4().hex[:8]
    print(f"Target: sale #{sale_id} | live inventory: {starting_inventory} | "
          f"{args.requests} requests @ concurrency {args.concurrency}\n")

    wall_start = time.perf_counter()
    with ThreadPoolExecutor(max_workers=args.concurrency) as pool:
        futures = [
            pool.submit(reserve, args.base_url, sale_id, f"lt-{run_tag}-{i}")
            for i in range(args.requests)
        ]
        results = [f.result() for f in futures]
    wall = time.perf_counter() - wall_start

    outcomes = {}
    for outcome, _ in results:
        outcomes[outcome] = outcomes.get(outcome, 0) + 1
    latencies = sorted(lat for _, lat in results)
    successes = outcomes.get("reserved", 0)

    print(f"{'Total requests':<22}{args.requests}")
    for outcome in sorted(outcomes):
        print(f"{outcome:<22}{outcomes[outcome]}")
    print()
    print(f"{'Wall time':<22}{wall:.2f}s ({args.requests / wall:.0f} req/s)")
    print(f"{'Mean latency':<22}{statistics.mean(latencies) * 1000:.1f} ms")
    print(f"{'p50':<22}{percentile(latencies, 50) * 1000:.1f} ms")
    print(f"{'p95':<22}{percentile(latencies, 95) * 1000:.1f} ms")
    print(f"{'p99':<22}{percentile(latencies, 99) * 1000:.1f} ms")
    print()

    ending_inventory = None
    try:
        _, ending_inventory = resolve_sale(args.base_url, sale_id)
        print(f"{'Ending inventory':<22}{ending_inventory}")
    except SystemExit:
        pass  # sale may have sold out and left the active list untouched; inventory read is best-effort

    if successes <= starting_inventory:
        print(f"\nPASS: {successes} successes against {starting_inventory} units. Zero oversells.")
        sys.exit(0)

    print(f"\nFAIL: {successes} successes against {starting_inventory} units. OVERSOLD.")
    sys.exit(1)


if __name__ == "__main__":
    main()
