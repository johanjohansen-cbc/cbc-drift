# CBC Driftsdokumentation — 05 · Backup & gendannelse

> Backup-tiers · restore-procedurer · restore-drill · RTO/RPO.
> **Verificeret:** 2026-07-20 via live SSH (`plesk db "SELECT … FROM
> BackupsScheduled"`, backup-mappe-inventory). Fuld rollback-detalje: se
> plugin-repoets `docs/05-deploy-workflow.md §10`.

---

## 1. Backup-tiers (hvad beskytter hvad)

| Tier | Hvad | Hyppighed | Hvor | Verificeret |
|---|---|---|---|---|
| **Plesk full backup** | Alle subscriptions (filer + DB + config + mail) | **Daglig 00:00**, ugentlig fuld | **Microsoft OneDrive** (via Plesk-extension) | Kørte 2026-07-20 00:16 ✓ |
| **Pre-deploy DB-dump** | event-DB + plugin/tema-tarball | Pr. deploy (auto i `deploy.sh`) | `/var/backups/cbc-pre-deploy/` (`700`, filer `600`) | Sidst 2026-07-07 (ingen deploy siden = frys) |
| **Hetzner snapshot** | Hele disken (bare-metal-image) | **Ugentlig, MANUEL** | Hetzner Cloud | ‹UDFYLD: bekræft seneste snapshot-dato i konsollen› |
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
- **‹UDFYLD: OneDrive-mappe/sti + hvilken OneDrive-konto›** (fra Plesk → Tools →
  Backup Manager → Remote Storage Settings).

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
2. **Alternativt:** ny boks + Plesk-installation → gendan fra **OneDrive**-backup
   via Backup Manager (Remote Storage). Kræver OneDrive-login (07) + evt.
   re-pointing af DNS/firewall/tunnel.
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

- **Runbook:** ‹UDFYLD: link til restore-drill-runbook› (scratch-CX-server →
  gendan fra OneDrive → verificér → slet samme dag).
- **Verifikation under drillen skal inkludere** `drift/tools/web-exposure-check.sh`
  mod scratch-serveren (`BASE=https://<scratch-host> bash web-exposure-check.sh`) —
  tester at nginx-direktiverne (02-adgang §7.2) fulgte med gendannelsen.
- **Status:** booket **tirsdag 2026-08-18** — skal gennemføres før september.
- **Efter drill:** notér resultat + faktisk RTO i dette dok.

---

## 4. RTO / RPO (mål)

| Scenarie | RTO (gendannelsestid) | RPO (max datatab) |
|---|---|---|
| Enkelt-fil/DB (Plesk-backup) | ~5-15 min | op til 24 t (daglig backup) |
| Fuld boks (Hetzner-snapshot) | ~15-30 min | op til 7 dage (ugentligt snapshot) |
| Deploy-rollback | ~2-5 min | 0 (pre-deploy-dump) |

> Snapshot-RPO (7 dage) er den svageste. Den forbedres ved hyppigere manuelle
> snapshots eller højere OneDrive-rotation.

---

## 5. Verifikations-kommandoer

```bash
ssh cbc-prod 'plesk db "SELECT last, period, rotation, remoteStorage, email FROM BackupsScheduled\G"'
ssh cbc-prod 'ls -la /var/backups/cbc-pre-deploy/ | tail'
# Hetzner-snapshots: verificeres i console.hetzner.cloud (ikke synligt fra boksen)
```
