FROM wordpress:latest


RUN apt-get update \
    && apt-get install -y mariadb-server mariadb-client curl git \
    && rm -rf /var/lib/apt/lists/*


RUN curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    -o /usr/local/bin/wp \
    && chmod +x /usr/local/bin/wp

RUN mkdir -p /local-theme \
    && git clone --depth 1 https://github.com/Kahrazar/storefront-eiemprende.git \
    /local-theme/storefront-eiemprende

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
    PRIMARY_COLOR="#2f6f4e" \
    SECONDARY_COLOR="#f2c14e" \
    ACCENT_COLOR="#c44536"

COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 80

ENTRYPOINT ["/start.sh"]
