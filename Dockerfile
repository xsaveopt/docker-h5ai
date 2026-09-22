FROM debian:stable-slim AS build

ENV PHP_VERSION=8.5
ENV H5AI_VERSION=0.30.0

RUN set -xe \
    && apt update -yqq \
    && apt upgrade -yqq \
    && apt install -yqq --no-install-recommends \
        curl \
        unzip \
        ca-certificates \
        nginx \
        apache2-utils \
    && curl -sSL https://packages.sury.org/php/README.txt | bash -x \
    && apt update -yqq \
    && apt install -yqq --no-install-recommends \
        php${PHP_VERSION}-fpm \
    && curl -fsSL -o /tmp/h5ai.zip https://github.com/lrsjng/h5ai/releases/download/v${H5AI_VERSION}/h5ai-${H5AI_VERSION}.zip \
    && unzip -q /tmp/h5ai.zip -d /tmp/ \
    && mkdir -p /app/files \
    && mv /tmp/_h5ai /app \
    && chown -R www-data:www-data /app \
    && rm -rf /tmp/* \
    && apt purge -yqq --auto-remove curl unzip ca-certificates

FROM scratch AS runtime
COPY --from=build / /
COPY nginx.conf /etc/nginx/nginx.conf
COPY php-fpm.conf /etc/h5ai/php-fpm.conf
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

USER 33:33
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["php", "-r", "$b=getenv('BASE_PATH');$p='/health';if($b!==false&&$b!==''&&$b!=='/'){$b='/'.ltrim($b,'/');$b=rtrim($b,'/');$p=$b.'/health';}$c=@file_get_contents('http://127.0.0.1:8080'.$p,false,stream_context_create(['http'=>['timeout'=>2,'ignore_errors'=>true]]));$h=$http_response_header[0]??'';exit(strpos($h,' 200 ')!==false?0:1);"]

ENTRYPOINT ["/entrypoint.sh"]
