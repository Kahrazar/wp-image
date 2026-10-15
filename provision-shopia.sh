#!/usr/bin/env bash
set -Eeuo pipefail
source /usr/local/lib/wp-image/shopia-common.sh

if [ "${SHOPIA_IS_ENABLED}" = false ]; then
  echo "ShopIA disabled; skipping onboarding."
  exit 0
fi
if [ -z "${CHATBOT_BACKEND_URL:-}" ]; then
  echo "ShopIA onboarding deferred: set CHATBOT_BACKEND_URL, then run provision-shopia.sh."
  exit 0
fi
if ! "${WP[@]}" plugin is-active shopia-chatbot-assistant; then
  echo "ShopIA onboarding deferred: the plugin is not active." >&2
  exit 0
fi
if ! "${WP[@]}" plugin is-active woocommerce; then
  echo "ShopIA onboarding deferred: WooCommerce is not active." >&2
  exit 0
fi
# The backend calls back into WooCommerce to verify credentials. This command
# must run after Apache, DNS, Nginx and HTTPS are ready, never before Apache starts.
# The current plugin reports incomplete onboarding as a warning (exit status 0)
# and retries it on later admin visits. An unavailable backend must not stop WP.
if ! "${WP[@]}" chatbot provision-auto; then
  echo "ShopIA onboarding failed; WordPress remains available. Retry provision-shopia.sh or open wp-admin." >&2
  exit 0
fi
# Upstream's CLI also exits 0 for incomplete onboarding; verify stored state.
if ! "${WP[@]}" eval '$state = get_option("chatbot_provision", array()); if (empty($state["tenant_id"]) || empty($state["wc_verified"])) { exit(1); }'; then
  echo "ShopIA onboarding is incomplete; check wp chatbot audit and retry after HTTPS/backend readiness." >&2
fi
