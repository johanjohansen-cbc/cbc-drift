<?php
/**
 * Title: CBC Program
 * Slug: cbc-kickoff/program
 * Categories: cbc-kickoff
 * Description: Two-track conference schedule (Salg / Teknik) with shared full-width slots.
 *
 * NOTE FOR INTEGRATION: the schedule below is wrapped in a core/html block so it
 * renders faithfully as static content. In production, output this same markup
 * from the template that loops over session data. Row recipe:
 *   - Shared slot:  <div class="cbc-slot is-full"> time + one .cbc-cell
 *   - Two tracks:   <div class="cbc-slot"> time + .cbc-cell.is-salg + .cbc-cell.is-teknik
 *   - Section band: <div class="cbc-slot"><div class="cbc-band">…</div></div>
 *
 * @package CBC_KickOff
 */
?>
<!-- wp:group {"align":"full","className":"cbc-section","layout":{"type":"constrained"}} -->
<div class="wp-block-group alignfull cbc-section">
	<!-- wp:group {"className":"cbc-sec-head","layout":{"type":"default"}} -->
	<div class="wp-block-group cbc-sec-head">
		<!-- wp:paragraph {"className":"cbc-sec-tag"} --><p class="cbc-sec-tag">Program</p><!-- /wp:paragraph -->
		<!-- wp:heading {"level":2,"fontSize":"xx-large"} --><h2 class="wp-block-heading has-xx-large-font-size">Dagens forløb</h2><!-- /wp:heading -->
	</div>
	<!-- /wp:group -->

	<!-- wp:html -->
	<div class="cbc-day"><h3>Fredag</h3><span class="cbc-serif">11. september 2026</span></div>
	<div class="cbc-legend">
		<span><i style="background:var(--green)"></i> Salg</span>
		<span><i style="background:var(--teal)"></i> Teknik</span>
		<span><i style="background:var(--ink)"></i> Fælles</span>
	</div>
	<div class="cbc-sched">
		<div class="cbc-slot is-full">
			<div class="cbc-time">09:00–09:30</div>
			<div class="cbc-cell"><div class="ev">Ankomst og morgenmad</div><div class="room">Foyeren</div></div>
		</div>
		<div class="cbc-slot is-full">
			<div class="cbc-time">09:30–10:00</div>
			<div class="cbc-cell"><div class="ev">Velkomst v. Jan Nissen Petersen</div><div class="room">Scenen</div><div class="note">Jan jonglerer med sabler og sluger ild!</div></div>
		</div>
		<div class="cbc-slot">
			<div class="cbc-band">Messetid, møder og breakout sessions <span class="t">10:00–11:00</span></div>
		</div>
		<div class="cbc-slot">
			<div class="cbc-time">10:00–10:30</div>
			<div class="cbc-cell is-salg"><span class="cbc-track is-salg">Salg</span><div class="ev">Breakout: Kold kanvas i en varm AI-æra</div><div class="room">Rød Stue</div></div>
			<div class="cbc-cell is-teknik"><span class="cbc-track is-teknik">Teknik</span><div class="ev">Breakout: Sådan tøjler du din AI</div><div class="room">Blå Stue</div></div>
		</div>
		<div class="cbc-slot">
			<div class="cbc-time">10:30–11:00</div>
			<div class="cbc-cell is-salg"><span class="cbc-track is-salg">Salg</span><div class="ev">Demo: Sådan sælger du vand i Sahara</div><div class="room">Orange Scene</div><div class="note">Pistolsalg der aldrig fejler.</div><span class="host">Vært: Klaus Riskjær</span></div>
			<div class="cbc-cell is-teknik"><span class="cbc-track is-teknik">Teknik</span><div class="ev">Workshop: Hækl din egen firewall</div><div class="room">Hyggekælderen</div><div class="note">Craft møder tech.</div><span class="host">Vært: Frank Erichsen</span></div>
		</div>
		<div class="cbc-slot is-full">
			<div class="cbc-time">11:00–11:55</div>
			<div class="cbc-cell"><div class="ev">Keynote: Sådan barberer du en ged</div><div class="room">Scenen</div></div>
		</div>
		<div class="cbc-slot is-full">
			<div class="cbc-time">12:00–13:00</div>
			<div class="cbc-cell"><div class="ev">Frokost</div><div class="room">Frokoststuen</div><div class="note">Connies veganske skinkekutter serverer tempeh-hotdogs med bipollen.</div></div>
		</div>
	</div>
	<!-- /wp:html -->
</div>
<!-- /wp:group -->
