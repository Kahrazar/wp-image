FROM wordpress:latest


RUN apt-get update \
    && apt-get install -y mariadb-server mariadb-client curl git \
    && rm -rf /var/lib/apt/lists/*


RUN curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    -o /usr/local/bin/wp \
    && chmod +x /usr/local/bin/wp

RUN mkdir -p /root/.wp-cli \
    && printf "apache_modules:\n  - mod_rewrite\n" > /root/.wp-cli/config.yml

RUN mkdir -p /local-theme \
    && git clone --depth 1 https://github.com/Kahrazar/storefront-eiemprende.git \
    /local-theme/storefront-eiemprende

ARG SHOPIA_PLUGIN_REPO=https://github.com/QuintanillaAdrian/shopia-chatbot-assistant.git
ARG SHOPIA_PLUGIN_REF=main

RUN mkdir -p /local-plugins \
    && git clone --depth 1 --branch "$SHOPIA_PLUGIN_REF" "$SHOPIA_PLUGIN_REPO" \
    /local-plugins/shopia-chatbot-assistant \
    && rm -rf /local-plugins/shopia-chatbot-assistant/.git

ENV WP_TITLE="Tienda Test" \
    WP_ADMIN_USER=admin \
    WP_ADMIN_PASSWORD=admin123 \
    WP_ADMIN_EMAIL=admin@test.com \
    WC_CURRENCY=CRC \
    STORE_COUNTRY="CR:SJ" \
    STORE_CITY="Heredia" \
    STORE_ADDRESS="Heredia" \
    STORE_POSTCODE="40101" \
    DEMO_CATEGORY="Artesanías" \
    WP_URL="http://localhost:8080" \
    DEMO_PRODUCT_NAME="Máscara artesanal costarricense" \
    DEMO_PRODUCT_PRICE=15000 \
    DEMO_PRODUCTS_FILE="" \
    DEMO_PRODUCTS_JSON="" \
    DEMO_PRODUCTS_B64="" \
    SHOPIA_PLUGIN_REPO="https://github.com/QuintanillaAdrian/shopia-chatbot-assistant.git" \
    SHOPIA_PLUGIN_REF="main" \
    MCP_BEARER_TOKEN="CHANGE_ME" \
    PRIMARY_COLOR="#2f6f4e" \
    SECONDARY_COLOR="#f2c14e" \
    ACCENT_COLOR="#c44536"

COPY start.sh /start.sh

RUN sed -i 's/\r$//' /start.sh \
    && chmod +x /start.sh

EXPOSE 80

ENTRYPOINT ["bash", "/start.sh"]
