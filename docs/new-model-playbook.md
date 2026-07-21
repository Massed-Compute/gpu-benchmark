# New model playbook

When a new HF model drops:

1. `./bin/mc-bench plan --model <org/name>`
2. Launch SKUs via Massed MCP (`imageId: 184`, SSH key you can use from this machine — e.g. `songtree`)
3. `MC_BENCH_IPS=sku:ip ./bin/mc-bench run --model <org/name>`
4. Tool writes `results/raw/...`, screenshots, and `<slug>/<slug>.md`
5. Append the required footer from [writeup-footer.md](./writeup-footer.md) (pricing disclaimer + signup CTA)
6. Terminate run VMs (default unless `--keep`)

Small models → 1× L40S. Big → 2× Blackwell + 2× H100 (optional +4× L40S).

Brand voice + CTA casing: [massed-compute-design-system.md](./massed-compute-design-system.md). Full DS zip (logos, UI kits): `~/Downloads/Massed Compute Design System 2026-07-15.zip` (unpacked local copy: `~/Downloads/mc-design-system-2026-07-15/`). Repo keeps logos under `shared-images/`.
