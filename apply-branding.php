<?php
/** Apply only the managed palette/settings; never delete or reimport content. */
require_once __DIR__ . '/branding.php';

$environment = array();
foreach (array_merge(array_keys(wp_image_palette_defaults()), array(
    'ON_PRIMARY_COLOR', 'ON_ACCENT_COLOR', 'ON_SECONDARY_COLOR',
    'HEADER_BACKGROUND_COLOR', 'HEADER_TEXT_COLOR', 'HEADER_HOVER_COLOR',
    'FOOTER_BACKGROUND_COLOR', 'FOOTER_TEXT_COLOR', 'FOOTER_HOVER_COLOR',
)) as $name) {
    $environment[$name] = getenv($name);
}
try {
    $colors = wp_image_branding_config($environment);
} catch (InvalidArgumentException $error) {
    WP_CLI::error($error->getMessage());
}

$fingerprint = hash('sha256', 'wp-image-branding-v2:' . wp_json_encode($colors));
$force = getenv('WP_IMAGE_BRANDING_FORCE') === '1';
if (!$force && get_option('wp_image_branding_fingerprint') === $fingerprint) {
    WP_CLI::success('Branding configuration is unchanged.');
    return;
}

$palette = array();
foreach (wp_image_palette_defaults() as $name => $definition) {
    $palette[] = array('color' => $colors[$name], 'slug' => 'palette' . $definition[0], 'name' => 'Palette Color ' . $definition[0]);
}
update_option('kadence_global_palette', wp_json_encode(array(
    'palette' => $palette, 'second-palette' => $palette, 'third-palette' => $palette, 'active' => 'palette',
)), false);
update_option('my_primary_color', $colors['PRIMARY_COLOR'], false);
update_option('my_secondary_color', $colors['SECONDARY_COLOR'], false);
update_option('my_accent_color', $colors['ACCENT_COLOR'], false);

// Merge rather than discard sizing, typography, image, and responsive settings.
$merge_mod = static function ($name, $value) {
    $current = get_theme_mod($name, array());
    set_theme_mod($name, array_replace_recursive(is_array($current) ? $current : array(), $value));
};
$background = static function ($color) {
    return array('desktop' => array('color' => $color, 'type' => 'color'), 'tablet' => array('color' => $color, 'type' => 'color'), 'mobile' => array('color' => $color, 'type' => 'color'));
};
$header_navigation = array('color' => $colors['HEADER_TEXT_COLOR'], 'hover' => $colors['HEADER_HOVER_COLOR'], 'active' => $colors['HEADER_HOVER_COLOR']);
$footer_navigation = array('color' => $colors['FOOTER_TEXT_COLOR'], 'hover' => $colors['FOOTER_HOVER_COLOR'], 'active' => $colors['FOOTER_HOVER_COLOR']);
$surface_hover = wp_image_readable_color($colors['ACCENT_COLOR'], $colors['SURFACE_COLOR'], $colors['TEXT_STRONG_COLOR'], $colors['SURFACE_COLOR']);

$merge_mod('base_font', array('color' => 'palette4'));
$merge_mod('site_background', $background('palette8'));
$merge_mod('content_background', $background('palette9'));
$merge_mod('product_archive_content_background', $background('palette9'));
foreach (array('h1_font', 'h2_font', 'h3_font', 'h4_font', 'h5_font', 'h6_font') as $name) {
    $merge_mod($name, array('color' => 'palette3'));
}
$merge_mod('link_color', array(
    'highlight' => wp_image_readable_color($colors['PRIMARY_COLOR'], $colors['SURFACE_COLOR'], $colors['TEXT_STRONG_COLOR'], $colors['SURFACE_COLOR']),
    'highlight-alt' => $surface_hover,
    'highlight-alt2' => wp_image_readable_color($colors['SECONDARY_COLOR'], $colors['SURFACE_COLOR'], $colors['TEXT_STRONG_COLOR'], $colors['SURFACE_COLOR']),
    'style' => 'standard',
));
$merge_mod('buttons_color', array('color' => $colors['ON_PRIMARY_COLOR'], 'hover' => $colors['ON_ACCENT_COLOR']));
$merge_mod('buttons_background', array('color' => 'palette1', 'hover' => 'palette2'));
$merge_mod('buttons_secondary_color', array('color' => $colors['ON_SECONDARY_COLOR'], 'hover' => $colors['ON_ACCENT_COLOR']));
$merge_mod('buttons_secondary_background', array('color' => 'palette10', 'hover' => 'palette2'));

foreach (array(
    'header_wrap_background', 'header_top_background', 'header_main_background', 'header_bottom_background',
    'header_top_trans_background', 'header_main_trans_background', 'header_bottom_trans_background',
    'transparent_header_background', 'header_sticky_background', 'header_popup_background',
) as $name) {
    $merge_mod($name, $background($colors['HEADER_BACKGROUND_COLOR']));
}
foreach (array('primary_navigation_color', 'secondary_navigation_color', 'mobile_navigation_color', 'transparent_header_navigation_color', 'header_sticky_navigation_color') as $name) {
    $merge_mod($name, $header_navigation);
}
foreach (array('primary_navigation_background', 'secondary_navigation_background', 'mobile_navigation_background', 'transparent_header_navigation_background', 'header_sticky_navigation_background') as $name) {
    $merge_mod($name, array('color' => $colors['HEADER_BACKGROUND_COLOR'], 'hover' => $colors['HEADER_BACKGROUND_COLOR'], 'active' => $colors['HEADER_BACKGROUND_COLOR']));
}
$merge_mod('brand_typography', array('color' => $colors['HEADER_TEXT_COLOR']));
$merge_mod('brand_tag_typography', array('color' => $colors['HEADER_TEXT_COLOR']));
$merge_mod('brand_typography_color', $header_navigation);
$merge_mod('logo_icon_color', array('color' => $colors['HEADER_TEXT_COLOR']));
$merge_mod('transparent_header_site_title_color', array('color' => $colors['HEADER_TEXT_COLOR']));
$merge_mod('transparent_logo_icon_color', array('color' => $colors['HEADER_TEXT_COLOR']));
$merge_mod('header_sticky_site_title_color', array('color' => $colors['HEADER_TEXT_COLOR']));
$merge_mod('header_sticky_logo_icon_color', array('color' => $colors['HEADER_TEXT_COLOR']));
foreach (array('mobile_trigger_color', 'header_popup_close_color', 'header_search_color') as $name) {
    $merge_mod($name, array('color' => $colors['HEADER_TEXT_COLOR'], 'hover' => $colors['HEADER_HOVER_COLOR']));
}
foreach (array('mobile_trigger_background', 'header_popup_close_background', 'header_search_background', 'header_cart_background', 'header_mobile_cart_background') as $name) {
    $merge_mod($name, array('color' => $colors['HEADER_BACKGROUND_COLOR'], 'hover' => $colors['HEADER_BACKGROUND_COLOR']));
}
$merge_mod('dropdown_navigation_background', array('color' => $colors['HEADER_BACKGROUND_COLOR'], 'hover' => $colors['HEADER_BACKGROUND_COLOR'], 'active' => $colors['HEADER_BACKGROUND_COLOR']));
$merge_mod('dropdown_navigation_color', $header_navigation);

foreach (array('header_cart_color', 'header_mobile_cart_color') as $name) {
    $merge_mod($name, array('color' => $colors['HEADER_TEXT_COLOR'], 'hover' => $colors['HEADER_HOVER_COLOR']));
}
foreach (array('header_cart_total_color', 'header_mobile_cart_total_color') as $name) {
    $merge_mod($name, array('color' => $colors['ON_ACCENT_COLOR'], 'hover' => $colors['ON_ACCENT_COLOR']));
}
foreach (array('header_cart_total_background', 'header_mobile_cart_total_background') as $name) {
    $merge_mod($name, array('color' => 'palette2', 'hover' => 'palette2'));
}
foreach (array('transparent_header_cart_color', 'header_sticky_cart_color') as $name) {
    $merge_mod($name, array('color' => $colors['HEADER_TEXT_COLOR'], 'hover' => $colors['HEADER_HOVER_COLOR'], 'background' => $colors['HEADER_BACKGROUND_COLOR'], 'backgroundHover' => $colors['HEADER_BACKGROUND_COLOR']));
}
foreach (array('transparent_header_cart_total_color', 'header_sticky_cart_total_color') as $name) {
    $merge_mod($name, array('color' => $colors['ON_ACCENT_COLOR'], 'hover' => $colors['ON_ACCENT_COLOR'], 'background' => 'palette2', 'backgroundHover' => 'palette2'));
}
foreach (array('header_button_color', 'mobile_button_color') as $name) {
    $merge_mod($name, array('color' => $colors['ON_PRIMARY_COLOR'], 'hover' => $colors['ON_ACCENT_COLOR']));
}
foreach (array('header_button_background', 'mobile_button_background') as $name) {
    $merge_mod($name, array('color' => 'palette1', 'hover' => 'palette2'));
}
foreach (array('transparent_header_button_color', 'header_sticky_button_color') as $name) {
    $merge_mod($name, array('color' => $colors['ON_PRIMARY_COLOR'], 'hover' => $colors['ON_ACCENT_COLOR'], 'background' => 'palette1', 'backgroundHover' => 'palette2', 'border' => 'palette1', 'borderHover' => 'palette2'));
}

foreach (array('footer_wrap_background', 'footer_top_background', 'footer_middle_background', 'footer_bottom_background') as $name) {
    $merge_mod($name, $background($colors['FOOTER_BACKGROUND_COLOR']));
}
$merge_mod('footer_navigation_color', $footer_navigation);
$merge_mod('footer_navigation_background', array('color' => $colors['FOOTER_BACKGROUND_COLOR'], 'hover' => $colors['FOOTER_BACKGROUND_COLOR'], 'active' => $colors['FOOTER_BACKGROUND_COLOR']));
foreach (array('top', 'middle', 'bottom') as $row) {
    $merge_mod('footer_' . $row . '_widget_title', array('color' => $colors['FOOTER_TEXT_COLOR']));
    $merge_mod('footer_' . $row . '_widget_content', array('color' => $colors['FOOTER_TEXT_COLOR']));
    $merge_mod('footer_' . $row . '_link_colors', array('color' => $colors['FOOTER_TEXT_COLOR'], 'hover' => $colors['FOOTER_HOVER_COLOR']));
}
$merge_mod('footer_html_typography', array('color' => $colors['FOOTER_TEXT_COLOR']));
$merge_mod('footer_html_link_color', array('color' => $colors['FOOTER_TEXT_COLOR'], 'hover' => $colors['FOOTER_HOVER_COLOR']));

// Migrate only this export's legacy overrides on an already-imported site.
if ($force || get_option('wp_complete_theme_imported')) {
    // WP-CLI has no logged-in user here. As with WXR import, preserve the
    // already-stored form HTML instead of filtering it as a new user submission.
    kses_remove_filters();
    try {
        foreach (get_posts(array('post_type' => 'page', 'post_status' => 'any', 'numberposts' => -1)) as $post) {
            $content = wp_image_normalize_legacy_content($post->post_content);
            if ($content !== $post->post_content) {
                $result = wp_update_post(wp_slash(array('ID' => $post->ID, 'post_content' => $content)), true);
                if (is_wp_error($result)) {
                    WP_CLI::error('Cannot update legacy template colors: ' . $result->get_error_message());
                }
            }
        }
    } finally {
        kses_init();
    }
}

$css = wp_image_normalize_legacy_css(wp_get_custom_css('kadence'));
if ($css !== wp_get_custom_css('kadence')) {
    $result = wp_update_custom_css_post($css, array('stylesheet' => 'kadence'));
    if (is_wp_error($result)) {
        WP_CLI::error('Cannot normalize legacy branding CSS: ' . $result->get_error_message());
    }
}

foreach (array(
    array('ON_PRIMARY_COLOR', 'PRIMARY_COLOR'), array('ON_ACCENT_COLOR', 'ACCENT_COLOR'), array('ON_SECONDARY_COLOR', 'SECONDARY_COLOR'),
    array('HEADER_TEXT_COLOR', 'HEADER_BACKGROUND_COLOR'), array('HEADER_HOVER_COLOR', 'HEADER_BACKGROUND_COLOR'),
    array('FOOTER_TEXT_COLOR', 'FOOTER_BACKGROUND_COLOR'), array('FOOTER_HOVER_COLOR', 'FOOTER_BACKGROUND_COLOR'),
) as $pair) {
    if (wp_image_contrast($colors[$pair[0]], $colors[$pair[1]]) < 4.5) {
        WP_CLI::warning($pair[0] . ' has low contrast against ' . $pair[1] . '; use auto for a readable default.');
    }
}
update_option('wp_image_branding_colors', $colors, false);
update_option('wp_image_branding_fingerprint', $fingerprint, false);
WP_CLI::success('Palette and readable foreground colors applied.');
