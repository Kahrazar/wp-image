FROM wordpress:latest


RUN apt-get update \
    && apt-get install -y mariadb-server mariadb-client curl git \
    && rm -rf /var/lib/apt/lists/*


RUN curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    -o /usr/local/bin/wp \
    && chmod +x /usr/local/bin/wp

RUN mkdir -p /root/.wp-cli \
    && printf "apache_modules:\n  - mod_rewrite\n" > /root/.wp-cli/config.yml

ARG SHOPIA_PLUGIN_REPO=https://github.com/QuintanillaAdrian/shopia-chatbot-assistant.git
ARG SHOPIA_PLUGIN_REF=main

# Shopia is temporarily omitted until the upstream repo restores a valid
# WordPress plugin bootstrap file.
# RUN mkdir -p /local-plugins \
#     && git clone --depth 1 --branch "$SHOPIA_PLUGIN_REF" "$SHOPIA_PLUGIN_REPO" \
#     /local-plugins/shopia-chatbot-assistant \
#     && rm -rf /local-plugins/shopia-chatbot-assistant/.git

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
    SITE_DOMAIN=https://domain.com \
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
    SHOPIA_PLUGIN_REPO="https://github.com/QuintanillaAdrian/shopia-chatbot-assistant.git" \
    SHOPIA_PLUGIN_REF="main" \
    COMPLETE_THEME_REPO="https://github.com/Kahrazar/wp-complete-theme.git" \
    COMPLETE_THEME_REF="main" \
    COMPLETE_THEME_DIR="/local-templates/wp-complete-theme" \
    COMPLETE_THEME_IMPORT_ENABLED=true \
    MCP_BEARER_TOKEN="CHANGE_ME" \
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
COPY branding.php apply-branding.php branding-styles.php /usr/local/lib/wp-image/
COPY template-content.php prepare-complete-theme.php /usr/local/lib/wp-image/

RUN sed -i 's/\r$//' /start.sh /usr/local/bin/import-complete-theme.sh /usr/local/bin/apply-branding.sh \
    && chmod +x /start.sh /usr/local/bin/import-complete-theme.sh /usr/local/bin/apply-branding.sh

EXPOSE 80

ENTRYPOINT ["bash", "/start.sh"]
