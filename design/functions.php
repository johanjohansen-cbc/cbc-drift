<?php
/**
 * CBC KickOff (Child) — functions.
 *
 * @package CBC_KickOff
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

/**
 * Enqueue the parent theme stylesheet (only relevant for a classic parent
 * theme; block themes can leave this — it is harmless if the handle is absent).
 */
function cbc_kickoff_child_enqueue_parent() {
	$parent = get_template_directory() . '/style.css';
	if ( file_exists( $parent ) ) {
		wp_enqueue_style(
			'cbc-kickoff-parent',
			get_template_directory_uri() . '/style.css',
			array(),
			(string) filemtime( $parent )
		);
	}
}
add_action( 'wp_enqueue_scripts', 'cbc_kickoff_child_enqueue_parent', 5 );

// Load the CBC KickOff integration (styles, editor styles, patterns).
require get_stylesheet_directory() . '/inc/cbc-kickoff.php';
