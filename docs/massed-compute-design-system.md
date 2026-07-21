# Massed Compute Design System

> **Think it. Build it. Scale it.**

Visual + interaction design system for **Massed Compute** — a cloud GPU/CPU compute provider and NVIDIA Preferred Partner. The brand voice is technical, direct, and confident: no fluff, no upsell, no contracts.

This system was built primarily from the public marketing site at **<https://massedcompute.com/>** and the four brand logo files the user supplied. The internal VM marketplace product (`vm.massedcompute.com`) is mocked from public surface context — see **Caveats** below.

---

## Company snapshot

- **What they sell.** On-demand GPU + CPU compute power. NVIDIA Preferred Partner with access to the full enterprise NVIDIA catalog (B200, B100, H100, A100, L40S, RTX 6000 ADA, A6000, A40, etc.) billed by the hour with no long-term contracts and no bandwidth overcharges.
- **Differentiators they lead with.** They own and operate all infrastructure (no middleman) → faster issue resolution, better security, and Tier III data center reliability. Direct access to IT experts instead of tiered support. NVIDIA drivers + CUDA pre-installed so "everything just works." A one-click Virtual Desktop Interface (VDI) means non-developers can launch AI tools without a command line.
- **Compliance posture.** SOC 2, GDPR, HIPAA badges shown on the homepage.

## Products

| Product | What it is | Audience |
| --- | --- | --- |
| **On-Demand** | Hourly GPU/CPU rental via VM marketplace (`vm.massedcompute.com`) | Solo devs, researchers, small teams |
| **Bare Metal** | Direct access to physical servers — no hypervisor | Heavy AI training, custom configs |
| **GPU Clusters** | Multi-node clusters, bespoke builds | Enterprise / large training jobs |
| **Inventory API** | Programmatic provisioning of MC's full GPU inventory into another platform | Platform partners, resellers |

## Solutions (use-case pages)

Cloud GPU · VFX Rendering · Machine Learning & AI · High-Performance Computing · Scientific Simulations · Data Analytics & Visualization.

## Sources used

- **Marketing site** — <https://massedcompute.com/> (home, on-demand, footer/nav). Voice, copy patterns, product table, motifs. **Tech: WordPress.**
- **VM marketplace dashboard** — <https://vm.massedcompute.com/> (referenced but not crawled; sign-in walled). **Tech: Node.js.**
- **GitHub repo (imported)** — `Massed-Compute/vm-marketplace` (Next.js 16 · React 19 · Tailwind · HeroUI · MUI · FontAwesome Pro Light). Read directly to extract real brand colors, sidebar structure, theme system, and routes. The VM marketplace UI kit is now a faithful recreation rather than a guess.
- **Uploaded logos** — `uploads/Massed_Logotype_*` + `MC logo.png` + `Massed-Compute-Logo-200x200.png`.
- **Brand fonts (provided)** — Roboto, Roboto Condensed, Roboto Semi Condensed (full weight ranges, TTFs in `fonts/`).

## Tech stack (for prototype handoff)

When a design from this system lands in real code, this is where it goes:

| Surface | Stack | Implication for design |
| --- | --- | --- |
| `massedcompute.com` | **WordPress** | Pages are page-builder blocks. The `ui_kits/marketing-site/` components are cosmetic JSX — when handing off, translate them to the block library in use (Gutenberg, Elementor, Divi, etc.). Type/colors/spacing tokens in `colors_and_type.css` should be mapped to the theme's CSS variables (often `theme.json` in modern Gutenberg). |
| `vm.massedcompute.com` | **Node.js** | The `ui_kits/vm-marketplace/` components are React. The real app is server-rendered or SPA Node — assume framework-agnostic CSS-in-CSS or a CSS-Modules port is easiest. |

For better fidelity, explore the repo directly: <https://github.com/Massed-Compute/vm-marketplace>.

---

## CONTENT FUNDAMENTALS

**Tone.** Confident, technical, slightly pugnacious. Massed Compute positions itself as the no-BS alternative to hyperscaler cloud — copy actively names the things they *don't* do ("no middleman," "no long-term commitments," "no extended contracts," "no hidden bandwidth fees," "no command line required," "no driver headaches"). Anti-fluff is the voice.

**Person.** Mostly second-person, addressed to the builder ("Whatever your project, we have the GPUs to power it…"). First-person plural ("We own and operate…") only when staking a credibility claim about the company.

**Casing.**
- **Headlines:** Sentence case. "Access the planet's best cloud computing infrastructure and build and deploy AI."
- **Eyebrows / section labels:** Title Case or sentence case, small caps weight visually but written as normal letters.
- **Buttons / CTAs:** ALL CAPS, tracked-out slightly. "LAUNCH GPU OR CPU INSTANCE", "TALK TO AN EXPERT", "LEARN MORE", "LOG IN TO LAUNCH".
- **Body:** Sentence case. Em-dashes and ampersands welcome.

**Tagline.** **"Think it. Build it. Scale it."** — three short verb-noun chunks separated by periods, often set in an italic serif as an editorial accent against the otherwise all-sans system.

**Headline pattern.** The homepage rotates one giant claim with a swappable second clause:
> *"Access the planet's best cloud computing infrastructure and **\_\_\_**."*
> …**build and deploy AI** / **unleash your code** / **analyze big data** / **accelerate machine learning**.
Use this Mad-Libs pattern any time you need a hero on a campaign page.

**Sentence rhythm.** Short. Declarative. Then a longer follow-up that explains the mechanic.
> *Example:* "At Massed Compute we own and operate all infrastructure, giving you direct access to compute power. Full control over systems means issues are resolved in minutes (not hours), optimized performance, enhanced security, and unparalleled reliability."

**Specifics over adjectives.** Marketing copy leans on concrete tool names (Jupyter, vLLM, ComfyUI, Hugging Face TGI, Ollama, CrewAI) and GPU SKUs (H100 SXM5, A100 PCIe, RTX 6000 ADA) rather than generic "powerful" claims. When in doubt, name a real tool.

**Reading level.** Write at an 8th-grade reading level. Short words, short sentences, plain phrasing. Technical specifics (tool names, GPU SKUs, units) are welcome, but the connective language around them stays simple and clear.

**Punctuation in body copy.** Avoid em-dashes and colons in body copy unless they're really necessary. Prefer a period and a new sentence. (Headlines, taglines, and the editorial italic accent can still use them for effect.)

**No emoji.** None on the site. Don't introduce them.

**Numbers and units.** Hours (`$2.35/hr`), GB (`80 GB`), GPU counts (`x 8`). Always spaced as shown. Currency is `$X.XX/hr`.

**Common verbs.** Launch, deploy, scale, render, train, analyze, unleash, accelerate, build. Avoid "leverage," "empower," "synergy."

**Frame it positively.** Lead with what the builder gains, not with a wall of negations. The "no middleman / no commitments" pattern is a signature move, so keep it — but use it as a punchy counterpoint, not the default sentence shape. Prefer the affirmative rewrite of a negative claim: "keep full control" over "don't lose control," "your price holds all year" over "we never raise your rate," "stop whenever you like" reframed as "pay only for the hours you use." Avoid stacking imperative negatives at the reader ("don't," "never," "stop," "can't"); state the benefit instead.

**Never call the product "cheap."** Massed Compute competes on value and honest pricing, not on being the bottom of the barrel. Use "affordable," "cost-effective," "the most economic option," "pay only for what you use," or a concrete rate ("$.43+/hr") instead of "cheap."

---

## VISUAL FOUNDATIONS

**Brand mark.** Single-letter `M` constructed from two angular planes with a small triangular notch in the bottom-left of the left plane. Always solid Compute Orange. Wordmark uses a heavy geometric sans set tight, no tracking.

**Color.**
- **Compute Orange `#FD3300`** is the only brand accent. Used for the M mark, primary buttons, inline italic headline accents, the "actively being billed" callout, MCP "New" badges, link hovers. Pulled directly from the repo's `tailwind.config.ts`. It's loud and used sparingly — a single orange element per viewport is the norm.
- **Deep Orange `#8C2000`** (`--mc-orange-deep`) — reserved for full-bleed CTA banner sections only (e.g. "Spin up a GPU in ninety seconds"). Never used for buttons or type.
- **Secondary Teal `#087E8B`** — sparingly used for receipt links and select navigation accents inside the product (`secondary` token in the repo).
- **Ink `#0B0B0F`** — near-black for the LOGIN button, the Four Ways product card fills, footer background, primary text on light bg.
- **Paper `#FFFFFF` / Bone `#F8FAFC`** — page background. The site alternates pure white (hero, products, NVIDIA) with bone (API section, Pay by Hour) to break long scroll sections.
- **Section dark `#14141A`** (`--ink-900`) — used for the Compliance card grid section and the Four Ways card fills.
- **Mid grays** — neutral scale from `#1A1A1F` to `#E6E4DF`.
- **NVIDIA Green `#76B900`** appears only inside the NVIDIA Preferred Partner badge — never as a UI accent on its own.
- **Compliance badges** (SOC 2, GDPR, HIPAA) keep their original artwork colors; don't recolor them.

**Type.**
- **Display headlines:** **Roboto** (non-condensed, weight 800–900) for all major headings. The wide, bold proportions suit the site's confident, editorial voice. `--font-display` now points to `"Roboto"` first, with `"Roboto Condensed"` as fallback. Condensed is still available for sub-labels and utility contexts.
- **UI body + small text:** **Roboto** (locally hosted, 300–900 + italics).
- **Editorial italic accent:** Inline `<em>` in **Roboto Black Italic** (900). Used for one emphatic word per headline — *"deploy AI fast."*, *"GPUs"*, *"your"*, *"Every"*, *"hour."* — always in `--mc-orange`. The italic floats against the upright sans.
- **Mono:** **Geist Mono** (locally hosted, full weight range) for prices, GPU SKUs, code, kbd shortcuts, eyebrow data labels.
- **Hierarchy:** Display headlines are large (36–66 px desktop), weight 900, tight leading (1.01), `text-wrap: balance`. Body text is 16–17 px Roboto Regular at 1.6 leading.

> **All brand faces are local.** Roboto, Roboto Condensed, Geist, and Geist Mono all live in `fonts/` as TTFs and are wired up in `colors_and_type.css`. No web-font CDN dependency remains.

**Backgrounds — section sequence (homepage top → bottom).**
1. **Nav** — white `#FFFFFF`, 96% opacity + blur on scroll
2. **Hero** — white `#FFFFFF`, two-column split, black headline + orange italic em
3. **Four Ways to Compute** — white section header; dark `--ink-900` card fills in a 4-column grid
4. **API / Code** — bone `--bone` (`#F8FAFC`) with dark code block panels
5. **NVIDIA Partner** — white `#FFFFFF`
6. **Compliance & Reliability** — dark `--ink-900` with `--ink-800` card fills
7. **Pay by the Hour** — bone `--bone`, includes the live pricing ticker
8. **CTA Banner** — deep burnt orange `--mc-orange-deep` (`#8C2000`)
9. **Footer** — near-black `--ink-1000` (`#0B0B0F`)

**No abstract gradients, no purple, no glassmorphism.** Flat color blocks separated by hard edges. The watermark `M` behind the old dark hero has been retired.

**Imagery vibe.** Warm, slightly desaturated, real photography of data centers and servers; mixed with bold flat 3D-rendered illustration in orange/white/black. Slight grain on photos, never B&W. Marketing PNG assets are full-bleed with a transparent background to drop onto either page color.

**Animation.** Minimal. Page transitions are crossfades. Hovers are 150–200 ms easing (cubic-bezier(0.4, 0, 0.2, 1)). No bounce. No parallax. No scroll-jacked sections. Buttons fade their background, not their scale.

**Hover & press.**
- **Filled orange button:** hover → 8 % darken (`#E63800`). Press → 14 % darken (`#C73100`).
- **Outlined orange button:** hover → fill with orange, text flips to white. Press → darken.
- **Dark button on white:** hover → swap to orange fill, text → white.
- **Link / nav item:** hover → underline appears 1 px from baseline, color flips to orange.
- No `:active` scale transforms. No glow shadows.

**Borders & radii.**
- The brand uses **small, tight radii** — not fully square. Buttons and inputs are `4 px` (`--radius-sm`). Default cards are `6 px` (`--radius-md`), large cards `8 px` (`--radius-lg`). Larger surfaces (modals, wizard) go up to `12 px` (`--radius-xl`). `--radius-xs` (2 px) is for inline code and chips, `--radius-none` (0) exists but is rarely used.
- The **pill** (`--radius-pill`, 9999px) is retained for tertiary CTAs and small status/availability dots only — not for primary buttons.
- Border weight: 1 px hairlines in mid-gray (`--border-soft` / `--bw-hair`), or 1.5–2 px (`--bw-base` / `--bw-bold`) in Ink for emphasis. Card borders use `--border-medium`.

**Shadow / elevation.** Almost none. The site uses *separation by color block* rather than drop shadow. When a shadow is needed (floating menu, modal), it's a single soft `0 12px 32px rgba(11,11,15,0.08)` — never multi-layered.

**Transparency & blur.** None on marketing. Inside the VM marketplace product, a thin top-nav uses `backdrop-filter: blur(12px)` over a translucent Ink layer.

**Layout rules.**
- 12-column grid, 1280px content width, 24 px gutters.
- Headlines hang to the left margin and run wide; body text caps at ~70 ch.
- Fixed top nav (72 px tall) with a bottom hairline; nothing else is sticky.
- Section padding is generous — 96–160 px vertical between blocks.

**Cards.** Square corners (6–8 px), 1 px hairline border in `--border-soft`, no shadow by default, generous internal padding (24–32 px). On hover, the border darkens to Ink and the title flips to Compute Orange.

**Tables (pricing).** Heavy, full-width, alternating row stripes (`#FFFFFF` / `#F7F6F2`). GPU SKU column is bold; price column is right-aligned and mono.

---

## ICONOGRAPHY

- **The real product uses FontAwesome Pro 6 with the `fa-light` weight** — hairline 1 px strokes, square caps. See `app/_components/sidebar/Sidebar.tsx` for the full vocabulary: `fa-layer-group`, `fa-server`, `fa-brands fa-docker`, `fa-person-running`, `fa-money-bill`, `fa-plug`, `fa-telescope`, `fa-books`, `fa-gear`, `fa-discord`, `fa-sun-bright`, `fa-circle-half-stroke`, `fa-moon`.
- **In this design system we substitute** with hand-stroked Lucide-style hairline SVGs (1.25–1.5 px stroke) because FA Pro can't load from CDN without a paid kit ID. Visually near-identical. When taking designs to production, swap inline SVGs for `<i className="fa-light fa-...">`.
- **NVIDIA logo / compliance badges** are 3rd-party artwork — use them as PNGs without modification.
- **No emoji ever.** No unicode-character icons (no `→`, `★`, etc. used as glyphs).
- **No gradient or duotone icons.** Single-color, single-stroke only.

> **Flag:** ~~We could not access the VM-marketplace codebase~~. **Resolved:** the repo is now imported (`Massed-Compute/vm-marketplace`). Icons use FontAwesome Pro Light at `fa-light` weight. For this design system we substitute Lucide-style hairline SVGs because FA Pro can't be redistributed.

---

## File index

```
README.md                ← you are here
SKILL.md                 ← agent-readable skill manifest
colors_and_type.css      ← all CSS custom properties + font imports
fonts/                   ← (uses Google Fonts CDN; no local TTFs yet — drop here if licensed)
assets/                  ← logos, marks, and the avatar PNG
preview/                 ← Design System tab cards (one HTML file per concept)
ui_kits/
  marketing-site/        ← Massed Compute homepage / marketing pages
    index.html           ← interactive prototype
    Hero.jsx
    Header.jsx
    Footer.jsx
    ProductCard.jsx
    PricingTable.jsx
    Button.jsx
    ComplianceBadges.jsx
  vm-marketplace/        ← VM dashboard mock (BEST-EFFORT — repo not accessible)
    index.html
    AppShell.jsx
    InstanceCard.jsx
    NewInstanceWizard.jsx
    PriceTable.jsx
```

## How to use this system

1. **Pulling visuals into a new HTML artifact?** Link `colors_and_type.css`, copy whichever logo from `assets/` matches your background, and reach for the components inside `ui_kits/marketing-site/`. They're mainly cosmetic React components — copy the JSX you need and inline it.
2. **Writing copy?** Re-read the *Content Fundamentals* block above. When stuck, drop in the Mad-Libs headline pattern.
3. **Building a slide deck?** Use Ink (`#0B0B0F`) for chapter slides, Paper for content slides, Compute Orange for the one thing per slide that matters most. Editorial italic serif for taglines.
4. **In a developer agent context?** Read `SKILL.md` and treat this folder as a reusable Claude Code skill.

---

## Caveats — please help me iterate

- **`Massed-Compute/vm-marketplace` is now imported.** The VM marketplace UI kit at `ui_kits/vm-marketplace/` is rebuilt from the real Next.js 16 / React 19 repo — brand colors, sidebar structure, theme system and routes all match. Outstanding: real auth pages (login/signup), settings sub-pages (API keys, SSH keys), and the MCP surface.
- **Display typeface is a substitute.** I used **Geist** because the actual marketing-site face isn't identified in public sources. If you can send the licensed font file (and any approved Adobe Fonts / Google Fonts equivalent), I'll swap it in.
  - **Resolved.** The user supplied Roboto + Roboto Condensed full families; they now live in `fonts/` and are wired up in `colors_and_type.css`.
- **Brand orange hex is confirmed** as `#FD3300` (updated from earlier `#DE2F02`).
- **No real iconography set.** I'm using Lucide as a substitute that fits the brand visually. Confirm or send the real set.
  - **Resolved.** Real product uses FontAwesome Pro 6 Light — documented in the iconography section.
- **No product screenshots of the VM marketplace.** Anything we mock there is informed guess-work.
  - **Resolved.** Built from the real repo.

**Ask:** Please review the cards in the Design System tab and call out anything off-brand. Specifically: confirm the new orange hex `#FD3300`, confirm the display font, and tell me which gaps in the VM marketplace kit (auth, settings sub-pages, MCP) should land first.
