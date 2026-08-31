#!/usr/bin/env bash
#
# Run this as the last instruction of any image built on iron-debian. It does
# the hardening that can only be done once nothing else will follow it:
# removing the package manager, the account-management tools and the write
# permissions the build needed but the runtime does not.
#
# Several of these steps are deliberately here rather than in the base image's
# own Dockerfile. Debian's packaging is far less forgiving than Alpine's — dpkg
# fails hard on a missing group, and maintainer scripts shell out to `ln` — so
# a base image that had already stripped those could not have a single package
# installed on top of it. The comments below say which is which and why.

# fail if a command fails
set -e
set -o pipefail

# Remove unnecessary accounts, excluding the app user and root. Debian packages
# chown their files to system groups during configure — nginx-common wants
# root:adm — and dpkg treats a missing group as a hard error, so these have to
# survive until nothing more will be installed.
sed -i -r "/^($APP_USER|root|nobody)/!d" /etc/group
sed -i -r "/^($APP_USER|root|nobody)/!d" /etc/passwd

# Remove the interactive login shell for everybody
sed -i -r 's#^(.*):[^:]*$#\1:/usr/sbin/nologin#' /etc/passwd

# Disable password login for everybody
while IFS=: read -r username _; do passwd -l "$username"; done < /etc/passwd || true

# `ln` is removed here rather than in the base image because Debian maintainer
# scripts use it — nginx-common's postinst calls it on line 37 — and dpkg
# reports the failure as a bare "exit status 127" with no clue what was
# missing. Everything else in this list the base image has already removed;
# repeating it costs nothing and catches anything a package brought back.
find /bin /etc /lib /sbin /usr -xdev \( \
  -name hexdump -o \
  -name chgrp -o \
  -name ln -o \
  -name od -o \
  -name strings -o \
  -name su -o \
  -name sudo \
  \) -delete

# The account and privilege tooling. Named individually rather than by
# emptying /usr/sbin: on Debian that directory holds service binaries as well
# as admin commands, so wiping it takes the application with it — nginx lives
# there.
find /usr/bin /usr/sbin -xdev -maxdepth 1 \( \
  -name 'useradd' -o -name 'userdel' -o -name 'usermod' -o \
  -name 'groupadd' -o -name 'groupdel' -o -name 'groupmod' -o \
  -name 'adduser' -o -name 'deluser' -o -name 'addgroup' -o -name 'delgroup' -o \
  -name 'chpasswd' -o -name 'chgpasswd' -o -name 'newusers' -o \
  -name 'passwd' -o -name 'chsh' -o -name 'chfn' -o -name 'visudo' -o \
  -name 'chroot' -o -name 'unshare' -o -name 'nsenter' -o \
  -name 'setcap' -o -name 'getcap' -o -name 'capsh' -o -name 'setpriv' -o \
  -name 'mount' -o -name 'umount' -o -name 'swapon' -o -name 'swapoff' -o \
  -name 'sysctl' -o -name 'insmod' -o -name 'rmmod' -o -name 'modprobe' -o \
  -name 'depmod' -o -name 'start-stop-daemon' -o -name 'update-rc.d' -o \
  -name 'invoke-rc.d' -o -name 'ldconfig' \
  \) -delete

# Anything a package installed setuid or setgid is a privilege boundary the
# base image did not agree to.
find /bin /etc /lib /sbin /usr -xdev -type f -a \( -perm /4000 -o -perm /2000 \) -delete

# Remove apt and dpkg. The base image deliberately keeps them so that images
# built on it can install what they need; by now, nothing more will be.
find /usr/bin /usr/sbin /usr/lib/apt -xdev \( -type f -o -type l \) \
  \( -name 'apt*' -o -name 'dpkg*' \) -delete
rm -rf /etc/apt /var/lib/apt /var/lib/dpkg /var/cache/apt /usr/lib/apt /usr/share/dpkg

# set rx to all directories, except the writable ones below
find "$APP_DIR" -type d -exec chmod 500 {} +

# set r to all files
find "$APP_DIR" -type f -exec chmod 400 {} +

# the two directories the app is allowed to write to
chmod -R u=rwx "$DATA_DIR/"
chmod -R u=rwx "$TMP_DIR/"

# chown all app files
chown "$APP_USER":"$APP_USER" -R "$APP_DIR" "$DATA_DIR" "$TMP_DIR"

# Remove chown after use. Deliberately not removed in the Dockerfile: doing
# that there means this script's own chown fails on every image built on top.
find /usr/bin /usr/sbin /bin -xdev \( -type f -o -type l \) -name 'chown' -delete

# remove any symlink broken by the steps above
find /bin /etc /lib /sbin /usr -xdev -type l -exec test ! -e {} \; -delete

# finally remove this file
rm "$0"
