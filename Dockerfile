FROM php:8.2-apache

# Extensões e mod_rewrite
RUN docker-php-ext-install pdo pdo_mysql mysqli && a2enmod rewrite

# Silenciar aviso de ServerName e garantir um DirectoryIndex
RUN printf "ServerName localhost\n" > /etc/apache2/conf-available/servername.conf \
 && a2enconf servername \
 && printf "DirectoryIndex index.php index.html\n" > /etc/apache2/conf-available/dirindex.conf \
 && a2enconf dirindex

ENV TZ=Europe/Lisbon

# Copia a app para dentro da imagem
COPY ./src /var/www/html
RUN chown -R www-data:www-data /var/www/html
