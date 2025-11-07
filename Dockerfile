# Dockerfile
FROM php:8.2-apache

# Instala extensões necessárias para MySQL (PDO, mysqli) e utilitários básicos
RUN docker-php-ext-install pdo pdo_mysql mysqli

# Habilita o mod_rewrite (útil para frameworks)
RUN a2enmod rewrite

# Ajuste opcional do DocumentRoot (se quiser /var/www/html/public, descomente)
# ENV APACHE_DOCUMENT_ROOT=/var/www/html/public
# RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/000-default.conf /etc/apache2/apache2.conf

# Define timezone (opcional)
ENV TZ=Europe/Lisbon

# Copia o código (ou use volume no compose)
COPY ./src /var/www/html

# Permissões (opcional, depende do host)
RUN chown -R www-data:www-data /var/www/html
