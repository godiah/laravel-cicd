ARG PHP_VERSION=8.4
FROM php:${PHP_VERSION}-fpm-alpine

LABEL org.opencontainers.image.source="https://github.com/godiah/laravel-cicd"
LABEL org.opencontainers.image.description="PHP-FPM base image with all Laravel production extensions pre-installed"

# ---- Runtime system libraries ----
RUN apk add --no-cache \
    curl \
    libpng \
    libjpeg-turbo \
    freetype \
    icu-libs \
    libzip \
    libxml2 \
    oniguruma \
    postgresql-libs

# ---- Compile and install PHP extensions ----
# Build deps are installed temporarily and removed after compilation to keep the image small.
# All extensions are included so this base image works for both MySQL and PostgreSQL projects.
RUN apk add --no-cache --virtual .build-deps \
        libpng-dev \
        libjpeg-turbo-dev \
        freetype-dev \
        icu-dev \
        libzip-dev \
        libxml2-dev \
        oniguruma-dev \
        postgresql-dev \
        autoconf \
        gcc \
        g++ \
        make \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" \
        pdo_mysql \
        pdo_pgsql \
        pgsql \
        mbstring \
        xml \
        zip \
        bcmath \
        intl \
        gd \
        opcache \
        pcntl \
    && pecl install redis \
    && docker-php-ext-enable redis \
    && apk del .build-deps \
    && rm -rf /tmp/pear

# ---- PHP configuration ----
COPY php/php.ini /usr/local/etc/php/php.ini
COPY php/www.conf /usr/local/etc/php-fpm.d/www.conf
COPY php/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

WORKDIR /var/www/html

EXPOSE 9000

HEALTHCHECK --interval=10s --timeout=5s --retries=3 --start-period=20s \
    CMD sh -c "nc -z localhost 9000 || exit 1"

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["php-fpm"]
