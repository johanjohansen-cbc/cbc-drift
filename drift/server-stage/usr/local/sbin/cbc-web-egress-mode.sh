#!/bin/bash
# CBC blast-radius 2026-10-22 — skift web-egress-filteret mellem log-only og enforce.
#   cbc-web-egress-mode.sh status     : vis tilstand, taellere og allowlist-stoerrelse
#   cbc-web-egress-mode.sh log-only   : log, men tillad (adfaerd som foer filteret)
#   cbc-web-egress-mode.sh enforce    : log + DROP alt der ikke er paa allowlisten
# Opdaterer BAADE den levende regel (atomisk 'nft replace rule') og /etc/nftables.d/cbc_fw.nft.
set -uo pipefail
FILE=/etc/nftables.d/cbc_fw.nft
MODE=${1:-status}

chain(){ nft -a list chain inet cbc_fw web_egress 2>/dev/null; }
current(){ chain | grep -oE 'cbc-egress-mode: [a-z-]+' | awk '{print $2}'; }
count4(){ nft list set inet cbc_fw web_allow4 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u | wc -l; }
count6(){ nft list set inet cbc_fw web_allow6 2>/dev/null | grep -oE '[0-9a-fA-F]*:[0-9a-fA-F:]+' | sort -u | wc -l; }

case "$MODE" in
  status)
    echo "tilstand: $(current)"
    echo "allowlist: v4=$(count4) IP, v6=$(count6) IP"
    chain | grep -E 'cbc-egress-hits|accept|cbc-egress-mode'
    echo "drop-log sidste 24 t: $(journalctl -k --since '-24 hours' 2>/dev/null | grep -c 'cbc-egress-drop:')"
    exit 0 ;;
  log-only) VERB=return ;;
  enforce)  VERB=drop ;;
  *) echo "brug: $0 status|log-only|enforce"; exit 2 ;;
esac

if [ "$VERB" = drop ]; then
  n4=$(count4)
  [ "$n4" -ge 5 ] || { echo "AFVIST: web_allow4 har kun $n4 IP'er — koer cbc-web-egress-refresh.sh foerst"; exit 1; }
fi

HANDLE=$(chain | grep 'cbc-egress-mode' | grep -oE 'handle [0-9]+' | awk '{print $2}')
[ -n "$HANDLE" ] || { echo "FEJL: fandt ikke mode-reglen i web_egress"; exit 1; }
nft replace rule inet cbc_fw web_egress handle "$HANDLE" "$VERB" comment "\"cbc-egress-mode: $MODE\"" || { echo "FEJL: nft replace rule"; exit 1; }
cp -a "$FILE" "$FILE.pre-mode-$(date +%Y%m%d%H%M%S)"
sed -i -E "s/^([[:space:]]*)(return|drop) comment \"cbc-egress-mode: [a-z-]+\"/\1$VERB comment \"cbc-egress-mode: $MODE\"/" "$FILE"
nft -c -f "$FILE" || { echo "ADVARSEL: $FILE fejler syntaks-check efter sed — gendan fra .pre-mode-*"; exit 1; }
logger -t cbc-web-egress-mode -- "web_egress sat til $MODE"
echo "web_egress: $(current) (levende + persisteret)"
