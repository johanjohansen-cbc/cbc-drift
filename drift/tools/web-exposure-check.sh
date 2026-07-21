#!/usr/bin/env bash
# =============================================================================
# web-exposure-check.sh — ekstern verifikation af at interne filer IKKE serveres
# =============================================================================
# Tester UDEFRA (gennem Cloudflare) at S2-dev-fil-blokeringen på event.cbcit.dk
# virker: docs/, tools/, *.md, *.sh, *.lock, *.dist, composer.json → blokeret,
# mens sitet og dets assets stadig serveres normalt.
#
# KØR EFTER: enhver migrering (Plesk → andet), restore/DR, snapshot-gendannelse
# eller ændring af nginx-direktiverne (drift/02-adgang §7.2 har verbatim-kilden).
# Reglerne bor i SERVER-config (Plesk "Additional nginx directives"), ikke i
# plugin-repoet — en genopbygget server uden dem eksponerer docs/ LYDLØST.
# Dette script er værnet mod netop dét.
#
# Kørsel:  bash web-exposure-check.sh          (kræver kun bash + curl)
# Exit:    0 = alt OK · 1 = mindst én test fejlede
#
# Bemærk: browser-User-Agent er påkrævet — Cloudflare giver 403 på curl-UA
# (kendt gotcha, drift/06 §2.4). "Blokeret" accepterer både 403 og 404 (nginx
# siger 404, dot-fil-deny siger 403; sikkerhedskravet er blot: ikke 2xx).
# =============================================================================

set -u

BASE="${BASE:-https://event.cbcit.dk}"
PLUGIN="$BASE/wp-content/plugins/cbc-event-planner"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

fails=0

check() { # check <expect> <url> — expect: "200" eller "blocked" (403/404)
    local expect="$1" url="$2" code
    code=$(curl -s -o /dev/null -w "%{http_code}" -A "$UA" --max-time 15 "$url")
    local ok=0
    if [ "$expect" = "blocked" ]; then
        { [ "$code" = "403" ] || [ "$code" = "404" ]; } && ok=1
    else
        [ "$code" = "$expect" ] && ok=1
    fi
    if [ "$ok" = "1" ]; then
        printf '[ ok ] %s  %s (forventet %s)\n' "$code" "$url" "$expect"
    else
        printf '[FEJL] %s  %s (forventet %s)\n' "$code" "$url" "$expect"
        fails=$((fails + 1))
    fi
}

echo "=== Web-exposure-check: $BASE ($(date +%F\ %T)) ==="
echo ""
echo "--- Baseline: sitet serveres normalt ---"
check 200     "$BASE/"
check 200     "$PLUGIN/assets/css/frontend.css"

echo ""
echo "--- Interne filer skal være blokeret (403/404) ---"
check blocked "$PLUGIN/docs/handover/00-oversigt.md"
check blocked "$PLUGIN/docs/06-security-pre-deploy.md"
check blocked "$PLUGIN/docs/02aw-fase8-commit85-sikkerhedsaudit.md"
check blocked "$PLUGIN/README.md"
check blocked "$PLUGIN/deploy.sh"
check blocked "$PLUGIN/composer.json"
check blocked "$PLUGIN/composer.lock"
check blocked "$PLUGIN/phpcs.xml.dist"
check blocked "$PLUGIN/tools/phpcs/composer.json"
check blocked "$PLUGIN/.git/config"

echo ""
echo "--- Bypass-varianter af docs/ ---"
check blocked "$PLUGIN/docs/01-datamodel.md?x=1"
check blocked "$PLUGIN/docs//01-datamodel.md"
check blocked "$PLUGIN/docs/./01-datamodel.md"
check blocked "$PLUGIN/docs%2f01-datamodel.md"

echo ""
if [ "$fails" -eq 0 ]; then
    echo "=== ALT OK — ingen interne filer eksponeret ==="
    exit 0
else
    echo "=== $fails FEJL — se drift/02-adgang §7.2 for nginx-direktiverne der skal (gen)indsættes ==="
    exit 1
fi
