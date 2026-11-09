#!/bin/sh
set -eu
# The image's Nix closure must be available before mounting the persistent store.
# Copy missing paths on every image upgrade; never overwrite the live Nix DB.
if [ "${INITIALIZE_STORE:-}" = 1 ]; then
  mkdir -p /data/nix/store
  cp -an /nix/store/. /data/nix/store/
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
mkdir -p /run/sshd /var/empty /data/ssh
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
cat /tmp/builder-shadow > /etc/shadow
rm /tmp/builder-shadow
exec "$(command -v sshd)" -D -e -f /config/sshd_config
