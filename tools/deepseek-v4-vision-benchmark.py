#!/usr/bin/env python3
"""Streaming DeepSeek V4 benchmark with concurrency and DSpark counter deltas."""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import re
import statistics
import time
import urllib.error
import urllib.request

DEFAULT_PROMPT = (
    "Write a detailed implementation guide for a thread-safe LRU cache in Python. "
    "Include complete code, tests, complexity analysis, and operational tradeoffs."
)


def get_text(url: str, timeout: float) -> str:
    with urllib.request.urlopen(url, timeout=timeout) as response:
        return response.read().decode()


def discover_model(base_url: str, timeout: float) -> str:
    return json.loads(get_text(f"{base_url}/v1/models", timeout))["data"][0]["id"]


def counters(base_url: str, timeout: float) -> tuple[float | None, float | None]:
    try:
        text = get_text(f"{base_url}/metrics", timeout)
    except urllib.error.URLError:
        return None, None
    def total(names: tuple[str, ...]) -> float | None:
        values = []
        for name in names:
            values.extend(float(x) for x in re.findall(rf"^vllm:{name}(?:\{{[^}}]*\}})?\s+([0-9.eE+-]+)$", text, re.M))
        return sum(values) if values else None
    return total(("spec_decode_num_accepted_tokens_total",)), total(("spec_decode_num_draft_tokens_total", "spec_decode_num_drafted_tokens_total"))


def completion(base_url: str, model: str, prompt: str, max_tokens: int, timeout: float, thinking: bool) -> dict[str, float]:
    payload = {
        "model": model, "messages": [{"role": "user", "content": prompt}],
        "temperature": 0, "max_tokens": max_tokens, "stream": True,
        "stream_options": {"include_usage": True},
        "chat_template_kwargs": {"thinking": thinking},
    }
    request = urllib.request.Request(
        f"{base_url}/v1/chat/completions", data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"}, method="POST",
    )
    start = time.perf_counter()
    first = None
    tokens = None
    with urllib.request.urlopen(request, timeout=timeout) as response:
        for raw in response:
            line = raw.decode(errors="replace").strip()
            if not line.startswith("data:"):
                continue
            body = line[5:].strip()
            if body == "[DONE]":
                break
            event = json.loads(body)
            usage = event.get("usage")
            if usage and usage.get("completion_tokens") is not None:
                tokens = int(usage["completion_tokens"])
            for choice in event.get("choices") or []:
                delta = choice.get("delta") or {}
                if first is None and (delta.get("content") or delta.get("reasoning_content") or delta.get("reasoning")):
                    first = time.perf_counter()
    end = time.perf_counter()
    if tokens is None:
        raise RuntimeError("stream did not return completion_tokens usage")
    first = first or end
    return {"tokens": float(tokens), "ttft": first - start, "elapsed": end - start, "decode_tps": tokens / max(end - first, 1e-9)}


def run_group(args, base: str, model: str) -> dict[str, float]:
    start = time.perf_counter()
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.concurrency) as pool:
        futures = [pool.submit(completion, base, model, args.prompt, args.max_tokens, args.timeout, args.thinking) for _ in range(args.concurrency)]
        results = [future.result() for future in futures]
    elapsed = time.perf_counter() - start
    return {
        "tokens": sum(item["tokens"] for item in results),
        "aggregate_tps": sum(item["tokens"] for item in results) / elapsed,
        "median_ttft": statistics.median(item["ttft"] for item in results),
        "median_decode_tps": statistics.median(item["decode_tps"] for item in results),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    parser.add_argument("--model")
    parser.add_argument("--prompt", default=DEFAULT_PROMPT)
    parser.add_argument("--max-tokens", type=int, default=512)
    parser.add_argument("--warmups", type=int, default=1)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--concurrency", type=int, default=1)
    parser.add_argument("--timeout", type=float, default=3600)
    parser.add_argument("--thinking", action="store_true")
    args = parser.parse_args()
    if args.concurrency < 1:
        parser.error("--concurrency must be positive")
    base = args.base_url.rstrip("/")
    model = args.model or discover_model(base, args.timeout)
    print(f"model={model} concurrency={args.concurrency} max_tokens={args.max_tokens} thinking={args.thinking}")
    for index in range(args.warmups):
        print(f"warmup {index + 1}/{args.warmups} ...", flush=True)
        run_group(args, base, model)
    before = counters(base, args.timeout)
    results = []
    for index in range(args.runs):
        result = run_group(args, base, model)
        results.append(result)
        print(f"run {index + 1}: tokens={result['tokens']:.0f} ttft={result['median_ttft']:.3f}s per-request-decode={result['median_decode_tps']:.2f} tok/s aggregate={result['aggregate_tps']:.2f} tok/s")
    after = counters(base, args.timeout)
    for key in ("median_ttft", "median_decode_tps", "aggregate_tps"):
        values = [item[key] for item in results]
        print(f"median {key}: {statistics.median(values):.3f} (range {min(values):.3f}-{max(values):.3f})")
    if None not in (*before, *after):
        accepted, drafted = after[0] - before[0], after[1] - before[1]
        print(f"DSpark counter delta: accepted={accepted:g} drafted={drafted:g} ratio={accepted / drafted if drafted else 0:.3f}")


if __name__ == "__main__":
    try:
        main()
    except (urllib.error.URLError, RuntimeError, json.JSONDecodeError) as exc:
        raise SystemExit(f"benchmark failed: {exc}") from exc
