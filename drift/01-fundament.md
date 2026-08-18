# CBC Driftsdokumentation — 01 · Fundament

> Konti & leverandører · hardware/OS · netværk & DNS.
> **Verificeret:** 2026-07-20 via live SSH-inventory (`hostnamectl`, `ip`,
> `plesk bin`, `nft`). Cloudflare-DNS/zone-detaljer markeret **‹CF-DASHBOARD›**.

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
| **Kent / LB-leverandør** | Ekstern load balancer foran `datagaarden.dk` | LB-IP'er `185.21.232.10-12` · kontakt ‹UDFYLD Kent› | — |

> **‹UDFYLD›:** Registrar-navn og Kents kontaktinfo. Cloudflare-kontoen bekræftes
> som "CBC IT v2" — verificér ejerskab/plan i dashboardet (07 dækker login).

---

## 2. Hardware & hosting

| | |
|---|---|
| **Udbyder** | Hetzner Cloud (EU — GDPR-relevant) |
| **Type** | **CPX32** (4 vCPU / 8 GB / 150 GB), server-id **135078172** (bekræftet i break-glass 07 §1/§6.1). **Bemærk:** de gamle plugin-docs nævnte "CX22" — forkert. |
| **CPU** | AMD EPYC-Genoa (4 vCPU) |
| **Disk** | 150 GB, 20 % brugt (28 GB) pr. 2026-07-20 |
| **Hostname** | `server.cbcit.dk` |
| **Konsol-navn** | `cbc-server` (i Hetzner Cloud-konsollen) |
| **OS** | Ubuntu 24.04.4 LTS |
| **Kernel** | 6.8.0-136-generic |
| **Tidszone** | Europe/Copenhagen |
| **Genstart** | Boksen genstarter **selv** efter natlige `unattended-upgrades`. Alle tjenester kommer automatisk op (verificeret i drift). Seneste boot 2026-07-19 04:00. |

**OS-opdateringer:** `unattended-upgrades` kører automatisk (Ubuntu-standard) og
genstarter ved kerne-opdateringer. Plesk-komponenter (PHP, MariaDB, nginx) patches
via Plesk's egen auto-update. **App-laget (WP/plugin/tema) er derimod fastfrosset**
frem til efter konferencen — se 03-software §frys.

---

## 3. Netværk

### 3.1 IP-adresser

| Interface | Adresse |
|---|---|
| `eth0` (v4) | `178.104.70.94/32` |
| `eth0` (v6) | `2a01:4f8:c2c:6018::1/64` |
| loopback | `127.0.0.1`, `::1` |

### 3.2 Åbne/lyttende porte (fra `ss -tulpn`, 2026-07-20)

| Port | Bind | Tjeneste | Eksponering |
|---|---|---|---|
| **22** | `0.0.0.0`, `::` | SSH | Offentlig (firewall tillader; key-only) |
| **80/443** | public IP | nginx (web) | **Kun Cloudflare-IP'er** (cbc_fw) + Kents LB på 443 |
| **8443** | `[::]`, `0.0.0.0` | Plesk-panel | **IKKE firewall-åben** → kun via Cloudflare Tunnel |
| **53** | public IP + local | BIND (Plesk DNS) | Offentlig (authoritative DNS for Plesk-styrede zoner) |
| **25 / 465 / 587** | localhost / ::1 | Postfix (mail) | Lokal + udgående relay til Brevo |
| **3306** | `127.0.0.1` | MariaDB | Kun localhost |
| 7080/7081/8880/8443 | localhost | Plesk interne | Lokal |

> **Note port 53:** Boksen kører BIND og er authoritative DNS for de zoner Plesk
> styrer (bl.a. `datagaarden.dk` via `ns1/ns2.datagaarden.dk`). For
> `event.cbcit.dk`/`cbcit.dk` er **Cloudflare** authoritative — Plesk-zonen for dem
> er sekundær/lokal og *ikke* den der besvares udadtil.

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
| `datagaarden.dk` | **Plesk BIND** (`ns1/ns2.datagaarden.dk` → 178.104.70.94) | **Kents LB** (185.21.232.10-12) | Via LB (undtaget origin-guard) |

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

- **Encryption mode: `Full` — med "Automatic mode" aktiveret (~2026-06-23).**
  ⚠️ Afviger fra det tilsigtede *Full (strict)* (prod-dagens opsætning). Automatic
  har formentlig valgt Full fordi zonen også proxier hosts på Kents LB, hvis
  certs CF ikke kan validere. **Anbefaling:** pin *Full (strict)* for
  `event.cbcit.dk`/`cbcit.dk` via en Configuration Rule (per-host), i stedet for
  at hæve hele zonen.
- **Origin Certificates** (CF-signerede, installeret på boksen):
  `cbcit.dk` + `www.cbcit.dk` → udløb **2041-07-12** · `event.cbcit.dk` +
  `*.event.cbcit.dk` → udløb **2041-07-06**.
- Trafik (seneste døgn ved aflæsning): ~20k TLS 1.3, ~1,4k TLS 1.2, ~10k
  ikke-TLS (formentlig HTTP→HTTPS-redirects; verificér at "Always Use HTTPS" er på).

### 4.4 Mail-DNS — VIGTIGT: to zoner, kun CF'ens gælder udadtil

**Cloudflare er authoritative for hele `cbcit.dk` (inkl. `event.`-subdomænet).**
Plesk BIND har en *lokal* zone for `event.cbcit.dk` med SPF/DKIM/DMARC — men den
besvares IKKE udadtil. Verden ser kun CF-zonen.

**I CF-zonen (det der faktisk gælder):**

| Record | Værdi |
|---|---|
| MX `cbcit.dk` | `cbcit-dk.mail.protection.outlook.com` → **@cbcit.dk-mail = Microsoft 365** |
| SPF `cbcit.dk` (TXT) | Lang legacy-liste: mange ip4/ip6 + `include:spf.protection.outlook.com`, `include:servers.mcsv.net` (Mailchimp), `include:spf.simply.com`, `a:spf1.kobalt.dk`, `a:cbcit.dk` `-all`. **Indeholder IKKE Brevo.** (⚠️ `a:cbcit.dk` resolver til CF-proxy-IP'er, ikke origin — død vægt.) |
| DKIM | `brevo1/brevo2._domainkey` → Brevo · `k2/k3` → Mailchimp · flere → Amazon SES (root, `mail.`, `inbound.`) |
| DMARC `_dmarc.cbcit.dk` | `v=DMARC1; p=none; rua=…dmarc-reports.cloudflare.net` — **p=none, IKKE quarantine** (CF DMARC Management) |
| `event.cbcit.dk` | **INGEN SPF-, DKIM- eller DMARC-records i CF-zonen** |
| Øvrig mail-infra | `inbound.cbcit.dk` MX → Amazon SES inbound · `smtp-relay-1` → SES SMTP · `mail.cbcit.dk` SPF → SES · `spf.cbcit.dk` (SPF-makro m. `include:spf.brevo.com`) |

> **✅ Empirisk afklaret 2026-07-20:** Event-mails afsendes som **`noreply@cbcit.dk`**
> (ikke @event.cbcit.dk), og Brevo DKIM-signerer alignet med `cbcit.dk` —
> mail-tester.com: **SPF ✓ DKIM ✓ DMARC ✓** (7,6/10; fradrag var testmail-indhold,
> ikke autentificering). Se 04-drift §3.2. Plesk-zonens `event.cbcit.dk`-records
> forbliver kosmetiske (usynlige udadtil) — harmløst, men værd at vide.
> Forbedringspunkter: DMARC er `p=none` (kun monitorering); SPF-legacy-listen
> kan trimmes (bl.a. den døde `a:cbcit.dk`-mekanisme).

---

## 5. Verifikations-kommandoer (til re-verificering)

```bash
ssh cbc-prod 'hostnamectl; ip -brief addr; timedatectl'
ssh cbc-prod 'ss -tulpn | sort -u'
ssh cbc-prod 'plesk bin domain --list; plesk bin subscription --list'
ssh cbc-prod 'plesk bin dns --info event.cbcit.dk | grep -iE "TXT|MX|A "'
```
