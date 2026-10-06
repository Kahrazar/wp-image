<?php
/**
 * Plugin Name: WP Image Branding Colors
 * Description: Exposes resolved foreground/background roles to frontend and editor blocks.
 */

function wp_image_enqueue_branding_variables() {
    $colors = get_option('wp_image_branding_colors', array());
    if (!is_array($colors) || !$colors) {
        return;
    }
    $variables = array(
        '--brand-on-primary' => 'ON_PRIMARY_COLOR', '--brand-on-accent' => 'ON_ACCENT_COLOR', '--brand-on-secondary' => 'ON_SECONDARY_COLOR',
        '--brand-header-background' => 'HEADER_BACKGROUND_COLOR', '--brand-header-text' => 'HEADER_TEXT_COLOR', '--brand-header-hover' => 'HEADER_HOVER_COLOR',
        '--brand-footer-background' => 'FOOTER_BACKGROUND_COLOR', '--brand-footer-text' => 'FOOTER_TEXT_COLOR', '--brand-footer-hover' => 'FOOTER_HOVER_COLOR',
    );
    $css = ':root{';
    foreach ($variables as $variable => $name) {
        if (isset($colors[$name]) && preg_match('/^#[0-9a-fA-F]{6}$/D', $colors[$name])) {
            $css .= $variable . ':' . $colors[$name] . ';';
        }
    }
    $css .= '}';
    wp_register_style('wp-image-branding-colors', false, array(), null);
    wp_enqueue_style('wp-image-branding-colors');
    wp_add_inline_style('wp-image-branding-colors', $css);
}

// enqueue_block_assets also loads these variables inside the editor iframe.
add_action('enqueue_block_assets', 'wp_image_enqueue_branding_variables', 20);
