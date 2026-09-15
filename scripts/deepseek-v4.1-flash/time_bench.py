#!/usr/bin/env python3
"""Timed single-stream decode using official DeepSeek-V4.1 generate().

Copy this file into the snapshot `inference/` directory, then:

  torchrun --nproc-per-node 8 time_bench.py \\
    --ckpt-path /models/DeepSeek-V4.1-Flash-TP8 \\
    --config /models/DeepSeek-V4.1-Flash/inference/config.json \\
    --max-new-tokens 128 --warmup 1 --repeats 5 \\
    --out /mc-bench/out/official-generate-bench.json
"""
from __future__ import annotations

import json
import os
import statistics
import sys
import time
from argparse import ArgumentParser
from pathlib import Path

_INF = Path(__file__).resolve().parent
sys.path.insert(0, str(_INF))
sys.path.insert(0, str(_INF.parent / "encoding"))

import torch
import torch.distributed as dist
from safetensors.torch import load_model
from transformers import AutoTokenizer

from encoding import encode_messages
from generate import generate
from model import ModelArgs, Transformer


PROMPT = (
    "Write a detailed technical explanation of mixture-of-experts routing, "
    "expert parallelism, and KV-cache growth. Keep writing until you run out of tokens."
)


def main() -> None:
    parser = ArgumentParser()
    parser.add_argument("--ckpt-path", required=True)
    parser.add_argument("--config", required=True)
    parser.add_argument("--max-new-tokens", type=int, default=128)
    parser.add_argument("--warmup", type=int, default=1)
    parser.add_argument("--repeats", type=int, default=5)
    parser.add_argument("--temperature", type=float, default=0.6)
    parser.add_argument("--thinking-mode", default="chat")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    world_size = int(os.getenv("WORLD_SIZE", "1"))
    rank = int(os.getenv("RANK", "0"))
    local_rank = int(os.getenv("LOCAL_RANK", "0"))
    if world_size > 1:
        dist.init_process_group("nccl")
    if rank != 0:
        def _silent(*_a, **_k):
            return None
        # generate.py uses print for progress; keep ranks quiet
        import builtins
        builtins.print = _silent  # noqa: A001

    torch.cuda.set_device(local_rank)
    torch.cuda.memory._set_allocator_settings("expandable_segments:True")
    torch.set_default_dtype(torch.bfloat16)
    torch.set_num_threads(8)
    torch.manual_seed(33377335)

    with open(args.config) as f:
        model_args = ModelArgs(**json.load(f))
        model_args.temperature = args.temperature
    model_args.max_batch_size = 1

    t_load0 = time.perf_counter()
    tokenizer = AutoTokenizer.from_pretrained(args.ckpt_path)
    with torch.device("cuda"):
        model = Transformer(model_args, tokenizer)
    load_model(model, os.path.join(args.ckpt_path, f"model{rank}-mp{world_size}.safetensors"))
    torch.set_default_device("cuda")
    if torch.cuda.is_available():
        torch.cuda.synchronize()
    load_s = time.perf_counter() - t_load0

    prompt_tokens = tokenizer.encode(encode_messages(
        [{"role": "user", "content": PROMPT}],
        thinking_mode=args.thinking_mode,
    ))
    eos_id = tokenizer.eos_token_id

    for _ in range(args.warmup):
        generate(model, [prompt_tokens], args.max_new_tokens, eos_id)
        if torch.cuda.is_available():
            torch.cuda.synchronize()

    runs = []
    for _ in range(args.repeats):
        if torch.cuda.is_available():
            torch.cuda.synchronize()
        t0 = time.perf_counter()
        completion_tokens = generate(model, [prompt_tokens], args.max_new_tokens, eos_id)
        if torch.cuda.is_available():
            torch.cuda.synchronize()
        dt = time.perf_counter() - t0
        n = len(completion_tokens[0])
        runs.append({"latency_s": dt, "new_tokens": n, "tok_s": (n / dt) if dt > 0 else 0.0})

    tok_s_list = [r["tok_s"] for r in runs]
    payload = {
        "model": "deepseek-ai/DeepSeek-V4.1-Flash",
        "engine": "official-generate.py+tp8",
        "mode": "single-stream",
        "load_s": load_s,
        "max_new_tokens": args.max_new_tokens,
        "world_size": world_size,
        "runs": runs,
        "mean_tok_s": statistics.fmean(tok_s_list) if tok_s_list else 0.0,
        "median_tok_s": statistics.median(tok_s_list) if tok_s_list else 0.0,
    }
    if rank == 0:
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(payload, indent=2) + "\n")
        print(json.dumps(payload, indent=2), file=sys.stderr)
        print("BENCH_JSON", str(out), file=sys.stderr)

    if world_size > 1:
        dist.barrier()
        dist.destroy_process_group()


if __name__ == "__main__":
    main()
