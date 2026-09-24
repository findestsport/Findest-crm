---
version: alpha
name: Findest-Design-System
description: |
  Design system untuk Findest Sport — distributor premium sport supplement Bali.
  Photography-first commerce, pill-shape chrome, editorial magazine layout.
  Inspired by Nike design language (extreme typographic contrast, ink/canvas/soft-cloud
  palette, red hanya untuk sale). Adapt untuk B2B distributor context: mix
  bahasa Indonesia + English, tone athletic-professional, target audience gym
  owner + apotek + F&B partner.

colors:
  # Chrome — carries ~95% of surface area
  ink: "#111111"           # near-black, primary text + CTA
  canvas: "#ffffff"        # page background
  soft-cloud: "#f5f5f5"    # product stage grey, secondary surface
  hairline: "#cacacb"      # 1px dividers
  hairline-soft: "#e5e5e5" # inset bottom-line on sticky bars

  # Text hierarchy
  charcoal: "#39393b"      # slightly softer body
  mute: "#707072"          # subtitle, footer, secondary meta
  stone: "#9e9ea0"         # inverse secondary on dark surface

  # Semantic — ONLY appear at these moments
  sale: "#d30005"          # discounted price, "% off" copy, NEW badge accent
  sale-deep: "#780700"     # sale hover/pressed state
  success: "#007d48"       # in-stock indicator, delivery confirmed
  success-bright: "#1eaa52" # inverse success on dark surface
  info: "#1151ff"          # informational link/badge in member callout

  # Brand accent — reserved for editorial moments only, never for chrome
  # Findest identity: warm neutral, not neon
  findest-warm: "#EEEDE5"  # subtle warm off-white for editorial hero backdrops

typography:
  display-campaign:
    fontFamily: Bebas Neue
    fontSize: 96px
    fontWeight: 500
    lineHeight: 0.9
    letterSpacing: -0.005em
    textTransform: uppercase
  heading-xl:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: 500
    lineHeight: 1.2
  heading-lg:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: 500
    lineHeight: 1.2
  heading-md:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: 500
    lineHeight: 1.75
  body-md:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: 400
    lineHeight: 1.5
  body-strong:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: 500
    lineHeight: 1.5
  button-md:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: 500
    lineHeight: 1.5
  button-sm:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: 500
    lineHeight: 1.5
  caption-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: 500
    lineHeight: 1.5
  caption-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: 500
    lineHeight: 1.5
  utility-xs:
    fontFamily: Inter
    fontSize: 10px
    fontWeight: 500
    lineHeight: 1.75

rounded:
  none: 0px
  sm: 18px
  md: 24px
  lg: 30px      # pill CTAs
  full: 9999px  # circular icon buttons + swatch dots

spacing:
  xxs: 2px
  xs: 4px
  sm: 8px
  md: 12px
  lg: 18px
  xl: 24px
  xxl: 30px
  section: 48px  # major block rhythm

components:
  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.canvas}"
    typography: "{typography.button-md}"
    rounded: "{rounded.lg}"
    padding: 14px 32px
    height: 52px
  button-secondary:
    backgroundColor: "{colors.soft-cloud}"
    textColor: "{colors.ink}"
    typography: "{typography.button-md}"
    rounded: "{rounded.lg}"
    padding: 14px 32px
    height: 52px
  button-outline-on-image:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.button-md}"
    rounded: "{rounded.lg}"
    padding: 10px 20px
  button-icon-circular:
    backgroundColor: "{colors.soft-cloud}"
    textColor: "{colors.ink}"
    rounded: "{rounded.full}"
    size: 36px
  search-pill:
    backgroundColor: "{colors.soft-cloud}"
    textColor: "{colors.ink}"
    typography: "{typography.body-md}"
    rounded: "{rounded.md}"
    padding: 10px 16px
    height: 40px
  filter-chip:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    borderColor: "{colors.hairline}"
    typography: "{typography.button-sm}"
    rounded: "{rounded.lg}"
    padding: 8px 16px
  filter-chip-active:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.canvas}"
    typography: "{typography.button-sm}"
    rounded: "{rounded.lg}"
  badge-promo:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    borderColor: "{colors.hairline}"
    typography: "{typography.caption-sm}"
    rounded: "{rounded.lg}"
    padding: 4px 10px
  badge-sale-text:
    textColor: "{colors.sale}"
    typography: "{typography.caption-md}"
  product-card:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    rounded: "{rounded.none}"
    padding: 0px
  product-card-image:
    backgroundColor: "{colors.soft-cloud}"
    rounded: "{rounded.none}"
    aspectRatio: "1/1"
  swatch-dot:
    rounded: "{rounded.full}"
    size: 10px
  campaign-tile:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.canvas}"
    typography: "{typography.display-campaign}"
    rounded: "{rounded.none}"
    aspectRatio: "4/5"
  qty-stepper:
    backgroundColor: "{colors.canvas}"
    borderColor: "{colors.hairline}"
    rounded: "{rounded.full}"
    padding: 2px
  utility-bar:
    backgroundColor: "{colors.soft-cloud}"
    textColor: "{colors.ink}"
    typography: "{typography.caption-sm}"
    height: 28px
  primary-nav:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.body-strong}"
    height: 52px
    borderBottom: "1px solid {colors.hairline-soft}"
---

## Overview

Findest adalah distributor sport supplement premium di Bali. Design system-nya
mengambil DNA Nike (photography-first commerce, extreme typographic contrast,
pill-shape chrome, monokromatik palette) — di-adapt untuk B2B distributor
context dengan customer campuran (gym owner, apotek, cafe, homestay).

Prinsip utama: **chrome tenang, foto & angka bicara**. Semua ornament design
(shadow, gradient, warna decorative, sharp corners) dibuang. Palette hitam/putih/
soft-cloud grey carry ~95% permukaan; merah hanya muncul di harga sale.
Photography dan macro/spec numbers yang jadi hero visual — bukan card style.

## Colors

### Primary Chrome
- **Ink** (`{colors.ink}` — `#111111`) — text utama, CTA pill, active state,
  overlay campaign, semua "action" moment
- **Canvas** (`{colors.canvas}` — `#ffffff`) — background page, inverse text di
  ink surface, on-image CTA
- **Soft Cloud** (`{colors.soft-cloud}` — `#f5f5f5`) — product photo stage,
  secondary button, utility bar, search pill, swatch tiles
- **Hairline** (`{colors.hairline}` — `#cacacb`) — 1px dividers antar filter row,
  PDP disclosure row, cart line
- **Hairline Soft** (`{colors.hairline-soft}` — `#e5e5e5`) — inset shadow di
  sticky bars, tab strip underline

### Text
- **Ink** — primary text (headline, product name, price)
- **Charcoal** (`#39393b`) — slightly softer body
- **Mute** (`{colors.mute}` — `#707072`) — product subtitle, footer link, meta
- **Stone** (`{colors.stone}` — `#9e9ea0`) — inverse secondary on dark surface

### Semantic
- **Sale** (`{colors.sale}` — `#d30005`) — HARGA DISKON only. Never background,
  never CTA color, never badge fill
- **Success** (`{colors.success}` — `#007d48`) — in-stock indicator, delivery
  confirmed status
- **Info** (`{colors.info}` — `#1151ff`) — informational link, member benefit
  callout

### Rules
- Tidak ada decorative accent color — no purple, no cyan, no ochre
- Warna "brand" bukan warna, tapi **treatment**: black typography, soft-cloud
  photography stage, editorial layout
- Semantic color muncul di 1 moment per viewport, tidak di-cascade
- Dark mode: swap ink ↔ canvas, semua tetap monokromatik

## Typography

### Font Family
- **Bebas Neue** — editorial campaign headline only (96px, uppercase, 0.9 line-height).
  Open-source substitute untuk Nike Futura ND. Free via Google Fonts.
- **Inter** — semua UI chrome, body copy, button, caption. Weights: 400, 500, 700.
  Free via Google Fonts.

### Hierarchy

| Token | Size | Weight | Use |
|---|---|---|---|
| `{typography.display-campaign}` | 96px | 500 | Editorial campaign headline burned into hero photography (uppercase, line-height 0.9) |
| `{typography.heading-xl}` | 32px | 500 | Section headers ("FEATURED", "BRAND KAMI"), page title |
| `{typography.heading-lg}` | 24px | 500 | Sub-section title, PDP product name, large CTA label |
| `{typography.heading-md}` | 16px | 500 | Card title, FAQ row label, filter group header |
| `{typography.body-md}` | 16px | 400 | Body copy, search placeholder, product description |
| `{typography.body-strong}` | 16px | 500 | Product card name, nav link, price row |
| `{typography.button-md}` | 16px | 500 | Standard pill CTAs |
| `{typography.button-sm}` | 14px | 500 | Filter chip, compact pill CTA |
| `{typography.caption-md}` | 14px | 500 | Product subtitle ("Muscle First · 2 LB"), meta |
| `{typography.caption-sm}` | 12px | 500 | Filter count, badge text, color count |
| `{typography.utility-xs}` | 10px | 500 | Utility bar copy, legal fine print |

### Principles
- **Extreme contrast** — jump langsung dari 96px display → 16px body, no middle.
  Ini bikin "billboard atas, catalog bawah" feel di setiap page.
- **Letter-spacing 0** untuk semua size, kecuali display Bebas dengan -0.005em
- **Uppercase reserved** untuk Bebas display + campaign eyebrow only. Body dan
  section header pakai Title Case atau sentence case.
- **Numbers** pakai Inter regular untuk price row biasa. Bebas Neue untuk macro
  spec (25g PROTEIN / 30 SERV / 120 kcal) di PDP dan tracking header.

## Layout

### Spacing System
- Base unit **8px**
- `{spacing.xxs}` 2px · `{spacing.xs}` 4px · `{spacing.sm}` 8px · `{spacing.md}` 12px ·
  `{spacing.lg}` 18px · `{spacing.xl}` 24px · `{spacing.xxl}` 30px · `{spacing.section}` 48px
- Section rhythm: **48px** vertical gap between major blocks (hero → trending →
  brand tile → footer). Never <32px, never >64px.
- Product cards: **0 internal padding** — image full-bleed, metadata rows
  langsung di bawah dengan 8px gap antar rows.

### Grid
- Mobile-first: single column at <600px
- 2-up product grid at 600-1024px
- 3-up product grid at 1024px+
- Max content width ~1440px dengan edge gutters 16px mobile → 80px ultrawide

### Whitespace Philosophy
Whitespace adalah tool separation, bukan breath. Section langsung butt against
each other vertically. Foto product tile edge-to-edge di grid — no padding around
image. "Udara" datang dari `{colors.soft-cloud}` stage foto, bukan dari layout
margin.

## Shape

### Border Radius
| Token | Value | Use |
|---|---|---|
| `{rounded.none}` | 0 | Cards, campaign tiles, product images, navigation, footer |
| `{rounded.sm}` | 18px | Avatar container di member card |
| `{rounded.md}` | 24px | Search pill, input, filter dropdown |
| `{rounded.lg}` | 30px | ALL CTA pills — primary, secondary, on-image, filter chip |
| `{rounded.full}` | 9999px | Swatch dots (10px), circular icon buttons (36px) |

### Two-Shape Vocabulary
Sistem cuma punya 2 shape: **pill** (rounded 24-30px) untuk semua interactive
chrome, dan **flat rectangle** (rounded 0) untuk semua containers. Tidak ada
`rounded.sm` di card, tidak ada sharp corner di CTA. Konsisten across the app.

## Elevation

- **Level 0 — Flat** — default untuk semua card, button, section. No shadow.
- **Level 1 — Hairline** — 1px solid `{colors.hairline}` sebagai divider antar
  filter row, footer column, PDP disclosure
- **Level 2 — Inset** — `box-shadow: inset 0 -1px 0 {colors.hairline-soft}` di
  sticky utility bar bottom edge

**Zero drop-shadow** di retail chrome. Card ga "lift" from page. Depth cue
cuma dari 1px inset hairline pada sticky strip dan contrast full-bleed
photography vs `{colors.soft-cloud}` product backdrop.

## Voice & Tone

### Language Mix
Findest customer mostly Indonesia-speaking. UI copy mix Indonesian utility
dengan English editorial:
- **Editorial hero** — English imperative ("Fuel The Session.", "On The Way.",
  "Just In.")
- **Section header** — Indonesian ("Sering Lu Pesan", "Brand Kami")
- **CTA** — English single-verb ("Add to Bag", "Checkout", "Place Order")
- **Body copy** — Indonesian natural, no formal ("Kirim ke", "Estimasi tiba
  11:15", "3 produk · Fitness Plus Sanur")

### Tone
- **Athletic-professional** — bukan gym bro slang, bukan corporate formal
- **Imperative** untuk CTA ("Add", "Checkout", "Call") — direct action
- **Editorial** untuk hero ("Fuel", "Move", "Recover") — motivational moment
- **Utilitarian** untuk chrome ("Sort By", "3 items", "ETA 11:15") — no fluff

### Do's
- Short punchy phrases di hero
- Sentence case di body
- Uppercase in Bebas Neue display only
- Specific numbers ("3 items", "ETA 11:15") bukan vague ("some items", "soon")

### Don'ts
- Avoid "Selamat datang di aplikasi resmi kami" — corporate speak
- Avoid excessive emoji (max 1 per screen, only if functional)
- Avoid "Klik di sini!" — CTA harus self-descriptive verb
- Avoid ALL CAPS di body (uppercase reserved untuk Bebas display)

## Findest Business Rules

### Markup / Pricing
- Default markup **24%** dari HPP untuk brand baru (Muscle First, Evolene,
  Pranaon, Hotto, Sportisi, Rimba, Vector Labs, Provus)
- Existing ON products tetap markup **10%** (kompetitif untuk 13 gym exclusive)
- Sale price ditampilkan `{colors.sale}` + strike-through original + "% off"

### Customer Segmentation
| Tipe | Count | Access |
|---|---|---|
| Fitness Plus (exclusive gym) | 10 | Only ON products |
| Apotek | 15 | Semua brand + BPOM cert visible |
| F&B (cafe, resto) | 58 | Semua brand |
| Gym Lain (non-exclusive) | 8 | Semua brand |
| Reseller | 2 | Semua brand + wholesale price |
| Findest Point (outlet sendiri) | 7 | Internal — bukan customer |

App auto-filter product visibility based on customer segment.

### Payment Methods
- **Cash on Delivery** — bayar saat sampai
- **Transfer Bank** — BCA + upload bukti (dominant)
- **Kredit 30 Hari** — invoice payable, terverifikasi finance

Ditampilkan per customer profile — reseller dapat kredit 30 hari otomatis,
walk-in retail cuma COD/Transfer.

### Delivery
- **Same-day** kalo order sebelum 12:00 WITA (area Denpasar/Sanur/Kuta/Canggu)
- **Next-day** kalo order lebih siang atau area Ubud/Uluwatu
- Driver info di-track real-time via Supabase Realtime

## Components

Component definitions ada di frontmatter YAML atas. Berikut usage notes:

### `button-primary`
Pill hitam full ink. Satu per viewport, maksimal. Used at PDP "Add to Bag",
Cart "Checkout", Checkout "Place Order", Auth "Sign In".

### `button-secondary`
Pill soft-cloud grey. Alternate action ("Favorite", "Save for Later") di same
viewport. Never solo — always accompany primary.

### `button-outline-on-image`
Crisp white pill di full-bleed campaign photo. Position bottom-left. Universal
"Shop This Image" pattern. Padding lebih tight (10px 20px).

### `filter-chip` + `filter-chip-active`
Default: canvas bg, hairline border, ink text. Active: fully inverted ink bg,
canvas text. No middle state.

### `product-card`
Zero radius, zero shadow, zero padding. Foto full-bleed 1:1 di soft-cloud stage.
Metadata rows di bawah dengan 8px gap: swatch dots → tag → name → category → price.
Sale price di `{colors.sale}` + strike-through original + "% off".

### `campaign-tile`
Full-bleed photography (dark placeholder pakai gradient kalo real photo belum ada)
dengan Bebas Neue 56-96px headline burned in (uppercase). Overlay CTA pill di
bottom-left. Aspect ratio 4:5 mobile, 16:9 desktop.

### `qty-stepper`
Pill full-round dengan 1px hairline border. Minus/plus button transparent
inside pill, span di tengah menampilkan number. Compact — 26px height.

## Don'ts (Anti-Patterns)

- ❌ Drop shadows or card elevation
- ❌ Purple/cyan/orange decorative accent colors
- ❌ Sharp corner buttons (semua CTA harus pill 30px)
- ❌ Padding inside product cards (foto full-bleed langsung)
- ❌ Two campaign tiles same-scale in one row (alternate dengan 2-up product grid)
- ❌ Underline apapun selain inline text link + active nav
- ❌ Third button shape (cuma pill or icon-circular)
- ❌ Emoji as icon (pakai SVG monoline)
- ❌ Monospace font untuk data (Inter atau Bebas Neue only)
- ❌ Sale color `{colors.sale}` di background, CTA, atau chrome

## Do's

- ✅ Reserve Bebas 96px HANYA untuk editorial campaign hero
- ✅ Stage every product photo di `{colors.soft-cloud}` — the grey is the "studio"
- ✅ Pill 30px untuk semua CTA konsisten
- ✅ Section rhythm 48px antara major blocks
- ✅ Sale price merah + strike-through original + "% off" — trio pattern
- ✅ On-image CTA anchored bottom-left (universal "shop this image" position)
- ✅ Section header pakai border-bottom 1px `{colors.hairline}` — no decorative divider

## Responsive Behavior

| Breakpoint | Width | Key Change |
|---|---|---|
| mobile | 320-599px | Single column, campaign hero 4:5, Bebas hero 48-64px |
| tablet | 600-1023px | 2-up product grid, campaign hero maintains 4:5 |
| desktop | 1024-1439px | 3-up product grid, primary nav center cluster expanded |
| ultrawide | 1440px+ | Max content 1440px, outer gutters grow to 80px |

- Touch target minimum 44×44 (WCAG AAA). Pills 52px height, icon-circular 36px+8px hit padding
- Filter sidebar collapse to "Hide Filters" toggle < 1024px
- Editorial headline Bebas: 96px desktop → 64px tablet → 48px mobile, line-height stays 0.9

## Iteration Guide

1. Ubah 1 component saja per edit — verify semua token reference resolve
2. Reference tokens directly (`{colors.ink}`, `{component.button-primary}`,
   `{rounded.lg}`) — never paraphrase
3. Add new variants sebagai separate entries (`-active`, `-disabled`, `-focused`)
4. Default text ke `{typography.body-md}`; reach untuk `{typography.body-strong}`
   di product name & nav link; `{typography.display-campaign}` strictly untuk
   editorial hero
5. Keep `{colors.ink}` scarce per viewport — kalo lebih dari satu solid ink pill/
   block di same fold, neutralize satu ke `button-secondary`
6. Sebelum introduce new component, tanya: apakah bisa expressed dengan pill +
   flat-card + photography-on-soft-cloud vocabulary?

## Known Gaps

- **Real product photography** — currently SVG silhouette placeholders. Butuh
  foto asli tub/bottle di soft-cloud background untuk feel "real Nike-level"
- **Editorial hero imagery** — currently CSS gradient placeholder. Butuh foto
  atlet/gym context yang cinematic
- **Brand illustrations** — logo Muscle First/Evolene/Pranaon/dll belum ada
- **Dark mode not fully tested** — spec sudah ada tapi semua screen currently
  designed light-first
