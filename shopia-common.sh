#!/usr/bin/env bash
# Shared by the local installer and the explicit post-HTTPS onboarding command.
case "${SHOPIA_ENABLED:-true}" in
  true|TRUE|1|yes|YES|on|ON) SHOPIA_IS_ENABLED=true ;;
  false|FALSE|0|no|NO|off|OFF)
    SHOPIA_IS_ENABLED=false
    ;;
  *)
    echo "SHOPIA_ENABLED must be true or false." >&2
    exit 1
    ;;
esac

WP_PATH="${WP_PATH:-/var/www/html}"
WP=(php -d memory_limit=512M /usr/local/bin/wp --allow-root --path="${WP_PATH}")
# --url also supplies HTTP_HOST for older, request-derived wp-config.php files.
SHOPIA_SITE_URL="${WP_HOME:-}"
if [ -z "${SHOPIA_SITE_URL}" ]; then
  case "${SITE_DOMAIN:-}" in
    ""|domain.com|http://domain.com|https://domain.com|http://domain.com/|https://domain.com/) ;;
    *) SHOPIA_SITE_URL="${SITE_DOMAIN}" ;;
  esac
fi
SHOPIA_SITE_URL="${SHOPIA_SITE_URL:-${WP_URL:-}}"
if [ -n "${SHOPIA_SITE_URL}" ]; then
  WP+=(--url="${SHOPIA_SITE_URL}")
fi
