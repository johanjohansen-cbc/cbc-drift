#!/bin/bash
# CBC blast-radius 2026-10-22 — hent officielle IP-ranges for udbydere med hurtigt roterende IP'er
# og skriv /etc/cbc-web-egress-ranges.txt (laeses af cbc-web-egress-refresh.sh -> web_allow_net4/6).
#   Google-tjenester: https://www.gstatic.com/ipranges/goog.json  (Site Kit / googleapis; IKKE GCP-kunder)
#   Meta/Facebook:    RIPEstat announced-prefixes for AS32934       (graph.facebook.com / CAPI)
# Fail-safe: ved fejl i hentning/validering beholdes den eksisterende fil, og Johan faar en mail.
set -uo pipefail
OUT=/etc/cbc-web-egress-ranges.txt
LOG=/var/log/cbc-web-egress-refresh.log
ALERT=johan@cbcit.dk
GOOG=https://www.gstatic.com/ipranges/goog.json
META=https://stat.ripe.net/data/announced-prefixes/data.json?resource=AS32934

log(){ printf '%s %s\n' "$(date '+%F %T')" "ranges: $*" >>"$LOG"; logger -t cbc-web-egress-ranges -- "$*"; }
notify(){ [ -x /usr/sbin/sendmail ] || return 0
  printf 'To: %s\nSubject: %s\nContent-Type: text/plain; charset=UTF-8\n\n%s\n' "$ALERT" "$1" "$2" | /usr/sbin/sendmail -t 2>/dev/null || true; }
fail(){ log "ABORT: $*"; notify "[CBC] web-egress ranges-opdatering FEJLEDE" "Afbrudt: $*

$OUT er UAENDRET (sikker tilstand). Se $LOG paa serveren."; exit 1; }

v4re='^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$'
v6re='^[0-9a-fA-F:]+/[0-9]{1,3}$'

G=$(curl -fsS --max-time 30 "$GOOG") || fail "curl goog.json fejlede"
GL=$(printf '%s' "$G" | python3 -c 'import json,sys; d=json.load(sys.stdin); [print(p.get("ipv4Prefix") or p.get("ipv6Prefix")) for p in d["prefixes"]]' 2>/dev/null) || fail "goog.json kunne ikke parses"
G4=$(printf '%s\n' "$GL" | grep -E "$v4re" | sort -u); G6=$(printf '%s\n' "$GL" | grep -E "$v6re" | sort -u)
g4=$(printf '%s\n' "$G4" | grep -c .); g6=$(printf '%s\n' "$G6" | grep -c .); gt=$(printf '%s\n' "$GL" | grep -c .)
[ $((g4+g6)) -eq "$gt" ] && [ "$g4" -ge 20 ] && [ "$g4" -le 400 ] && [ "$g6" -ge 5 ] && [ "$g6" -le 300 ] || fail "goog.json validering ($g4 v4 / $g6 v6 af $gt)"

M=$(curl -fsS --max-time 30 "$META") || fail "curl RIPEstat AS32934 fejlede"
ML=$(printf '%s' "$M" | python3 -c 'import json,sys; d=json.load(sys.stdin); [print(p["prefix"]) for p in d["data"]["prefixes"]]' 2>/dev/null) || fail "RIPEstat-svar kunne ikke parses"
M4=$(printf '%s\n' "$ML" | grep -E "$v4re" | sort -u); M6=$(printf '%s\n' "$ML" | grep -E "$v6re" | sort -u)
m4=$(printf '%s\n' "$M4" | grep -c .); m6=$(printf '%s\n' "$M6" | grep -c .); mt=$(printf '%s\n' "$ML" | grep -c .)
# Meta annoncerer mange /48'ere: 238 v4 + 322 v6 pr. 2026-10-22 -> rummelige, men endelige graenser
[ $((m4+m6)) -eq "$mt" ] && [ "$m4" -ge 10 ] && [ "$m4" -le 800 ] && [ "$m6" -ge 2 ] && [ "$m6" -le 1000 ] || fail "AS32934 validering ($m4 v4 / $m6 v6 af $mt)"

TMP=$(mktemp)
{
  echo "# AUTOGENERERET af /usr/local/sbin/cbc-web-egress-ranges-fetch.sh $(date '+%F %T') — redigér ikke i haanden."
  echo "# Netvaerks-ranges som web-uid'erne maa kontakte paa TCP 443/587 (ud over hostnavnene i cbc-web-egress-hosts.txt)."
  echo "# Godkendt af Johan 2026-10-22: Google (Site Kit) + Meta (Facebook Pixel/CAPI) for datagaarden.dk."
  echo "#"; echo "# --- Google-tjenester ($GOOG): $g4 v4 + $g6 v6 ---"; printf '%s\n' "$G4" "$G6"
  echo "#"; echo "# --- Meta/Facebook AS32934 (RIPEstat): $m4 v4 + $m6 v6 ---"; printf '%s\n' "$M4" "$M6"
} > "$TMP"
if [ -f "$OUT" ] && diff -q <(grep -v '^#' "$OUT") <(grep -v '^#' "$TMP") >/dev/null; then
  rm -f "$TMP"; log "no change (google $g4/$g6, meta $m4/$m6)"; exit 0
fi
[ -f "$OUT" ] && cp -a "$OUT" "$OUT.bak-$(date +%Y%m%d%H%M%S)"
install -m 644 "$TMP" "$OUT"; rm -f "$TMP"
log "UPDATED $OUT (google $g4/$g6, meta $m4/$m6)"
/usr/local/sbin/cbc-web-egress-refresh.sh
