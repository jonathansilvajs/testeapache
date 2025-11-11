FROM php:8.2-apache

ENV DEBIAN_FRONTEND=noninteractive

# 1) Ferramentas + toolchains de build + libs necessárias a GD/mbstring/zip/xml
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    $PHPIZE_DEPS \
    ca-certificates git unzip curl wget nano vim gosu expect \
    libzip-dev zlib1g-dev \
    libxml2-dev \
    libonig-dev \
    libjpeg62-turbo-dev libfreetype6-dev libpng-dev libwebp-dev \
 && rm -rf /var/lib/apt/lists/*

# 2) Extensões PHP em passos separados (usa -j1 para reduzir RAM no Portainer)
RUN set -eux; docker-php-ext-install -j1 pdo pdo_mysql mysqli
RUN set -eux; docker-php-ext-install -j1 xml
RUN set -eux; docker-php-ext-install -j1 zip

# 3) GD (com jpeg/freetype/webp)
RUN set -eux; \
    docker-php-ext-configure gd --with-jpeg --with-freetype --with-webp; \
    docker-php-ext-install -j1 gd

# 4) mbstring (com fallback de debug se falhar)
RUN set -eux; docker-php-ext-install -j1 mbstring || { \
      echo '--- mbstring build failed; dumping config logs ---'; \
      find /usr/src -name "config.log" -maxdepth 6 2>/dev/null | xargs -r printf '\n>>> %s\n' | sed 's/^/FILE: /'; \
      find /usr/src -name "config.log" -maxdepth 6 2>/dev/null | xargs -r tail -n +1; \
      exit 1; \
    }

# 5) Firebird client + headers (Bookworm) e build do interbase/pdo_firebird
RUN apt-get update && apt-get install -y --no-install-recommends \
      libfbclient2 libfbclient-dev \
 && rm -rf /var/lib/apt/lists/*

# Detecta automaticamente onde está o ibase.h e compila
RUN set -eux; \
    IBASE_H="$(dpkg -L libfbclient-dev | grep -E '/ibase\.h$' | head -n1 || true)"; \
    if [ -z "$IBASE_H" ]; then \
      echo 'ibase.h não encontrado em libfbclient-dev; conteúdos do pacote:'; \
      dpkg -L libfbclient-dev || true; \
      exit 1; \
    fi; \
    IBASE_PREFIX="/usr"; \
    echo ">> Usando --with-interbase=${IBASE_PREFIX} (ibase.h em: $IBASE_H)"; \
    docker-php-ext-configure interbase --with-interbase="${IBASE_PREFIX}"; \
    docker-php-ext-install -j1 interbase pdo_firebird || { \
      echo '--- interbase build failed; dumping config logs ---'; \
      find /usr/src -name "config.log" -maxdepth 6 2>/dev/null | xargs -r printf '\n>>> %s\n' | sed 's/^/FILE: /'; \
      find /usr/src -name "config.log" -maxdepth 6 2>/dev/null | xargs -r tail -n +1; \
      exit 1; \
    }

# 6) Apache: módulos úteis
RUN a2enmod rewrite headers

# 7) Composer (instalador oficial)
RUN php -r "copy('https://getcomposer.org/installer','/tmp/composer-setup.php');" \
 && php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer \
 && rm -f /tmp/composer-setup.php

# 8) Apache + php.ini (ajustável via ENV)
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

# 9) Scripts internos (DB antes do clone, clone 1x, composer)
COPY ./bootstrap.sh /usr/local/bin/bootstrap.sh
COPY ./src/init-db.php /usr/local/bin/init-db.php
RUN chmod +x /usr/local/bin/bootstrap.sh /usr/local/bin/init-db.php

# 10) Limpeza dos toolchains (imagem menor)
RUN apt-get purge -y --auto-remove $PHPIZE_DEPS \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html
CMD ["/usr/local/bin/bootstrap.sh"]
