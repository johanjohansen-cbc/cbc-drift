#!/bin/sh
# Re-apply CBC host firewall table idempotently (does not touch fail2ban table)
nft list table inet cbc_fw >/dev/null 2>&1 && nft delete table inet cbc_fw
nft -f /etc/nftables.d/cbc_fw.nft
# CBC blast-radius 2026-10-22: genindlaes sidst-kendte web-egress allowlist-IP'er (persisteret
# af cbc-web-egress-refresh.sh), saa web-uid'erne ikke staar uden allowlist efter boot.
[ -f /etc/nftables.d/cbc_web_egress_elements.nft ] && nft -f /etc/nftables.d/cbc_web_egress_elements.nft || true
