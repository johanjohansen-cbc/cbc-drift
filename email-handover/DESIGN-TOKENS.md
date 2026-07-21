# CBC Email — Design Tokens

Same brand system as the website and slide deck, expressed for email (hex,
inline). Email can't use CSS variables reliably, so these are literal values —
keep them consistent with `theme.json` on the web side.

## Colour
| Token | Hex | Use in email |
|-------|-----|--------------|
| Brand teal | `#14798A` | Hero/header background, primary button, links, bold labels |
| Teal deep | `#0E5C6A` | Button hover (supporting clients), time labels |
| Teal wash | `#E2F0F2` | Tinted panels, "Messe" chip card |
| Brand green | `#5BAE3A` | Accent dot in wordmark, "2026" highlight, "Møder" chip, footer link |
| Green deep | `#3F8A27` | Green text where contrast matters |
| Green wash | `#E9F4E3` | "Møder" chip card background |
| Ink | `#16201F` | Body text, footer background |
| Ink soft | `#3A4744` | Secondary body text |
| Paper | `#F7F8F6` | Page background, neutral panels |
| Surface | `#FFFFFF` | Card background |
| Line | `#E5E9E5` | Borders / row dividers |
| Muted | `#69736F` | Tertiary text, legal line |
| Light-on-teal | `#CFE7EB` | Secondary text on the teal hero |

## Type
- Headline: `Arial, Helvetica, sans-serif`, bold, letter-spacing ~ -1px. Hero H1 ~46/50 (→34/38 on mobile).
- Body: `Arial, Helvetica, sans-serif`, 16/24, color Ink; secondary Ink-soft.
- Flourish: `Georgia, 'Times New Roman', serif` italic (dates only).
- Eyebrow/labels: 12–13px bold, letter-spacing 1.5–2px, uppercase.

## Spacing
- Card width 600px; side padding 40px desktop → 24px mobile (`.px`).
- Section padding ~32px vertical inside the body cell.

## Brand wordmark (no image needed)
`CBC <span style="color:#5BAE3A">&bull;</span> Event` — white on teal in headers, ink in the footer line. Swap for a hosted logo PNG only if you have one optimised for email.
