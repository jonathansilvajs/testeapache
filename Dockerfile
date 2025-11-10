FROM php:8.2-apache

# =========================
# 1) Sistema + dependências
# =========================
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates software-properties-common \
    git unzip curl wget vim nano gosu expect \
    libzip-dev libpng-dev libjpeg62-turbo-dev libfreetype6-dev libwebp-dev \
    libkrb5-dev libxml2-dev \
 && rm -rf /var/lib/apt/lists/*

# =========================
# 2) Extensões PHP 8.2
# =========================
RUN docker-php-ext-configure imap --with-kerberos --with-imap-ssl \
 && docker-php-ext-install pdo pdo_mysql mysqli mbstring curl gd xml zip imap \
 && a2enmod rewrite headers

# =========================
# 3) Composer (instalador oficial)
# =========================
RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" \
 && php composer-setup.php --install-dir=/usr/local/bin --filename=composer \
 && rm composer-setup.php

# =========================
# 4) Apache + PHP.ini
# =========================
RUN printf "ServerName localhost\n" > /etc/apache2/conf-available/servername.conf \
 && a2enconf servername \
 && printf "DirectoryIndex index.php index.html\n" > /etc/apache2/conf-available/dirindex.conf \
 && a2enconf dirindex

# Configurações do PHP.ini
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

# =========================
# 5) Scripts internos
# =========================
COPY ./bootstrap.sh /usr/local/bin/bootstrap.sh
COPY ./src/init-db.php /usr/local/bin/init-db.php
RUN chmod +x /usr/local/bin/bootstrap.sh /usr/local/bin/init-db.php \
 && chown www-data:www-data /usr/local/bin/bootstrap.sh /usr/local/bin/init-db.php

# =========================
# 6) Workdir e entrypoint
# =========================
WORKDIR /var/www/html
CMD ["/usr/local/bin/bootstrap.sh"]
