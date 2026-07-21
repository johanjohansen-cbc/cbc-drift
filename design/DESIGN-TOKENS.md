# CBC KickOff 2026 — Design Tokens

All tokens live in `theme.json` and are exposed by WordPress as CSS custom
properties (`--wp--preset--…`). `assets/css/cbc-kickoff.css` consumes those
variables, so **changing a value in `theme.json` re-skins the whole site.**

## Colour

| Slug | Hex | Role |
|------|-----|------|
| `ink` | `#16201F` | Primary text |
| `ink-soft` | `#3A4744` | Secondary text |
| `paper` | `#F7F8F6` | Page background |
| `surface` | `#FFFFFF` | Cards / panels |
| `line` | `#E5E9E5` | Hairlines / borders |
| `muted` | `#69736F` | Tertiary text |
| `teal` | `#14798A` | **Brand primary** — buttons, links, Teknik track, CTA block |
| `teal-deep` | `#0E5C6A` | Hover / strong |
| `teal-wash` | `#E2F0F2` | Teal tint |
| `green` | `#5BAE3A` | **Brand accent** — brand dot, Salg track, alt cards |
| `green-deep` | `#3F8A27` | Readable green (text/tags) |
| `green-wash` | `#E9F4E3` | Green tint |

Sampled from the CBC logo (teal wordmark + green Denmark mark).

### Re-brand in one move
If the official CBC teal differs from `#14798A`, change **only** the `teal`
(and matching `teal-deep` / `teal-wash`) entries in `theme.json`. Everything
else follows automatically. Same for `green`.

## Typography

| Family | Slug | Use |
|--------|------|-----|
| Bricolage Grotesque | `bricolage` | Headlines, stats, event titles |
| Hanken Grotesk | `hanken` | Body text, UI |
| Instrument Serif (italic) | `instrument` | Single editorial flourish (date, "1:1-møder") |

Font sizes are fluid: `small`, `medium` (17px body), `large`, `x-large`,
`xx-large` (section H2), `huge` (hero H1, clamps 48→124px).

## Spacing

Custom spacing scale slugs `30`–`80` (12px → clamp 80–140px). Section vertical
rhythm is `clamp(64px, 9vw, 96px)` via `.cbc-section`.

## The two-track system

The program colour-codes sessions independently of room names:
**Salg = green**, **Teknik = teal**, **Fælles (shared) = ink**.
Driven by `.cbc-cell.is-salg` / `.is-teknik` and `.cbc-track.is-salg` / `.is-teknik`.
