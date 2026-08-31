FROM debian:13.6-slim@sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132

LABEL org.opencontainers.image.source="https://github.com/irondragonservices/iron-debian"

# make a pipe fail on the first failure
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# The user the app should run as
ENV APP_USER=app
# The home directory
ENV APP_DIR="/$APP_USER"
# Where persistent data (volume) should be stored
ENV DATA_DIR="$APP_DIR/data"
# Where configuration should be stored
ENV CONF_DIR="$APP_DIR/conf"
# Where an app may write at runtime. The rest of $APP_DIR is read-only after
# post-install.sh, so anything that needs to write a pid file or a socket needs
# somewhere to put it.
ENV TMP_DIR="$APP_DIR/tmp"

# Update base system
# hadolint ignore=DL3018,DL3009,DL3008
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Add custom user and setup home directory
# useradd rather than adduser: adduser is a Perl wrapper from a package that
# debian:13-slim no longer ships, and pulling it in to create one account would
# add a Perl runtime to a base image whose whole point is having less in it.
RUN useradd --shell /bin/true --uid 1000 --home-dir $APP_DIR --create-home --user-group $APP_USER \
  && mkdir "$DATA_DIR" "$CONF_DIR" "$TMP_DIR" \
  && chown -R "$APP_USER" "$APP_DIR" "$CONF_DIR" "$TMP_DIR" \
  && chmod 700 "$APP_DIR" "$DATA_DIR" "$CONF_DIR" "$TMP_DIR"

# Remove existing crontabs, if any.
RUN rm -fr /var/spool/cron \
	&& rm -fr /etc/crontabs \
	&& rm -fr /etc/periodic

# The admin commands under /usr/sbin are stripped in post-install.sh rather
# than here. Two reasons: /sbin and /lib are symlinks into /usr on a merged
# Debian, and `find /sbin ! -type d -delete` matches and deletes the symlink
# itself, breaking PATH and every find after it; and dpkg needs ldconfig and
# start-stop-daemon from that directory, so emptying it at base-build time
# leaves an image nothing can be installed on top of.

# Remove world-writeable permissions except for /tmp/
RUN find / -xdev -type d -perm /0002 -exec chmod o-w {} + \
	&& find / -xdev -type f -perm /0002 -exec chmod o-w {} + \
	&& chmod 777 /tmp/ \
  && chown $APP_USER:root /tmp/

# The account list is pruned in post-install.sh rather than here. Debian
# packages chown their files to system groups during configure — nginx-common
# wants root:adm — and dpkg, unlike apk, treats a missing group as a hard
# error, so a base image with only app, root and nobody in /etc/group is one
# that no Debian package can be installed onto.

# Remove apt configs. -> Commented out because we need apk to install other stuff
#RUN find /bin /etc /lib /sbin /usr \
#  -xdev -type f -regex '.*apt.*' \
#  ! -name apt \
#  -exec rm -fr {} +

# Remove temp shadow,passwd,group
RUN find /bin /etc /lib /sbin /usr -xdev -type f -regex '.*-$' -exec rm -f {} +

# Ensure system dirs are owned by root and not writable by anybody else.
RUN find /bin /etc /lib /sbin /usr -xdev -type d \
  -exec chown root:root {} \; \
  -exec chmod 0755 {} \;

# Remove suid & sgid files
RUN find /bin /etc /lib /sbin /usr -xdev -type f -a \( -perm /4000 -o -perm /2000 \) -delete

RUN find /bin /etc /lib /sbin /usr -xdev \( \
  -name hexdump -o \
  -name chgrp -o \
  -name od -o \
  -name strings -o \
  -name su -o \
  -name sudo \
  \) -delete

# `ln` is the exception and is removed in
# post-install.sh instead: Debian maintainer scripts use it — nginx-common's
# postinst calls it on line 37 — and dpkg reports the failure as a bare
# "exit status 127" with no clue as to what was missing.

# Remove init scripts since we do not use them.
RUN rm -fr /etc/init.d /lib/rc /etc/conf.d /etc/inittab /etc/runlevels /etc/rc.conf /etc/logrotate.d

# Remove kernel tunables
RUN rm -fr /etc/sysctl* /etc/modprobe.d /etc/modules /etc/mdev.conf /etc/acpi

# Remove root home dir
RUN rm -fr /root

# Remove fstab
RUN rm -f /etc/fstab

# Remove any symlinks that we broke during previous steps
RUN find /bin /etc /lib /sbin /usr -xdev -type l -exec test ! -e {} \; -delete

# add-in post installation file for permissions
COPY post-install.sh $APP_DIR/
RUN chmod 500 $APP_DIR/post-install.sh

# default directory is /app
WORKDIR $APP_DIR
