# GPU Benchmark

This repository contains benchmark data and documentation for evaluating the inference speeds of various large language models (LLMs) on different GPUs.

![Datacenter](./shared-images/datacenter.jpg)

## About Massed Compute

Massed Compute leverages cutting-edge technology to offer scalable and efficient distributed computing solutions. We provide flexible computing power for AI research, visual effects production, data science, and more. Our goal is to empower organizations with the tools they need to maximize their computational capabilities.

For more information, visit [Massed Compute](https://massedcompute.com/?utm_source=github.com).

## Benchmarking Overview

This repository covers benchmarking LLM inference speeds on different GPUs, including:

### Llama

- [Llama 3 70B](./llama-3/llama-3-70B.md)
- [Llama 3.1 70B](./llama-3/llama-3.1-70B.md)
- [Llama 3.1 8B](./llama-3.1-8b/llama-3.1-8b.md)
- [Llama 3.3 70B](./llama-3.3-70b/llama-3.3-70b.md)

### NVIDIA Nemotron

- [Llama 3.1 Nemotron Nano 8B](./nemotron-nano-8b/nemotron-nano-8b.md)
- [Nemotron 3 Nano 30B (A3B)](./nemotron-3-nano-30b/nemotron-3-nano-30b.md)
- [Llama 3.1 Nemotron 70B Instruct](./nemotron-70b-instruct/nemotron-70b-instruct.md)

### DeepSeek

- [DeepSeek R1 Distill Llama 8B](./deepseek-r1-distill-llama-8b/deepseek-r1-distill-llama-8b.md)
- [DeepSeek R1 Distill Qwen 32B](./deepseek-r1-distill-qwen-32b/deepseek-r1-distill-qwen-32b.md)
- [DeepSeek R1 Distill Llama 70B](./deepseek-r1-distill-llama-70b/deepseek-r1-distill-llama-70b.md)
- [DeepSeek V4 Flash](./deepseek-v4-flash/deepseek-v4-flash.md)

### Qwen

- [Qwen2.5 7B Instruct](./qwen2-5-7b-instruct/qwen2-5-7b-instruct.md)
- [Qwen3 32B](./qwen3-32b/qwen3-32b.md)
- [Qwen3 30B-A3B (MoE)](./qwen3-30b-a3b/qwen3-30b-a3b.md)

### GLM

- [GLM-4.7-Flash](./glm-4.7-flash/glm-4.7-flash.md)

### Ornith

- [Ornith 1.0 9B](./ornith-1.0-9b/ornith-1.0-9b.md)
- [Ornith 1.0 35B (MoE)](./ornith-1.0-35b/ornith-1.0-35b.md)

### MiniCPM-Robot (embodied)

- [MiniCPM-RobotManip](./minicpm-robotmanip/minicpm-robotmanip.md)
- [MiniCPM-RobotTrack](./minicpm-robottrack/minicpm-robottrack.md)

### Image / Video

- [Krea 2 Turbo](./krea-2-turbo/krea-2-turbo.md)
- [Bernini-R 14B](./bernini-r-14b/bernini-r-14b.md)

### Image / Multimodal

- [Ideogram v4 Instant](./ideogram-v4-instant/ideogram-v4-instant.md)
- [SenseNova-U1 Infographic V3](./sensenova-u1-8b-mot-infographic-v3/sensenova-u1-8b-mot-infographic-v3.md)

### Creative writing

- [Astrea R8 Chat 9B](./astrea-r8-chat-9b/astrea-r8-chat-9b.md)

### Hunyuan / Hy3

- [Hy3 IQ1_M GGUF](./hy3-iq1-m/hy3-iq1-m.md)

### Motif

- [Motif-3-Beta (partial)](./motif-3-beta/motif-3-beta.md)

Each benchmark includes:

- **Model Description**: Overview of the model being tested.
- **Hardware Specifications**: Details about the GPUs used.
- **Benchmark Results**: Inference speed and performance metrics.

## Methodology

The original 2024 Llama 3 suite used [Hugging Face TGI](https://github.com/huggingface/text-generation-inference). The 2026 additions use modern serving engines — [vLLM](https://github.com/vllm-project/vllm) and [SGLang](https://github.com/sgl-project/sglang) — run on live Massed Compute instances.

Pinned profile for the 2026 runs: random prompts, input=128 / output=128 tokens, request-rate=inf, concurrency 1 / 8 / 32 (headline numbers use concurrency 32). GPUs include RTX PRO 6000 Blackwell, H100, H200 NVL, and L40S. Bench VMs were terminated after each capture.
The 2026-07-20 additions also cover agentic coding (Ornith), embodied VLA (MiniCPM-Robot), text-to-image (Krea 2 Turbo), and video rendering (Bernini-R), with modality-appropriate metrics alongside the vLLM/SGLang LLM profile.

