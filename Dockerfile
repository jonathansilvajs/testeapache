# Dockerfile
FROM php:8.2-apache

# Instala git e extensões PHP
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && docker-php-ext-install pdo pdo_mysql mysqli \
 && a2enmod rewrite

# Silencia o aviso de ServerName e define um DirectoryIndex padrão
RUN printf "ServerName localhost\n" > /etc/apache2/conf-available/servername.conf \
 && a2enconf servername \
 && printf "DirectoryIndex index.php index.html\n" > /etc/apache2/conf-available/dirindex.conf \
 && a2enconf dirindex

# Timezone
ENV TZ=Europe/Lisbon

# Copia o entrypoint customizado
COPY ./bootstrap.sh /usr/local/bin/bootstrap.sh
RUN chmod +x /usr/local/bin/bootstrap.sh

# Comando de inicialização (clona só uma vez e inicia o Apache)
CMD ["/usr/local/bin/bootstrap.sh"]
