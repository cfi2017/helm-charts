#!/usr/bin/env bash
# End-to-end check using the same image, init script and volume layout as the chart.
set -euo pipefail
cd "$(dirname "$0")/../../.."
readonly image=nixos/nix:2.24.14
readonly test_dir=$(mktemp -d)
readonly volume="nix-builder-test-${RANDOM}-$$"
worker=""
cleanup() {
  if [[ -n "$worker" ]]; then docker rm -f "$worker" >/dev/null; fi
  docker volume rm "$volume" >/dev/null
  sudo chown -R "$(id -u):$(id -g)" "$test_dir"
  rm -rf "$test_dir"
}
trap cleanup EXIT
mkdir -p "$test_dir/config" "$test_dir/keys/..projected"
cp charts/nix-builder/files/{worker.sh,sshd_config} "$test_dir/config/"
printf 'sandbox = false\nexperimental-features = nix-command flakes\nsubstituters =\n' > "$test_dir/config/nix.conf"
ssh-keygen -q -t ed25519 -N '' -f "$test_dir/keys/id_ed25519"
cp "$test_dir/keys/id_ed25519.pub" "$test_dir/keys/..projected/authorized_keys"
ln -s ..projected/authorized_keys "$test_dir/keys/authorized_keys"
# Reproduce Kubernetes Secret projection: a 0777 directory, symlinked key and
# root-owned 0400 key file. Direct AuthorizedKeysFile access must reject this.
chmod 755 "$test_dir" "$test_dir/config" "$test_dir/keys/..projected"
chmod 777 "$test_dir/keys"
chmod 400 "$test_dir/keys/..projected/authorized_keys"
sudo chown root:root "$test_dir/keys" "$test_dir/keys/..projected" "$test_dir/keys/..projected/authorized_keys"
docker volume create "$volume" >/dev/null
# Repeat initialization to exercise reuse of a populated store database.
for attempt in 1 2; do
  docker run --rm --entrypoint /bin/sh \
    -v "$test_dir/config:/config:ro" -v "$volume:/data" \
    -e INITIALIZE_STORE=1 "$image" /config/worker.sh
  if [[ "$attempt" == 1 ]]; then
    # Simulate a PVC last used by 0.1.1, whose SSH setup edited store-backed
    # passwd/shadow files. The second initialization must repair image files.
    docker run --rm --entrypoint /bin/sh -v "$volume:/data" "$image" -ec '
      for file in /etc/passwd /etc/shadow; do
        source=$(readlink -f "$file")
        printf "legacy modification\n" >> "/data$source"
      done
    '
  fi
done
base_system=$(docker run --rm --entrypoint /bin/sh "$image" -c 'source=$(readlink -f /etc/passwd); printf "%s" "${source%/etc/passwd}"')
worker=$(docker run -d --entrypoint /bin/sh \
  -v "$test_dir/config:/config:ro" \
  -v "$test_dir/config/nix.conf:/etc/nix/nix.conf:ro" \
  -v "$test_dir/keys:/keys:ro" -v "$volume:/data" \
  --mount "type=volume,src=$volume,dst=/nix,volume-subpath=nix" \
  "$image" /config/worker.sh)
for attempt in $(seq 1 30); do
  if docker exec "$worker" /bin/sh -c 'test -s /run/sshd.pid'; then break; fi
  sleep 1
done
docker exec "$worker" nix-store --verify-path "$base_system"
[[ "$(docker exec "$worker" stat -c '%a' /keys)" == 777 ]]
[[ "$(docker exec "$worker" stat -c '%u:%g:%a' /run/sshd)" == 0:0:700 ]]
[[ "$(docker exec "$worker" stat -c '%u:%g:%a' /run/sshd/authorized_keys)" == 0:0:600 ]]
# Use another Nix container as the client, sharing only the worker's network.
output=$(docker run --rm --network "container:$worker" --entrypoint /bin/sh \
  -v "$test_dir/keys:/keys:ro" \
  -e 'NIX_SSHOPTS=-p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/tmp/known_hosts' \
  "$image" -ec '
    nix --extra-experimental-features "nix-command flakes" build \
      --store "ssh-ng://root@127.0.0.1?ssh-key=/keys/id_ed25519" \
      --option substituters "" --no-link --print-out-paths --impure \
      --expr '\''derivation { name = "remote-smoke"; system = "x86_64-linux"; builder = "/bin/sh"; args = [ "-c" "echo built > $out" ]; }'\''
  ')
[[ "$(docker exec "$worker" cat "$output")" == built ]]
host_key=$(docker exec "$worker" cat /data/ssh/ssh_host_ed25519_key.pub)
docker restart "$worker" >/dev/null
[[ "$(docker exec "$worker" cat /data/ssh/ssh_host_ed25519_key.pub)" == "$host_key" ]]
printf 'Remote build and persistent SSH host key verified.\n'
