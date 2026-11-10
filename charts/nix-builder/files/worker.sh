#!/bin/sh
set -eu
# The image's Nix closure must be available before mounting the persistent store.
# Copy missing paths on every image upgrade; never overwrite the live Nix DB.
if [ "${INITIALIZE_STORE:-}" = 1 ]; then
  mkdir -p /data/nix/store
  cp -an /nix/store/. /data/nix/store/
  # Older workers edited these symlinks in place, corrupting the image's store
  # path. Restore only the two image-owned files before reusing an old PVC.
  for file in /etc/passwd /etc/shadow; do
    source=$(readlink -f "$file")
    case "$source" in
      /nix/store/*)
        cp --remove-destination --preserve=mode,ownership,timestamps "$source" "/data$source"
        ;;
    esac
  done
  if [ ! -e /data/nix/var/nix/db/db.sqlite ]; then
    cp -a /nix/var /data/nix/
  else
    # Register the new image closure in the existing store database.
    nix-store --dump-db > /data/image-registration
    NIX_STATE_DIR=/data/nix/var/nix nix-store --load-db < /data/image-registration
    rm /data/image-registration
    cp -a /nix/var/nix/profiles/. /data/nix/var/nix/profiles/
  fi
  exit 0
fi
if [ "${REGISTER_ATTIC:-}" = 1 ]; then
  # Register the uploader closure with the builder's Nix version, not the
  # tools image's Nix version, and keep it alive during garbage collection.
  nix-store --load-db < /attic-bin/registration
  mkdir -p /nix/var/nix/gcroots/attic-uploader
  rm -f /nix/var/nix/gcroots/attic-uploader/*
  while IFS= read -r path; do
    ln -sfn "$path" "/nix/var/nix/gcroots/attic-uploader/$(basename "$path")"
  done < /attic-bin/roots
  exit 0
fi
mkdir -p /run/sshd /var/empty /data/ssh
# Secret volume directories can be world-writable. Keep StrictModes enabled
# and copy the projected file into a private, root-owned runtime directory.
chown 0:0 /run/sshd
chmod 0700 /run/sshd
install -m 0600 -o 0 -g 0 /keys/authorized_keys /run/sshd/authorized_keys
# /etc/passwd can point into the image's Nix closure. Replace the symlink,
# keeping SSH account changes in the container filesystem, outside the store.
cp -L /etc/passwd /tmp/builder-passwd
cp --remove-destination /tmp/builder-passwd /etc/passwd
chmod 0644 /etc/passwd
rm /tmp/builder-passwd
if ! grep -q '^sshd:' /etc/passwd; then
  printf 'sshd:x:65533:65534:SSH privilege separation:/var/empty:/bin/sh\n' >> /etc/passwd
fi
if [ ! -f /data/ssh/ssh_host_ed25519_key ]; then
  ssh-keygen -q -t ed25519 -N '' -f /data/ssh/ssh_host_ed25519_key
fi
# The upstream image locks root; permit public-key login with password auth disabled.
while IFS=: read -r user password rest; do
  [ -n "$user" ] || continue
  [ "$user" != root ] || password='*'
  printf '%s:%s:%s\n' "$user" "$password" "$rest"
done < /etc/shadow > /tmp/builder-shadow
chmod 0600 /tmp/builder-shadow
cp --remove-destination /tmp/builder-shadow /etc/shadow
rm /tmp/builder-shadow
exec "$(command -v sshd)" -D -e -f /config/sshd_config
