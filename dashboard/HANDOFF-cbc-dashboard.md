# Handoff → Claude Code: CBC Event konferenceoverblik-dashboard

## Formål

Vi har designet et nyt, sleek dashboard til siden **CBC Event → konferenceoverblik** i WP-admin.
Den færdige, godkendte prototype ligger i `cbc-event-dashboard.html` (vedlagt). Din opgave er at
integrere designet i det eksisterende CBC Event-plugin — **uden at røre forretningslogikken**.
Al datafunktionalitet (deltagere, leverandører, stande, noter, overnatning, aftenfest, annullering)
er allerede kodet. Du skal koble den eksisterende data på den nye markup.

**Vigtigt:** Backenden bor i WP-admin. Respekter de begrænsninger det giver (se §6).

---

## 1. Orientér dig først (gør dette før du ændrer noget)

Prototypen er lavet ud fra to skærmbilleder af den nuværende overbliksside. Den side **findes allerede**
— den har i forvejen "Vis (28)"-fold-ud og annullér-links. Find den og forstå den, før du skriver kode:

1. Lokalisér plugin-mappen (sandsynligvis `wp-content/plugins/` — søg efter teksten
   `konferenceoverblik` eller menupunktet `CBC Event`).
2. Find render-callbacken for overblikssiden — søg efter `add_menu_page` / `add_submenu_page`
   og teksten `CBC Event — konferenceoverblik` eller `Nøgletal` / `Fordeling`.
3. Kortlæg datakilderne, der allerede leverer:
   - antal deltagere + liste (navn, firma)
   - antal leverandører + liste
   - **antal stande solgt + fordeling pr. leverandør** (brugeren bekræfter at dette er kodet — find kilden)
   - aftenfest (deltagere + leverandører)
   - overnatning dagen før / på dagen (deltagere + leverandører)
   - **noten** der angives ved tilmelding for både deltagere og leverandører (find feltnavnet)
   - annullér-handlingen inkl. dens **nonce/capability-tjek**
4. Notér eksisterende funktions-/metode-navne, så du genbruger dem 1:1 i stedet for at duplikere.

> Skriv et kort resumé af hvad du fandt (filer, funktioner, datafelter), før du går i gang.

---

## 2. Sådan ser den nye struktur ud

Layoutet i prototypen:

- **Header**: titel + "Aktiv konference"-badge.
- **KPI-stribe** (6 felter): Deltagere, Leverandører, Stande solgt, Aftenfest, Overnatning dagen før,
  Overnatning på dagen. Hvert felt: lille label + stort tal + en sub-linje.
- **Venstre kolonne — Tilmeldinger**: fold-ud-kort for *Deltagere* og *Leverandører*
  (navn · firma/kontakt, annullér-link, og **note vist inline når den findes**).
  Deltagerkortet har en klient-side filterboks.
- **Højre kolonne — Stande + Logistik**:
  - *Stande solgt*: total + fordeling pr. leverandør med proportional bjælke.
  - *Aftenfest* / *Overnatning dagen før* / *Overnatning på dagen*: hver folder ud i to
    undergrupper (Deltagere / Leverandører) vist som "chips".

Al CSS er scoped under `.cbc-dashboard`. Fold-ud bruger native `<details>`/`<summary>` (ingen JS-afhængighed).
Den eneste JS er filterboksen.

---

## 3. Integrationsopgaver

### 3a. Assets (CSS + JS) enqueues korrekt — ikke inline
Flyt CSS'en fra prototypens `<style>` ud i en separat fil i pluginet, fx
`assets/admin/css/cbc-dashboard.css`, og filter-JS'en til `assets/admin/js/cbc-dashboard.js`.

- Enqueue **kun på overblikssiden** — ikke globalt i admin. Brug `$hook`-argumentet fra
  `admin_enqueue_scripts`, eller `get_current_screen()->id`, til at gate det.
- Versionér med plugin-versionen for cache-busting.
- **Fjern** følgende fra prototypen — de var kun til preview: `body { … }`-reglerne,
  `.cbc-wp-notice`-blokken (det er WP's egen opdateringsnotits), og det indledende HTML-kommentarboilerplate.

```php
add_action('admin_enqueue_scripts', function ($hook) {
    // Erstat med pluginets faktiske hook-suffix for overbliksiden:
    if ($hook !== 'toplevel_page_cbc-event') {
        return;
    }
    $ver = CBC_EVENT_VERSION; // brug pluginets eksisterende versions-konstant
    wp_enqueue_style('cbc-dashboard', plugins_url('assets/admin/css/cbc-dashboard.css', __FILE__), [], $ver);
    wp_enqueue_script('cbc-dashboard', plugins_url('assets/admin/js/cbc-dashboard.js', __FILE__), [], $ver, true);
});
```

### 3b. Markup ind i render-callbacken
Læg dashboard-markuppen (alt fra `<div class="cbc-dashboard">` til dens lukkende `</div>`) ind i den
eksisterende render-funktion. Behold gerne en ydre `<div class="wrap">` udenom, så siden flugter med WP-admin.

### 3c. Erstat sample-data med rigtige loops
Prototypen er fyldt med hardcodede demo-navne. Erstat dem med pluginets data. Eksempelmønstre:

**KPI-tal** — brug de eksisterende tællere; ingen nye queries hvis de allerede findes.

**Deltagerliste** med note + annullér:
```php
<ul class="cbc-list" data-list="deltagere">
<?php foreach ($deltagere as $d) : ?>
    <li class="cbc-person">
        <span class="who">
            <span class="name"><?php echo esc_html($d->navn); ?></span>
            <span class="org"><?php echo esc_html($d->firma); ?></span>
            <?php if (!empty($d->note)) : ?>
                <div class="cbc-note">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M5 4h11l3 3v13H5z"/><path d="M8 9h7M8 13h7M8 17h4"/></svg>
                    <span><b>Note:</b> <?php echo esc_html($d->note); ?></span>
                </div>
            <?php endif; ?>
        </span>
        <a href="<?php echo esc_url($cancel_url); ?>" class="cbc-cancel">Annullér</a>
    </li>
<?php endforeach; ?>
</ul>
```
Samme mønster for leverandører (med kontaktperson i `.org` i stedet for firma).

**"X med note"-tælleren** i korthovedet: udregn `count()` af dem med ikke-tom note og indsæt i `.meta`.
Gør det samme for leverandørkortet.

**Stande-fordeling** — beregn bjælkebredden proportionalt med den højeste værdi:
```php
<?php $max = max(array_map(fn($s) => $s->antal, $stande)) ?: 1; ?>
<?php foreach ($stande as $s) : ?>
    <div class="cbc-stand-row">
        <span class="vendor"><?php echo esc_html($s->leverandor); ?></span>
        <span class="qty"><?php echo (int) $s->antal; ?></span>
        <span class="cbc-bar"><i style="width:<?php echo round($s->antal / $max * 100); ?>%"></i></span>
    </div>
<?php endforeach; ?>
```
Total i `.cbc-count` = `array_sum` af antallene; sub-linjen "N leverandører" = `count($stande)`.

**Logistik-chips** (aftenfest / overnatning) — loop navnene ind som `<span class="cbc-chip">`.
Hold tællerne i `.sg-count` / `.cbc-count` i sync med de faktiske array-længder.

### 3d. Annullér-handlingen
Genbrug pluginets **eksisterende** annullér-flow uændret (action, nonce, capability-tjek, redirect).
Du må kun ændre, hvordan linket *præsenteres* — ikke hvad det gør. Hvis det nuværende link bruger en
nonce-genereret URL, så byg samme URL og læg den i `href`.

---

## 4. Sikkerhed & output (ufravigeligt)

- Escape **alt** dynamisk output: `esc_html()`, `esc_attr()`, `esc_url()`.
- Beskyt annullér og enhver state-ændrende handling med nonce + `current_user_can()` — genbrug
  det der allerede er der; tilføj ikke nye usikrede handlinger.
- Ingen rå SQL i templaten — kald de eksisterende data-lag/funktioner.

---

## 5. Tilgængelighed & kvalitet

- Behold synligt tastaturfokus og `prefers-reduced-motion`-reglen fra prototypen.
- Tjek at fold-ud virker uden JS (det er native `<details>`).
- Filter-JS'en skal fejle pænt hvis listen ikke findes (det gør den allerede — `if (!list) return;`).
- Responsivt ned til mobil — kolonnerne stacker via de eksisterende media queries.

---

## 6. WP-admin-begrænsninger (respekter disse)

- **Scope al CSS** under `.cbc-dashboard` — ingen bare element-selektorer på `body`, `h1`, `table` osv.
  der kan lække ud i resten af admin. (Prototypen overholder det allerede.)
- **Ingen eksterne fonte/CDN'er.** Systemfont-stakken er bevidst valgt. Ikoner er inline-SVG —
  alternativt brug WP's indbyggede **Dashicons** (allerede tilgængelige i admin) hvis I foretrækker det.
- Indlæs ikke assets på andre admin-sider (se §3a-gating).
- Antag at WP's egne stylesheets er aktive på siden — test at intet brækker visuelt sammen med dem.

---

## 7. Definition of done

- [ ] Overbliksiden viser det nye dashboard med rigtige data fra pluginet.
- [ ] KPI-tal, "X med note", stande-total/fordeling og alle undergruppe-tællere matcher data.
- [ ] Noter vises kun når de findes — og er korrekt escaped.
- [ ] Annullér virker præcis som før (nonce + capability bevaret).
- [ ] CSS/JS enqueues kun på denne side, versioneret, scoped, uden global lækage.
- [ ] Ingen forretningslogik ændret; kun præsentationslaget.
- [ ] Preview-rester fjernet (`body`-styles, WP-notits, boilerplate-kommentar).
- [ ] Responsivt + tastaturfokus + reduced-motion intakt.

---

## 8. Åbne beslutninger (afklar med ejeren før build, hvis muligt)

1. **Stande** som egen sektion (som nu) vs. flettet ind ved hver leverandør i leverandørlisten?
2. Skal **lange noter** kunne klappes sammen, eller altid vises fuldt ud (nuværende adfærd)?
3. Ikoner: behold inline-SVG, eller skift til **Dashicons** for konsistens med resten af admin?

Hvis de ikke kan afklares nu, byg efter den nuværende prototype-adfærd og flag valgene i din PR-beskrivelse.
