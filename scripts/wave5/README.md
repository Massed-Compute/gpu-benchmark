# Wave 5 reproduction scripts

Public map of which script produced each Wave 5 page. Run on a disposable Massed Compute GPU VM with `HF_TOKEN` set (or `~/.cache/huggingface/token`). These are operator scripts, not a CI harness.

| Page | Primary script(s) | Notes |
|---|---|---|
| [Laguna XS.2](../laguna-xs-2/laguna-xs-2.md) | `remote_vllm_llm.sh` via `remote_wave5a.sh` | Stock `vllm bench serve`, random 128/128 |
| [Laguna S 2.1 NVFP4](../laguna-s-2.1/laguna-s-2.1.md) | `remote_vllm_llm.sh` via `remote_wave5c.sh` | Model `poolside/Laguna-S-2.1-NVFP4` |
| [Atlas-Coder-2 0.5B](../atlas-coder-2-0.5b/atlas-coder-2-0.5b.md) | `remote_atlas_merge.sh` then `remote_atlas_a6000.sh` (SDPA) or `remote_atlas_tf.sh` (default attn) | A6000 page row = SDPA; Blackwell page row = default attn |
| [Nanbeige4.2-3B](../nanbeige4-2-3b/nanbeige4-2-3b.md) | `remote_nanbeige_hf.sh` | transformers; forces `rope_scaling=None` |
| [Solar Open2 NVFP4](../solar-open2-250b-a15b/solar-open2-250b-a15b.md) | `remote_solar_upstage.sh` via `remote_wave5c.sh` | Custom chat harness — **not** `vllm bench serve` |
| [Mage-Flow](../mage-flow/mage-flow.md) | `remote_mage_flow.sh` | Official Mage package + SDPA |
| [FLUX.1-dev INT8 ConvRot](../flux1-dev-int8-convrot/flux1-dev-int8-convrot.md) | `remote_flux_convrot.sh` | ComfyUI timed gens |

Orchestrators: `remote_wave5a.sh` (Nanbeige + Atlas + Laguna-XS), `remote_wave5c.sh` (Solar Upstage + Laguna-S NVFP4).
