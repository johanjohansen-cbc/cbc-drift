# CBC Driftsdokumentation — 00 · Oversigt

> **Formål:** Samlet, standardiseret teknisk dokumentation af produktionsserveren
> `server.cbcit.dk`, så en anden tekniker kan overtage driften uden forudgående
> kendskab. Dækker infrastruktur fra bunden: hardware, OS, netværk, adgang,
> software, sikkerhed, sites, drift, mail og backup.
>
> **Målgruppe:** Overtagende drifts-tekniker med Linux-/WordPress-/Plesk-erfaring.
> Trinene er konkrete; hvor en handling kræver credentials, henvises til
> break-glass-dokumentet (07), aldrig til hemmeligheden selv.
>
> **Verificeret:** Indholdet er bygget på en **live read-only SSH-inventory af
> produktionsboksen 2026-07-20**, ikke på hukommelse. Hver fil har en
> "Verificeret"-note. Cloudflare-lagets detaljer er markeret **‹CF-DASHBOARD›**
> og hentes fra Cloudflare-kontoen (kan ikke ses fra boksen).
>
> **Sidst opdateret:** 2026-07-20 · **Ejer:** Johan Johansen (johan@cbcit.dk)

---

## 1. Sådan er dokumentationen organiseret

Denne mappe (`_handover/drift/`) er den **samlede driftsmanual for hele serveren**:

| Fil | Indhold |
|---|---|
| **00-oversigt.md** (dette dok) | Arkitektur, hurtigfakta, kritiske invarianter, dok-vedligehold |
| **01-fundament.md** | Konti & leverandører · hardware/OS · netværk & DNS |
| **02-adgang-og-sikkerhed.md** | SSH · firewall (cbc_fw) · Cloudflare Tunnel/Access · origin-guard · hærdning |
| **03-software-og-sites.md** | Software-stack + versioner + frys-politik · pr-site-opsætning |
| **04-drift.md** | Deploy & release · cron/baggrundsjobs · mail (Brevo) · logs/overvågning |
| **05-backup-og-gendannelse.md** | Plesk→OneDrive · snapshots · restore-drill · RTO/RPO |
| **06-runbooks-og-laerdomme.md** | Trin-for-trin-runbooks · kendte gotchas · disaster recovery |
| **tools/web-exposure-check.sh** | Ekstern smoke-test: interne filer (docs/ m.m.) blokeret + site OK — kør efter restore/migrering |

**Relaterede, allerede eksisterende dokumenter** (i plugin-repoet — mere
applikations-/deploy-nære, refereres herfra frem for at blive dupliceret):

| Dok | Placering | Rolle |
|---|---|---|
| **04-hosting-checklist** | `wp-content/plugins/cbc-event-planner/docs/` | WP-Cron + hardening-tjekliste |
| **05-deploy-workflow** | samme | Detaljeret deploy-bibel (bare repos, deploy.sh, GitHub-mirror) |
| **06-security-pre-deploy** | samme | Kode- + server-sikkerhedsaudit |
| **08-hvis-sitet-er-nede** | samme (+ `.docx` til print) | Nødark for ikke-teknikere |
| **07 — break-glass-adgang** | **‹UDFYLD sted — se 06-runbooks §break-glass›** | Fuld adgang + credentials til alle systemer. Uden for git. |

---

## 2. Systemarkitektur (fugleperspektiv)

```
                                Internet
                                   │
                 ┌─────────────────┴──────────────────┐
                 │                                    │
     ┌───────────▼────────────┐          ┌────────────▼────────────┐
     │  Cloudflare             │          │  Kents load balancer    │
     │  (konto "CBC IT v2")    │          │  185.21.232.10-12        │
     │  · event.cbcit.dk       │          │  · datagaarden.dk        │
     │  · cbcit.dk             │          │  (KENTS-LB-TEMP, WIP)    │
     │  proxy + WAF + Access   │          │  Plesk-DNS, ej Cloudflare │
     │  CF = authoritative DNS │          │  Wordfence som WAF        │
     └───────────┬────────────┘          └────────────┬────────────┘
                 │ kun CF-IP'er på 80/443              │ kun LB-IP'er på 443
                 └────────────────┬───────────────────┘
                                  │
                    ┌─────────────▼──────────────┐
                    │  Hetzner vServer            │
                    │  server.cbcit.dk            │
                    │  178.104.70.94 / IPv6       │
                    │  Ubuntu 24.04 · nft cbc_fw  │
                    │ ┌─────────────────────────┐ │
                    │ │ Plesk Obsidian 18        │ │
                    │ │ nginx → Apache → PHP-FPM │ │
                    │ │ WordPress · MariaDB      │ │
                    │ └─────────────────────────┘ │
                    └──────┬───────────┬──────────┘
                  udgående │           │ admin-adgang
                      mail  │           │ (Plesk 8443 IKKE firewall-åben)
                           ▼           ▼
                    ┌──────────┐  ┌──────────────┐   backup
                    │  Brevo   │  │ Cloudflare   │   ────────►  Microsoft
                    │ SMTP 587 │  │ Tunnel → 8443│              OneDrive
                    └──────────┘  │ (bag Access) │            (Plesk daglig)
                                  └──────────────┘
```

**To fronting-modeller på samme boks** — hold dem adskilt i hovedet:

1. **Cloudflare-sporet** (`event.cbcit.dk`, `cbcit.dk`): al web-trafik gennem
   Cloudflare. Firewallen slipper kun Cloudflares IP-ranges ind på 80/443, og
   `cbc-origin-guard` afviser (403) enhver origin-anmodning der ikke kom via CF.
2. **Kent-LB-sporet** (`datagaarden.dk`): selvstændigt WordPress-site frontet af
   en ekstern load balancer (Kent), **ikke** Cloudflare. Bruger Plesk's egen DNS,
   er bevidst undtaget origin-guarden, og beskyttes af Wordfence på app-niveau.

---

## 3. Hurtigfakta (én-side-referencen)

| | |
|---|---|
| **Server** | Hetzner vServer `server.cbcit.dk` · 4 vCPU (AMD EPYC-Genoa) · 7,6 GB RAM · 150 GB · Ubuntu 24.04.4 LTS |
| **Primær IP** | `178.104.70.94` (v4) · `2a01:4f8:c2c:6018::1` (v6) |
| **Panel** | Plesk Obsidian 18.0.78.4 — via **`https://plesk-event.cbcit.dk`** (Cloudflare Tunnel `cbc-plesk` + Access; port 8443 er ikke firewall-åben) |
| **SSH** | `ssh cbc-prod` (root, key-only) — port 22 åben, password-auth slået fra |
| **Sites** | `event.cbcit.dk` (CBC Event Planner) · `cbcit.dk` (**WP + WooCommerce-webshop, QuickPay-betalinger**) · `datagaarden.dk` (selvstændigt WP) |
| **Stack** | nginx 1.30 → Apache 2.4 → PHP 8.4 · MariaDB 10.11 · WordPress 7.0.1 |
| **Mail** | Udgående via Brevo (`smtp-relay.brevo.com:587`) |
| **Backup** | Plesk daglig 00:00 → Microsoft OneDrive (rotation 7, ugentlig fuld) |
| **Deploy** | `git push both main` fra laptop → `deploy.sh`/`deploy-theme.sh` på server (se 04-drift) |
| **Break-glass** | Alle logins/credentials: dokument **07** (‹UDFYLD sted›) |

---

## 4. Kritiske invarianter ("rør ikke / husk altid")

Disse er indbygget i setuppet. Brydes de, går noget i stykker — ofte stille.

1. **Nye subscriptions SKAL have incoming mail slået fra.** En ny Plesk-
   subscription på et `*.cbcit.dk`-domæne kaprer ellers MX/mail-leveringen for
   hele `@cbcit.dk`. `cbcit.dk` og `datagaarden.dk` står derfor på
   *"Mail service: Disabled for incoming mail"*. **Sæt altid `mail --off` på nye
   subscriptions** (se 04-drift §mail).
2. **Version-frys frem til efter konferencen (september 2026).** WordPress-core
   (7.0.1) og PHP (8.4) må ikke opgraderes til næste major før efter eventet.
   Auto-apply er bevidst slået fra (`DISALLOW_FILE_MODS=true`); opdateringer
   overvåges kun (ugentlig notify-mail) og anvendes manuelt efter backup + test.
3. **`event.cbcit.dk`/`cbcit.dk` må kun nås via Cloudflare.** Firewallen +
   `cbc-origin-guard` håndhæver det. Rør ikke ved reglerne uden at forstå
   begge lag (se 02-adgang §firewall + §origin-guard).
4. **`datagaarden.dk` er undtaget origin-guarden med vilje** (nås via Kents LB).
   Tilføj den ALDRIG til origin-guarden, og fjern ikke `KENTS-LB-TEMP`-firewall-
   reglen uden at koordinere med Kent.
5. **Deploy sker via `git push both`** (prod bare repo + GitHub-mirror) — ikke
   direkte fil-redigering på serveren. Se 04-drift.
6. **DB-dumps i `/var/backups/cbc-pre-deploy/` indeholder PII** (password-hashes,
   deltagerdata). Mappen er `700`, filer `600`. Hold dem der.

---

## 5. Afgrænsning (hvad dette dok bevidst IKKE dækker)

- **n8n-automatiserings-boksen** — en *separat* Hetzner-server, endnu ikke sat op
  (planlagt efter konferencen). Den kører aldrig på denne boks. Dokumenteres
  særskilt når den etableres.
- **Applikationens interne kode/datamodel** — se plugin-repoets `docs/01-datamodel.md`
  m.fl. Dette dok er drift, ikke udvikling.
- **Faktiske credentials** — ligger i break-glass (07) + password manager, aldrig her.

---

## 6. Vedligeholdelse af dette dokument

- **Opdatér ved enhver infrastruktur-ændring** (ny subscription, firewall-regel,
  cert-fornyelse, versions-bump, backup-ændring). Notér dato i den relevante fils
  "Verificeret"-linje.
- **Versionér det** — mappen ligger pt. kun på Johans laptop. Anbefaling: commit
  `_handover/drift/` til et privat git-repo (fx GitHub-mirror-kontoen, jf.
  plugin-repoets §14), så den overlever laptop-tab på linje med koden.
- **Re-verificér mod boksen** mindst før hver konference: kør inventory-
  kommandoerne i hver fils "Verificeret"-note igen og ret afvigelser.

---

## 7. Dokumenthistorik

| Dato | Ændring | Af |
|---|---|---|
| 2026-07-20 | Oprettet. Fuld live-inventory af prod-boksen. CF-lag + break-glass-binding afventer. | Claude (Opus) under Johans supervision |
