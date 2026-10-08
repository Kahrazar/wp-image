<?php
/** Plain-text inputs shared by WXR preparation and its regression checks. */
function wp_image_template_values($environment, $domain)
{
    $title = $environment['WP_TITLE'] ?? '';
    $city = $environment['STORE_CITY'] ?? '';
    $address = $environment['STORE_ADDRESS'] ?? '';
    $exact_address = implode(', ', array_filter(array($address, $city, $environment['STORE_COUNTRY'] ?? ''), static function ($value) {
        return $value !== '';
    }));
    $exact_address = trim($exact_address . ' ' . ($environment['STORE_POSTCODE'] ?? ''));
    $defaults = array(
        'EI_WEBSITE_TITLE' => $title,
        'EI_WEBSITE_BUSINESS' => $title,
        'EI_WEBSITE_DOMAIN' => $domain,
        'EI_WEBSITE_ADDRESS' => $city !== '' ? $city : $address,
        'EI_WEBSITE_EXACT_ADDRESS' => $exact_address,
        'EI_WEBSITE_EMAIL' => '',
        'EI_WEBSITE_SLOGAN' => '',
        'EI_WEBSITE_SLOGAN_SUBTEXT' => '',
        'EI_WEBSITE_HISTORY_SLOGAN' => '',
        'EI_EMPRENDE_MISSION_TEXT' => '',
        'EI_EMPRENDE_PHILOSOPHY_TEXT' => '',
        'EI_EMPRENDE_WEBSITE_FOUNDATION_TEXT' => '',
    );
    $values = array();
    foreach ($defaults as $name => $default) {
        $value = $environment[$name] ?? '';
        $values['{{' . $name . '}}'] = $value !== '' ? $value : $default;
    }
    return $values;
}

function wp_image_prepare_template($xml, $environment)
{
    $document = new DOMDocument();
    $previous_errors = libxml_use_internal_errors(true);
    try {
        if (!$document->loadXML($xml, LIBXML_NONET)) {
            throw new RuntimeException('Invalid complete-theme WXR.');
        }
    } finally {
        libxml_clear_errors();
        libxml_use_internal_errors($previous_errors);
    }
    $xpath = new DOMXPath($document);
    $xpath->registerNamespace('wp', 'http://wordpress.org/export/1.2/');
    foreach ($xpath->query('/rss/channel/item[wp:post_type="attachment"]') as $item) {
        $item->parentNode->removeChild($item);
    }
    if (($environment['COMPLETE_THEME_KEEP_BOOKING_TERMS'] ?? '') !== '1') {
        foreach ($xpath->query('/rss/channel/wp:term[starts-with(wp:term_taxonomy, "ttbm_")]') as $term) {
            $term->parentNode->removeChild($term);
        }
    }

    $values = wp_image_template_values($environment, $environment['COMPLETE_THEME_TARGET_DOMAIN'] ?? '');
    $html_values = array_map(static function ($value) {
        return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    }, $values);
    $legacy_tokens = array(
        '{{email address}}' => '{{EI_WEBSITE_EMAIL}}', '{email address}' => '{{EI_WEBSITE_EMAIL}}',
        '{{email}}' => '{{EI_WEBSITE_EMAIL}}', '{email}' => '{{EI_WEBSITE_EMAIL}}',
        '{{physical address}}' => '{{EI_WEBSITE_EXACT_ADDRESS}}', '{physical address}' => '{{EI_WEBSITE_EXACT_ADDRESS}}',
    );
    $source = rtrim($environment['COMPLETE_THEME_SOURCE_URL'] ?? '', '/');
    $target = rtrim($environment['COMPLETE_THEME_TARGET_URL'] ?? '', '/');
    foreach ($xpath->query('//text()') as $node) {
        $text = strtr($node->nodeValue, $legacy_tokens);
        $text = preg_replace('/(?<!\{)\{(EI_[A-Z_]+)\}(?!\})/', '{{$1}}', $text);
        if ($source !== '' && $target !== '') {
            $text = str_replace($source, $target, $text);
        }
        preg_match_all('/\{\{EI_[A-Z_]+\}\}/', $text, $tokens);
        foreach ($tokens[0] as $token) {
            if (!array_key_exists($token, $values)) {
                throw new RuntimeException('Unsupported template placeholder: ' . $token);
            }
        }
        $is_html = $node->parentNode->localName === 'encoded'
            && in_array($node->parentNode->namespaceURI, array(
                'http://purl.org/rss/1.0/modules/content/', 'http://wordpress.org/export/1.2/excerpt/',
            ), true);
        $text = strtr($text, $is_html ? $html_values : $values);
        if ($text !== $node->nodeValue) {
            $node->nodeValue = $text;
        }
    }
    return $document->saveXML();
}
