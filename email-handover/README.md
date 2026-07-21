# CBC Email Templates — Style Migration Handover

Bring **every** email template in the conference system's template engine onto
the CBC brand: consistent header, footer, typography, colours, buttons instead
of plain-text CTAs — without changing what the emails *do*.

The gold-standard reference is **`reference/cbc-kickoff-invitation.html`** (a
fully built, validated invitation). The `partials/` are the reusable building
blocks. `EMAIL-CODING-STANDARDS.md` is the ruleset; `DESIGN-TOKENS.md` is the
palette/type. This kit is **read-only reference** — translate it into the
engine; don't serve these files directly.

> **Work in this order: investigate → propose a plan → wait for approval →
> migrate → verify. Don't edit templates until the plan is approved.**

---

## What's in the box
```
README.md                    This brief
EMAIL-CODING-STANDARDS.md    The email-safe ruleset (why tables, inline CSS, VML, etc.)
DESIGN-TOKENS.md             Brand colours, type, spacing for email
partials/
  layout.html                Master shell (head + wrapper + card + header/body/footer slots)
  header-hero.html           Teal hero header — announcements / marketing
  header-compact.html        Slim teal bar — transactional
  footer.html                Dark footer
  button.html                Bulletproof primary button (VML + <a>)
  card-strip.html            Optional 3-up highlight band
reference/
  cbc-kickoff-invitation.html  Fully built example following every standard
```

## Step 1 — Investigate (no edits)
1. Read `EMAIL-CODING-STANDARDS.md` and `DESIGN-TOKENS.md`, and open the reference HTML.
2. Locate the email template engine: which library/syntax (Blade, Twig, Handlebars, Liquid, Go templates, MJML, raw PHP…), where templates live, and how mail is assembled/sent.
3. **Inventory every template.** List each one with its purpose (e.g. tilmeldingsbekræftelse, password reset, mødeanmodning modtaget/accepteret/afvist, leverandør godkendt, reminder, program-ændring, invitation).
4. Identify the **shared layout** (if any) vs the per-template body, and catalogue each template's **dynamic variables / conditionals / loops** — these must survive untouched.
5. Note current state: inline vs `<style>`, table vs div layout, existing buttons vs plain links, whether a plain-text part is sent.

## Step 2 — Propose a plan (wait for approval)
- Map the partials to the engine's include/component system (e.g. `layout.html` → the engine's base layout the templates extend; `button.html` → a button include/macro).
- List every file you'll add or change, and show how each existing template will be refactored to extend the base.
- Produce the **per-template table** below (purpose → header variant → primary action → notes), so the human can sanity-check the button/header decisions before you touch anything.

## Step 3 — Establish the shared chrome
- Create/refactor a **base email layout** from `partials/layout.html`, wired to the engine. Keep the engine's existing variable names; map the neutral `{{ placeholders }}` to them.
- Turn `header-hero`, `header-compact`, `footer`, `button` (and optionally `card-strip`) into engine partials/includes/macros.
- Centralise the palette/type per `DESIGN-TOKENS.md`. (Email needs literal hex inline — if the engine supports it, expose them as template constants so they're defined once.)

## Step 4 — Migrate each template
For every template:
- Extend the base layout; move its unique content into the **body** slot; delete now-duplicated `<html>/<head>/header/footer` boilerplate.
- Restyle the body to the standards: table layout, inline styles, the type scale, tinted panels for detail blocks, dividers via `Line` colour.
- **Preserve all dynamic logic** — variables, `if`/loops, merge tokens — exactly. Don't rename anything.

### The two judgment rules (apply taste, not find-and-replace)
- **Button rule:** give each email **one** primary action and render *that* as the bulletproof button (`button.html`); set its label/URL from the existing variables. Keep secondary/inline links as styled teal links. Two buttons only if there are genuinely two distinct actions. Don't convert every link.
- **Header rule:** **hero** header for announcement/marketing mail (invitation, save-the-date, reminder, program update); **compact** header for transactional mail (confirmations, password reset, notifications). Use the `card-strip` only where it adds a real hook (e.g. the invitation) — not on transactional mail.

## Step 5 — Verify
- Render each migrated template with **sample data** (fill every variable; exercise conditionals/loops).
- Confirm no broken/renamed variables and that links resolve.
- Test rendering in **Outlook for Windows** specifically (VML button = rounded pill, spacing holds), plus Gmail and Apple Mail. A browser preview ≈ the non-Outlook clients only.
- If a plain-text part exists, update it to match each template's content.
- Produce a **migration summary**: every template, header variant chosen, primary action, and what changed.

## Guardrails
- Don't change business logic, recipients, send conditions, or variable names.
- Idempotent: re-running shouldn't double-apply chrome.
- Keep each template under ~102 KB (Gmail clipping).
- Work on a branch; show the summary + how to preview before anything ships.
- Keep æ ø å correct (UTF-8) end to end.

---

## Per-template plan (fill during Step 2)
| Template | Purpose | Header | Primary action (→ button) | Secondary links | Notes |
|----------|---------|--------|---------------------------|-----------------|-------|
| _e.g._ tilmeldingsbekraeftelse | Deltager confirmation | compact | "Se din tilmelding" | program-link | keep QR/ical if present |
| … | | | | | |
