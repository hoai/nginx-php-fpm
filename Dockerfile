ARG VERSION=8.0.0-fpm-1.18.0-nginx-buster
FROM dwchiang/nginx-php-fpm:${VERSION}

LABEL maintainer="Ernest Chiang <me@ernestchiang.com>"

ARG VERSION_PHP_FPM_MINOR
ARG VERSION_OS
ENV VERSION_OS=${VERSION_OS} 

### ----------------------------------------------------------
### PHP
### ----------------------------------------------------------

RUN set -x && \
    # install lib packages
    apt-get update &&\
    apt-get install --no-install-recommends --no-install-suggests -y \
        bc \
        # for bz2
        #   - ref: https://github.com/docker-library/php/issues/47
        libbz2-dev \
        # for gd
        #   - ref: https://stackoverflow.com/questions/61228386/installing-gd-extension-in-docker
        libfreetype6-dev \
        libpng-dev \
        libjpeg62-turbo-dev \
        && \
    # install general usage packages
    apt-get install --no-install-recommends --no-install-suggests -y \
        # for composer
        git \
        && \
    # docker-php
    #   - Removed `mbstring` on alpine: https://stackoverflow.com/questions/59251008/docker-laravel-configure-error-package-requirements-oniguruma-were-not-m/59253249#59253249
    #     Due to this error: `configure: error: Package requirements (oniguruma) were not met: Package 'oniguruma', required by 'virtual:world', not found`
    # for gd
    #   - ref: https://github.com/docker-library/php/pull/910#issuecomment-559383597
    if [ $(echo "${VERSION_PHP_FPM_MINOR} >= 7.4" | bc) -eq 1 ]; then \
        docker-php-ext-configure gd --with-freetype --with-jpeg ; \
    else \
        docker-php-ext-configure gd --with-freetype-dir=/usr --with-jpeg-dir=/usr --with-png-dir=/usr ; \
    fi && \
    docker-php-ext-install -j$(nproc) \
        bcmath \
        mysqli \
        pdo \
        pdo_mysql \
        bz2 \
        gd \
        exif \
        opcache \
        && \
    docker-php-source delete && \
    # php configurations
    mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" && \
    # Memory, Time, Size Limits
    #   You can limit these at your orchestration layer.
    echo "memory_limit=2048M" > $PHP_INI_DIR/conf.d/memory-limit.ini && \
    echo "max_execution_time=900" >> $PHP_INI_DIR/conf.d/memory-limit.ini && \
    echo "post_max_size=20M" >> $PHP_INI_DIR/conf.d/memory-limit.ini && \
    echo "upload_max_filesize=20M" >> $PHP_INI_DIR/conf.d/memory-limit.ini && \
    # Time Zone
    echo "date.timezone=${PHP_TIMEZONE:-UTC}" > $PHP_INI_DIR/conf.d/date_timezone.ini && \
    # Display errors in stderr
    echo "display_errors=stderr" > $PHP_INI_DIR/conf.d/display-errors.ini && \
    # Disable PathInfo
    echo "cgi.fix_pathinfo=0" > $PHP_INI_DIR/conf.d/path-info.ini && \
    # Disable expose PHP
    echo "expose_php=0" > $PHP_INI_DIR/conf.d/path-info.ini && \    
    # composer
    curl -sS https://getcomposer.org/installer | php -- --quiet --install-dir=/usr/local/bin --filename=composer && \
    # clean up
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /usr/share/nginx/html/*

### ----------------------------------------------------------
### Test with Laravel
### ----------------------------------------------------------


COPY php/*.php /usr/share/nginx/html
COPY laravel-8.5.5/public /usr/share/nginx/html
COPY laravel-8.5.5 /var/www/html
COPY php/laravel-8 /var/www/html/

RUN set -x && \
    if [ -f "/var/www/html/composer.lock" ]; then \
        if [ "${APP_ENV}" == "development" ] || [ "${APP_ENV}" == "dev" || "${APP_ENV}" == "staging" ] || [ "${APP_ENV}" == "stage" ]; then \
            composer global require hirak/prestissimo ; \
            composer install --working-dir=/var/www/html ; \
        else \
            composer global require hirak/prestissimo ; \
            composer install --no-dev --working-dir=/var/www/html ; \
        fi \
    fi && \
    # resolve: The stream or file "/var/www/html/storage/logs/laravel.log" could not be opened in append mode: failed to open stream: Permission denied
    touch /var/www/html/storage/logs/laravel.log && \
    touch /var/log/cron.log && \
    chown -R www-data:www-data /usr/share/nginx/html && \
    chown -R www-data:www-data /var/www/html && \
    find /var/www/html/storage -type f -exec chmod 664 {} \; && \
    find /var/www/html/storage -type d -exec chmod 770 {} \;

# TODO: cron

CMD ["/docker-entrypoint.sh"]
