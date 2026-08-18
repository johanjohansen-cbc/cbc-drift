# CBC Driftsdokumentation — 05 · Backup & gendannelse

> Backup-tiers · restore-procedurer · restore-drill · RTO/RPO.
> **Verificeret:** 2026-07-20 via live SSH; **2026-08-18 via gennemført
> restore-drill** (fuld gendannelse af event.cbcit.dk på scratch-server — se §3).
> Fuld rollback-detalje: se plugin-repoets `docs/05-deploy-workflow.md §10`.

---

## 1. Backup-tiers (hvad beskytter hvad)

| Tier | Hvad | Hyppighed | Hvor | Verificeret |
|---|---|---|---|---|
| **Plesk full backup** | Alle subscriptions (filer + DB + config + mail) | **Daglig 00:12**, fuld hver 7. dag | **Microsoft OneDrive** (via Plesk-extension) | **Restore-drill 2026-08-18: gendannelse bevist ✓** (§3) |
| **Pre-deploy DB-dump** | event-DB + plugin/tema-tarball | Pr. deploy (auto i `deploy.sh`) | `/var/backups/cbc-pre-deploy/` (`700`, filer `600`) | Bruges løbende ved deploys |
| **Hetzner snapshot** | Hele disken (bare-metal-image) | **Ugentlig, AUTOMATISK** (mandag 09:00 fra Johans maskine: Task Scheduler-opgaven "CBC Hetzner ugentlig snapshot", script `C:\Users\JohanJohansen\cbc-ops\hetzner-snapshot.ps1`; DB-dump først, behold 3 nyeste, statusmail til johan@) | Hetzner Cloud | E2E-testet 2×; mailer BÅDE ved OK og FEJL — udebliver mandagsmailen, er rutinen død (fx maskine slukket) |
| **Git-mirror** | Al kode + historik | Pr. `git push both` | GitHub (privat) + prod bare repos | Se 04-drift §1 |

### 1.1 Plesk → OneDrive (detaljer, fra `BackupsScheduled`)

| Felt | Værdi |
|---|---|
| Type | Server-niveau (alle subscriptions) |
| Repository | `one-drive-backup` (ekstern) |
| Interval | Dagligt (`period=86400`), fuld ugentligt (`full_backup_period=604800`) |
| Tidspunkt | 00:00 |
| Rotation | **7** (beholder 7 backups) |
| Indhold | Alt ved domænet (`with_content=true`, mail inkluderet) |
| Notifikation | `johan@cbcit.dk` |
| Sidste kørsel | 2026-07-20 00:16, valideret samme dag |

- Backup-jobbet drives af Plesk Backup Manager (poller-cron hvert 15. min i
  `/etc/cron.d/plesk-backup-manager-task`).
- OneDrive-koblingen: Plesk-extension `one-drive-backup` (konto-login → 07).
- **OneDrive-konto/mappe:** Johans virksomheds-OneDrive (**johan@cbcit.dk**),
  mappen **`server.cbcit.dk`**. ⚠️ **Kendt risiko:** kontoen er personbundet —
  offboardes Johan, slettes OneDrive'et efter M365-standard 30 dage OG
  extensionens token dør straks (backup stopper tavst). **Besluttet followup:**
  flyt til dedikeret servicekonto (fx backup@cbcit.dk, kræver egen M365-licens —
  shared mailbox har ikke OneDrive). Beslutning efter september-konferencen.
- **Kryptering (VIGTIGT — ændret 2026-08-18):** Password-beskyttelse
  ("Specified password") blev slået til **2026-08-18**; passwordet ligger i
  Johans password manager og er fra da af **påkrævet ved restore på fremmed
  server**. Backups taget FØR 2026-08-18 er `panel-key`-krypterede og
  **selv-dekrypterende**: nøglen ligger i selve backuppen, så alle credentials
  (sysuser-/DB-passwords) kan gendannes af enhver med adgang til
  OneDrive-filerne (bevist under drillen). For de gamle backupper er M365 MFA
  eneste værn; de roterer ud af 7-dages-vinduet af sig selv.
- **Lagringsformat i OneDrive:** extensionen gemmer backups **chunket** — de
  synlige filer `backup_X.tar_size_N` er få-bytes stub-markører (N = ægte
  størrelse). **Manuel download fra OneDrive-webben er derfor UBRUGELIG** til
  restore; gendannelse kræver extension-tilslutning på målserveren (§2.3).
  CLI-værktøjerne (`pleskbackup`, `pmm-ras --export-file-as-file`) kan IKKE
  læse ext-storage.
- **Filer, backup-processen ikke kan læse, giver evig "minor issues"-advarsel:**
  arkiveren kører som sitets sysuser — root-ejede filer i vhosten springes over
  med warning på HVER kørsel (set 22/7→18/8: en root-600 SQL-dump; flyttet til
  `/var/backups/cbc-purge-backup/`). Regel: læg aldrig root-ejede filer i
  `/var/www/vhosts/…`; vedligeholdelses-dumps hører til i `/var/backups/`.
  Advarsels-detaljer pr. backup:
  `/var/lib/psa/dumps/.discovered/<dump>/dumpresult_WARNINGS`.

> **Bemærk retention vs. rotation:** kun 7 backups beholdes på OneDrive. For et
> RPO længere tilbage end ~1 uge er man afhængig af Hetzner-snapshots. Overvej at
> hæve rotation eller tage et manuelt snapshot før store ændringer (fx post-konference-
> opgradering).

---

## 2. Restore-procedurer

### 2.1 Enkelt-fil / DB fra Plesk-backup

```
Plesk-panel (via CF Tunnel) → Tools & Settings → Backup Manager
  → vælg backup (dato) → Restore → vælg objekter (filer/DB/mail) → Restore
```
Kan gendanne selektivt (kun én database, én mappe) uden fuld overskrivning.

### 2.2 Kode-rollback (deploy gik galt)

Se 04-drift §1.4 + `docs/05-deploy-workflow.md §10`. Kort: `git checkout <ref>` +
chown + `systemctl reload plesk-php84-fpm`. Pre-deploy-dumpet i
`/var/backups/cbc-pre-deploy/` gendanner DB hvis en migration var destruktiv:
```bash
su -s /bin/bash event.cbcit.dk_x3pjx5okzbn -c "…/wp db import /var/backups/cbc-pre-deploy/db-<ts>.sql"
```

### 2.3 Disaster recovery (boks tabt / korrupt)

1. **Hurtigst:** Hetzner-konsol → gendan seneste **snapshot** (hele disken).
   RTO ~15-30 min. Alt (Plesk, sites, config) kommer tilbage til snapshot-punktet.
2. **Alternativt:** ny boks + Plesk → gendan fra **OneDrive**-backup.
   **Gennemprøvet 2026-08-18 (restore-drill) — følg denne rækkefølge:**
   1. Ny server (Hetzner, Ubuntu 24.04). Plesk-version skal være ≥ prods.
   2. **Licens:** en frisk Plesk kører med default-nøgle = **0 domæner** →
      restore umulig. Trial fås i dag KUN via Plesks web-installer
      (plesk.com/free-trial → formular med SSH-adgang til serveren; kræver
      port 22 åben for deres infrastruktur under installationen). Ved ægte DR:
      brug CBC's betalte licens hvis muligt.
   3. Installér extension: `plesk bin extension --install one-drive-backup` →
      i panelet: Backup Manager → Remote Storage Settings → OneDrive →
      M365-login (07) → mappe `server.cbcit.dk`. **Opret INGEN
      backup-tidsplan** på den nye server, før den ER den nye prod (skriveadgang
      til backup-mappen!).
   4. Restore i Backup Manager: vælg nyeste backup → Selected objects →
      Subscription. **Backup-passwordet (Johans password manager) er påkrævet**
      for backups efter 2026-08-18. "Corrupted signature"-advarslen er forventet
      (fremmed server) — flueben og fortsæt.
   5. **Efter restore — kendte manglende brikker (server-level config følger
      IKKE med subscription-backuppen):**
      - `/etc/nginx/conf.d/cbc-origin-guard.conf` SKAL genskabes, ellers
        fejler `nginx -t` med `unknown "cbc_origin_not_trusted" variable`
        (subscriptionens "Additional nginx directives" refererer den).
        Verbatim-kilde: 02-adgang §7.2. Uden CF foran kan den midlertidigt
        neutraliseres: `geo $realip_remote_addr $cbc_origin_not_trusted { default 0; }`
      - Kør `/opt/psa/admin/bin/httpdmng --reconfigure-domain event.cbcit.dk`
        + genstart nginx, hvis sitet svarer med Plesk-panelets default-side.
   6. Re-point DNS/firewall/tunnel (07) — ALDRIG mens scratch-/testserver
      stadig lever.
3. **Kode** hentes uafhængigt fra GitHub-mirror (se `docs/05 §14.4`).
4. **Efter gendannelse (og efter enhver migrering væk fra Plesk):** kør
   `drift/tools/web-exposure-check.sh` — verificerer udefra at S2-dev-fil-
   blokeringen (docs/ m.m.) stadig er aktiv. Reglerne bor i server-config,
   ikke i plugin-repoet, og forsvinder LYDLØST hvis de ikke genindsættes
   (verbatim-kilde: 02-adgang §7.2).

> **⚠️ Fra break-glass (08):** gendan ALDRIG en backup/snapshot på egen hånd i
> panik — det kan overskrive nyeste data. Ved tvivl: kontakt Johan / følg 08.

---

## 3. Restore-drill

En **restore-drill er en planlagt øvelse**, hvor en backup faktisk gendannes på en
scratch-server og verificeres — så vi ved at backups virker, ikke bare at de tages.

- **Runbook:** = proceduren i §2.3 pkt. 2 (den ER drillens facit) + scratch-regler:
  scratch-server slettes SAMME dag (indeholder prod-PII), ingen DNS-ændringer,
  Hetzner-firewall på scratch åben KUN for operatørens IP, gendan ALDRIG hen
  over prod.
- **Verifikation under drillen skal inkludere** `drift/tools/web-exposure-check.sh`
  mod scratch-serveren (`BASE=https://<scratch-host> bash web-exposure-check.sh`) —
  tester at nginx-direktiverne (02-adgang §7.2) fulgte med gendannelsen.

### 3.1 Resultat af drill 2026-08-18 (GENNEMFØRT ✓)

Fuld gendannelse af event.cbcit.dk-subscriptionen (backup 18/8 00:12 = fuld 12/8
+ 6 inkrementer) på scratch-CX23 i nbg1, Plesk 18.0.80.3.
**Alle verifikationer grønne:** WP booter, siteurl korrekt, brugere/posts matcher
prod eksakt (afvigelse = tilmeldinger efter backup-tidspunkt), alle 17
plugin-tabeller, plugin-/temaversioner korrekte, uploads, statiske filer (200),
sysuser-crontab og certifikater (inkl. CF-Origin-privatnøgle) fulgte med.
Scratch-server + drill-firewall slettet samme dag (API-verificeret).

**Fund fra drillen (indarbejdet i §1.1 + §2.3):**
1. Manuel OneDrive-download ubrugelig (chunket format) → restore kræver
   extension-tilslutning.
2. `cbc-origin-guard.conf` er server-level og følger IKKE med → nginx fejler
   indtil genskabt.
3. Backuppen var IKKE password-beskyttet (panel-key = selv-dekrypterende;
   alle credentials gendannet uden password) → password-beskyttelse aktiveret
   2026-08-18 og verificeret på efterfølgende backup (`encryption-type="password"`).
4. Trial-licens kun via Plesks web-installer; default-nøgle tillader 0 domæner.

**Målt RTO:** ~2½ time første gang (inkl. omveje/licens-bøvl); med §2.3-proceduren
estimeret **~45-60 min** (Plesk-installationen dominerer). Ren
backup-transfer+deploy OneDrive→Hetzner: **under 2 min** for event-subscriptionen.

**ÅBENT PUNKT til næste drill:** `web-exposure-check.sh` blev IKKE kørt mod
scratch (opdaget efter sletning). S2-dev-fil-blokeringens overlevelse ved restore
er derfor stadig uverificeret — origin-guard-fundet (pkt. 2) beviser dog samme
pointe: server-level nginx-config skal genskabes manuelt. Næste drill: kør
tjekket FØR scratch slettes. Anbefalet kadence: gentag drill efter større
infra-ændringer, min. årligt.

---

## 4. RTO / RPO (mål)

| Scenarie | RTO (gendannelsestid) | RPO (max datatab) |
|---|---|---|
| Enkelt-fil/DB (Plesk-backup) | ~5-15 min | op til 24 t (daglig backup) |
| Fuld boks (Hetzner-snapshot) | ~15-30 min | op til 7 dage (ugentligt snapshot) |
| Subscription på FRISK boks (OneDrive-backup) | **~45-60 min** (målt/estimeret ved drill 2026-08-18, se §3.1) | op til 24 t |
| Deploy-rollback | ~2-5 min | 0 (pre-deploy-dump) |

> Snapshot-RPO (7 dage) er den svageste. Den forbedres ved hyppigere manuelle
> snapshots eller højere OneDrive-rotation.

---

## 5. Verifikations-kommandoer

```bash
ssh cbc-prod 'plesk db "SELECT last, period, rotation, remoteStorage, email FROM BackupsScheduled\G"'
ssh cbc-prod 'ls -la /var/backups/cbc-pre-deploy/ | tail'
# Hetzner-snapshots: verificeres i console.hetzner.cloud (ikke synligt fra boksen)

# Liste over backups i OneDrive (navn + ægte størrelse), set fra serveren:
ssh cbc-prod "/opt/psa/admin/bin/backup_restore_helper --extension-transport ext://one-drive-backup/server/ -operation list -path ''"

# Er nyeste backup password-krypteret? (skal sige encryption-type="password"):
ssh cbc-prod 'grep -oE "encryption-type=\"[^\"]*\"" $(ls -t /var/lib/psa/dumps/backup_info_*.xml | head -1) | sort -u'

# Advarsler på seneste backups (dumpresult_WARNINGS = "minor issues" i UI):
ssh cbc-prod 'ls /var/lib/psa/dumps/.discovered/*/dumpresult_WARNINGS 2>/dev/null | tail -3'
```
