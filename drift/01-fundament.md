# CBC Driftsdokumentation — 01 · Fundament

> Konti & leverandører · hardware/OS · netværk & DNS.
> **Verificeret:** 2026-07-20 via live SSH-inventory (`hostnamectl`, `ip`,
> `plesk bin`, `nft`); **re-verificeret 2026-10-26** (fuld read-only audit:
> `ss`, `nft`, ekstern portscan fra Windows, DNS-opslag, Cloudflare-API).
> Cloudflare-DNS/zone-detaljer markeret **‹CF-DASHBOARD›**.

---

## 1. Konti & leverandører

Alle **logins/credentials ligger i break-glass (07)** + password manager — herunder
kun *hvad* kontoen er og *hvad* den bruges til.

| Leverandør | Rolle | Konto/reference | Login |
|---|---|---|---|
| **Hetzner Cloud** | Serverhotel (vServer + snapshots) | Projekt m. server `server.cbcit.dk` (`cbc-server` i konsollen) | 07 |
| **Cloudflare** | DNS + proxy + WAF + Zero-Trust Access + Tunnel | Konto **"CBC IT v2"** | 07 |
| **Brevo** | Udgående SMTP-relay (transaktionsmail) | SMTP-konto, relay `smtp-relay.brevo.com:587` | 07 |
| **Microsoft OneDrive** | Off-site backup-destination (via Plesk-extension) | **Johans personlige** virksomheds-konto (johan@cbcit.dk), mappe `server.cbcit.dk` — ⚠️ personbundet, servicekonto-flytning besluttet som followup (05 §1.1) | 07 |
| **GitHub** | Privat kode-mirror (`cbc-event-planner`, `cbc-child`) | Bruger `johanjohansen-cbc` (private repos) | 07 |
| **Domæneregistrar** | Registrering af `cbcit.dk`, `datagaarden.dk` | **Simply.com** (Johan-verificeret 2026-07-20; 07 angav tidligere fejlagtigt punktum.dk) | 07 |
| **Kent / Kobalt (historisk)** | Load balancer foran `datagaarden.dk` **frem til DNS-flip 2026-08-26** (brofasen; LB-IP'er `185.21.232.10-12`, firewall-regel + undtagelser fjernet 2026-08-27) | Kent Grady, kgrady@kobalt.dk — aftalen ophører 2026-12-31 | 07 |
| **wwi** | DNS-udbyder for `datagaarden.dk` + `datagården.dk` (NS `ns1/ns2.wwi.dk`, `ns3.wwi.as`, `ns4.wwi.eu`) | Kontakt via site-ejeren (Data Gården) | — |

> Registrar (Simply.com), Kents kontaktinfo og Cloudflare-kontoen "CBC IT v2"
> (Pro-plan) er alle bekræftet (2026-07-20 / 2026-10-26). Eneste rest: formålet
> med zonen `cbcnet.dk` i samme CF-konto (§4.2).

---

## 2. Hardware & hosting

| | |
|---|---|
| **Udbyder** | Hetzner Cloud (EU — GDPR-relevant) |
| **Type** | **CPX32** (4 vCPU / 8 GB / 150 GB), server-id **135078172** (bekræftet i break-glass 07 §1/§6.1). **Bemærk:** de gamle plugin-docs nævnte "CX22" — forkert. |
| **CPU** | AMD EPYC-Genoa (4 vCPU) |
| **Disk** | 150 GB, 25 % brugt (35 GB) pr. 2026-10-26 |
| **Hostname** | `server.cbcit.dk` |
| **Konsol-navn** | `cbc-server` (i Hetzner Cloud-konsollen) |
| **OS** | Ubuntu 24.04.5 LTS |
| **Kernel** | 6.8.0-147-generic (pr. 2026-10-26) |
| **Tidszone** | Europe/Copenhagen |
| **Genstart** | Boksen genstarter **selv** kl. 04:00 når en kerne-opdatering kræver det (`unattended-upgrades` + Automatic-Reboot). Alle tjenester kommer automatisk op (verificeret i drift, bl.a. boots 2026-10-10 og 2026-10-14). |

**OS-/platform-opdateringer (siden 2026-10-23 — se 04-drift §2.3 + 06 §1.10):**
- `unattended-upgrades` (Ubuntu security, apt-daily ~01:20 / upgrade ~02:10).
- **`cbc-security-updates.sh` hver 4. time** (00:45, 04:45 …): Plesk-PHP
  (`plesk-php8*`), Ubuntu-security, og siden 2026-10-26 også `cloudflared`,
  `imunify*` og `alt-php-internal*`. Mailer johan@ kun når noget blev opgraderet.
  Baggrund: PHP-RCE'en CVE-2026-109618 (21/10-2026) blev først patchet af Plesks
  natkørsel ~14 t efter release.
- Plesk-komponenter (panel, nginx, MariaDB m.m.) via Plesks egen natkørsel ~06:25.
- **App-laget:** WP-core/plugins/temaer — se 03-software §2 (frysen er ophævet
  2026-10-08; majors kun mellem konferencer).

---

## 3. Netværk

### 3.1 IP-adresser

| Interface | Adresse |
|---|---|
| `eth0` (v4) | `178.104.70.94/32` |
| `eth0` (v6) | `2a01:4f8:c2c:6018::1/64` |
| loopback | `127.0.0.1`, `::1` |

### 3.2 Åbne/lyttende porte (fra `ss -tulpn` 2026-10-26 + ekstern TCP-scan af 24 porte fra Windows samme dag: **kun 22 og 80 svarer udefra**)

| Port | Bind | Tjeneste | Eksponering |
|---|---|---|---|
| **22** | `0.0.0.0`, `::` | SSH | Offentlig (firewall tillader; key-only for root; ~500 fejlede login-forsøg/uge = baggrundsstøj, fail2ban `ssh` + `recidive` aktive) |
| **80/443** | public IP | nginx (web) | **Kun Cloudflare-IP'er** (cbc_fw; port 80 dog ACME-åben, se 02) — Kents-LB-hullet på 443 fjernet 2026-08-27 |
| **8443** | `[::]`, `0.0.0.0` | Plesk-panel | **IKKE firewall-åben** → kun via Cloudflare Tunnel |
| **53** | public IP + local | BIND (Plesk DNS) | Offentlig (authoritative DNS for Plesk-styrede zoner) |
| **25 / 465 / 587** | localhost / ::1 | Postfix (mail) | Lokal + udgående relay til Brevo |
| **3306** | `127.0.0.1` | MariaDB | Kun localhost |
| 7080/7081/8880/8443 | localhost | Plesk interne | Lokal |
| udp høje porte | `*` | `cloudflared` (QUIC til CF edge, 7844 udad) | Udgående tunnel — intet lytter udefra |

> **Note port 53:** Boksen kører BIND og *tror* den er authoritative for de zoner
> Plesk styrer, men ingen offentlig delegering peger på den: `datagaarden.dk`s
> offentlige NS er **wwi** (`ns1/ns2.wwi.dk` m.fl.), og for
> `event.cbcit.dk`/`cbcit.dk` er **Cloudflare** authoritative. Plesk-zonerne er
> altså lokale kopier og *ikke* dem der besvares udadtil.

### 3.3 Firewall

Se **02-adgang-og-sikkerhed §firewall** — custom nftables-tabel `cbc_fw` med
input- **og** egress-filtrering.

---

## 4. DNS & fronting

### 4.1 Fronting pr. domæne

| Domæne | Authoritative DNS | Fronting | Origin-adgang |
|---|---|---|---|
| `event.cbcit.dk` | **Cloudflare** (CBC IT v2) | CF proxy + WAF + noindex | Kun via CF (firewall + origin-guard) |
| `cbcit.dk` | **Cloudflare** | CF proxy | Kun via CF |
| `datagaarden.dk` + `datagården.dk` (`xn--datagrden-92a.dk`) | **wwi** (`ns1/ns2.wwi.dk`, `ns3.wwi.as`, `ns4.wwi.eu`) | **CF for SaaS** (siden 2026-08-26): www-CNAME + apex-ANAME → `sites.cbcit.dk`; custom hostnames i cbcit.dk-zonen | Kun via CF (firewall + origin-guard, siden 2026-08-27) |

### 4.2 Cloudflare-zonen `cbcit.dk` (verificeret i dashboard 2026-07-20)

Plan: **Pro** · DNS Setup: Full (CF authoritative) · 59 records. Kontoen rummer
også zonen **`cbcnet.dk`** (‹UDFYLD: formål/indhold›).

**Records relevante for DENNE boks** (`178.104.70.94`):

| Record | Type | Peger på | Proxy |
|---|---|---|---|
| `cbcit.dk` (+`www` CNAME) | A | 178.104.70.94 | ✅ Proxied |
| `event.cbcit.dk` | A | 178.104.70.94 | ✅ Proxied |
| `sites.cbcit.dk` | A | 178.104.70.94 | ✅ Proxied — "SaaS fallback-origin/CNAME-target for kundesites (datagaarden m.fl.)" |
| `server.cbcit.dk` | A | 178.104.70.94 | ⚠️ **DNS only** — eksponerer origin-IP'en (CF's dashboard flager det). Bevidst? Mitigeret af firewall+origin-guard, men overvej at fjerne/omdøbe. |
| `plesk-event.cbcit.dk` | **Tunnel** | tunnel `cbc-plesk` | ✅ Proxied — "CF Access-gated Plesk panel via tunnel cbc-plesk (prod-dag 2026-07-10)" |

**Zonen rummer desuden et større CBC-økosystem UDEN FOR denne boks** (dokumenteres
her som kontekst, drift af dem er ikke dækket af denne manual): `api.cbcit.dk`
(91.98.12.232, "CBC backend API Hetzner LB"), `legacy.cbcit.dk` (deprecated CBCnet
v4), shop-platform (`lb.shop`/`shop-template`/`shop-redirect`/`tjdata` → Kents
LB-net 185.21.232.x), `stage.cbcit.dk` → **Cloudflare Pages** (`cbc-stage.pages.dev`),
`cdn.cbcit.dk` → **R2-bucket `cbc-product-images`**, `datagaarden.cbcit.dk` +
`docs.cbcit.dk` → Kents LB, dump/sponsor/remote/old-server/sftp-1/ext-ftp-selek
(diverse eksterne IP'er), samt MS365-integrationsrecords.

### 4.3 SSL/TLS & Origin-certifikater (verificeret i dashboard 2026-07-20)

- **Encryption mode (zone): `Full` — med "Automatic mode" aktiveret (~2026-06-23).**
  Zonen deles med ~18 hosts (bl.a. Kents LB), hvis certs CF ikke kan validere, så
  zone-niveauet hæves bevidst IKKE. I stedet er *Full (strict)* pinnet **pr. host**
  via Configuration Rules (ruleset "CBC config settings", fase
  `http_config_settings`, id `592ffe8d…`, læst/skrevet via API 2026-10-28):
  `event.cbcit.dk` (siden prod-dagen 2026-07-10) · `cbcit.dk` + `www` (juli 2026) ·
  `api.cbcit.dk` (Kents LB, Origin CA) · **`datagaarden.dk` + `www` (2026-10-28,
  regel-id `610ee39b…`, audit-punkt 9)**. Alle CBC-origins kører dermed Strict,
  verificeret udefra 28/10 (200/301, ingen 526). IDN-aliasset `datagården.dk` er
  bevidst IKKE med (intet cert, kun redirect). Rollback ved 526: slet reglen
  (`DELETE /zones/{zid}/rulesets/592ffe8d…/rules/{rule-id}`) — CF falder tilbage
  til zonens `Full`.
- **Origin Certificates** (CF-signerede, installeret på boksen):
  `cbcit.dk` + `www.cbcit.dk` → udløb **2041-07-12** · `event.cbcit.dk` +
  `*.event.cbcit.dk` → udløb **2041-07-06**. **`datagaarden.dk` + `www`: Let's
  Encrypt via Plesk SSL It!** (siden 2026-10-28, udløb 2027-01-26, fornyes
  automatisk af `keep-secured`-cronen; HTTP-01 virker gennem CF). CF Origin CA
  var ikke muligt, fordi datagaarden.dk ikke er en zone på kontoen. Dermed har
  alle tre origins CF-validérbare certs, og Strict er pinnet pr. host (se ovenfor).
- **Zone-indstillinger aflæst via CF-API 2026-10-26:** `ssl=full`,
  `min_tls_version=1.2`, `tls_1_3=on`, `always_use_https=off` (origin
  301-redirecter selv HTTP→HTTPS på alle tre sites — verificeret udefra), HSTS
  på zone-niveau (max-age 1 år, includeSubDomains, nosniff), `security_level=medium`,
  `browser_check=on`, DNSSEC **ikke** aktiveret, ingen CAA-record. Zone-wide
  indstillinger ændres aldrig uden at tænke på de ~18 andre sites i zonen.

### 4.4 Mail-DNS — VIGTIGT: to zoner, kun CF'ens gælder udadtil

**Cloudflare er authoritative for hele `cbcit.dk` (inkl. `event.`-subdomænet).**
Plesk BIND har en *lokal* zone for `event.cbcit.dk` med SPF/DKIM/DMARC — men den
besvares IKKE udadtil. Verden ser kun CF-zonen.

**I CF-zonen (det der faktisk gælder):**

| Record | Værdi |
|---|---|
| MX `cbcit.dk` | `cbcit-dk.mail.protection.outlook.com` → **@cbcit.dk-mail = Microsoft 365** |
| SPF `cbcit.dk` (TXT) | **Ryddet 2026-10-29:** `v=spf1 include:spf.protection.outlook.com include:servers.mcsv.net a:spf1.kobalt.dk -all` (MS365 + Mailchimp + Kobalt-mailcluster; 3 lookups). **Indeholder IKKE Brevo** (Brevo-mails sendes som `noreply@cbcit.dk` og godkendes via DKIM-alignment, ikke SPF). `a:spf1.kobalt.dk` **fjernes 2027-01-01** (Kents legacy, aftalt m. Johan). Før-værdi + rollback: `/root/cbc-hardening-2026-10/README.md` (29/10). |
| DKIM | `brevo1/brevo2._domainkey` → Brevo · `k2/k3` → Mailchimp · flere → Amazon SES (root, `mail.`, `inbound.`) |
| DMARC `_dmarc.cbcit.dk` | `v=DMARC1; p=none; rua=…dmarc-reports.cloudflare.net` — **p=none, IKKE quarantine** (CF DMARC Management) |
| `event.cbcit.dk` | **INGEN SPF-, DKIM- eller DMARC-records i CF-zonen** |
| Øvrig mail-infra | `inbound.cbcit.dk` MX → Amazon SES inbound · `smtp-relay-1` → SES SMTP · `mail.cbcit.dk` SPF → SES · `spf.cbcit.dk` (SPF-makro, bruges kun af `datagaarden.dk`; ryddet 2026-10-29 til `include:spf.protection.outlook.com include:spf.brevo.com include:amazonses.com a:spf1.kobalt.dk -all`) |

> **✅ Empirisk afklaret 2026-07-20:** Event-mails afsendes som **`noreply@cbcit.dk`**
> (ikke @event.cbcit.dk), og Brevo DKIM-signerer alignet med `cbcit.dk` —
> mail-tester.com: **SPF ✓ DKIM ✓ DMARC ✓** (7,6/10; fradrag var testmail-indhold,
> ikke autentificering). Se 04-drift §3.2. Plesk-zonens `event.cbcit.dk`-records
> forbliver kosmetiske (usynlige udadtil) — harmløst, men værd at vide.
> Forbedringspunkter: DMARC er `p=none` (kun monitorering). SPF-legacy-listen
> blev trimmet 2026-10-29 (se tabellen nedenfor).

**Audit-fund 2026-10-26 (mail-autenticitet, åbne punkter — ejes af Johan):**

| Domæne | Status | Konsekvens |
|---|---|---|
| `cbcit.dk` | **SPF ryddet 2026-10-29** (alle ~20 legacy-IP'er, død `a:cbcit.dk` og `include:spf.simply.com` fjernet; de gamle IP'er var døde TDC/Kobalt-hosts eller fremmede Hetzner-kunder). Tilbage: MS365 + Mailchimp + `a:spf1.kobalt.dk` (til 2027-01-01). 3 lookups. DMARC `p=none`. Brevo-DKIM `brevo1/brevo2` OK. | **Udestår:** DMARC → `quarantine`, men FØRST efter header-test af server-cron-mails (`root@server.cbcit.dk` via Brevo) viser alignet DKIM — ellers ryger alarm-mails i spam. Tidligst 2–3 uger efter SPF-ændringen. |
| `datagaarden.dk` | SPF `include:spf.protection.outlook.com include:mail.iteras.dk include:spf.cbcit.dk ip4:87.55.238.154 -all` (7 lookups efter makro-oprydning 29/10). **Ingen DMARC-record.** Ingen Brevo-DKIM (kun MS365 `selector1`). DNS hos **wwi**, ikke CF. | WP-mails fra sitet (Contact Form 7) sendes via Brevo uden alignet DKIM → fejler, hvis DMARC skærpes. Opret DMARC `p=none` + autentificér domænet i Brevo FØR enforcement. |
| `event.cbcit.dk` | Ingen egne mail-records (afsender er `noreply@cbcit.dk`). | Ingen handling. |

---

## 5. Verifikations-kommandoer (til re-verificering)

```bash
ssh cbc-prod 'hostnamectl; ip -brief addr; timedatectl'
ssh cbc-prod 'ss -tulpn | sort -u'
ssh cbc-prod 'plesk bin domain --list; plesk bin subscription --list'
ssh cbc-prod 'plesk bin dns --info event.cbcit.dk | grep -iE "TXT|MX|A "'
```
