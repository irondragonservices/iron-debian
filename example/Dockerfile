FROM ghcr.io/irondragonservices/iron-debian:13

# apt is deliberately still present in the base image; post-install.sh below is
# what removes it, once nothing else will need it.
RUN apt-get update \
  && apt-get install -y --no-install-recommends nginx \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && find /etc/nginx -mindepth 1 ! -name mime.types -delete \
  && rm -rf /var/log/nginx /var/lib/nginx \
  && echo '<h1>iron-debian</h1>' > "$DATA_DIR/index.html"

COPY nginx.conf $CONF_DIR/

# Always last.
RUN $APP_DIR/post-install.sh

EXPOSE 8080
USER $APP_USER
CMD ["nginx", "-c", "/app/conf/nginx.conf", "-p", "/app", "-e", "/dev/stderr"]
