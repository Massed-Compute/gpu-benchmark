---
name: massed-compute-design
description: Use this skill to generate well-branded interfaces and assets for Massed Compute (the on-demand GPU/CPU cloud and NVIDIA Preferred Partner), either for production or throwaway prototypes/mocks/etc. Contains essential design guidelines, colors, type, fonts, assets, and UI kit components for prototyping.
user-invocable: true
---

# Massed Compute design skill

Read the `README.md` file in this skill for the full visual + content system, then explore the other files below.

## Tech stack note

- The marketing site (`massedcompute.com`) is a **WordPress** site — when handing off marketing-page designs from this system, expect to translate the JSX cosmetics into Gutenberg / page-builder blocks and map tokens onto the theme's CSS variables.
- The VM marketplace product (`vm.massedcompute.com`) is a **Next.js 16 / React 19 / Tailwind / HeroUI / MUI** app. The kit in `ui_kits/vm-marketplace/` is a faithful recreation of the real `Massed-Compute/vm-marketplace` codebase — sidebar nav, theme system, brand colors and routes match. Icons substitute FontAwesome Pro Light with Lucide-style hairline SVGs.

## Skill layout

```
README.md              ← full brand + visual + content guide (READ THIS FIRST)
colors_and_type.css    ← all design tokens (link from any HTML artifact)
assets/                ← logos (M mark + horizontal lockups on light/dark) + 200×200 favicon
preview/               ← per-token specimen cards (Type, Colors, Spacing, Components, Brand)
ui_kits/
  marketing-site/      ← Massed Compute marketing site recreation (Home / Products / Pricing) — WordPress in prod
  vm-marketplace/      ← VM dashboard recreation — Next.js 16 / React 19 / Tailwind / HeroUI in prod
```

## How to use

If creating visual artifacts (slides, mocks, throwaway prototypes, sales decks, marketing pages):

1. Read `README.md` for tone, voice, motifs, hover/press behavior, casing rules.
2. Link `colors_and_type.css` from your HTML so you inherit Compute Orange `#FD3300`, secondary teal `#087E8B`, Paper, Bone, the Roboto + Roboto Condensed + Geist Mono stack, and all spacing/radii tokens. The same file ships light/system/dark theme variables (`--surface`, `--foreground`, `--muted`, `--border`) used by the VM marketplace kit — toggle by adding `class="dark"` to `<html>`.
3. Drop a logo from `assets/` — `logo-horizontal-on-light.png` on Paper backgrounds, `logo-horizontal-on-dark.png` on Ink.
4. Reach for the JSX components in `ui_kits/marketing-site/` (`Header`, `Hero`, `ProductCards`, `WhyMC`, `Partner`, `Footer`, `PricingTable`) or `ui_kits/vm-marketplace/` (`Sidebar`, `BrowsePage`, `DeployPage`, `RunningInstances` with live sparklines, `BillingPage`, `LaunchWizard`, `ThemeSelector`). They're cosmetic copies — feel free to inline only the JSX you need.
5. Static HTML or React are both fine. Avoid emoji, avoid abstract gradients, avoid Inter/Roboto.

If working on production code, copy the design tokens out of `colors_and_type.css` and read the rules in `README.md` to become an expert on the Massed Compute brand.

## If the user invokes this skill with no other guidance

Ask:
1. What surface are they designing for? Marketing page, in-product screen, slide deck, social card, blog header?
2. What's the audience — solo dev, ML researcher, enterprise procurement, or general visitor?
3. Do they need to highlight a specific product (Bare Metal / On-Demand / GPU Clusters / Inventory API) or solution (Cloud GPU / VFX / ML / HPC / Sci-sim / Data viz)?
4. Light or dark hero?

Then act as an expert designer and ship either a static HTML artifact or production code, applying the rules from `README.md`.

## Voice cheat-sheet (don't reread the full README every time)

- Sentence-case headlines. ALL CAPS, tracked +0.06em, for buttons.
- Mad-libs hero pattern: *"Access the planet's best cloud computing infrastructure and ___."* Fill the blank with a verb-phrase about what the user will do.
- Tagline: *"Think it. Build it. Scale it."* in Instrument Serif Italic.
- Lead with what they *don't* do: no middleman, no commitments, no overcharges, no driver headaches. Use this as a punchy counterpoint, not the default sentence — otherwise frame benefits positively (affirm what they gain rather than stacking "don't / never / stop / can't").
- Never describe the product as "cheap." Use "affordable," "cost-effective," "the most economic option," or a concrete rate ($.43+/hr).
- Name real tools (Jupyter, vLLM, ComfyUI, PyTorch, Hugging Face TGI) and real GPU SKUs (H100, A100, L40S, RTX 6000 ADA) instead of generic adjectives.
- No emoji.


---

<p align="center">
  <a href="https://massedcompute.com/?utm_source=github.com&utm_campaign=gpu-benchmark">
    <img src="../shared-images/logo-horizontal-on-light.png" alt="Massed Compute" height="56"/>
  </a>
</p>

<p align="center">
  <strong><a href="https://massedcompute.com/?utm_source=github.com&utm_campaign=gpu-benchmark">LAUNCH GPU OR CPU INSTANCE</a></strong>
</p>

> **Pricing note:** Listed `$/hr` rates are point-in-time from the capture date. Confirm live pricing in the marketplace before you launch — rates can change. Pay only for the hours you use; no long-term contracts.
