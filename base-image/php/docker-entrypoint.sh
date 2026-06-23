#!/bin/sh
set -e

# Ensure correct ownership of storage and cache volumes.
# Named Docker volumes mount as root on first boot — this fixes permissions
# without requiring the container to run as root permanently.
chown -R www-data:www-data \
    /var/www/html/storage \
    /var/www/html/bootstrap/cache

chmod -R 775 \
    /var/www/html/storage \
    /var/www/html/bootstrap/cache

# Hand off to the main command (php-fpm by default)
exec "$@"
