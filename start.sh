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

# =========================
# WordPress Core Download
# =========================

if [ ! -f wp-load.php ]; then
  echo "Descargando WordPress..."
  $WP core download
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
    print "if (isset($_SERVER[\"HTTP_HOST\"])) {"
    print "    $_SERVER[\"HTTPS\"] = \"on\";"
    print "    define(\"WP_HOME\", \"https://\" . $_SERVER[\"HTTP_HOST\"]);"
    print "    define(\"WP_SITEURL\", \"https://\" . $_SERVER[\"HTTP_HOST\"]);"
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
      WP_URL="https://$PUBLIC_IP"
      echo "Usando IP pÃºblica: $WP_URL"
    else
      WP_URL="https://localhost:8080"
      echo "No se pudo obtener IP pÃºblica, manteniendo localhost"
    fi
  fi

  $WP core install \
    --url="$WP_URL" \
    --title="$WP_TITLE" \
    --admin_user="$WP_ADMIN_USER" \
    --admin_password="$WP_ADMIN_PASSWORD" \
    --admin_email="$WP_ADMIN_EMAIL"

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
# Storefront Child Theme Setup
# =========================

  echo "Instalando Storefront..."

  $WP theme install storefront --activate

  echo "Copiando Child Theme..."

  if [ ! -d /local-theme/storefront-eiemprende ]; then
    echo "Descargando Child Theme..."
    mkdir -p /local-theme
    git clone --depth 1 https://github.com/Kahrazar/storefront-eiemprende.git \
      /local-theme/storefront-eiemprende
  fi

  mkdir -p /var/www/html/wp-content/themes
  rm -rf /var/www/html/wp-content/themes/storefront-eiemprende
  cp -r /local-theme/storefront-eiemprende \
    /var/www/html/wp-content/themes/storefront-eiemprende

  echo "Corrigiendo permisos..."

  chown -R www-data:www-data /var/www/html/wp-content

  echo "Activando Child Theme..."

  $WP theme activate storefront-eiemprende


  SHOP_PAGE_ID=$($WP option get woocommerce_shop_page_id)

  if [[ -n "$SHOP_PAGE_ID" && "$SHOP_PAGE_ID" != "0" ]]; then
    $WP option update show_on_front 'page'
    $WP option update page_on_front "$SHOP_PAGE_ID"
  else
    echo "No se encontro la pagina Shop."
  fi

# =========================
# Child Theme Configuration
# =========================

  echo "Configurando Child Theme..."

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

  $WP option update my_primary_color "${PRIMARY_COLOR}"
  $WP option update my_secondary_color "${SECONDARY_COLOR}"
  $WP option update my_accent_color "${ACCENT_COLOR}"

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

  echo "Instalando Shopia Chatbot Assistant..."

  if [ ! -d /local-plugins/shopia-chatbot-assistant ]; then
    echo "Descargando Shopia Chatbot Assistant..."
    mkdir -p /local-plugins
    git clone --depth 1 --branch "${SHOPIA_PLUGIN_REF:-main}" \
      "${SHOPIA_PLUGIN_REPO:-https://github.com/QuintanillaAdrian/shopia-chatbot-assistant.git}" \
      /local-plugins/shopia-chatbot-assistant
    php /usr/local/bin/patch-shopia-plugin.php /local-plugins/shopia-chatbot-assistant
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


else
  echo "WordPress ya estÃ¡ instalado."
fi

# =========================
# Apache Startup
# =========================

echo "Iniciando Apache..."

exec apache2-foreground
