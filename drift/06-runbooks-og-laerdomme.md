# CBC Driftsdokumentation — 06 · Runbooks & lærdomme

> Trin-for-trin-runbooks · kendte drifts-gotchas · disaster recovery ·
> break-glass-binding · reference-indeks.
> **Verificeret:** 2026-07-20. Break-glass-sektion (§4) afventer 07-placering.

---

## 1. Runbooks (almindelige opgaver)

### 1.1 Deploy ny kode
Se **04-drift §1**. Kort: `git push both main` (laptop) → på server `deploy-theme.sh`
så `deploy.sh`. **Verificér altid en statisk asset efter deploy** (se §2.1):
```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://event.cbcit.dk/wp-content/themes/cbc-child/style.css  # → 200
```

### 1.2 Rollback
Se **04-drift §1.4**. Scriptet printer den eksakte rollback-kommando ved hver kørsel.

### 1.3 Restore fra backup
Se **05-backup §2**. Plesk Backup Manager (via CF Tunnel) → vælg dato → Restore.

### 1.4 "Sitet er nede"
Følg **`docs/08-hvis-sitet-er-nede.md`** (nødark, også som `.docx` til print).
Kort: tjek mobildata → status.hetzner.com + cloudflarestatus.com → power-cycle i
Hetzner-konsol → vent 10 min → ellers kontakt Johan / break-glass.

### 1.5 Opret ny subscription (HUSK mail-invarianten)
```
Plesk → Subscriptions → Add. EFTERFØLGENDE STRAKS:
plesk bin subscription -u <domain> -mail_service false     # ellers kapres @cbcit.dk-mail!
```
Se **04-drift §3.3** + **00-oversigt §4 (invariant 1)**.

### 1.6 Anvend WP-/plugin-opdatering (efter frysen ophæves — tidligst efter konferencen)
1. Tag et manuelt Hetzner-snapshot (restore-punkt).
2. `su -s /bin/bash <sysuser> -c "…/wp core update"` (eller plugin/theme update) — aldrig via wp-admin (`DISALLOW_FILE_MODS`).
3. `wp cbc db migrate` (hvis plugin) + `systemctl reload plesk-php84-fpm`.
4. Smoke-test (browser + `wp cron event list`). Rollback = gendan snapshot.

### 1.7 Tilføj udgående integration (ny egress)
`cbc_fw` output-chain er **default drop**. Ny udgående port kræver en accept-regel,
ellers fejler forbindelsen stille. Tjek `journalctl -k | grep cbc_fw` for drops,
tilføj reglen, og opdatér firewall-persistensen (se 02-adgang §3.3).

### 1.8 Ny WP-side i plugin'et
Nye sider kræver manuel `ensure-pages` på prod (sider oprettes ikke automatisk ved
deploy). Se plugin-docs / kør plugin'ets side-provisionering efter deploy.

---

## 2. Kendte drifts-gotchas (dyrt lærte)

### 2.1 umask-lækage → ustylet site (KRITISK)
Deploy-scripts sætter `umask 077` for fortrolige backups. Den kan lække ind i
`git pull` → opdaterede filer bliver mode `600` → **nginx serverer statiske assets
(CSS/JS/fonte) som en anden bruger end ejeren → HTTP 403 → sitet renderer helt
ustylet, mens PHP-sider loader fint.** Lumsk: curl af HTML'en passerer (inline
styles virker), kun *linkede* assets 403'er. Scripts normaliserer nu perms
(755/644), men **verificér altid en statisk asset efter deploy** (§1.1).

### 2.2 chown-gruppe: plugin ≠ tema
Plugin-mappen ejes `<sysuser>:psaserv`; **temaer ejes `<sysuser>:psacln`**. Ved
manuel rollback: brug `chown --reference=../twentytwentyfive` for temaet, ellers
forkert gruppe → 403.

### 2.3 opcache serverer stale kode
Efter enhver kode-ændring **skal** `systemctl reload plesk-php84-fpm` køres, ellers
serveres den gamle kode fra opcache. Deploy-scripts gør det automatisk.

### 2.4 curl mod prod → 403 uden browser-UA
`event.cbcit.dk`/`cbcit.dk` er bag Cloudflare + origin-guard. En rå `curl` udefra
kan få 403. Brug browser-User-Agent (`-A "Mozilla/5.0"`) ved manuelle tests, eller
test fra selve boksen (loopback er origin-trusted).

### 2.5 `wp` som root forurener perms
Kør ALTID `wp` som sysuser via `su -s /bin/bash <sysuser>` — aldrig som root
(skaber root-ejede cache/transient-filer → efterfølgende 403/skrivefejl).

### 2.6 Mail-kapring ved ny subscription
Se §1.5. Den hyppigste fodbold: glemt `mail_service false` → `@cbcit.dk`-mail
holder op med at virke.

> **App-kode-lærdomme** (esc_js/nonce, SQL UTC-skew, tidszone-håndtering m.fl.)
> hører i plugin-repoets `docs/` + projekt-hukommelsen — ikke her. Dette er
> drifts-gotchas.

---

## 3. Disaster recovery
Se **05-backup §2.3** (snapshot → OneDrive → GitHub-mirror) + **08-nødark**.

---

## 4. Break-glass (07) — binding

Break-glass-dokumentet (**07**) indeholder logins/credentials og den fulde
adgangskæde. Det ligger **uden for git** (bevidst).

- **Model:** 07 er **pointer-only** — det indeholder ingen hemmeligheder selv,
  men peger på den delte CBC password manager (Roboform, safe notes) og
  `/root/cbc-deploy-creds.txt` på serveren. Der findes desuden en ledsagende
  **LLM-guide-prompt** (`07-break-glass-llm-guide-prompt.md`) der kan føre en
  efterfølger igennem overtagelsen skridt for skridt.
- **Placering (pr. 2026-07-20):** `C:\TMP` på Johans laptop — **midlertidig
  arbejdskopi** (revideret 2026-07-20, post-prod-dag). ⚠️ Skal flyttes til varig,
  laptop-uafhængig placering: privat GitHub-repo (dokumentet er "fortroligt, men
  ikke hemmeligt" by design) + opdateret print i pengeskabet (jf. 07 §11).
- **Dækning i 07 pr. system** (efter revisionen 2026-07-20 — "☐ vault" =
  beskrevet i 07, men selve credential-entry'en i Roboform skal verificeres/oprettes,
  jf. 07 §2-tjeklisten og §12-drillen):

| System | I 07? | Vault-entry verificeret? |
|---|---|---|
| Hetzner Cloud-konsol (+noVNC-redning) | ✅ §6.1/§8 | ✅ 2026-07-20 |
| SSH (root, nøgle `cbc_hetzner`) | ✅ §2/§4 | ✅ 2026-07-20 |
| Server-creds (`/root/cbc-deploy-creds.txt`) | ✅ §5 | — (på serveren) |
| Cloudflare **"CBC IT v2"** (+ Access/Tunnel) | ✅ §6.2 (rev. 2026-07-20) | ✅ 2026-07-20 |
| CF Tunnel connector-token | ✅ §2 (rev.) | ✅ 2026-07-20 |
| Plesk-admin (`plesk login admin`-metoden) | ✅ §5 | ✅ 2026-07-20 |
| Brevo (SMTP) | ✅ §6.3 | ✅ 2026-07-20 |
| Microsoft 365/OneDrive + **backup-krypteringspassword** | ✅ §6.5 | ✅ 2026-07-20 |
| GitHub-mirror (`johanjohansen-cbc`, nøgle `cbc_github`) | ✅ §6.4 | ✅ 2026-07-20 |
| Domæneregistrar (**Simply.com**) | ✅ §6.6 | ✅ 2026-07-20 |
| **QuickPay** (webshop-betalinger) | ✅ §6.7 | ✅ 2026-07-20 — CBC IT ejer konto+indløseraftale |
| Kent / LB (datagaarden) | ✅ §6.8 | ✅ Kent Grady, kgrady@kobalt.dk |

> **Vault-model:** Roboform; entries som safe notes/gemte logins under servicens
> navn. Verificeret af Johan 2026-07-20 (alle 11 punkter). Næste trin er
> **07 §12-drillen med en KOLLEGA** — Johans egen verifikation beviser at
> nøglerne findes, drillen beviser at en *anden* kan bruge dem. Ingen
> credentials gengives i denne manual.

> **⏰ NYT ÅBENT PUNKT (fundet 2026-07-20):** Aftalen med Kobalt (Kent Grady)
> **ophører 2026-12-31** → datagaarden.dk mister sin fronting (Kents LB).
> Beslut i efteråret: flyt datagaarden bag Cloudflare (som de øvrige sites —
> origin-guard-undtagelsen og `KENTS-LB-TEMP` ryddes så op samtidig) eller
> etablér anden fronting. Efter konferencen, FØR december.

---

## 5. Reference-indeks (alle dokumenter)

**Denne driftsmanual** (`_handover/drift/`):
`00-oversigt` · `01-fundament` · `02-adgang-og-sikkerhed` · `03-software-og-sites`
· `04-drift` · `05-backup-og-gendannelse` · `06` (dette).

**Plugin-repoets `docs/`** (applikations-/deploy-nære):
`04-hosting-checklist` · `05-deploy-workflow` · `06-security-pre-deploy` ·
`08-hvis-sitet-er-nede` (+ `.docx`).

**Uden for git:** `07 — break-glass-adgang` (‹UDFYLD sted›) · restore-drill-runbook.

**Eksternt:** Hetzner-konsol (`console.hetzner.cloud`) · Cloudflare-dashboard
(`dash.cloudflare.com`, CBC IT v2) · Brevo · Plesk-panel (via CF Tunnel).
