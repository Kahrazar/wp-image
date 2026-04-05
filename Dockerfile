FROM wordpress:latest


RUN apt-get update \
    && apt-get install -y mariadb-server mariadb-client curl \
    && rm -rf /var/lib/apt/lists/*


RUN curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    -o /usr/local/bin/wp \
    && chmod +x /usr/local/bin/wp

ENV WP_URL=http://localhost:8080 \
    WP_TITLE="Tienda Test" \
    WP_ADMIN_USER=admin \
    WP_ADMIN_PASSWORD=admin123 \
    WP_ADMIN_EMAIL=admin@test.com \
    WC_CURRENCY=CRC \
    STORE_COUNTRY="CR:SJ" \
    STORE_CITY="Heredia" \
    STORE_ADDRESS="Heredia" \
    STORE_POSTCODE="40101" \
    DEMO_CATEGORY="Artesanías" \
    DEMO_PRODUCT_NAME="Máscara artesanal costarricense" \
    DEMO_PRODUCT_PRICE=15000

COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 80

ENTRYPOINT ["/start.sh"]