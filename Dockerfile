FROM php:8.2-apache

# =========================
# 1) Sistema + dependências
# =========================
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates unzip \
    libzip-dev \
    libpng-dev libjpeg62-turbo-dev libfreetype6-dev libwebp-dev \
    gosu \
 && rm -rf /var/lib/apt/lists/*

# =========================
# 2) Extensões PHP
# =========================
RUN docker-php-ext-install zip \
 && docker-php-ext-configure gd --with-jpeg --with-freetype --with-webp \
 && docker-php-ext-install gd \
 && docker-php-ext-install pdo pdo_mysql mysqli \
 && a2enmod rewrite

# =========================
# 3) Composer (instalador oficial)
# =========================
RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" \
 && php composer-setup.php --install-dir=/usr/local/bin --filename=composer \
 && rm composer-setup.php

# =========================
# 4) Apache: ajustes básicos
# =========================
RUN printf "ServerName localhost\n" > /etc/apache2/conf-available/servername.conf \
 && a2enconf servername \
 && printf "DirectoryIndex index.php index.html\n" > /etc/apache2/conf-available/dirindex.conf \
 && a2enconf dirindex

# Define timezone
ENV TZ=Europe/Lisbon

# =========================
# 5) Scripts internos
# =========================
# Copia os scripts do teu repositório
COPY ./bootstrap.sh /usr/local/bin/bootstrap.sh
COPY ./src/init-db.php /usr/local/bin/init-db.php

# Permissões de execução
RUN chmod +x /usr/local/bin/bootstrap.sh /usr/local/bin/init-db.php \
 && chown www-data:www-data /usr/local/bin/bootstrap.sh /usr/local/bin/init-db.php

# =========================
# 6) Workdir e entrypoint
# =========================
WORKDIR /var/www/html
CMD ["/usr/local/bin/bootstrap.sh"]
