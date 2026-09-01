# irondragonservices/iron-debian

Hardened Debian base image for Docker.

Forked from [ironpeakservices/iron-debian](https://github.com/ironpeakservices/iron-debian).
The hardening approach is theirs; the automation that keeps a published image
current is new, and so are the fixes listed at the bottom — the upstream image
could be built but nothing could be built *on* it.

Reach for [iron-alpine](https://github.com/irondragonservices/iron-alpine)
first. This exists for the things that need glibc, a Debian package, or a
`.deb` you do not control.

```sh
docker pull ghcr.io/irondragonservices/iron-debian:13      # any 13.x
docker pull ghcr.io/irondragonservices/iron-debian:13.6    # exactly this
```

The tag tracks the Debian release the image is built on, so `:13.6` is
iron-debian built on `debian:13.6-slim`.

## How is this different from debian-slim

- ca-certificates included
- `/app` for everything app-related: `$CONF_DIR`, `$DATA_DIR`, `$TMP_DIR`
- runs as an unprivileged user, uid 1000
- crontabs, init scripts, kernel tunables, `/root` and `/etc/fstab` removed
- `hexdump`, `chgrp`, `od`, `strings`, `su` and `sudo` removed
- every setuid and setgid bit removed
- world-writable permissions stripped from everything but `/tmp`
- system directories owned by root and not writable by anybody else

and, once `post-install.sh` has run, also: no apt, no dpkg, no `ln`, no
account-management or privilege tooling, no `chown`, and only `app`, `root`
and `nobody` left in `/etc/passwd`.

## Using it

```dockerfile
FROM ghcr.io/irondragonservices/iron-debian:13

RUN apt-get update \
  && apt-get install -y --no-install-recommends your-package \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

COPY your.conf $CONF_DIR/

# Always last, and not optional. See below.
RUN $APP_DIR/post-install.sh

USER $APP_USER
```

See [the nginx example](example/) for a complete, runnable one.

### post-install.sh is where most of the hardening happens

More so here than on Alpine, and the reason is dpkg. It is far less forgiving
than apk, so several hardening steps cannot be done in the base image without
making it impossible to install anything on top:

- **Accounts.** Debian packages chown their files to system groups during
  configure — `nginx-common` wants `root:adm`. dpkg treats a missing group as a
  hard error, so `/etc/group` can only be pruned at the end.
- **`ln`.** Maintainer scripts shell out to it; `nginx-common`'s postinst calls
  it on line 37. dpkg surfaces its absence as a bare `exit status 127`.
- **apt and dpkg themselves**, for the obvious reason.
- **The privilege tooling** — `useradd`, `mount`, `chroot`, `setcap` and the
  rest — is named individually rather than by emptying `/usr/sbin`, because on
  Debian that directory holds service binaries too. Emptying it takes nginx
  with it.

So an iron-debian image that has not run `post-install.sh` is a base image
mid-build, not a finished one.

## Environment

| Variable | Default | For |
|---|---|---|
| `APP_USER` | `app` | The unprivileged user, uid 1000 |
| `APP_DIR` | `/app` | Home. Read-only after `post-install.sh` |
| `CONF_DIR` | `/app/conf` | Configuration. Read-only at runtime |
| `DATA_DIR` | `/app/data` | Persistent data. Mount a volume here |
| `TMP_DIR` | `/app/tmp` | Scratch — pid files, sockets, upload buffers |

## Verifying what you pulled

```sh
cosign verify ghcr.io/irondragonservices/iron-debian:13 \
  --certificate-identity-regexp '^https://github\.com/irondragonservices/\.github/\.github/workflows/image-(release|refresh)\.yml@refs/heads/main$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-github-workflow-repository irondragonservices/iron-debian
```

Be precise about the identity. The signature is produced by the shared
reusable workflow in
[irondragonservices/.github](https://github.com/irondragonservices/.github),
not by a workflow in this repository, so the certificate names *that* path.
A looser pattern such as `^https://github.com/irondragonservices/` would
accept a signature from any workflow in any repository in the organisation,
which is a much weaker claim than it looks. The
`--certificate-github-workflow-repository` flag is what ties the signature back
to this repository.

Both `image-release` and `image-refresh` sign: the nightly rebuild republishes
when the package set has actually changed, and it signs what it pushes.

## Update policy

Renovate digest-pins the base and auto-merges a green bump; the pull request
gate is what makes that safe; a nightly cache-free rebuild catches package
updates that never moved the base tag; a nightly re-scan catches CVEs disclosed
after the build. Details in
[irondragonservices/.github](https://github.com/irondragonservices/.github).

## Changes from upstream

This repository arrived containing nothing but a Renovate config. What came
across from upstream needed the following before it worked.

- **The base packages are now upgraded, not just added to.** The step commented
  *update base system* only installed `ca-certificates`, so the image shipped
  whatever the base image tag happened to contain. Distributions patch a
  package well before they rebuild and republish the base image, so a digest
  pin — which is what Renovate maintains — pins the *unpatched* set until
  upstream gets round to a rebuild. It is the same trap on Debian.
  This is also what makes the nightly cache-free rebuild worth running: without
  it, that job rebuilt the same packages every night and picked up nothing.
- **The base image nothing could be built on.** Upstream deleted apt at
  base-build time (`find / -xdev -name '*apt*' | xargs rm -rf`), directly
  contradicting the comment two steps later explaining that the package
  manager is kept so derived images can install things. apt now survives until
  `post-install.sh`, as apk does in iron-alpine.
- **`su` and `sudo` were never removed.** The find had `-name su \` with no
  `-o` before `-name sudo`, so the two ANDed into a filename that cannot
  exist and the sweep silently matched nothing.
- **`chown` was removed in the Dockerfile**, so `post-install.sh`'s own
  `chown` failed on every image built on the base. It is removed at the end of
  the script now, after it has been used.
- **`find /sbin /usr/sbin ! -type d -delete` deleted `/sbin` itself.** On a
  usr-merged Debian that path is a symlink, `! -type d` matches it, and every
  later `find /bin /etc /lib /sbin /usr` then failed with exit 1.
- `! -name apk` in the same sweep was copy-paste from iron-alpine. There is no
  apk in a Debian image.
- **Base bumped from `debian:11.6-slim` to `debian:13.6-slim`.** Bullseye's
  security support ends this year.
- `adduser` replaced with `useradd`: `debian:13-slim` no longer ships the
  package, and pulling it back in would add a Perl runtime to a base image
  whose point is having less in it.
- Added `$TMP_DIR`, which the layout documented but nothing created.
- `ENV key value` replaced with `ENV key=value`.
- The example is new; upstream's pointed at a `docker.pkg.github.com` registry
  that has been switched off.
- The release workflow ran on `master` in a repository whose default branch is
  `main`, used `::set-output` and `actions/create-release`, both long dead, and
  authenticated as an account in another organisation.
