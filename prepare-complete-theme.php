<?php
require __DIR__ . '/template-content.php';

try {
    if ($argc !== 3 || !is_file($argv[1])) {
        throw new RuntimeException('Usage: prepare-complete-theme.php INPUT_XML OUTPUT_XML');
    }
    $xml = file_get_contents($argv[1]);
    if ($xml === false || file_put_contents($argv[2], wp_image_prepare_template($xml, getenv())) === false) {
        throw new RuntimeException('Cannot prepare the complete-theme WXR.');
    }
} catch (Throwable $error) {
    fwrite(STDERR, $error->getMessage() . "\n");
    exit(1);
}
