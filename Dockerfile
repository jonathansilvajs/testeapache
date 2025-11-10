FROM php:8.2-apache

# Instala extensões e habilita módulos
RUN docker-php-ext-install pdo pdo_mysql mysqli && a2enmod rewrite

# Configuração do Apache
RUN printf "ServerName localhost\n" > /etc/apache2/conf-available/servername.conf \
 && a2enconf servername \
 && printf "DirectoryIndex index.php index.html\n" > /etc/apache2/conf-available/dirindex.conf \
 && a2enconf dirindex

ENV TZ=Europe/Lisbon

# Copia todo o conteúdo de src (inclui init-db.php)
COPY ./src /var/www/html
RUN chown -R www-data:www-data /var/www/html

# Executa o init antes de iniciar o Apache
CMD php /var/www/html/init-db.php && apache2-foreground
