FROM php:8.2-apache

ENV DEBIAN_FRONTEND=noninteractive

# Dependências de sistema
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git unzip curl wget vim nano gosu expect \
    libzip-dev libpng-dev libjpeg62-turbo-dev libfreetype6-dev libwebp-dev libxml2-dev libkrb5-dev \
 && docker-php-ext-configure gd --with-jpeg --with-freetype --with-webp \
 && docker-php-ext-install pdo pdo_mysql mysqli mbstring curl gd xml zip \
 && a2enmod rewrite headers \
 && rm -rf /var/lib/apt/lists/*

# Composer
RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" \
 && php composer-setup.php --install-dir=/usr/local/bin --filename=composer \
 && rm composer-setup.php

# Apache e PHP.ini
RUN printf "ServerName localhost\n" > /etc/apache2/conf-available/servername.conf \
 && a2enconf servername \
 && printf "DirectoryIndex index.php index.html\n" > /etc/apache2/conf-available/dirindex.conf \
 && a2enconf dirindex

ENV TZ=Europe/Lisbon
ENV PHP_MEMORY_LIMIT=512M
ENV PHP_POST_MAX_SIZE=64M
ENV PHP_UPLOAD_MAX_FILESIZE=64M
ENV TIMEZONE=Europe/Lisbon

RUN set -eux; \
    cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"; \
    sed -i "s~^memory_limit = .*~memory_limit = ${PHP_MEMORY_LIMIT}~" "$PHP_INI_DIR/php.ini"; \
    sed -i "s~^post_max_size = .*~post_max_size = ${PHP_POST_MAX_SIZE}~" "$PHP_INI_DIR/php.ini"; \
    sed -i "s~^upload_max_filesize = .*~upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE}~" "$PHP_INI_DIR/php.ini"; \
    sed -i "s~;date.timezone =.*~date.timezone = ${TIMEZONE}~" "$PHP_INI_DIR/php.ini"

COPY ./bootstrap.sh /usr/local/bin/bootstrap.sh
COPY ./src/init-db.php /usr/local/bin/init-db.php
RUN chmod +x /usr/local/bin/bootstrap.sh /usr/local/bin/init-db.php

WORKDIR /var/www/html
CMD ["/usr/local/bin/bootstrap.sh"]
