#!/usr/bin/env bash
set -Eeuo pipefail

WP_PATH="${WP_PATH:-/var/www/html}"
WP=(php -d memory_limit=512M /usr/local/bin/wp --allow-root --path="${WP_PATH}")

if ! "${WP[@]}" theme is-active kadence >/dev/null 2>&1; then
  echo "Kadence is not active; skipping WP Image branding."
  exit 0
fi

if [ "${1:-}" = "--force" ]; then
  export WP_IMAGE_BRANDING_FORCE=1
  shift
fi
"${WP[@]}" eval-file /usr/local/lib/wp-image/apply-branding.php "$@"
