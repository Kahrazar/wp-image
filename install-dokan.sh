#!/usr/bin/env bash
set -Eeuo pipefail

WP_PATH="${WP_PATH:-/var/www/html}"
WP=(php -d memory_limit=512M /usr/local/bin/wp --allow-root --path="${WP_PATH}")
if [ -n "${WP_HOME:-${WP_URL:-}}" ]; then
  WP+=(--url="${WP_HOME:-${WP_URL}}")
fi

case "${MARKETPLACE:-false}" in
  true|TRUE|1|yes|YES|on|ON)
    if ! "${WP[@]}" --skip-plugins=dokan-lite plugin is-active woocommerce; then
      echo "Dokan requires active WooCommerce." >&2
      exit 1
    fi
    echo "Instalando Dokan Lite..."
    if ! "${WP[@]}" --skip-plugins=dokan-lite plugin is-installed dokan-lite; then
      "${WP[@]}" --skip-plugins=dokan-lite plugin install dokan-lite
    fi
    if ! "${WP[@]}" plugin is-active dokan-lite; then
      "${WP[@]}" plugin activate dokan-lite
    fi
    ;;
  false|FALSE|0|no|NO|off|OFF)
    if "${WP[@]}" --skip-plugins=dokan-lite plugin is-active dokan-lite >/dev/null 2>&1; then
      "${WP[@]}" --skip-plugins=dokan-lite plugin deactivate dokan-lite
    fi
    echo "Dokan deshabilitado; los datos existentes se conservan."
    ;;
  *)
    echo "MARKETPLACE must be true or false." >&2
    exit 1
    ;;
esac
