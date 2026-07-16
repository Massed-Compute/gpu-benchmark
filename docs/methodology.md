# Methodology

- Engines: vLLM (`vllm/vllm-openai:v0.8.5`) and SGLang (`lmsysorg/sglang:latest`)
- Workload: random, input=128, output=128, request-rate=inf, concurrency 1/8/32
- Headline metric: output tok/s at concurrency 32; also TTFT/TPOT and tok/s per $
- Lifecycle: launch Massed VM (image 184) → setup → bench both engines → JSON + PNG + markdown → terminate
- Caps: ≤32B → 1 VM; 70B+ → 2 VMs default (Blackwell vs H100), max 3 with L40S

Screenshots for writeups use the **classic TGI-table look** (maroon terminal, Prefill/Decode latency + throughput boxes) — same vibe as the 2024 github shots. Generated from vLLM/SGLang stats via `mc_bench.screenshot.render_showcase_png`.
