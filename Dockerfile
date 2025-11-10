FROM php:8.2-apache

# Pacotes de sistema + Git + Composer deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates unzip \
    libzip-dev \
    libpng-dev libjpeg62-turbo-dev libfreetype6-dev libwebp-dev \
    gosu \
 && rm -rf /var/lib/apt/lists/*

# Extensões PHP necessárias
# zip
RUN docker-php-ext-install zip
# gd (com jpeg/freetype/webp)
RUN docker-php-ext-configure gd --with-jpeg --with-freetype --with-webp \
 && docker-php-ext-install gd
# MySQL
RUN docker-php-ext-install pdo pdo_mysql mysqli \
 && a2enmod rewrite

# Composer (instalador oficial)
RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" \
 && php composer-setup.php --install-dir=/usr/local/bin --filename=composer \
 && rm composer-setup.php

# Apache: ServerName + DirectoryIndex
RUN printf "ServerName localhost\n" > /etc/apache2/conf-available/servername.conf \
 && a2enconf servername \
 && printf "DirectoryIndex index.php index.html\n" > /etc/apache2/conf-available/dirindex.conf \
 && a2enconf dirindex

ENV TZ=Europe/Lisbon

# Entrypoint
COPY ./bootstrap.sh /usr/local/bin/bootstrap.sh
RUN chmod +x /usr/local/bin/bootstrap.sh

CMD ["/usr/local/bin/bootstrap.sh"]
