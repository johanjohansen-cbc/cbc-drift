<?php
/**
 * Title: CBC Vendors
 * Slug: cbc-kickoff/vendors
 * Categories: cbc-kickoff
 * Description: Vendor/exhibitor card grid. Loop the .cbc-vcard markup over vendor data.
 *
 * @package CBC_KickOff
 */
?>
<!-- wp:group {"align":"full","className":"cbc-section cbc-vendors","layout":{"type":"constrained"}} -->
<div class="wp-block-group alignfull cbc-section cbc-vendors">
	<!-- wp:group {"className":"cbc-sec-head","layout":{"type":"default"}} -->
	<div class="wp-block-group cbc-sec-head">
		<!-- wp:paragraph {"className":"cbc-sec-tag is-green"} --><p class="cbc-sec-tag is-green">Leverandører</p><!-- /wp:paragraph -->
		<!-- wp:heading {"level":2,"fontSize":"xx-large"} --><h2 class="wp-block-heading has-xx-large-font-size">Mød udstillerne</h2><!-- /wp:heading -->
		<!-- wp:paragraph {"textColor":"muted"} --><p class="has-muted-color has-text-color">Log ind for at anmode om et møde med en leverandør.</p><!-- /wp:paragraph -->
	</div>
	<!-- /wp:group -->

	<!-- wp:html -->
	<div class="cbc-vgrid">
		<!-- Repeat this card per vendor -->
		<div class="cbc-vcard">
			<div class="vlogo">H</div>
			<h3>Helt Nyt Firma A/S</h3>
			<div class="rep">Vera Vendor</div>
			<a class="req" href="#login">Log ind for at anmode om møde →</a>
		</div>
	</div>
	<!-- /wp:html -->
</div>
<!-- /wp:group -->
