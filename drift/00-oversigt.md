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
> produktionsboksen 2026-07-20**, ikke på hukommelse, og **re-verificeret ved en
> fuld read-only sikkerhedsscanning 2026-10-26** (server, alle tre WP-sites,
> ekstern portscan/DNS/HTTP og Cloudflare-API). Hver fil har en
> "Verificeret"-note. Cloudflare-lagets detaljer er markeret **‹CF-DASHBOARD›**
> og hentes fra Cloudflare-kontoen/-API'et (kan ikke ses fra boksen).
>
> **Sidst opdateret:** 2026-10-27 · **Ejer:** Johan Johansen (johan@cbcit.dk)

---

## 1. Sådan er dokumentationen organiseret

Denne mappe (`_handover/drift/`) er den **samlede driftsmanual for hele serveren**:

| Fil | Indhold |
|---|---|
| **00-oversigt.md** (dette dok) | Arkitektur, hurtigfakta, kritiske invarianter, dok-vedligehold |
| **01-fundament.md** | Konti & leverandører · hardware/OS · netværk & DNS |
| **02-adgang-og-sikkerhed.md** | SSH · firewall (cbc_fw) · Cloudflare Tunnel/Access · origin-guard · hærdning |
| **03-software-og-sites.md** | Software-stack + versioner + opdateringspolitik · pr-site-opsætning |
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
| **07 — break-glass-adgang** | **`drift/07-break-glass-adgang.md` i dette repo** (+ `.docx`-printudgave til pengeskabet; kanonisk hjem = privat GitHub `johanjohansen-cbc/cbc-drift`) | Adgangs-nøglen: HVOR alle logins/credentials ligger (pointer-only — ingen hemmeligheder i selve dokumentet). |
| **Server-runbook (hærdning okt. 2026)** | `/root/cbc-hardening-2026-10/README.md` **på serveren** | Egress-filter, disable_functions, nginx-grænser, sikkerhedsopdaterings-cron, advisory-watch, audit-rettelser 26/10 — med rollback pr. ændring |

---

## 2. Systemarkitektur (fugleperspektiv)

```
                                Internet
                                   │
                    ┌──────────────▼──────────────┐
                    │  Cloudflare                  │
                    │  (konto "CBC IT v2")         │
                    │  · event.cbcit.dk            │
                    │  · cbcit.dk                  │
                    │  · datagaarden.dk (+IDN)     │
                    │    ↳ CF for SaaS →           │
                    │      sites.cbcit.dk          │
                    │  proxy + WAF + Access        │
                    │  CF = auth. DNS (cbcit.dk);  │
                    │  datagaarden-DNS hos wwi     │
                    └──────────────┬──────────────┘
                                   │ kun CF-IP'er på 80/443
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

**Én fronting-model for alle sites** (siden 2026-08-26 — før da kørte
`datagaarden.dk` midlertidigt bag Kents LB, "SPOR B-broen", nedlagt 2026-08-27):

1. **Cloudflare-sporet** (`event.cbcit.dk`, `cbcit.dk`): al web-trafik gennem
   Cloudflare. Firewallen slipper kun Cloudflares IP-ranges ind på 80/443, og
   `cbc-origin-guard` afviser (403) enhver origin-anmodning der ikke kom via CF.
2. **CF-for-SaaS-varianten** (`datagaarden.dk` + `datagården.dk`): selvstændigt
   WordPress-site med DNS hos **wwi** (ikke CF). www-CNAME'er + apex-ANAME'er
   peger på `sites.cbcit.dk` i cbcit.dk-zonen; CF "for SaaS" custom hostnames
   terminerer TLS og proxier til samme origin. Samme firewall- og origin-guard-
   beskyttelse som sporet ovenfor + Wordfence på app-niveau.

---

## 3. Hurtigfakta (én-side-referencen)

| | |
|---|---|
| **Server** | Hetzner vServer `server.cbcit.dk` · 4 vCPU (AMD EPYC-Genoa) · 7,6 GB RAM · 150 GB (25 % brugt) · Ubuntu 24.04.5 LTS (kernel 6.8.0-147, pr. 2026-10-26) |
| **Primær IP** | `178.104.70.94` (v4) · `2a01:4f8:c2c:6018::1` (v6) |
| **Panel** | Plesk Obsidian 18.0.81.4 — via **`https://plesk-event.cbcit.dk`** (Cloudflare Tunnel `cbc-plesk` + Access; port 8443 er ikke firewall-åben). Verificeret 2026-10-27: hostnavnet svarer 302 → Access-login. |
| **SSH** | `ssh cbc-prod` (root, key-only) — port 22 åben, password-auth slået fra for alle **undtagen** SFTP-chroot-brugeren `datagaardendk`, som kun kan logge ind med password **fra Datagaardens kontor-IP 87.55.238.154** (låst 2026-10-26); partner-dropbox `kent` er nøgle-only (se 02 §2.1) |
| **Sites** | `event.cbcit.dk` (CBC Event Planner, plugin 2.7.0) · `cbcit.dk` (**WP + WooCommerce-webshop, QuickPay-betalinger**) · `datagaarden.dk` (selvstændigt WP) — alle **WordPress 7.1.3** |
| **Stack** | nginx 1.30.5 → Apache 2.4.58 → PHP 8.4.27 (FPM) · MariaDB 10.11.14 |
| **Mail** | Udgående via Brevo (`smtp-relay.brevo.com:587`); Postfix lytter kun på loopback |
| **Backup** | Plesk daglig 00:12 → Microsoft OneDrive (rotation 7, ugentlig fuld; seneste fuld 2026-10-21, inkrementel hver nat — verificeret 2026-10-26); **password-krypteret fra 2026-08-18** (password i password manager, kræves ved restore); gendannelse BEVIST ved restore-drill 2026-08-18 (05 §3.1). Hetzner-snapshot ugentligt mandag 09:00 fra Johans PC (seneste 2026-10-26 OK) |
| **Patch-kadence** | OS-security + Plesk-PHP hver 4. time (`cbc-security-updates.sh`, siden 2026-10-23; dækker også cloudflared/Imunify siden 2026-10-26) · Plesk-komponenter natligt ~06:25 · advisory-watch dagligt 07:15 + ugentlig "alt OK"-mail mandag 07:30 · Imunify-malwarescan dagligt 03:00 · WP-integritetstjek dagligt 05:15 |
| **Deploy** | `git push both main` fra laptop → `deploy.sh`/`deploy-theme.sh` på server (se 04-drift) |
| **Break-glass** | Alle logins/credentials: dokument **07** (`drift/07-break-glass-adgang.md` + `.docx`) |

---

## 4. Kritiske invarianter ("rør ikke / husk altid")

Disse er indbygget i setuppet. Brydes de, går noget i stykker — ofte stille.

1. **Nye subscriptions SKAL have incoming mail slået fra.** En ny Plesk-
   subscription på et `*.cbcit.dk`-domæne kaprer ellers MX/mail-leveringen for
   hele `@cbcit.dk`. `cbcit.dk` og `datagaarden.dk` står derfor på
   *"Mail service: Disabled for incoming mail"*. **Sæt altid `mail --off` på nye
   subscriptions** (se 04-drift §mail).
2. **Opdateringspolitik (frysen blev ophævet 2026-10-08 efter konferencen).**
   Sikkerhedsopdateringer til OS og PHP installeres automatisk (hver 4. time).
   **WordPress-MAJOR-opgraderinger kun mellem konferencer**, altid med
   Hetzner-snapshot + DB-dump først og test på Local. På `event.cbcit.dk` er
   `DISALLOW_FILE_MODS=true` (ingen auto-opdatering af plugins — deploy via git);
   på `cbcit.dk`/`datagaarden.dk` auto-opdaterer de fleste plugins sig selv.
   PHP må ikke skifte major (8.5.x) uden test. Se 03-software §2.
3. **`event.cbcit.dk`/`cbcit.dk` må kun nås via Cloudflare.** Firewallen +
   `cbc-origin-guard` håndhæver det. Rør ikke ved reglerne uden at forstå
   begge lag (se 02-adgang §firewall + §origin-guard).
4. **`datagaarden.dk` er OGSÅ bag Cloudflare og origin-guarden** (siden
   2026-08-26/27; den historiske LB-undtagelse og `KENTS-LB-TEMP`-firewall-reglen
   er nedlagt). Custom-hostname-opsætningen bor i cbcit.dk-zonens
   "SSL for SaaS" — slet aldrig `sites.cbcit.dk`-recorden, den er fallback-origin.
5. **Deploy sker via `git push both`** (prod bare repo + GitHub-mirror) — ikke
   direkte fil-redigering på serveren. Se 04-drift.
6. **DB-dumps i `/var/backups/cbc-pre-deploy/` indeholder PII** (password-hashes,
   deltagerdata). Mappen er `700`, filer `600`. Hold dem der.
7. **Web-processernes udgående trafik er allowlistet (egress-enforce siden
   2026-10-23).** PHP-FPM-brugerne for de tre sites må kun kontakte ~70 kendte
   hostnavne + Google/Meta-ranges på 80/443/587. **Et nyt plugin, en ny
   licens-server eller et nyt API fra WordPress bliver tavst droppet**, indtil
   hostnavnet er tilføjet i `/etc/cbc-web-egress-hosts.txt` (runbook 06 §1.9).
   Den daglige egress-rapport (06:55) viser drops.
8. **XML-RPC er lukket på alle tre sites** (nginx 403 siden 2026-10-26). Jetpack,
   WordPress-mobilappen og andre XML-RPC-klienter virker derfor ikke — og skal
   ikke slås til uden at genåbne bevidst (02 §7.2).

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
- **Versionering (løst 2026-07-20):** mappen er et eget git-repo med kanonisk
  hjem i det private GitHub-repo `johanjohansen-cbc/cbc-drift`; arbejdskopi
  `C:\Users\JohanJohansen\Local Sites\cbc-event-planner\app\public\_handover\drift\`
  på Johans PC. Commit + `git push` efter hver ændring.
- **Server-runbooken** `/root/cbc-hardening-2026-10/README.md` (på boksen) er
  den operative log for hærdningsændringer siden okt. 2026 — skriv dér FØRST
  (med rollback), og løft essensen hertil bagefter.
- **Re-verificér mod boksen** mindst før hver konference: kør inventory-
  kommandoerne i hver fils "Verificeret"-note igen og ret afvigelser.

---

## 7. Dokumenthistorik

| Dato | Ændring | Af |
|---|---|---|
| 2026-07-20 | Oprettet. Fuld live-inventory af prod-boksen. CF-lag + break-glass-binding afventer. | Claude (Opus) under Johans supervision |
| 2026-07-21 | S2-portabilitet: verbatim nginx-direktiver (02 §7.2) + `tools/web-exposure-check.sh`. | Claude |
| 2026-08-18 | Restore-drill gennemført: 05 §2.3/§3.1 opdateret, backup password-krypteret. | Claude |
| 2026-08-27/28 | datagaarden.dk flyttet til CF for SaaS; Kents-LB-bro nedlagt (01/02/03/06/07). | Claude |
| 2026-10-27 | Fuld ajourføring efter okt. 2026: PHP-0-day (21/10), card-testing-hardening cbcit.dk (21/10), blast-radius-værn (egress-enforce, disable_functions, nginx-grænser 22–23/10), sikkerhedsopdaterings-cron + advisory-watch (23/10), fuld sikkerhedsscanning + rettelser (26/10: SFTP-IP-lås, XML-RPC lukket, filrettigheder, brugernavns-enumeration, CF-regler). Versioner, invarianter, runbooks og 07 opdateret. | Claude (Fable 5.1) under Johans supervision |
