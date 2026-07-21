# CBC Email — Coding Standards

These are the rules every CBC email template must follow. They exist because
**Outlook for Windows renders with Word's engine**, not a browser — so modern
CSS silently fails there. The reference implementation that follows all of this
is `reference/cbc-kickoff-invitation.html`.

## Structure
- XHTML Transitional doctype + the `v:` / `o:` namespaces on `<html>` (needed for VML buttons).
- One outer 100%-width table with a `bgcolor` page background; one centered **600px** inner "card" table. Max width 600.
- Layout is **tables only** — no flexbox, grid, float, `position`, or negative margins.
- Add `role="presentation"`, `cellpadding="0"`, `cellspacing="0"`, `border="0"` to every layout table; `mso-table-lspace/rspace:0pt`.

## CSS
- **Everything critical is inline.** The `<style>` block is progressive enhancement only (hover, mobile media query, a couple of resets) — assume Outlook ignores it.
- Colored backgrounds need **both** the `bgcolor="#…"` attribute **and** an inline `background:#…` (Outlook reads the attribute).
- No background-image gradients or images for Outlook — use a **solid** `bgcolor`. (The web hero's line-texture/gradient is intentionally dropped in email.)
- `border-radius` is fine but **degrades to square in Outlook** — acceptable everywhere except the primary button, which uses VML to stay a pill.

## Typography
- Font stack: `Arial, Helvetica, sans-serif`. The display headline is Arial bold + tight letter-spacing (Bricolage is NOT available in mail).
- The italic flourish (date) uses `Georgia, 'Times New Roman', serif` italic — the web-safe stand-in for Instrument Serif.
- Do not `@import` or rely on web fonts; if you add a `<link>`/`@font-face`, treat it as enhancement with the Arial fallback intact.

## Buttons vs links  (the important rule)
- Each email has **one primary action** → render it as the **bulletproof button** (`partials/button.html`): VML `roundrect` for Outlook + styled `<a>` for the rest. Min height ~44–50px (tap target).
- **Don't button-bomb.** Secondary and inline links stay as styled links (teal, bold, `text-decoration` as appropriate). Two buttons max, and only if there are genuinely two distinct actions.

## Images
- Host absolutely over **https**; never rely on inline `<svg>` (Outlook strips it). Logos as hosted PNG/GIF.
- Always set `alt`, `border:0`, `display:block`, an explicit `width`, and `-ms-interpolation-mode:bicubic`.
- Never build an email as one big image — many clients block images by default; text must carry the message.

## Accessibility & deliverability
- `lang="da"`, a real `<title>`, and a unique **preheader** (hidden preview line, 40–110 chars) per template.
- Maintain contrast (body text on white/paper passes AA).
- Include `meta color-scheme` / `supported-color-schemes` = light.
- Keep total HTML under ~**102 KB** (Gmail clips above that).
- UTF-8 throughout; verify **æ ø å** render (use entities like `&middot;`, `&rarr;` for symbols).
- If the system sends multipart, keep the **plain-text part** in sync with the HTML.

## Mobile
- `<meta viewport>` set; a `max-width:620px` media query makes the container fluid (`.container`), reduces side padding (`.px`), shrinks the H1 (`.h1`), and stacks multi-column rows (`.stack` / `.stack-gap`).
