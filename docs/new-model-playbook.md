# New model playbook

When a new HF model drops:

1. `./bin/mc-bench plan --model <org/name>`
2. Launch SKUs via Massed MCP (`imageId: 184`, SSH key you can use from this machine — e.g. `songtree`)
3. `MC_BENCH_IPS=sku:ip ./bin/mc-bench run --model <org/name>`
4. Tool writes `results/raw/...`, screenshots, and `<slug>/<slug>.md`
5. Append the required footer from [writeup-footer.md](./writeup-footer.md) (pricing disclaimer + signup CTA)
6. Terminate run VMs (default unless `--keep`)

Small models → start on the **smallest SKU that fits** (often 1× L40 / L40S / A6000), then optionally one mid/large SKU to show scale-up. Large MoE / multi-GPU models → 1–2 bigger SKUs only (e.g. 2× Blackwell, H200). Do **not** put inventory/capacity/billing launch failures in published writeups — pick working SKUs and ship those numbers.

Brand voice + CTA casing: [massed-compute-design-system.md](./massed-compute-design-system.md). Full DS zip (logos, UI kits): `~/Downloads/Massed Compute Design System 2026-07-15.zip` (unpacked local copy: `~/Downloads/mc-design-system-2026-07-15/`). Repo keeps logos under `shared-images/`.


---

<p align="center">
  <a href="https://massedcompute.com/?utm_source=github.com&utm_campaign=gpu-benchmark">
    <img src="../shared-images/logo-horizontal-on-light.png" alt="Massed Compute" height="56"/>
  </a>
</p>

<p align="center">
  <strong><a href="https://massedcompute.com/?utm_source=github.com&utm_campaign=gpu-benchmark">LAUNCH GPU OR CPU INSTANCE</a></strong>
</p>

> **Pricing note:** Listed `$/hr` rates are point-in-time from the capture date. Confirm live pricing in the marketplace before you launch — rates can change. Pay only for the hours you use.
