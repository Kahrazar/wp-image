<?php
/** Shared color resolution for provisioning and later branding-only updates. */

function wp_image_palette_defaults() {
    return array(
        'PRIMARY_COLOR' => array(1, '#2f6f4e'),
        'ACCENT_COLOR' => array(2, '#c44536'),
        'TEXT_STRONG_COLOR' => array(3, '#1a202c'),
        'TEXT_COLOR' => array(4, '#2d3748'),
        'TEXT_MUTED_COLOR' => array(5, '#4a5568'),
        'BORDER_COLOR' => array(6, '#718096'),
        'BACKGROUND_SUBTLE_COLOR' => array(7, '#edf2f7'),
        'BACKGROUND_COLOR' => array(8, '#f7fafc'),
        'SURFACE_COLOR' => array(9, '#ffffff'),
        'SECONDARY_COLOR' => array(10, '#f2c14e'),
        'SUCCESS_COLOR' => array(11, '#13612e'),
        'INFO_COLOR' => array(12, '#1159af'),
        'ALERT_COLOR' => array(13, '#b82105'),
        'WARNING_COLOR' => array(14, '#f7630c'),
        'RATING_COLOR' => array(15, '#f5a524'),
    );
}

function wp_image_env_color($environment, $name, $default, $allow_auto = false) {
    $value = trim((string) ($environment[$name] ?? ''));
    if ($value === '') {
        return $default;
    }
    if ($allow_auto && strtolower($value) === 'auto') {
        return 'auto';
    }
    if (!preg_match('/^#[0-9a-fA-F]{6}$/D', $value)) {
        throw new InvalidArgumentException($name . ' must be a six-digit hex color' . ($allow_auto ? ' or auto.' : '.'));
    }
    return strtolower($value);
}

function wp_image_luminance($color) {
    $channels = array();
    for ($offset = 1; $offset < 7; $offset += 2) {
        $channel = hexdec(substr($color, $offset, 2)) / 255;
        $channels[] = $channel <= 0.04045 ? $channel / 12.92 : pow(($channel + 0.055) / 1.055, 2.4);
    }
    return 0.2126 * $channels[0] + 0.7152 * $channels[1] + 0.0722 * $channels[2];
}

function wp_image_contrast($foreground, $background) {
    $first = wp_image_luminance($foreground);
    $second = wp_image_luminance($background);
    return (max($first, $second) + 0.05) / (min($first, $second) + 0.05);
}

function wp_image_auto_foreground($background, $dark, $light) {
    $best = wp_image_contrast($dark, $background) >= wp_image_contrast($light, $background) ? $dark : $light;
    if (wp_image_contrast($best, $background) >= 4.5) {
        return $best;
    }
    // Custom text/surface colors can both have poor contrast. Black/white always
    // provide a readable fallback for a solid six-digit hex background.
    return wp_image_contrast('#000000', $background) >= wp_image_contrast('#ffffff', $background) ? '#000000' : '#ffffff';
}

function wp_image_readable_color($preferred, $background, $dark, $light) {
    return wp_image_contrast($preferred, $background) >= 4.5
        ? $preferred
        : wp_image_auto_foreground($background, $dark, $light);
}

function wp_image_branding_config($environment) {
    $colors = array();
    foreach (wp_image_palette_defaults() as $name => $definition) {
        $colors[$name] = wp_image_env_color($environment, $name, $definition[1]);
    }
    foreach (array('PRIMARY', 'ACCENT', 'SECONDARY') as $role) {
        $name = 'ON_' . $role . '_COLOR';
        $value = wp_image_env_color($environment, $name, 'auto', true);
        $colors[$name] = $value === 'auto'
            ? wp_image_auto_foreground($colors[$role . '_COLOR'], $colors['TEXT_STRONG_COLOR'], $colors['SURFACE_COLOR'])
            : $value;
    }
    foreach (array('HEADER', 'FOOTER') as $role) {
        $background = $role . '_BACKGROUND_COLOR';
        $colors[$background] = wp_image_env_color($environment, $background, $colors['PRIMARY_COLOR']);
        foreach (array('TEXT', 'HOVER') as $state) {
            $name = $role . '_' . $state . '_COLOR';
            $value = wp_image_env_color($environment, $name, 'auto', true);
            $colors[$name] = $value === 'auto'
                ? ($state === 'HOVER'
                    ? wp_image_readable_color($colors['ACCENT_COLOR'], $colors[$background], $colors['TEXT_STRONG_COLOR'], $colors['SURFACE_COLOR'])
                    : wp_image_auto_foreground($colors[$background], $colors['TEXT_STRONG_COLOR'], $colors['SURFACE_COLOR']))
                : $value;
        }
    }
    return $colors;
}

function wp_image_normalize_legacy_css($css) {
    return preg_replace_callback(
        '~(\.single-product div\.product \.woocommerce-tabs ul\.tabs(?: li\.active)?\s*\{)([^}]*)(\})~',
        static function ($match) {
            return $match[1] . preg_replace('~(border-bottom:\s*(?:1|3)px solid )#293a35(;?)~i', '$1var(--global-palette6)$2', $match[2]) . $match[3];
        },
        $css
    );
}

function wp_image_normalize_legacy_content($content) {
    $content = preg_replace(
        '~<!-- wp:html -->\s*<style>\.site-footer-wrap\{background: #cad2c3;\}</style>\s*<!-- /wp:html -->~',
        '',
        $content
    );
    return preg_replace_callback(
        '~(<!-- wp:kadence/form )(\{[^\r\n]*?\})( -->)~',
        static function ($match) {
            $attributes = json_decode($match[2], true);
            if (!is_array($attributes)
                || ($attributes['uniqueID'] ?? '') !== '68_867119-89'
                || ($attributes['submit'][0]['background'] ?? '') !== 'palette2') {
                return $match[0];
            }
            $submit = &$attributes['submit'][0];
            $on_accent = 'var(--brand-on-accent, var(--global-palette3))';
            if (in_array(strtolower((string) ($submit['color'] ?? '')), array('#ffffff', '#fff', 'palette9'), true)) {
                $submit['color'] = $on_accent;
            }
            if (strtolower((string) ($submit['backgroundHover'] ?? '')) === '#253b35') {
                $submit['backgroundHover'] = 'palette2';
                $submit['backgroundHoverOpacity'] = 1;
                if (empty($submit['colorHover']) || in_array(strtolower($submit['colorHover']), array('#ffffff', '#fff', 'palette9'), true)) {
                    $submit['colorHover'] = $on_accent;
                }
            }
            // Preserve WordPress's escaping for comment-sensitive custom labels.
            return $match[1] . serialize_block_attributes($attributes) . $match[3];
        },
        $content
    );
}
