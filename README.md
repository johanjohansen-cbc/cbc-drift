# CBC — drifts- og overdragelsesdokumentation

Privat repo. Kanonisk hjem for al dokumentation, der IKKE hører til i
applikations-repoerne (`cbc-event-planner` / `cbc-child`), fordi den dækker
**serveren og driften som helhed** — eller er overdragelsesmateriale.

> ⚠️ **Fortroligt, men ikke hemmeligt** (samme model som break-glass 07):
> dokumenterne peger på hvor adgange og hemmeligheder ligger, men indeholder
> ingen hemmeligheder selv. De faktiske credentials ligger i CBC's delte
> password manager (Roboform) og i `/root/cbc-deploy-creds.txt` på serveren.

## Indhold

| Mappe/fil | Hvad |
|---|---|
| **`drift/00-oversigt.md`** | Arkitektur, hurtigfakta, invarianter — **start her** |
| `drift/01-fundament.md` | Konti/leverandører, server, netværk, DNS/Cloudflare, certifikater |
| `drift/02-adgang-og-sikkerhed.md` | SSH, firewall (cbc_fw), Plesk-adgang (CF Access/Tunnel), WAF, hærdning |
| `drift/03-software-og-sites.md` | Software-stack, versions-frys, de tre sites på boksen |
| `drift/04-drift.md` | Deploy-flows, cron, mail (Brevo), logs, rutiner |
| `drift/05-backup-og-gendannelse.md` | Backup-lag (OneDrive/snapshots), restore, RTO/RPO |
| `drift/06-runbooks-og-laerdomme.md` | Nødprocedurer, gotchas, break-glass-binding, åbne punkter |
| **`drift/07-break-glass-adgang.md`** | Bus-factor-dokument: fuld adgangs-genvinding for en efterfølger |
| `drift/07-break-glass-llm-guide-prompt.md` | Ledsagende LLM-prompt der guider en efterfølger gennem 07 |
| `design/` | Frontend-design-overdragelse (KickOff-tema: tokens, patterns, CSS) |
| `email-handover/` | E-mail-template-system (layout, partials, kodestandarder) |
| `dashboard/` | Konferenceoverbliks-dashboard (handoff + reference-HTML) |

## Vedligehold

- Driftsmanualen (`drift/00–06`) er bygget på **live-verifikation** (server +
  Cloudflare-dashboard), senest 2026-07-20. Re-verificér før større ændringer og
  før konferencen — hver fil angiver verifikations-kommandoer.
- **07 vedligeholdes sammen med stakken**: enhver ændring i adgang/konti skal
  afspejles i 07 samme dag. Print-udgaven i pengeskabet skal fornys ved
  væsentlige ændringer (se 07 §11).
- Arbejdskopien ligger i `app/public/_handover/` på Johans Local-maskine og
  pushes hertil (`git push origin main`).
