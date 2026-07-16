# GPU Benchmark

Benchmark data and writeups for LLM inference on Massed Compute GPUs — **vLLM** and **SGLang**.

![Datacenter](./shared-images/datacenter.jpg)

## About Massed Compute

Massed Compute offers scalable GPU cloud for AI research, VFX, data science, and more.

More: [massedcompute.com](https://massedcompute.com/?utm_source=github.com)

## Benchmarks

### New (2026) — vLLM + SGLang

- [Qwen2.5 7B Instruct on 1× L40S](./qwen2-5-7b-instruct/qwen2-5-7b-instruct.md)

### Archive (2024) — Hugging Face TGI

- [Llama 3 70B](./results/archive/2024-08-llama3/llama-3-70B.md)
- [Llama 3.1 70B](./results/archive/2024-08-llama3/llama-3.1-70B.md)

## How we run it

Same online profile on every card: input=128, output=128, concurrency 1 / 8 / 32.

Orchestrator: [`./bin/mc-bench`](./bin/mc-bench) — launch → bench → classic terminal showcase screenshots → writeup → terminate VMs.

See [docs/methodology.md](./docs/methodology.md) and [docs/new-model-playbook.md](./docs/new-model-playbook.md).

## Caps (traffic + cost)

| Model size | Max VMs | Default SKUs |
|------------|---------|--------------|
| ≤32B | 1 | `gpu_1x_l40s` |
| ~70B+ | 2 (3 max) | Blackwell 2× + H100 2× [+ L40S 4×] |
