#!/usr/bin/env bash
set -Eeuo pipefail
source /usr/local/lib/wp-image/shopia-common.sh

PLUGIN_SOURCE=/local-plugins/shopia-chatbot-assistant
PLUGIN_TARGET="${WP_PATH}/wp-content/plugins/shopia-chatbot-assistant"
if [ "${SHOPIA_IS_ENABLED}" = false ]; then
  if "${WP[@]}" --skip-plugins=shopia-chatbot-assistant plugin is-active shopia-chatbot-assistant; then
    "${WP[@]}" --skip-plugins=shopia-chatbot-assistant plugin deactivate shopia-chatbot-assistant
  fi
  echo "ShopIA disabled; stored onboarding credentials are preserved."
  exit 0
fi
if [ ! -f "${PLUGIN_SOURCE}/chatbot-assistant.php" ] || [ ! -f "${PLUGIN_SOURCE}/vendor/autoload.php" ] || [ ! -f "${PLUGIN_SOURCE}/.wp-image-bundle.sha256" ]; then
  echo "ShopIA bundle is incomplete; rebuild WP Image with Composer dependencies." >&2
  exit 1
fi
if ! "${WP[@]}" --skip-plugins=shopia-chatbot-assistant plugin is-active woocommerce; then
  echo "ShopIA requires active WooCommerce." >&2
  exit 1
fi

# Replace managed source only when the bundled package changes. Never uninstall:
# the plugin's uninstall hook would delete onboarding options and WooCommerce keys.
if [ ! -f "${PLUGIN_TARGET}/chatbot-assistant.php" ] || [ ! -f "${PLUGIN_TARGET}/vendor/autoload.php" ] || ! cmp -s "${PLUGIN_SOURCE}/.wp-image-bundle.sha256" "${PLUGIN_TARGET}/.wp-image-bundle.sha256"; then
  echo "Installing bundled ShopIA source..."
  mkdir -p "${WP_PATH}/wp-content/plugins"
  PLUGIN_STAGE=$(mktemp -d "${WP_PATH}/wp-content/plugins/.shopia-stage.XXXXXX")
  trap 'rm -rf "${PLUGIN_STAGE}"' EXIT
  cp -a "${PLUGIN_SOURCE}/." "${PLUGIN_STAGE}/"
  chown -R www-data:www-data "${PLUGIN_STAGE}"
  rm -rf "${PLUGIN_TARGET}"
  mv "${PLUGIN_STAGE}" "${PLUGIN_TARGET}"
  trap - EXIT
fi
if ! "${WP[@]}" plugin is-active shopia-chatbot-assistant; then
  "${WP[@]}" plugin activate shopia-chatbot-assistant
fi
echo "ShopIA installed. Onboarding runs after public HTTPS is ready, or from wp-admin."
