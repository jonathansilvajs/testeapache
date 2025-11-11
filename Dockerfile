FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Europe/Lisbon \
    PHP_MEMORY_LIMIT=512M \
    PHP_POST_MAX_SIZE=64M \
    PHP_UPLOAD_MAX_FILESIZE=64M \
    TIMEZONE=Europe/Lisbon

# 1) Tools, PPA do PHP 8.2 e pacotes PHP (inclui interbase/pdo_firebird)
RUN apt-get update -o Acquire::Retries=3 \
 && apt-get install -y --no-install-recommends \
    ca-certificates apt-transport-https software-properties-common gnupg curl wget unzip git nano vim gosu expect \
 && add-apt-repository -y ppa:ondrej/php \
 && apt-get update -o Acquire::Retries=3 \
 && apt-get install -y --no-install-recommends \
    apache2 libapache2-mod-php8.2 \
    php8.2 php8.2-cli php8.2-common php8.2-xml php8.2-zip php8.2-curl php8.2-imap \
    php8.2-gd php8.2-mysql php8.2-mbstring \
    php8.2-interbase php8.2-pdo-firebird \
 && rm -rf /var/lib/apt/lists/*

# 2) Apache mods e index
RUN a2enmod rewrite headers \
 && printf "DirectoryIndex index.php index.html\n" > /etc/apache2/conf-available/dirindex.conf \
 && a2enconf dirindex \
 && printf "ServerName localhost\n" > /etc/apache2/conf-available/servername.conf \
 && a2enconf servername

# 3) Ajustar php.ini (Apache SAPI)
RUN set -eux; \
    PHP_INI="/etc/php/8.2/apache2/php.ini"; \
    sed -i "s~^memory_limit = .*~memory_limit = ${PHP_MEMORY_LIMIT}~" "$PHP_INI"; \
    sed -i "s~^post_max_size = .*~post_max_size = ${PHP_POST_MAX_SIZE}~" "$PHP_INI"; \
    sed -i "s~^upload_max_filesize = .*~upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE}~" "$PHP_INI"; \
    sed -i "s~;date.timezone =.*~date.timezone = ${TIMEZONE}~" "$PHP_INI"

# 4) Composer
RUN php -r "copy('https://getcomposer.org/installer','/tmp/composer-setup.php');" \
 && php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer \
 && rm -f /tmp/composer-setup.php

# 5) Scripts internos
COPY ./bootstrap.sh /usr/local/bin/bootstrap.sh
COPY ./src/init-db.php /usr/local/bin/init-db.php
RUN chmod +x /usr/local/bin/bootstrap.sh /usr/local/bin/init-db.php

# 6) Docroot e portas
WORKDIR /var/www/html
EXPOSE 80

# 7) Arranque
# Observação: nesta imagem, o comando para foreground é 'apache2ctl -D FOREGROUND'
CMD ["/usr/local/bin/bootstrap.sh"]
