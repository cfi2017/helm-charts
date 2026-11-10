#!/bin/sh
set -eu
export NIX_REMOTE=local
# This init container can see its image's store. Preserve the closure before
# mounting the builder's store over /nix in the uploader container.
mkdir -p /shared-nix/store /attic-bin
cp -a --update=none /nix/store/. /shared-nix/store/
# Docker Nix images may copy the executable into /bin rather than symlink it.
cp -L "$(command -v attic)" /attic-bin/attic
chmod 0755 /attic-bin/attic
nix-store --dump-db > /attic-bin/registration
nix --extra-experimental-features nix-command path-info --all > /attic-bin/roots
