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
- [Llama 3.1 8B](./llama-3.1-8b/llama-3.1-8b.md)
- [Llama 3.3 70B (Blackwell vs H100)](./llama-3.3-70b/llama-3.3-70b.md)
- [Nemotron Nano 8B (Blackwell vs H100)](./nemotron-nano-8b/nemotron-nano-8b.md)
- [GLM-4.7-Flash (Blackwell vs H100)](./glm-4.7-flash/glm-4.7-flash.md)
- [Nemotron 3 Nano 30B (Blackwell vs H100)](./nemotron-3-nano-30b/nemotron-3-nano-30b.md)
- [Nemotron 70B Instruct (H200 vs H100)](./nemotron-70b-instruct/nemotron-70b-instruct.md)

## DeepSeek + Newest Local (2026) — vLLM + SGLang

- [DeepSeek R1 Distill Llama 8B (Blackwell vs H100)](./deepseek-r1-distill-llama-8b/deepseek-r1-distill-llama-8b.md)
- [DeepSeek R1 Distill Qwen 32B (Blackwell vs H100)](./deepseek-r1-distill-qwen-32b/deepseek-r1-distill-qwen-32b.md)
- [Qwen3 32B (Blackwell vs H100)](./qwen3-32b/qwen3-32b.md)
- [Qwen3 30B-A3B MoE (Blackwell vs H100)](./qwen3-30b-a3b/qwen3-30b-a3b.md)
- [DeepSeek R1 Distill Llama 70B (2x Blackwell vs 2x H200)](./deepseek-r1-distill-llama-70b/deepseek-r1-distill-llama-70b.md)

## How we run new benches

Orchestrator: [`./bin/mc-bench`](./bin/mc-bench) — launch → vLLM + SGLang → classic terminal showcase screenshots → writeup → terminate.

See [docs/methodology.md](./docs/methodology.md).
