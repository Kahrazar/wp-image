#!/usr/bin/env bash
set -Eeuo pipefail

export WP_CLI_ALLOW_ROOT=1

WP_PATH="${WP_PATH:-/var/www/html}"
TEMPLATE_DIR="${COMPLETE_THEME_DIR:-/local-templates/wp-complete-theme}"
IMPORT_ENABLED="${COMPLETE_THEME_IMPORT_ENABLED:-true}"
MARKER_OPTION="wp_complete_theme_imported"

WP=(
  php
  -d
  memory_limit=512M
  /usr/local/bin/wp
  --allow-root
  --path="${WP_PATH}"
)

case "${IMPORT_ENABLED}" in
  false|FALSE|0|no|NO|off|OFF)
    echo "Complete theme import deshabilitado."
    exit 0
    ;;
esac

if "${WP[@]}" option get "${MARKER_OPTION}" >/dev/null 2>&1; then
  echo "Complete theme ya fue importado."
  exit 0
fi

CONTENT_XML="${TEMPLATE_DIR}/content/design-content.xml"
UPLOADS_ARCHIVE="${TEMPLATE_DIR}/media/uploads.tar.gz"
THEME_MODS_FILE="${TEMPLATE_DIR}/theme/kadence-theme-mods.json"
CUSTOM_CSS_FILE="${TEMPLATE_DIR}/theme/custom-css.css"
SITE_STRUCTURE_FILE="${TEMPLATE_DIR}/config/site-structure.json"
SOURCE_URL_FILE="${TEMPLATE_DIR}/metadata/source-url.txt"

for REQUIRED_FILE in "${CONTENT_XML}" "${THEME_MODS_FILE}" "${CUSTOM_CSS_FILE}" "${SITE_STRUCTURE_FILE}"; do
  if [ ! -f "${REQUIRED_FILE}" ]; then
    echo "ERROR: falta archivo requerido del template: ${REQUIRED_FILE}" >&2
    exit 1
  fi
done

if ! "${WP[@]}" theme is-active kadence; then
  echo "ERROR: Kadence debe estar activo antes de importar el template." >&2
  exit 1
fi

if ! "${WP[@]}" plugin is-active kadence-blocks; then
  echo "ERROR: Kadence Blocks debe estar activo antes de importar el template." >&2
  exit 1
fi

normalize_url() {
  local URL="$1"
  URL="${URL%/}"
  printf '%s' "${URL}"
}

is_placeholder_domain() {
  case "$1" in
    ""|"domain.com"|"http://domain.com"|"https://domain.com")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

TARGET_URL="${COMPLETE_THEME_TARGET_URL:-}"

if [ -z "${TARGET_URL}" ] && [ -n "${SITE_DOMAIN:-}" ] && ! is_placeholder_domain "${SITE_DOMAIN}"; then
  TARGET_URL="${SITE_DOMAIN}"
fi

if [ -z "${TARGET_URL}" ]; then
  TARGET_URL="${WP_URL:-}"
fi

if [ -z "${TARGET_URL}" ]; then
  TARGET_URL="$("${WP[@]}" option get home)"
fi

case "${TARGET_URL}" in
  http://*|https://*)
    ;;
  *)
    TARGET_URL="${WP_PROTOCOL:-https}://${TARGET_URL}"
    ;;
esac

TARGET_URL="$(normalize_url "${TARGET_URL}")"
SOURCE_URL="http://localhost:8081"

if [ -f "${SOURCE_URL_FILE}" ]; then
  SOURCE_URL="$(normalize_url "$(tr -d '\r\n' < "${SOURCE_URL_FILE}")")"
fi

TARGET_DOMAIN="${TARGET_URL#http://}"
TARGET_DOMAIN="${TARGET_DOMAIN#https://}"
TARGET_DOMAIN="${TARGET_DOMAIN%%/*}"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

PREPARED_XML="${WORK_DIR}/design-content.xml"
KEEP_BOOKING_TERMS="0"

if "${WP[@]}" plugin is-active tour-booking-manager >/dev/null 2>&1; then
  KEEP_BOOKING_TERMS="1"
fi

echo "Preparando template Kadence..."
echo "URL origen: ${SOURCE_URL}"
echo "URL destino: ${TARGET_URL}"

COMPLETE_THEME_SOURCE_URL="${SOURCE_URL}" \
COMPLETE_THEME_TARGET_URL="${TARGET_URL}" \
COMPLETE_THEME_TARGET_DOMAIN="${TARGET_DOMAIN}" \
COMPLETE_THEME_KEEP_BOOKING_TERMS="${KEEP_BOOKING_TERMS}" \
php -r '
$input = $argv[1];
$output = $argv[2];

$source = rtrim(getenv("COMPLETE_THEME_SOURCE_URL") ?: "http://localhost:8081", "/");
$target = rtrim(getenv("COMPLETE_THEME_TARGET_URL") ?: "", "/");
$domain = getenv("COMPLETE_THEME_TARGET_DOMAIN") ?: "";
$site_title = getenv("WP_TITLE") ?: "Tienda";
$city = getenv("STORE_CITY") ?: "";
$address = getenv("STORE_ADDRESS") ?: "";
$country = getenv("STORE_COUNTRY") ?: "";
$postcode = getenv("STORE_POSTCODE") ?: "";
$address_short = trim($city !== "" ? $city : $address);
$address_exact = trim(implode(", ", array_filter(array($address, $city, $country))));
if ($postcode !== "") {
    $address_exact = trim($address_exact . " " . $postcode);
}

$data = file_get_contents($input);
if ($data === false) {
    fwrite(STDERR, "No se pudo leer el XML del template.\n");
    exit(1);
}

if ($source !== "" && $target !== "") {
    $data = str_replace($source, $target, $data);
}

$data = preg_replace_callback(
    "/\\s*<item>.*?<\\/item>/s",
    function ($matches) {
        return strpos($matches[0], "<wp:post_type>attachment</wp:post_type>") === false
            ? $matches[0]
            : "";
    },
    $data
);

if (getenv("COMPLETE_THEME_KEEP_BOOKING_TERMS") !== "1") {
    $data = preg_replace_callback(
        "/\\s*<wp:term>.*?<\\/wp:term>/s",
        function ($matches) {
            return strpos($matches[0], "<wp:term_taxonomy>ttbm_") === false
                ? $matches[0]
                : "";
        },
        $data
    );
}

$replacements = array(
    "{{EI_WEBSITE_TITLE}}" => getenv("EI_WEBSITE_TITLE") ?: $site_title,
    "{{EI_WEBSITE_BUSINESS}}" => getenv("EI_WEBSITE_BUSINESS") ?: $site_title,
    "{{EI_WEBSITE_DOMAIN}}" => getenv("EI_WEBSITE_DOMAIN") ?: $domain,
    "{{EI_WEBSITE_ADDRESS}}" => getenv("EI_WEBSITE_ADDRESS") ?: $address_short,
    "{{EI_WEBSITE_EXACT_ADDRESS}}" => getenv("EI_WEBSITE_EXACT_ADDRESS") ?: $address_exact,
    "{{EI_WEBSITE_SLOGAN}}" => getenv("EI_WEBSITE_SLOGAN") ?: $site_title,
    "{{EI_WEBSITE_SLOGAN_SUBTEXT}}" => getenv("EI_WEBSITE_SLOGAN_SUBTEXT") ?: "Bienvenido a " . $site_title,
    "{{EI_WEBSITE_HISTORY_SLOGAN}}" => getenv("EI_WEBSITE_HISTORY_SLOGAN") ?: "Nuestra historia",
    "{{EI_EMPRENDE_MISSION_TEXT}}" => getenv("EI_EMPRENDE_MISSION_TEXT") ?: "",
    "{{EI_EMPRENDE_PHILOSOPHY_TEXT}}" => getenv("EI_EMPRENDE_PHILOSOPHY_TEXT") ?: "",
    "{{EI_EMPRENDE_WEBSITE_FOUNDATION_TEXT}}" => getenv("EI_EMPRENDE_WEBSITE_FOUNDATION_TEXT") ?: "",
);

$data = strtr($data, $replacements);

if (file_put_contents($output, $data) === false) {
    fwrite(STDERR, "No se pudo escribir el XML preparado.\n");
    exit(1);
}
' "${CONTENT_XML}" "${PREPARED_XML}"

WP_CONTENT_DIR="$("${WP[@]}" eval 'echo WP_CONTENT_DIR;')"

if [ -f "${UPLOADS_ARCHIVE}" ]; then
  echo "Restaurando Media Library del template..."
  mkdir -p "${WP_CONTENT_DIR}"
  tar --exclude='uploads/wc-logs' -xzf "${UPLOADS_ARCHIVE}" -C "${WP_CONTENT_DIR}"
  chown -R www-data:www-data "${WP_CONTENT_DIR}/uploads" || true
else
  echo "No se encontro media/uploads.tar.gz; se omite restauracion de uploads."
fi

echo "Limpiando contenido base antes de importar template..."
CONTENT_TYPES="page,post,custom_css,wp_block,wp_navigation,wp_template,wp_template_part,wp_global_styles,nav_menu_item"
POST_IDS="$("${WP[@]}" post list --post_type="${CONTENT_TYPES}" --post_status=any --format=ids || true)"

if [ -n "${POST_IDS}" ]; then
  "${WP[@]}" post delete ${POST_IDS} --force
fi

MENU_IDS="$("${WP[@]}" menu list --format=ids || true)"

if [ -n "${MENU_IDS}" ]; then
  for MENU_ID in ${MENU_IDS}; do
    "${WP[@]}" menu delete "${MENU_ID}" || true
  done
fi

echo "Instalando WordPress Importer..."
if ! "${WP[@]}" plugin is-installed wordpress-importer; then
  "${WP[@]}" plugin install wordpress-importer
fi

if ! "${WP[@]}" plugin is-active wordpress-importer; then
  "${WP[@]}" plugin activate wordpress-importer
fi

echo "Importando contenido del template..."
"${WP[@]}" import "${PREPARED_XML}" --authors=create --skip=attachment

echo "Aplicando Kadence theme mods del template..."
COMPLETE_THEME_MODS_FILE="${THEME_MODS_FILE}" "${WP[@]}" eval '
$file = getenv("COMPLETE_THEME_MODS_FILE");
$mods = json_decode(file_get_contents($file), true);

if (!is_array($mods)) {
    WP_CLI::error("kadence-theme-mods.json no es JSON valido.");
}

$skip = array(
    "0" => true,
    "custom_css_post_id" => true,
    "nav_menu_locations" => true,
);

foreach ($mods as $key => $value) {
    if (isset($skip[(string) $key])) {
        continue;
    }

    set_theme_mod($key, $value);
}

WP_CLI::success("Kadence theme mods importados.");
'

echo "Aplicando CSS adicional del template..."
COMPLETE_THEME_CSS_FILE="${CUSTOM_CSS_FILE}" "${WP[@]}" eval '
$file = getenv("COMPLETE_THEME_CSS_FILE");
$css = file_exists($file) ? file_get_contents($file) : "";

if ($css === false) {
    WP_CLI::error("No se pudo leer custom-css.css.");
}

wp_update_custom_css_post($css, array("stylesheet" => "kadence"));
WP_CLI::success("CSS adicional importado.");
'

echo "Restaurando estructura del sitio..."
COMPLETE_THEME_STRUCTURE_FILE="${SITE_STRUCTURE_FILE}" "${WP[@]}" eval '
$file = getenv("COMPLETE_THEME_STRUCTURE_FILE");
$structure = json_decode(file_get_contents($file), true);

if (!is_array($structure)) {
    WP_CLI::error("site-structure.json no es JSON valido.");
}

$find_page_id = function ($slug) {
    if (!$slug) {
        return 0;
    }

    $page = get_page_by_path($slug, OBJECT, "page");
    return $page ? (int) $page->ID : 0;
};

if (!empty($structure["permalink_structure"])) {
    update_option("permalink_structure", $structure["permalink_structure"]);
}

if (!empty($structure["show_on_front"])) {
    update_option("show_on_front", $structure["show_on_front"]);
}

$front_id = $find_page_id($structure["front_page"]["slug"] ?? "");
if ($front_id) {
    update_option("page_on_front", $front_id);
}

$posts_id = $find_page_id($structure["posts_page"]["slug"] ?? "");
if ($posts_id) {
    update_option("page_for_posts", $posts_id);
}

$shop_id = $find_page_id($structure["shop_page"]["slug"] ?? "");
if ($shop_id) {
    update_option("woocommerce_shop_page_id", $shop_id);
}

$woocommerce_pages = array(
    "cart" => "woocommerce_cart_page_id",
    "checkout" => "woocommerce_checkout_page_id",
    "my-account" => "woocommerce_myaccount_page_id",
);

foreach ($woocommerce_pages as $slug => $option) {
    $page_id = $find_page_id($slug);
    if ($page_id) {
        update_option($option, $page_id);
    }
}

$locations = get_theme_mod("nav_menu_locations", array());
foreach (($structure["menu_locations"] ?? array()) as $location => $menu_data) {
    $slug = $menu_data["slug"] ?? "";
    $name = $menu_data["name"] ?? "";
    $menu = $slug ? wp_get_nav_menu_object($slug) : false;

    if (!$menu && $name) {
        $menu = wp_get_nav_menu_object($name);
    }

    if ($menu) {
        $locations[$location] = (int) $menu->term_id;
    }
}

set_theme_mod("nav_menu_locations", $locations);
WP_CLI::success("Estructura del sitio restaurada.");
'

echo "Reaplicando branding desde variables de entorno..."
"${WP[@]}" eval '
$primary = getenv("PRIMARY_COLOR") ?: "#2f6f4e";
$secondary = getenv("SECONDARY_COLOR") ?: "#f2c14e";
$accent = getenv("ACCENT_COLOR") ?: "#c44536";

update_option("my_primary_color", $primary, false);
update_option("my_secondary_color", $secondary, false);
update_option("my_accent_color", $accent, false);

$palette_item = function($color, $slug, $name) {
    return array(
        "color" => $color,
        "slug" => $slug,
        "name" => $name,
    );
};

$active_palette = array(
    $palette_item($primary, "palette1", "Palette Color 1"),
    $palette_item($accent, "palette2", "Palette Color 2"),
    $palette_item("#1A202C", "palette3", "Palette Color 3"),
    $palette_item("#2D3748", "palette4", "Palette Color 4"),
    $palette_item("#4A5568", "palette5", "Palette Color 5"),
    $palette_item("#718096", "palette6", "Palette Color 6"),
    $palette_item("#EDF2F7", "palette7", "Palette Color 7"),
    $palette_item("#F7FAFC", "palette8", "Palette Color 8"),
    $palette_item("#ffffff", "palette9", "Palette Color 9"),
    $palette_item($secondary, "palette10", "Palette Color Complement"),
    $palette_item("#13612e", "palette11", "Palette Color Success"),
    $palette_item("#1159af", "palette12", "Palette Color Info"),
    $palette_item("#b82105", "palette13", "Palette Color Alert"),
    $palette_item("#f7630c", "palette14", "Palette Color Warning"),
    $palette_item("#f5a524", "palette15", "Palette Color Rating"),
);

update_option(
    "kadence_global_palette",
    wp_json_encode(
        array(
            "palette" => $active_palette,
            "second-palette" => $active_palette,
            "third-palette" => $active_palette,
            "active" => "palette",
        )
    ),
    false
);

set_theme_mod("link_color", array("highlight" => "palette1", "highlight-alt" => "palette2", "highlight-alt2" => "palette10", "style" => "standard"));
set_theme_mod("buttons_color", array("color" => "palette9", "hover" => "palette9"));
set_theme_mod("buttons_background", array("color" => "palette1", "hover" => "palette2"));
set_theme_mod("buttons_secondary_color", array("color" => "palette3", "hover" => "palette9"));
set_theme_mod("buttons_secondary_background", array("color" => "palette10", "hover" => "palette2"));
set_theme_mod("header_wrap_background", array("desktop" => array("color" => "palette1")));
set_theme_mod("header_main_background", array("desktop" => array("color" => "palette1")));
set_theme_mod("primary_navigation_color", array("color" => "palette9", "hover" => "palette10", "active" => "palette10"));
set_theme_mod("mobile_navigation_color", array("color" => "palette9", "hover" => "palette10", "active" => "palette10"));
set_theme_mod("footer_wrap_background", array("desktop" => array("color" => "palette1")));
set_theme_mod("footer_bottom_background", array("desktop" => array("color" => "palette1")));
set_theme_mod("footer_navigation_color", array("color" => "palette9", "hover" => "palette10", "active" => "palette10"));
set_theme_mod("logo_icon_color", array("color" => "palette9"));

$brand_typography = get_theme_mod("brand_typography", array());
if (!is_array($brand_typography)) {
    $brand_typography = array();
}
$brand_typography["color"] = "palette9";
set_theme_mod("brand_typography", $brand_typography);

WP_CLI::success("Branding reaplicado.");
'

"${WP[@]}" rewrite structure '/%postname%/' --hard
"${WP[@]}" rewrite flush --hard
"${WP[@]}" option update "${MARKER_OPTION}" "1"

echo "Complete theme import finalizado."
