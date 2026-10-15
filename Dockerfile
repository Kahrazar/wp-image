FROM wordpress:latest
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Use Composer with the image's PHP so dependency platform checks match runtime.
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

RUN apt-get update \
    && apt-get install -y mariadb-server mariadb-client curl git \
    && rm -rf /var/lib/apt/lists/*


RUN curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    -o /usr/local/bin/wp \
    && chmod +x /usr/local/bin/wp

RUN mkdir -p /root/.wp-cli \
    && printf "apache_modules:\n  - mod_rewrite\n" > /root/.wp-cli/config.yml

ARG SHOPIA_PLUGIN_REPO=https://github.com/QuintanillaAdrian/chatbot-assistant.git
ARG SHOPIA_PLUGIN_REF=a9fc47bd3b3648f44cfaf1b1b8939011d7e288bc

RUN php -r 'if (version_compare(PHP_VERSION, "8.2", "<") || !extension_loaded("mbstring") || (!extension_loaded("bcmath") && !extension_loaded("gmp"))) { fwrite(STDERR, "ShopIA requires PHP 8.2+, mbstring and bcmath or gmp.\n"); exit(1); }' \
    && mkdir -p /local-plugins/shopia-chatbot-assistant \
    && cd /local-plugins/shopia-chatbot-assistant \
    && git init \
    && git remote add origin "$SHOPIA_PLUGIN_REPO" \
    && git fetch --depth 1 origin "$SHOPIA_PLUGIN_REF" \
    && git checkout --detach FETCH_HEAD \
    && git rev-parse HEAD > .wp-image-source-revision \
    && rm -rf .git \
    && COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader \
    && composer check-platform-reqs --no-dev \
    && test -f chatbot-assistant.php \
    && php -r 'require "vendor/autoload.php"; $h = new Hashids\Hashids("build-check"); if ($h->decode($h->encode(123)) !== [123]) { exit(1); }' \
    && find . -type f ! -name '.wp-image-bundle.sha256' -print0 \
       | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d ' ' -f 1 > .wp-image-bundle.sha256

ARG COMPLETE_THEME_REPO=https://github.com/Kahrazar/wp-complete-theme.git
ARG COMPLETE_THEME_REF=main

RUN mkdir -p /local-templates \
    && git clone --depth 1 --branch "$COMPLETE_THEME_REF" "$COMPLETE_THEME_REPO" \
    /local-templates/wp-complete-theme \
    && rm -rf /local-templates/wp-complete-theme/.git

ENV WP_TITLE="Tienda Test" \
    WP_ADMIN_USER=admin \
    WP_ADMIN_PASSWORD=admin123 \
    WP_ADMIN_EMAIL=admin@test.com \
    WC_CURRENCY=CRC \
    BOOKING_ENABLED=false \
    MARKETPLACE=false \
    SITE_DOMAIN="" \
    STORE_COUNTRY="CR:SJ" \
    STORE_CITY="Heredia" \
    STORE_ADDRESS="Heredia" \
    STORE_POSTCODE="40101" \
    DEMO_CATEGORY="Artesanías" \
    WP_PROTOCOL=https \
    WP_LOCALE=es_ES \
    WP_URL="http://localhost:8080" \
    DEMO_PRODUCT_NAME="Máscara artesanal costarricense" \
    DEMO_PRODUCT_PRICE=15000 \
    DEMO_PRODUCTS_FILE="" \
    DEMO_PRODUCTS_JSON="" \
    DEMO_PRODUCTS_B64="" \
    SHOPIA_ENABLED=true \
    CHATBOT_BACKEND_URL="" \
    COMPLETE_THEME_REPO="https://github.com/Kahrazar/wp-complete-theme.git" \
    COMPLETE_THEME_REF="main" \
    COMPLETE_THEME_DIR="/local-templates/wp-complete-theme" \
    COMPLETE_THEME_IMPORT_ENABLED=true \
    PRIMARY_COLOR="#2f6f4e" \
    SECONDARY_COLOR="#f2c14e" \
    ACCENT_COLOR="#c44536" \
    TEXT_STRONG_COLOR="#1a202c" \
    TEXT_COLOR="#2d3748" \
    TEXT_MUTED_COLOR="#4a5568" \
    BORDER_COLOR="#718096" \
    BACKGROUND_SUBTLE_COLOR="#edf2f7" \
    BACKGROUND_COLOR="#f7fafc" \
    SURFACE_COLOR="#ffffff" \
    SUCCESS_COLOR="#13612e" \
    INFO_COLOR="#1159af" \
    ALERT_COLOR="#b82105" \
    WARNING_COLOR="#f7630c" \
    RATING_COLOR="#f5a524" \
    ON_PRIMARY_COLOR=auto \
    ON_ACCENT_COLOR=auto \
    ON_SECONDARY_COLOR=auto \
    HEADER_BACKGROUND_COLOR="" \
    HEADER_TEXT_COLOR=auto \
    HEADER_HOVER_COLOR=auto \
    FOOTER_BACKGROUND_COLOR="" \
    FOOTER_TEXT_COLOR=auto \
    FOOTER_HOVER_COLOR=auto

COPY start.sh /start.sh
COPY import-complete-theme.sh /usr/local/bin/import-complete-theme.sh
COPY apply-branding.sh /usr/local/bin/apply-branding.sh
COPY install-shopia.sh provision-shopia.sh install-dokan.sh /usr/local/bin/
COPY shopia-common.sh /usr/local/lib/wp-image/shopia-common.sh
COPY branding.php apply-branding.php branding-styles.php /usr/local/lib/wp-image/
COPY template-content.php prepare-complete-theme.php /usr/local/lib/wp-image/
COPY php-memory.ini /usr/local/etc/php/conf.d/zz-wp-image-memory.ini

RUN sed -i 's/\r$//' /start.sh /usr/local/bin/import-complete-theme.sh /usr/local/bin/apply-branding.sh \
       /usr/local/bin/install-shopia.sh /usr/local/bin/provision-shopia.sh /usr/local/bin/install-dokan.sh /usr/local/lib/wp-image/shopia-common.sh \
    && chmod +x /start.sh /usr/local/bin/import-complete-theme.sh /usr/local/bin/apply-branding.sh \
       /usr/local/bin/install-shopia.sh /usr/local/bin/provision-shopia.sh /usr/local/bin/install-dokan.sh

EXPOSE 80

ENTRYPOINT ["bash", "/start.sh"]
