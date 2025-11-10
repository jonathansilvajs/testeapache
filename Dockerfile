FROM php:8.2-apache

ENV DEBIAN_FRONTEND=noninteractive

# 1) Sistema mínimo e libs necessárias (sem GD)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git unzip curl wget nano vim gosu expect \
    libzip-dev libxml2-dev \
 && rm -rf /var/lib/apt/lists/*

# 2) Extensões PHP estáveis no Bookworm (sem gd/imagem)
#    -j1 reduz memória no build (Portainer/BuildKit)
RUN set -eux; \
    docker-php-ext-install -j1 pdo pdo_mysql mysqli mbstring xml zip; \
    a2enmod rewrite headers

# 3) Composer (oficial)
RUN php -r "copy('https://getcomposer.org/installer','/tmp/composer-setup.php');" \
 && php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer \
 && rm -f /tmp/composer-setup.php

# 4) Apache + php.ini
RUN printf "ServerName localhost\n" > /etc/apache2/conf-available/servername.conf \
 && a2enconf servername \
 && printf "DirectoryIndex index.php index.html\n" > /etc/apache2/conf-available/dirindex.conf \
 && a2enconf dirindex

ENV TZ=Europe/Lisbon \
    PHP_MEMORY_LIMIT=512M \
    PHP_POST_MAX_SIZE=64M \
    PHP_UPLOAD_MAX_FILESIZE=64M \
    TIMEZONE=Europe/Lisbon

RUN set -eux; \
    cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"; \
    sed -i "s~^memory_limit = .*~memory_limit = ${PHP_MEMORY_LIMIT}~" "$PHP_INI_DIR/php.ini"; \
    sed -i "s~^post_max_size = .*~post_max_size = ${PHP_POST_MAX_SIZE}~" "$PHP_INI_DIR/php.ini"; \
    sed -i "s~^upload_max_filesize = .*~upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE}~" "$PHP_INI_DIR/php.ini"; \
    sed -i "s~;date.timezone =.*~date.timezone = ${TIMEZONE}~" "$PHP_INI_DIR/php.ini"

# 5) Scripts internos (DB antes do clone, clone 1x, composer)
COPY ./bootstrap.sh /usr/local/bin/bootstrap.sh
COPY ./src/init-db.php /usr/local/bin/init-db.php
RUN chmod +x /usr/local/bin/bootstrap.sh /usr/local/bin/init-db.php

WORKDIR /var/www/html
CMD ["/usr/local/bin/bootstrap.sh"]
