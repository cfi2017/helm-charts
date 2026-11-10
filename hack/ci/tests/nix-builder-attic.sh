#!/usr/bin/env bash
# Exercise real Attic publication, restart catch-up and signed cache downloads.
set -euo pipefail
cd "$(dirname "$0")/../../.."
readonly test_dir=$(mktemp -d)
readonly suffix="${RANDOM}-$$"
readonly network="attic-test-$suffix"
readonly data="attic-builder-$suffix"
readonly bins="attic-bins-$suffix"
readonly runtime="attic-runtime-$suffix"
readonly server_data="attic-server-data-$suffix"
readonly builder_image=nixos/nix:2.24.14
readonly tools_image=nixpkgs/attic:nixos-26.05-x86_64-linux
readonly controller_image=python:3.13-alpine
readonly server_image=ghcr.io/zhaofengli/attic:latest
server="" worker="" uploader=""
cleanup() {
  result=$?
  for container in "$uploader" "$worker" "$server"; do
    if [[ -n "$container" ]]; then
      if [[ "$result" != 0 ]]; then docker logs --tail 40 "$container" >&2 || true; fi
      docker rm -f "$container" >/dev/null || true
    fi
  done
  docker volume rm "$data" "$bins" "$runtime" "$server_data" >/dev/null || true
  docker network rm "$network" >/dev/null || true
  sudo chown -R "$(id -u):$(id -g)" "$test_dir"
  rm -rf "$test_dir"
}
trap cleanup EXIT
mkdir -p "$test_dir/config" "$test_dir/keys" "$test_dir/auth" "$test_dir/client/attic"
cp charts/nix-builder/files/{worker.sh,sshd_config,install-attic.sh,attic-uploader.py} "$test_dir/config/"
printf 'sandbox = false\nexperimental-features = nix-command flakes\n!include /attic-runtime/nix/nix.conf\n' > "$test_dir/config/nix.conf"
printf 'present before watcher startup\n' > "$test_dir/config/startup-proof"
printf 'created while watcher stopped\n' > "$test_dir/config/restart-proof"
cat > "$test_dir/config/server.toml" <<'TOML'
listen = "[::]:8080"
api-endpoint = "http://attic-server:8080/"
[database]
url = "sqlite:///data/server.db?mode=rwc"
[storage]
type = "local"
path = "/data/storage"
[chunking]
nar-size-threshold = 65536
min-size = 16384
avg-size = 65536
max-size = 262144
TOML
cat > "$test_dir/client/attic/config.toml" <<'TOML'
default-server = "builder"
[servers.builder]
endpoint = "http://attic-server:8080/"
token-file = "/attic-auth/token"
TOML
ssh-keygen -q -t ed25519 -N '' -f "$test_dir/keys/id_ed25519"
cp "$test_dir/keys/id_ed25519.pub" "$test_dir/keys/authorized_keys"
sudo chown root:root "$test_dir/keys" "$test_dir/keys/authorized_keys"
for volume in "$data" "$bins" "$runtime" "$server_data"; do docker volume create "$volume" >/dev/null; done
docker network create "$network" >/dev/null
hmac_key=$(openssl rand -base64 32)
server=$(docker run -d --network "$network" --network-alias attic-server \
  -p 127.0.0.1::8080 -v "$test_dir/config:/config:ro" -v "$server_data:/data" \
  -e "ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64=$hmac_key" \
  "$server_image" -f /config/server.toml)
server_port=$(docker port "$server" 8080/tcp | head -n1 | cut -d: -f2)
server_url="http://127.0.0.1:$server_port"
for attempt in $(seq 1 60); do
  if curl --silent --output /dev/null "$server_url/"; then break; fi
  sleep 1
done
docker run --rm --entrypoint /bin/atticadm \
  -v "$test_dir/config:/config:ro" -v "$server_data:/data" \
  -e "ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64=$hmac_key" \
  "$server_image" -f /config/server.toml make-token --sub ci --validity 1h \
  --pull 'efi-*' --push 'efi-*' --create-cache 'efi-*' > "$test_dir/auth/token"
chmod 400 "$test_dir/auth/token"
printf '::add-mask::%s\n' "$(cat "$test_dir/auth/token")"
docker run --rm --network "$network" --entrypoint /bin/attic \
  -v "$test_dir/client:/client:ro" -v "$test_dir/auth:/attic-auth:ro" \
  -e XDG_CONFIG_HOME=/client "$tools_image" cache create builder:efi-nixos
# Same init ordering and mounts as the Helm chart.
docker run --rm --entrypoint /bin/sh -v "$data:/data" \
  -v "$test_dir/config:/config:ro" -e INITIALIZE_STORE=1 "$builder_image" /config/worker.sh
docker run --rm --entrypoint /bin/sh \
  --mount "type=volume,src=$data,dst=/shared-nix,volume-subpath=nix" \
  -v "$bins:/attic-bin" -v "$test_dir/config:/config:ro" "$tools_image" /config/install-attic.sh
docker run --rm --entrypoint /bin/sh -e REGISTER_ATTIC=1 \
  --mount "type=volume,src=$data,dst=/nix,volume-subpath=nix" \
  -v "$bins:/attic-bin:ro" -v "$test_dir/config:/config:ro" "$builder_image" /config/worker.sh
worker=$(docker run -d --network "$network" --network-alias builder --entrypoint /bin/sh \
  --mount "type=volume,src=$data,dst=/nix,volume-subpath=nix" \
  -v "$data:/data" -v "$test_dir/config:/config:ro" \
  -v "$test_dir/config/nix.conf:/etc/nix/nix.conf:ro" \
  -v "$test_dir/keys:/keys:ro" -v "$runtime:/attic-runtime:ro" "$builder_image" /config/worker.sh)
startup_path=$(docker exec "$worker" nix-store --add /config/startup-proof)
start_uploader() {
  uploader=$(docker run -d --network "container:$worker" \
    --mount "type=volume,src=$data,dst=/nix,volume-subpath=nix" \
    -v "$bins:/attic-bin:ro" -v "$runtime:/attic-runtime" \
    -v "$test_dir/auth:/attic-auth:ro" -v "$test_dir/config:/config:ro" \
    -e ATTIC_ENDPOINT=http://attic-server:8080/ -e ATTIC_CACHE=efi-nixos \
    -e ATTIC_JOBS=5 -e DRAIN_TIMEOUT=180 -e RETRY_SECONDS=2 -e CONFIGURE_NIX=true \
    -e SSL_CERT_FILE=/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt \
    "$controller_image" python -u /config/attic-uploader.py)
}
wait_for_cached_path() {
  local hash=${1#/nix/store/}
  hash=${hash%%-*}
  for attempt in $(seq 1 180); do
    if curl --fail --silent --output /dev/null \
      -H "Authorization: Bearer $(cat "$test_dir/auth/token")" "$server_url/efi-nixos/$hash.narinfo"; then
      return 0
    fi
    sleep 1
  done
  printf 'Path was not published: %s\n' "$1" >&2
  return 1
}
start_uploader
wait_for_cached_path "$startup_path"
built_path=$(docker run --rm --network "$network" --entrypoint /bin/sh \
  -v "$test_dir/keys:/keys:ro" \
  -e 'NIX_SSHOPTS=-p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/tmp/known_hosts' \
  "$builder_image" -ec '
    nix --extra-experimental-features "nix-command flakes" build \
      --store "ssh-ng://root@builder?ssh-key=/keys/id_ed25519" \
      --option substituters "" --no-link --print-out-paths --impure \
      --expr '\''derivation { name = "attic-upload-smoke"; system = "x86_64-linux"; builder = "/bin/sh"; args = [ "-c" "echo cached-result > $out" ]; }'\''
  ')
# This is the same blocking drain the proxy invokes before scaling down.
docker exec "$uploader" python /config/attic-uploader.py --drain
wait_for_cached_path "$built_path"
# A new store path created without a watcher must be caught after restart.
docker rm -f "$uploader" >/dev/null
uploader=""
restart_path=$(docker exec "$worker" nix-store --add /config/restart-proof)
start_uploader
wait_for_cached_path "$restart_path"
docker exec "$uploader" python /config/attic-uploader.py --drain
# A fresh Nix client uses the builder's generated substituter/key/netrc config.
download=$(docker run --rm --network "$network" --entrypoint /bin/sh \
  -v "$runtime:/attic-runtime:ro" -e XDG_CONFIG_HOME=/attic-runtime \
  "$builder_image" -ec 'nix-store --realise "$1"; cat "$1"' sh "$built_path")
[[ "${download##*$'\n'}" == cached-result ]]
printf 'Attic startup catch-up, remote publication, restart recovery and signed download verified.\n'
