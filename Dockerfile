FROM alpine:3.19

ARG NGINX_VERSION=1.25.5

SHELL [ "/bin/ash", "-e", "-o", "pipefail", "-c" ]

COPY patches /tmp/patches

# hadolint ignore=DL3003,DL3018,SC2016
RUN <<EOF
addgroup -S nginx
adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx nginx
apk add --no-cache \
    brotli-libs \
    libgcc \
    liburing \
    mimalloc2 \
    pcre2
apk add --no-cache -t .build-deps \
    brotli-dev \
    build-base \
    cmake \
    curl \
    git \
    liburing-dev \
    linux-headers \
    make \
    mimalloc2-dev \
    pcre2-dev \
    perl \
    tar \
    zlib-dev \
    zstd-dev
mkdir -p /usr/src/nginx /etc/ssl /etc/letsencrypt /etc/nginx/sites-enabled
git clone --depth=1 --branch=openssl-3.1.5+quic \
    https://github.com/quictls/openssl /usr/src/openssl
git clone --depth=1 --shallow-submodules --recursive \
    https://github.com/google/ngx_brotli /usr/src/ngx_brotli
git clone --depth=1 https://github.com/tokers/zstd-nginx-module /usr/src/ngx_zstd
git clone --depth=1 https://github.com/grahamedgecombe/nginx-ct /usr/src/ngx_ct
git clone --depth=1 https://github.com/vozlt/nginx-module-vts /usr/src/ngx_vts
git clone --depth=1 https://github.com/openresty/memc-nginx-module /usr/src/ngx_memc
git clone --depth=1 https://github.com/openresty/redis2-nginx-module /usr/src/ngx_redis2
curl -Ssf https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz | \
    tar xzf - -C /usr/src/nginx --strip-components=1
curl -Ssfo /etc/ssl/dhparam.pem https://2ton.com.au/dhparam/4096
cd /usr/src/nginx
for f in /tmp/patches/*.patch; do patch -Np1 -i $f; done
./configure \
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/var/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/run/nginx.lock \
    --http-client-body-temp-path=/var/cache/nginx/client_temp \
    --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
    --user=nginx \
    --group=nginx \
    --with-compat \
    --with-file-aio \
    --with-threads \
    --with-pcre \
    --with-pcre-jit \
    --with-mail \
    --with-mail_ssl_module \
    --without-mail_pop3_module \
    --with-http_auth_request_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_realip_module \
    --with-http_slice_module \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_v3_module \
    --without-http_browser_module \
    --without-http_empty_gif_module \
    --without-http_fastcgi_module \
    --without-http_geo_module \
    --without-http_memcached_module \
    --without-http_mirror_module \
    --without-http_scgi_module \
    --without-http_split_clients_module \
    --without-http_userid_module \
    --with-openssl=/usr/src/openssl \
    --with-cc-opt='-O2 -pipe' \
    --with-ld-opt='-lmimalloc' \
    --add-dynamic-module=/usr/src/ngx_brotli \
    --add-dynamic-module=/usr/src/ngx_zstd \
    --add-dynamic-module=/usr/src/ngx_ct \
    --add-dynamic-module=/usr/src/ngx_vts \
    --add-dynamic-module=/usr/src/ngx_memc \
    --add-dynamic-module=/usr/src/ngx_redis2
make -j$(getconf _NPROCESSORS_ONLN)
make install
strip /usr/sbin/nginx objs/ngx_*_module.so
cp -v objs/ngx_*_module.so /var/lib/nginx/modules
rm -r /etc/nginx/html \
      /etc/nginx/*.default \
      /etc/nginx/koi-win \
      /etc/nginx/koi-utf \
      /etc/nginx/win-utf \
      /etc/nginx/scgi_params \
      /etc/nginx/fastcgi_params \
      /etc/nginx/fastcgi.conf
printf >> /etc/nginx/uwsgi_params \
 '\nuwsgi_param HTTP_EARLY_DATA $ssl_early_data if_not_empty;\n'
apk del .build-deps
rm -rf /tmp/patches /usr/src
nginx -Vt
EOF

COPY config /etc/nginx

COPY entrypoint.sh /usr/bin/run-nginx

VOLUME /var/log/nginx \
       /etc/letsencrypt \
       /etc/nginx/sites-enabled

EXPOSE 80 443

ENTRYPOINT ["run-nginx", "-g", "daemon off;"]
