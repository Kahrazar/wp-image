#!/bin/bash
set -e

echo "Iniciando MySQL..."

mariadbd-safe --datadir=/var/lib/mysql &

until mysqladmin ping -h127.0.0.1 --silent; do
  sleep 2
done

echo "MySQL listo."

mysql -uroot <<EOF
CREATE DATABASE IF NOT EXISTS wp;
CREATE USER IF NOT EXISTS 'wpuser'@'localhost' IDENTIFIED BY 'wppass';
GRANT ALL PRIVILEGES ON wp.* TO 'wpuser'@'localhost';
FLUSH PRIVILEGES;
EOF

cd /var/www/html

WP="php -d memory_limit=512M /usr/local/bin/wp --allow-root"

if [ ! -f wp-load.php ]; then
  echo "Descargando WordPress..."
  $WP core download
fi

if [ ! -f wp-config.php ]; then
  echo "Creando wp-config.php..."
  $WP config create \
    --dbname=wp \
    --dbuser=wpuser \
    --dbpass=wppass \
    --dbhost=127.0.0.1
fi

until $WP db check > /dev/null 2>&1; do
  sleep 2
done

echo "Base de datos verificada."

if ! $WP core is-installed; then

  echo "Instalando WordPress..."

  $WP core install \
    --url="$WP_URL" \
    --title="$WP_TITLE" \
    --admin_user="$WP_ADMIN_USER" \
    --admin_password="$WP_ADMIN_PASSWORD" \
    --admin_email="$WP_ADMIN_EMAIL"

  echo "Instalando WooCommerce..."

  $WP plugin install woocommerce --activate

  echo "Esperando a que WooCommerce termine su instalación..."

  until $WP option get woocommerce_db_version > /dev/null 2>&1; do
    sleep 2
  done

  echo "WooCommerce listo."

  echo "Configurando WooCommerce..."

  $WP wc tool run install_pages --user="$WP_ADMIN_USER"

  $WP option update blogname "$WP_TITLE"

  $WP option update woocommerce_currency "$WC_CURRENCY"
  $WP option update woocommerce_default_country "$STORE_COUNTRY"

  #$WP option update woocommerce_store_country "$STORE_COUNTRY"
  $WP option update woocommerce_store_address "$STORE_ADDRESS"
  $WP option update woocommerce_store_city "$STORE_CITY"
  $WP option update woocommerce_store_postcode "$STORE_POSTCODE"

  echo "Desactivando onboarding de WooCommerce..."

  $WP option update woocommerce_onboarding_profile '{"completed": true, "skipped": true}' --format=json
  $WP option update woocommerce_task_list_complete yes
  $WP option update woocommerce_setup_wizard_completed yes
  $WP option update woocommerce_onboarding_opt_in no
  $WP option update woocommerce_admin_install_timestamp $(date +%s)

  echo "Creando categoría..."

  CATEGORY_ID=$($WP wc product_cat create \
    --name="$DEMO_CATEGORY" \
    --user="$WP_ADMIN_USER" \
    --porcelain)

  echo "Creando producto demo..."

  $WP wc product create \
    --name="$DEMO_PRODUCT_NAME" \
    --type=simple \
    --regular_price="$DEMO_PRODUCT_PRICE" \
    --description="Producto demo generado automáticamente." \
    --short_description="Producto demo." \
    --categories='[{"id":'"$CATEGORY_ID"'}]' \
    --user="$WP_ADMIN_USER"

  echo "Instalando tema Kadence..."

  $WP theme install kadence --activate
  $WP plugin install kadence-blocks --activate

else
  echo "WordPress ya está instalado."
fi

echo "Iniciando Apache..."

exec apache2-foreground