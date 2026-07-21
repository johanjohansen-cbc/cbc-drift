# CBC KickOff 2026 — Design Handover

Front-end redesign for **event.cbcit.dk**, ready to integrate into the existing
WordPress (block) theme. Light, corporate, brand-accurate (CBC teal + green),
with a two-track program system.

The approved visual reference is **`preview/cbc-kickoff-approved.html`** — open
it in a browser. The WordPress assets in this package reproduce that design.

---

## What's in the box

```
theme.json                  Design tokens: colour, typography, spacing, button/link styles
assets/css/cbc-kickoff.css  Presentation styles, wired to theme.json via --wp--preset--* vars
assets/fonts/               Drop self-hosted woff2 here (see READ-ME-fonts.txt)
inc/cbc-kickoff.php          Enqueue (front + editor) + pattern-category registration
patterns/                   Section block patterns (hero, value-props, about, program, vendors, cta)
functions.php               Child-theme functions (Route A)
style.css                   Child-theme header (Route A)
DESIGN-TOKENS.md            Human-readable token reference + one-variable rebrand note
preview/                    The approved, signed-off design (source of truth)
```

---

## Decision note — pick a route based on the ACTIVE theme

**First, determine the active theme:** run `wp_is_block_theme()` (true = block/FSE
theme with a `templates/` folder and `theme.json`; false = classic theme).

### Route A — Child theme  (cleanest; survives parent updates)
Best when the active theme is a third-party/parent theme you don't want to edit
directly, block or classic.

1. Copy this whole folder into `wp-content/themes/cbc-kickoff-child/`.
2. In `style.css`, set `Template:` to the **active parent theme's folder slug**.
3. Add the fonts (see below), then activate the child theme.
4. `functions.php` already loads `inc/cbc-kickoff.php`. Done.

> If the parent is a **block theme**, the child's `theme.json` is merged over the
> parent's automatically. If it's a **classic theme**, `theme.json` still applies
> globally and the parent stylesheet is enqueued for you.

### Route B — Drop into the existing theme  (no new theme)
Best when you're already maintaining the active theme and just want the design in.

1. Copy `assets/`, `inc/`, and `patterns/` into the active theme folder.
2. **Merge** `theme.json`: if the theme already has one, merge the `settings.color.palette`,
   `settings.typography.fontFamilies`/`fontSizes`, `settings.spacing`, and the
   `styles` block in. If it has none, copy this one to the theme root.
3. In the theme's `functions.php`, add:
   ```php
   require get_stylesheet_directory() . '/inc/cbc-kickoff.php';
   ```
4. Add the fonts (see below).

Block themes auto-register the patterns in `/patterns`. (For a classic theme,
`inc/cbc-kickoff.php` registers them as a fallback.)

---

## Fonts (do this for either route)

Self-host for GDPR — see `assets/fonts/READ-ME-fonts.txt` for the exact filenames
the `theme.json` fontFace blocks expect. Latin subset covers æ ø å.

---

## Placing the sections

After activation, the patterns appear in the editor under the **"CBC KickOff"**
category (inserter → Patterns). Build the front page by inserting, in order:
**CBC Hero → CBC Value Props → CBC About → CBC Program → CBC Vendors → CBC CTA.**

In a block theme you can also paste them into a template/template-part
(e.g. `templates/front-page.html`). The site header (logo + nav) and footer are
left to the theme's existing template parts — `theme.json` restyles them via the
brand tokens (the logo mark + nav hover, buttons, and links pick up teal/green).

---

## Dynamic content mapping (important)

Two sections are presentational shells around data that the conference system
already manages — wire them to real output rather than leaving them static:

- **Program** (`patterns/cbc-program.php`): the schedule is in a core/html block
  so it renders as-is. In production, emit the **same markup** from the template
  that loops over sessions. Row recipe is documented at the top of that file.
  Track classes: `is-salg` (green) / `is-teknik` (teal); shared rows use
  `.cbc-slot.is-full`; section dividers use `.cbc-band`.
- **Vendors** (`patterns/cbc-vendors.php`): repeat the `.cbc-vcard` block per
  vendor. The circular logo badge falls back to the first letter; swap for the
  vendor's uploaded logo where available.

The hero/about/value-props/CTA are editable directly as blocks.

---

## Standards & compliance notes

- PHP is prefixed (`cbc_kickoff_`), `ABSPATH`-guarded, text-domain `cbc-kickoff`,
  assets cache-busted with `filemtime()`.
- No inline styles injected from PHP; all presentation is in the enqueued
  stylesheet or `theme.json`.
- Stylesheet loads in the editor too (`add_editor_style`) so patterns render true
  while editing.
- `prefers-reduced-motion` is respected (load-in animations disable).
- Colours meet AA for body text; track tags use tint-bg + deep-text for contrast.

## Re-skinning

Change `teal` (and `teal-deep`/`teal-wash`) in `theme.json` to match the official
CBC hex if it differs from `#14798A` — the entire site follows. See
`DESIGN-TOKENS.md`.
