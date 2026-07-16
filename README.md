# GPU Benchmark

Benchmark data and writeups for LLM inference on Massed Compute GPUs.

![Datacenter](./shared-images/datacenter.jpg)

## About Massed Compute

Massed Compute offers scalable GPU cloud for AI research, VFX, data science, and more.

More: [massedcompute.com](https://massedcompute.com/?utm_source=github.com)

## Llama (classic TGI screenshots)

- [Llama 3 70B](./llama-3-70b/llama-3-70b.md)
- [Llama 3.1 70B](./llama-3.1-70b/llama-3.1-70b.md)

## New (2026) — vLLM + SGLang

- [Qwen2.5 7B Instruct on 1× L40S](./qwen2-5-7b-instruct/qwen2-5-7b-instruct.md)

## How we run new benches

Orchestrator: [`./bin/mc-bench`](./bin/mc-bench) — launch → vLLM + SGLang → classic terminal showcase screenshots → writeup → terminate.

See [docs/methodology.md](./docs/methodology.md).
