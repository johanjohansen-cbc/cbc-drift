<?php
// CBC daglig digest 2026-11-06: read-only WP-status til cbc-digest.sh. Koeres som sitets sysuser via
//   wp --skip-themes eval-file /usr/local/lib/cbc-digest/wp-status.php
// Output: noegle=vaerdi-linjer. Aendrer INTET. (Ingen declare(strict_types) - wp eval-file-gotcha.)
try {
	$now = time(); $over = 0; $oldest = 0;
	foreach ((array) _get_cron_array() as $t => $hooks) {
		if ((int) $t < $now - 3600) { $over += count((array) $hooks); $oldest = max($oldest, $now - (int) $t); }
	}
	echo 'cron_overdue=', $over, "\n", 'cron_oldest_h=', (int) floor($oldest / 3600), "\n";
	echo 'wp_version=', get_bloginfo('version'), "\n";

	$chn = 'CBC\\EventPlanner\\Admin\\Cron_Health_Notice';
	if (class_exists($chn)) {
		global $wpdb;
		$t = $wpdb->prefix . 'cbc_email_outbox';
		echo 'outbox_pending=', (int) $wpdb->get_var("SELECT COUNT(*) FROM $t WHERE status='pending'"), "\n";
		echo 'outbox_failed24=', (int) $wpdb->get_var("SELECT COUNT(*) FROM $t WHERE status='failed_permanent' AND created_at >= UTC_TIMESTAMP() - INTERVAL 24 HOUR"), "\n";
		$last = $wpdb->get_var("SELECT TIMESTAMPDIFF(MINUTE, MAX(sent_at), UTC_TIMESTAMP()) FROM $t WHERE status='sent' AND sent_at IS NOT NULL");
		echo 'outbox_last_sent_min=', ($last === null ? '-' : (int) $last), "\n";
		$rem = wp_next_scheduled('cbc_send_reminders');
		echo 'reminder_next=', ($rem ? wp_date('Y-m-d H:i', $rem) : 'ikke planlagt'), "\n";
		$problems = (new $chn())->detect_problems();
		foreach ($problems as $p) { echo 'problem=', preg_replace('/\s+/', ' ', wp_strip_all_tags((string) $p)), "\n"; }
	}
} catch (Throwable $e) {
	echo 'problem=wp-status fejlede: ', $e->getMessage(), "\n";
}
