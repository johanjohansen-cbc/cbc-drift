<?php
/**
 * CBC KickOff 2026 — theme integration.
 *
 * Loads the presentation stylesheet (front end + editor) and registers the
 * "CBC KickOff" block-pattern category. Fonts are delivered via theme.json
 * fontFace declarations, so no font enqueue is needed here.
 *
 * Include this file from the active (child) theme's functions.php:
 *     require get_stylesheet_directory() . '/inc/cbc-kickoff.php';
 *
 * @package CBC_KickOff
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit; // No direct access.
}

/**
 * Enqueue the CBC KickOff presentation stylesheet on the front end.
 */
function cbc_kickoff_enqueue_styles() {
	$rel  = '/assets/css/cbc-kickoff.css';
	$path = get_stylesheet_directory() . $rel;
	$uri  = get_stylesheet_directory_uri() . $rel;

	if ( ! file_exists( $path ) ) {
		return;
	}

	wp_enqueue_style(
		'cbc-kickoff',
		$uri,
		array(),
		(string) filemtime( $path )
	);
}
add_action( 'wp_enqueue_scripts', 'cbc_kickoff_enqueue_styles' );

/**
 * Load the same stylesheet inside the block editor so patterns render true.
 */
function cbc_kickoff_enqueue_editor_styles() {
	add_editor_style( 'assets/css/cbc-kickoff.css' );
}
add_action( 'after_setup_theme', 'cbc_kickoff_enqueue_editor_styles' );

/**
 * Register the block-pattern category used by the CBC KickOff patterns.
 */
function cbc_kickoff_register_pattern_category() {
	if ( ! function_exists( 'register_block_pattern_category' ) ) {
		return;
	}

	register_block_pattern_category(
		'cbc-kickoff',
		array(
			'label'       => __( 'CBC KickOff', 'cbc-kickoff' ),
			'description' => __( 'Sections for the CBC KickOff conference site.', 'cbc-kickoff' ),
		)
	);
}
add_action( 'init', 'cbc_kickoff_register_pattern_category' );

/**
 * Fallback pattern registration.
 *
 * Block themes auto-load any PHP file in /patterns, so this loop is only a
 * safety net for classic themes or when the patterns live outside /patterns.
 * It is a no-op when WordPress has already registered them.
 */
function cbc_kickoff_register_patterns() {
	if ( ! function_exists( 'register_block_pattern' ) || wp_is_block_theme() ) {
		return;
	}

	foreach ( glob( get_stylesheet_directory() . '/patterns/*.php' ) as $pattern_file ) {
		require $pattern_file;
	}
}
add_action( 'init', 'cbc_kickoff_register_patterns' );
