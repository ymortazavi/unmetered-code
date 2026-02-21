#!/usr/bin/env python3
"""
Benchmark: measure llama-server tokens/sec at various context lengths.

Tests prompt evaluation and generation speed at 5 context sizes.
Works with any OpenAI-compatible endpoint (llama-server, vllm, etc.).
"""

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime

CONTEXT_POINTS = [256, 512, 1_024, 2_048, 4_096]
GEN_TOKENS = 128


def filler_text(target_tokens: int) -> str:
    parts = []
    n = 0
    while len(parts) < target_tokens:
        parts.append(str(n % 1000))
        n += 1
    return " ".join(parts)


def check_server(base_url: str) -> str | None:
    try:
        payload = json.dumps(
            {
                "messages": [{"role": "user", "content": "hi"}],
                "max_tokens": 1,
            }
        ).encode()
        req = urllib.request.Request(
            f"{base_url}/v1/chat/completions",
            data=payload,
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read())
            return data.get("model", "unknown")
    except Exception:
        return None


def run_point(base_url: str, target_ctx: int, gen_tokens: int) -> dict:
    filler = filler_text(target_ctx)

    payload = json.dumps(
        {
            "messages": [
                {"role": "system", "content": filler},
                {"role": "user", "content": "Count from 1 to 100, one number per line."},
            ],
            "max_tokens": gen_tokens,
            "temperature": 0.0,
            "stream": True,
        }
    ).encode()

    req = urllib.request.Request(
        f"{base_url}/v1/chat/completions",
        data=payload,
        headers={"Content-Type": "application/json"},
    )

    t_start = time.perf_counter()
    t_first_content = None
    content_chunks = 0
    usage = {}

    with urllib.request.urlopen(req, timeout=900) as resp:
        for raw_line in resp:
            line = raw_line.decode("utf-8", errors="replace").strip()
            if not line.startswith("data: "):
                continue
            data_str = line[6:].strip()
            if data_str == "[DONE]":
                break
            try:
                chunk = json.loads(data_str)
            except json.JSONDecodeError:
                continue

            choices = chunk.get("choices", [])
            if choices:
                delta = choices[0].get("delta", {})
                has_output = delta.get("content") or delta.get("reasoning")
                if has_output:
                    if t_first_content is None:
                        t_first_content = time.perf_counter()
                    content_chunks += 1

            if "usage" in chunk:
                usage = chunk["usage"]

    t_end = time.perf_counter()

    prompt_tokens = usage.get("prompt_tokens", target_ctx)
    completion_tokens = usage.get("completion_tokens", content_chunks)

    if t_first_content is None:
        t_first_content = t_start
        ttft = t_end - t_start
    else:
        ttft = t_first_content - t_start

    gen_time = t_end - t_first_content
    total_time = t_end - t_start

    return {
        "target_ctx": target_ctx,
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "ttft_s": round(ttft, 2),
        "gen_time_s": round(gen_time, 2),
        "total_time_s": round(total_time, 2),
        "prompt_tps": round(prompt_tokens / ttft, 1) if ttft > 0.05 else 0,
        "gen_tps": round(completion_tokens / gen_time, 1) if gen_time > 0.005 else 0,
    }


def fmt_k(n: int) -> str:
    return f"{n / 1000:.0f}K" if n >= 1000 else str(n)


def server_alive(base_url: str) -> bool:
    try:
        req = urllib.request.Request(f"{base_url}/v1/models")
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status == 200
    except Exception:
        return False


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Benchmark llama-server throughput at various context lengths",
    )
    parser.add_argument(
        "--url",
        default="http://localhost:8080",
        help="Server base URL (default: http://localhost:8080)",
    )
    parser.add_argument(
        "--output",
        "-o",
        help="Save results to a JSON file",
    )
    parser.add_argument(
        "--gen-tokens",
        type=int,
        default=GEN_TOKENS,
        help=f"Tokens to generate per test (default: {GEN_TOKENS})",
    )
    args = parser.parse_args()

    print()
    print("  llama-server Benchmark (vast.ai)")
    print("  " + "━" * 50)
    print(f"  Server:      {args.url}")
    print(f"  Gen tokens:  {args.gen_tokens}")
    print(f"  Test points: {', '.join(fmt_k(p) for p in CONTEXT_POINTS)}")
    print()

    sys.stdout.write("  Checking server... ")
    sys.stdout.flush()
    model = check_server(args.url)
    if model is None:
        print("FAILED")
        print("  Error: cannot reach the server. Is llama-server running?")
        sys.exit(1)
    print(f"OK  ({model})")

    sys.stdout.write("  Warming up...      ")
    sys.stdout.flush()
    try:
        run_point(args.url, 64, 16)
        print("OK")
    except Exception as exc:
        print(f"WARN ({exc})")

    print()

    col = "  {ctx:>10}  │ {prompt:>10}  │ {ttft:>8}  │ {ptps:>12}  │ {gtps:>10}  │ {total:>8}"
    hdr = col.format(
        ctx="Context",
        prompt="Prompt",
        ttft="TTFT",
        ptps="Prompt tok/s",
        gtps="Gen tok/s",
        total="Total",
    )
    sep = "  " + "─" * (len(hdr) - 2)

    print(hdr)
    print(sep)

    results = []

    for ctx in CONTEXT_POINTS:
        label = fmt_k(ctx)
        sys.stdout.write(f"  {label:>10}  │ ")
        sys.stdout.flush()

        try:
            r = run_point(args.url, ctx, args.gen_tokens)
            results.append(r)
            print(
                f"{r['prompt_tokens']:>10,}  │ "
                f"{r['ttft_s']:>6.1f}s  │ "
                f"{r['prompt_tps']:>10,.0f}  │ "
                f"{r['gen_tps']:>8,.1f}  │ "
                f"{r['total_time_s']:>6.1f}s"
            )
        except KeyboardInterrupt:
            print("interrupted")
            break
        except Exception as exc:
            print(f"ERROR  ({exc})")
            results.append({"target_ctx": ctx, "error": str(exc)})
            if not server_alive(args.url):
                print()
                print("  Server crashed (likely GPU out-of-memory).")
                break

    print(sep)
    print()

    ok = [r for r in results if "error" not in r]
    if ok:
        avg_gen = sum(r["gen_tps"] for r in ok) / len(ok)
        min_gen = min(r["gen_tps"] for r in ok)
        max_gen = max(r["gen_tps"] for r in ok)
        print(
            f"  Generation speed:  avg {avg_gen:.1f}  min {min_gen:.1f}  max {max_gen:.1f}  tok/s"
        )
        print(f"  Model:  {model}")
        print(f"  Date:   {datetime.now().strftime('%Y-%m-%d %H:%M')}")
        print()

    if args.output:
        out = {
            "model": model,
            "date": datetime.now().isoformat(),
            "gen_tokens": args.gen_tokens,
            "context_points": CONTEXT_POINTS,
            "results": results,
        }
        with open(args.output, "w") as f:
            json.dump(out, f, indent=2)
        print(f"  Results saved to {args.output}")
        print()


if __name__ == "__main__":
    main()
