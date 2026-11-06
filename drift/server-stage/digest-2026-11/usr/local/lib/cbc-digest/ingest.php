<?php
/**
 * CBC daglig digest 2026-11-06: parser én mail (fil i argv[1]) sendt til digest@server.cbcit.dk.
 * Kaldes af /usr/local/sbin/cbc-digest-ingest.sh som nobody. Plesk PHP-CLI, ingen extensions ud over iconv/mbstring.
 *
 *  - dekoder Subject/From (RFC 2047) og finder tekstdelen (text/plain foretrækkes, ellers groft strippet text/html)
 *  - gemmer i /var/spool/cbc-digest/inbox/YYYYMMDD-HHMMSS_mail-<afsender>.txt  (1. linje = emne, derefter body)
 *  - matcher emnet mod /etc/cbc-digest-alert-patterns -> lægges i /var/spool/cbc-digest/outbox som "alert"
 *  - /etc/cbc-digest.disabled findes -> lægges i outbox som "plain" (sendes straks uden praefiks), intet spooles
 * nobody MÅ IKKE sende mail selv (Plesk limit-out afviser systembrugere) -> outbox tømmes straks af root via
 * cbc-digest-alert.path/.service -> /usr/local/sbin/cbc-digest-alert.sh -> cbc-notify.sh.
 * Exit 0 = OK. Alt andet -> wrapperen lægger den rå besked i outbox som alarm (fejlsikker).
 * Indholdet er UTROVÆRDIGT (kan komme fra et kompromitteret WP-site): det gemmes kun som tekst,
 * og cbc-digest.sh HTML-escaper alt, før det kommer i mailen.
 */
declare(strict_types=1);

date_default_timezone_set('Europe/Copenhagen');
const SPOOL     = '/var/spool/cbc-digest/inbox';
const OUTBOX    = '/var/spool/cbc-digest/outbox';
const PATTERNS  = '/etc/cbc-digest-alert-patterns';
const DISABLED  = '/etc/cbc-digest.disabled';
const MAX_LINES = 400;

openlog('cbc-digest-ingest', LOG_PID, LOG_MAIL);

function unfold_headers(string $raw): array {
	$raw = preg_replace("/\r?\n[ \t]+/", ' ', $raw) ?? $raw;
	$h   = [];
	foreach (preg_split("/\r?\n/", $raw) ?: [] as $line) {
		if (preg_match('/^([A-Za-z0-9-]+):\s*(.*)$/', $line, $m)) {
			$k = strtolower($m[1]);
			if (!isset($h[$k])) { $h[$k] = $m[2]; }
		}
	}
	return $h;
}

function split_msg(string $raw): array {
	$parts = preg_split("/\r?\n\r?\n/", $raw, 2);
	return [unfold_headers($parts[0] ?? ''), $parts[1] ?? ''];
}

function mime_decode_header(string $v): string {
	$d = @iconv_mime_decode($v, ICONV_MIME_DECODE_CONTINUE_ON_ERROR, 'UTF-8');
	return $d === false ? $v : $d;
}

function param(string $header, string $name): string {
	if (preg_match('/' . $name . '\s*=\s*"([^"]*)"/i', $header, $m)) { return $m[1]; }
	if (preg_match('/' . $name . '\s*=\s*([^;\s]+)/i', $header, $m)) { return $m[1]; }
	return '';
}

function decode_body(string $body, array $h): string {
	$cte = strtolower(trim($h['content-transfer-encoding'] ?? ''));
	if ($cte === 'base64') { $body = (string) base64_decode(preg_replace('/\s+/', '', $body) ?? '', false); }
	elseif ($cte === 'quoted-printable') { $body = quoted_printable_decode($body); }
	$cs = strtolower(param($h['content-type'] ?? '', 'charset'));
	if ($cs !== '' && $cs !== 'utf-8' && $cs !== 'us-ascii') {
		$conv = @mb_convert_encoding($body, 'UTF-8', $cs);
		if (is_string($conv)) { $body = $conv; }
	}
	return $body;
}

function html_to_text(string $html): string {
	$html = preg_replace('#<(script|style|head)\b.*?</\1>#is', '', $html) ?? $html;
	$html = preg_replace('#<br\s*/?>|</(p|div|tr|li|h[1-6]|table)>#i', "\n", $html) ?? $html;
	$html = preg_replace('#</t[dh]>#i', "\t", $html) ?? $html;
	$txt  = html_entity_decode(strip_tags($html), ENT_QUOTES | ENT_HTML5, 'UTF-8');
	$txt  = preg_replace("/[ \t]+\n/", "\n", $txt) ?? $txt;
	return preg_replace("/\n{3,}/", "\n\n", $txt) ?? $txt;
}

/** Returnerer [plain, html] fundet i (under)delen. */
function find_text(array $h, string $body, int $depth = 0): array {
	$ct = strtolower($h['content-type'] ?? 'text/plain');
	if ($depth < 6 && str_starts_with($ct, 'multipart/')) {
		$b = param($h['content-type'] ?? '', 'boundary');
		if ($b === '') { return ['', '']; }
		$plain = ''; $html = '';
		foreach (explode('--' . $b, $body) as $chunk) {
			if (trim($chunk) === '' || str_starts_with($chunk, '--')) { continue; }
			[$ph, $pb] = split_msg(ltrim($chunk, "\r\n"));
			if (stripos($ph['content-disposition'] ?? '', 'attachment') !== false) { continue; }
			[$p, $x] = find_text($ph, $pb, $depth + 1);
			if ($plain === '' && $p !== '') { $plain = $p; }
			if ($html === '' && $x !== '') { $html = $x; }
		}
		return [$plain, $html];
	}
	if (str_starts_with($ct, 'text/html')) { return ['', decode_body($body, $h)]; }
	if (str_starts_with($ct, 'text/') || $ct === '') { return [decode_body($body, $h), '']; }
	return ['', ''];
}

function clean(string $s): string {
	if (!mb_check_encoding($s, 'UTF-8')) { $s = mb_convert_encoding($s, 'UTF-8', 'ISO-8859-1'); }
	$s = str_replace(["\r\n", "\r"], "\n", $s);
	return preg_replace('/[^\P{C}\n\t]/u', '', $s) ?? '';
}

/** Skriv fil exklusivt (x-mode) i $dir; returnerer sti eller null. */
function write_excl(string $dir, string $base, string $ext, string $content): ?string {
	umask(077);
	for ($i = 0; $i < 20; $i++) {
		$path = $dir . '/' . $base . ($i ? "_$i" : '') . $ext;
		$fh   = @fopen($path, 'x');
		if ($fh !== false) {
			$ok = fwrite($fh, $content) !== false;
			fclose($fh);
			if ($ok) { return $path; }
		}
	}
	return null;
}

/** Læg besked i outbox til straks-afsendelse af root (cbc-digest-alert.sh). Format: linje 1 = alert|plain, linje 2 = emne. */
function queue_out(string $mode, string $subject, string $body, string $job): bool {
	$p = write_excl(OUTBOX, date('Ymd-His') . '_' . $job, '.msg', $mode . "\n" . $subject . "\n" . $body . "\n");
	return $p !== null;
}

$file = $argv[1] ?? '';
$raw  = is_readable($file) ? (string) file_get_contents($file) : '';
if ($raw === '') { syslog(LOG_ERR, 'tom eller ulæselig besked'); exit(3); }

[$h, $body] = split_msg($raw);
$subject = trim(clean(mime_decode_header($h['subject'] ?? '(intet emne)')));
$from    = trim(clean(mime_decode_header($h['from'] ?? '?')));
$date    = trim(clean($h['date'] ?? ''));
[$plain, $html] = find_text($h, $body);
$text = $plain !== '' ? $plain : ($html !== '' ? html_to_text($html) : '(ingen tekstdel fundet)');
$text = clean(trim($text));
$lines = explode("\n", $text);
if (count($lines) > MAX_LINES) {
	$lines = array_slice($lines, 0, MAX_LINES);
	$lines[] = '… (afkortet af digest-ingest ved ' . MAX_LINES . ' linjer)';
}
$text = implode("\n", $lines);

// Job-navn = afsenderens adresse, renset til filnavn
$addr = preg_match('/<([^>]+)>/', $from, $m) ? $m[1] : $from;
$job  = 'mail-' . substr(preg_replace('/[^A-Za-z0-9_.-]+/', '_', strtolower($addr)) ?? 'ukendt', 0, 40);

$is_alert = false;
if (is_readable(PATTERNS)) {
	foreach (file(PATTERNS, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $pat) {
		$pat = trim($pat);
		if ($pat === '' || $pat[0] === '#') { continue; }
		$re = '~' . str_replace('~', '\~', $pat) . '~iu';
		if (@preg_match($re, $subject) === 1) { $is_alert = true; syslog(LOG_INFO, "alarm-mønster '$pat' matcher: $subject"); break; }
	}
}

$full = "Fra: $from\nDato: $date\n\n$text";

if (file_exists(DISABLED)) {
	$ok = queue_out($is_alert ? 'alert' : 'plain', $subject, $full, $job);
	syslog(LOG_INFO, 'digest slået fra -> outbox (' . ($ok ? 'ok' : 'FEJL') . "): $subject");
	exit($ok ? 0 : 4);
}

if ($is_alert) {
	$ok = queue_out('alert', $subject, $full . "\n\n-- Videresendt straks af cbc-digest-ingest (emnet matcher " . PATTERNS . ').', $job);
	syslog($ok ? LOG_INFO : LOG_ERR, 'alarm lagt i outbox (' . ($ok ? 'ok' : 'FEJL') . "): $subject");
	if (!$ok) { exit(5); }
	$full = "[SENDT STRAKS SOM ALARM]\n" . $full;
}

$path = write_excl(SPOOL, date('Ymd-His') . '_' . $job, '.txt', $subject . "\n" . $full . "\n");
if ($path !== null) { syslog(LOG_INFO, 'spoolet ' . basename($path) . ": $subject"); exit(0); }
syslog(LOG_ERR, "kunne ikke skrive i spool: $subject");
// Var den allerede lagt i outbox som alarm, er den ikke tabt; ellers -> wrapperen lægger den rå besked i outbox
exit($is_alert ? 0 : 6);
