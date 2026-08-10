#!/bin/bash
set -e

# =========================
# Startup
# =========================

echo "Iniciando MySQL..."

mariadbd-safe --datadir=/var/lib/mysql &

until mysqladmin ping -h127.0.0.1 --silent; do
  sleep 2
done

echo "MySQL listo."

# =========================
# MySQL Database Setup
# =========================

mysql -uroot <<EOF
CREATE DATABASE IF NOT EXISTS wp;

CREATE USER IF NOT EXISTS 'wpuser'@'localhost' IDENTIFIED BY 'wppass';
CREATE USER IF NOT EXISTS 'wpuser'@'127.0.0.1' IDENTIFIED BY 'wppass';

GRANT ALL PRIVILEGES ON wp.* TO 'wpuser'@'localhost';
GRANT ALL PRIVILEGES ON wp.* TO 'wpuser'@'127.0.0.1';

FLUSH PRIVILEGES;
EOF

# =========================
# WordPress CLI Setup
# =========================

cd /var/www/html

WP="php -d memory_limit=512M /usr/local/bin/wp --allow-root"
WP_PROTOCOL="${WP_PROTOCOL:-https}"
WP_LOCALE="${WP_LOCALE:-es_ES}"

case "$WP_PROTOCOL" in
  http|HTTP)
    WP_PROTOCOL="http"
    ;;
  https|HTTPS)
    WP_PROTOCOL="https"
    ;;
  *)
    echo "WP_PROTOCOL invalido: $WP_PROTOCOL. Usando https."
    WP_PROTOCOL="https"
    ;;
esac

# =========================
# WordPress Core Download
# =========================

if [ ! -f wp-load.php ]; then
  echo "Descargando WordPress..."
  $WP core download --locale="$WP_LOCALE"
fi

# =========================
# WP Config
# =========================

if [ ! -f wp-config.php ]; then
  echo "Creando wp-config.php..."

  $WP config create \
    --dbname=wp \
    --dbuser=wpuser \
    --dbpass=wppass \
    --dbhost=127.0.0.1 \
    --skip-check

  if [ ! -f wp-config.php ]; then
    echo "âŒ wp-config.php no se creÃ³"
    exit 1
  fi

  echo "Inyectando configuraciÃ³n dinÃ¡mica..."

  awk '
  /That'\''s all, stop editing!/ {
    print "$wp_protocol = strtolower(getenv(\"WP_PROTOCOL\") ?: \"https\");"
    print "if (!in_array($wp_protocol, array(\"http\", \"https\"), true)) {"
    print "    $wp_protocol = \"https\";"
    print "}"
    print "if ($wp_protocol === \"https\") {"
    print "    $_SERVER[\"HTTPS\"] = \"on\";"
    print "}"
    print "if (isset($_SERVER[\"HTTP_HOST\"])) {"
    print "    define(\"WP_HOME\", $wp_protocol . \"://\" . $_SERVER[\"HTTP_HOST\"]);"
    print "    define(\"WP_SITEURL\", $wp_protocol . \"://\" . $_SERVER[\"HTTP_HOST\"]);"
    print "}"
    print "define(\"SITE_DOMAIN\", getenv(\"SITE_DOMAIN\") ?: \"\");"
    print ""
  }
  { print }
  ' wp-config.php > wp-config.tmp && mv wp-config.tmp wp-config.php
fi
 
# =========================
# Database Verification
# =========================

echo "Config terminada"
echo "DEBUG DB CHECK:"
$WP db check || true
echo "Revisando BD"
until $WP db check > /dev/null 2>&1; do
  sleep 2
done

echo "Base de datos verificada."

# =========================
# WordPress Installation
# =========================

if ! $WP core is-installed; then

  echo "Instalando WordPress..."

  # Si es localhost
  if  [[ $WP_URL == *"localhost"* ]]; then
    PUBLIC_IP=$(curl -s --max-time 2 http://169.254.169.254/latest/meta-data/public-ipv4) || true

    if [[ -n "$PUBLIC_IP" ]]; then
      WP_URL="$WP_PROTOCOL://$PUBLIC_IP"
      echo "Usando IP pÃºblica: $WP_URL"
    else
      echo "No se pudo obtener IP pÃºblica, manteniendo $WP_URL"
    fi
  fi

  $WP core install \
    --url="$WP_URL" \
    --title="$WP_TITLE" \
    --admin_user="$WP_ADMIN_USER" \
    --admin_password="$WP_ADMIN_PASSWORD" \
    --admin_email="$WP_ADMIN_EMAIL" \
    --locale="$WP_LOCALE"

  CURRENT_LOCALE=$($WP option get WPLANG 2>/dev/null || true)
  if [ "$CURRENT_LOCALE" != "$WP_LOCALE" ]; then
    $WP language core install "$WP_LOCALE" --activate
  fi

  echo "Configurando permalink custom structure..."

  $WP option update permalink_structure '/%postname%/'

# =========================
# WooCommerce Installation
# =========================

  echo "Instalando WooCommerce..."

  $WP plugin install woocommerce --activate

  echo "Esperando a que WooCommerce termine su instalaciÃ³n..."

  until $WP option get woocommerce_db_version > /dev/null 2>&1; do
    sleep 2
  done

  echo "$WP_URL"

  echo "WooCommerce listo."

# =========================
# WooCommerce Store Settings
# =========================

  echo "Configurando WooCommerce..."

  $WP wc tool run install_pages --user="$WP_ADMIN_USER"

  $WP option update blogname "$WP_TITLE"

  $WP option update woocommerce_currency "$WC_CURRENCY"
  $WP option update woocommerce_default_country "$STORE_COUNTRY"
  $WP option update woocommerce_store_address "$STORE_ADDRESS"
  $WP option update woocommerce_store_city "$STORE_CITY"
  $WP option update woocommerce_store_postcode "$STORE_POSTCODE"

  echo "Desactivando onboarding de WooCommerce..."

  $WP option update woocommerce_onboarding_profile '{"completed": true, "skipped": true}' --format=json
  #$WP option update woocommerce_task_list_complete yes
  $WP option update woocommerce_setup_wizard_completed yes
  $WP option update woocommerce_onboarding_opt_in no
  $WP option update woocommerce_admin_install_timestamp $(date +%s)

# =========================
# Demo Product Setup
# =========================


  get_or_create_product_category() {
    local category_name="$1"
    local category_id

    category_id=$($WP term list product_cat \
      --name="$category_name" \
      --field=term_id | head -n 1 || true)

    if [[ -z "$category_id" ]]; then
      category_id=$($WP wc product_cat create \
        --name="$category_name" \
        --user="$WP_ADMIN_USER" \
        --porcelain)
    fi

    echo "$category_id"
  }

  create_initial_product() {
    local product_name="$1"
    local product_price="$2"
    local product_category="$3"
    local product_description="$4"
    local product_short_description="$5"
    local category_id

    if [[ -z "$product_name" || -z "$product_price" ]]; then
      echo "Saltando producto inicial sin nombre o precio."
      return
    fi

    if [[ -z "$product_category" ]]; then
      product_category="${DEMO_CATEGORY:-Demo}"
    fi

    category_id=$(get_or_create_product_category "$product_category")

    echo "Creando producto inicial: $product_name"

    $WP wc product create \
      --name="$product_name" \
      --type=simple \
      --regular_price="$product_price" \
      --description="$product_description" \
      --short_description="$product_short_description" \
      --categories='[{"id":'"$category_id"'}]' \
      --user="$WP_ADMIN_USER"
  }

  PRODUCTS_FILE="${DEMO_PRODUCTS_FILE:-}"

  if [[ -n "$DEMO_PRODUCTS_B64" ]]; then
    PRODUCTS_FILE="/tmp/demo-products.json"
    echo "$DEMO_PRODUCTS_B64" | base64 -d > "$PRODUCTS_FILE"
  elif [[ -n "$DEMO_PRODUCTS_JSON" ]]; then
    PRODUCTS_FILE="/tmp/demo-products.json"
    printf '%s' "$DEMO_PRODUCTS_JSON" > "$PRODUCTS_FILE"
  fi

  if [[ -n "$PRODUCTS_FILE" && -f "$PRODUCTS_FILE" ]]; then
    echo "Creando productos iniciales desde $PRODUCTS_FILE..."

    while IFS=$'\t' read -r NAME_B64 PRICE_B64 CATEGORY_B64 DESCRIPTION_B64 SHORT_DESCRIPTION_B64; do
      PRODUCT_NAME=$(printf '%s' "$NAME_B64" | base64 -d)
      PRODUCT_PRICE=$(printf '%s' "$PRICE_B64" | base64 -d)
      PRODUCT_CATEGORY=$(printf '%s' "$CATEGORY_B64" | base64 -d)
      PRODUCT_DESCRIPTION=$(printf '%s' "$DESCRIPTION_B64" | base64 -d)
      PRODUCT_SHORT_DESCRIPTION=$(printf '%s' "$SHORT_DESCRIPTION_B64" | base64 -d)

      create_initial_product \
        "$PRODUCT_NAME" \
        "$PRODUCT_PRICE" \
        "$PRODUCT_CATEGORY" \
        "$PRODUCT_DESCRIPTION" \
        "$PRODUCT_SHORT_DESCRIPTION"
    done < <(php -r '
      $file = $argv[1];
      $data = json_decode(file_get_contents($file), true);

      if (!is_array($data)) {
        fwrite(STDERR, "Invalid products JSON: {$file}\n");
        exit(1);
      }

      $products = $data["products"] ?? $data;

      if (!is_array($products)) {
        fwrite(STDERR, "Products JSON must be an array or contain a products array: {$file}\n");
        exit(1);
      }

      foreach ($products as $product) {
        if (!is_array($product)) {
          continue;
        }

        $fields = [
          $product["name"] ?? "",
          $product["price"] ?? "",
          $product["category"] ?? "",
          $product["description"] ?? "Producto demo generado automaticamente.",
          $product["short_description"] ?? "Producto demo."
        ];

        echo implode("\t", array_map("base64_encode", $fields)) . "\n";
      }
    ' "$PRODUCTS_FILE")
  else
    echo "Creando producto demo desde variables de entorno..."

    create_initial_product \
      "$DEMO_PRODUCT_NAME" \
      "$DEMO_PRODUCT_PRICE" \
      "$DEMO_CATEGORY" \
      "Producto demo generado automaticamente." \
      "Producto demo."
  fi


# =========================
# Kadence Theme Setup
# =========================

  echo "Instalando Kadence..."

  if ! $WP theme is-installed kadence; then
    $WP theme install kadence
  fi

  echo "Corrigiendo permisos..."

  chown -R www-data:www-data /var/www/html/wp-content

  echo "Activando Kadence..."

  $WP theme activate kadence

# =========================
# Kadence Blocks Plugin Setup
# =========================

  echo "Instalando Kadence Blocks..."

  if ! $WP plugin is-installed kadence-blocks; then
    $WP plugin install kadence-blocks
  fi

  if ! $WP plugin is-active kadence-blocks; then
    $WP plugin activate kadence-blocks
  fi

# =========================
# Kadence Starter Templates Plugin Setup
# =========================

  echo "Instalando Kadence Starter Templates..."

  if ! $WP plugin is-installed kadence-starter-templates; then
    $WP plugin install kadence-starter-templates
  fi

  if ! $WP plugin is-active kadence-starter-templates; then
    $WP plugin activate kadence-starter-templates
  fi

  SHOP_PAGE_ID=$($WP option get woocommerce_shop_page_id)

  if [[ -n "$SHOP_PAGE_ID" && "$SHOP_PAGE_ID" != "0" ]]; then
    $WP option update show_on_front 'page'
    $WP option update page_on_front "$SHOP_PAGE_ID"
  else
    echo "No se encontro la pagina Shop."
  fi

# =========================
# Theme Configuration
# =========================

  echo "Configurando tema..."

  if ! $WP menu list --fields=slug --format=csv | grep -qx primary-menu; then
    echo "Creando menu principal..."
    $WP menu create "Primary Menu"
  fi

  echo "Obteniendo paginas WooCommerce..."

  CART_PAGE_ID=$($WP option get woocommerce_cart_page_id)
  CHECKOUT_PAGE_ID=$($WP option get woocommerce_checkout_page_id)
  ACCOUNT_PAGE_ID=$($WP option get woocommerce_myaccount_page_id)

  echo "Configurando navegacion..."

  for PAGE_ID in "$SHOP_PAGE_ID" "$CART_PAGE_ID" "$CHECKOUT_PAGE_ID" "$ACCOUNT_PAGE_ID"; do
    if [[ -n "$PAGE_ID" && "$PAGE_ID" != "0" ]]; then
      $WP menu item add-post primary-menu "$PAGE_ID"
    fi
  done

  $WP menu location assign primary-menu primary

# =========================
# Branding
# =========================

  echo "Configurando branding..."

  PRIMARY_COLOR="${PRIMARY_COLOR:-#2f6f4e}"
  SECONDARY_COLOR="${SECONDARY_COLOR:-#f2c14e}"
  ACCENT_COLOR="${ACCENT_COLOR:-#c44536}"

  $WP eval '
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

    if (defined("WP_CLI") && WP_CLI) {
      WP_CLI::success("Kadence branding configured.");
    }
  '

# =========================
# WooCommerce Page Setup
# =========================
  echo "Configurando permalinks..."
  $WP rewrite structure '/%postname%/' --hard
  $WP rewrite flush --hard
  echo "Configurando Shop como homepage..."

# =========================
# WPTravelly Plugin Setup
# =========================

  case "${BOOKING_ENABLED:-false}" in
    true|TRUE|1|yes|YES|on|ON)
      echo "Instalando WPTravelly..."

      if ! $WP plugin is-installed tour-booking-manager; then
        $WP plugin install tour-booking-manager
      fi

      if ! $WP plugin is-active tour-booking-manager; then
        $WP plugin activate tour-booking-manager
      fi
      ;;
    *)
      echo "WPTravelly deshabilitado."
      ;;
  esac

# =========================
# Shopia Chatbot Assistant Plugin Setup
# =========================

  echo "Shopia Chatbot Assistant omitido temporalmente."

  if false; then
    echo "Instalando Shopia Chatbot Assistant..."

    if [ ! -d /local-plugins/shopia-chatbot-assistant ]; then
      echo "Descargando Shopia Chatbot Assistant..."
      mkdir -p /local-plugins
      git clone --depth 1 --branch "${SHOPIA_PLUGIN_REF:-main}" \
        "${SHOPIA_PLUGIN_REPO:-https://github.com/QuintanillaAdrian/shopia-chatbot-assistant.git}" \
        /local-plugins/shopia-chatbot-assistant
      rm -rf /local-plugins/shopia-chatbot-assistant/.git
    fi

    mkdir -p /var/www/html/wp-content/plugins
    rm -rf /var/www/html/wp-content/plugins/shopia-chatbot-assistant
    cp -r /local-plugins/shopia-chatbot-assistant \
      /var/www/html/wp-content/plugins/shopia-chatbot-assistant

    chown -R www-data:www-data /var/www/html/wp-content/plugins/shopia-chatbot-assistant

    if ! $WP plugin is-active shopia-chatbot-assistant; then
      echo "Ejecutando provisioning de Shopia..."
      $WP plugin activate shopia-chatbot-assistant
      $WP mcp request provision --generate_keys=1 --persist_secret=1
    fi
    echo "Finalizo la ejecucion de Shopia"
  fi

# =========================
# Complete Theme Import
# =========================

  /usr/local/bin/import-complete-theme.sh


else
  echo "WordPress ya estÃ¡ instalado."
fi

# =========================
# Apache Startup
# =========================

echo "Iniciando Apache..."

exec apache2-foreground
