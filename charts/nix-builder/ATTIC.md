# Attic publication and downloads

The optional uploader watches the builder's `/nix/store`, publishes new paths
with `attic watch-store`, and catches up on retained paths after startup. The
worker and uploader share the same Nix store volume. Keep persistence enabled
so a crash or interrupted upload can be recovered on the next startup.
Periodic catch-up also reconciles missed watcher events and failed queued paths;
`attic.catchUpIntervalSeconds` defaults to 300 seconds. Failed attempts retry
after `attic.retrySeconds` (30 seconds by default).

## Configure an existing cache and token

Create the cache on your Attic server before enabling the uploader. For example,
using an administrator's Attic client:

```sh
attic cache create efi:efi-nixos
```

Give the builder a token with pull and push access to that cache, and store it
in the builder's namespace:

```sh
kubectl create secret generic nix-builder-attic \
  --namespace builders --from-literal=token="$ATTIC_UPLOAD_TOKEN"
```

`efi-nixos` is the concrete destination cache. A permission pattern such as
`efi-*` can appear in the token's claims, but cannot be an upload destination.
The chart rejects wildcard cache names. It neither creates the cache nor issues
tokens, and never stores the token in a ConfigMap, Helm value or Nix store path.

Example Helm values:

```yaml
attic:
  enabled: true
  endpoint: https://cache.example.com/
  cache: efi-nixos
  auth:
    existingSecret: nix-builder-attic
    secretKey: token
  configureNix: true
  jobs: 5
  drainTimeoutSeconds: 600
```

Install or upgrade the builder with these values. `attic.enabled` defaults to
false, so existing installations keep their current behavior.
When upgrading an existing release, merge the new chart defaults with your
previous values so all new uploader settings get their defaults:

```sh
helm upgrade builder cfi2017/nix-builder --namespace builders \
  --reset-then-reuse-values --wait --timeout 15m -f values-attic.yaml
```

The tools image is `nixpkgs/attic:nixos-26.05-x86_64-linux`, which contains the
Attic client. On ARM64 nodes, set `attic.toolsImage.tag` to
`nixos-26.05-aarch64-linux`. The uploader runs in a Python container after init
containers copy and register the Attic runtime closure in the shared store.
Those runtime paths are protected by GC roots. No package downloads or image
builds are needed inside a running worker.

Upgrades from `0.1.1` also restore the image-owned `passwd` and `shadow` files
that earlier SSH setup could modify inside the store. SSH account changes now
live outside `/nix/store`, keeping the registered NAR hashes valid for uploads.

## Downloads on the builder

With `attic.configureNix: true`, the uploader runs `attic use` to discover the
cache's substituter URL and public signing key. It publishes a private netrc
and an atomic Nix configuration file in a shared runtime volume. The builder
includes that file and extends its existing substituters and trusted keys.
The access token stays outside `/nix`, and the builder's mount is read-only.
Set `attic.configureNix: false` for upload-only operation.

If the cache is unavailable at startup, the builder can still accept builds.
The uploader retries catch-up, and the worker stays running until a final push
succeeds. Cache configuration becomes available when Attic can be contacted.

## Upload-aware scale to zero

After the last SSH session closes and `scaleToZero.idleSeconds` elapses:

1. The proxy asks the uploader to drain. The uploader stops its watcher and
   pushes a snapshot of all valid store paths with `attic push --stdin`.
2. A successful push acknowledges completion. Only then may the proxy set the
   worker's replica count to zero.
3. An upload error or timeout keeps the worker running and resumes the watcher.
   Catch-up and later scale-down attempts retry automatically.

New SSH sessions can proceed during uploads. Any new session cancels that
scale-down attempt, even if it closes before the drain finishes. The watcher
resumes and a later drain takes a fresh snapshot, covering paths created while
watching was paused. Long-lived SSH sessions always keep the worker running.

Catch-up includes pre-existing store paths and intermediate build dependencies,
not only top-level outputs. Attic applies its usual already-cached and upstream
filtering. A large retained store may need a longer `attic.drainTimeoutSeconds`
than the default 600 seconds. A failed cache keeps the worker running, rather
than losing queued uploads to an automatic scale-down.

The internal control API requires a credential derived from the mounted token.
The proxy also mounts the token Secret read-only for that purpose and reads it
on each call. Health probes do not upload anything or wake stopped workers.
The proxy only reads and patches this worker's scale subresource.

A pre-stop hook also attempts a drain for normal pod termination. The worker's
termination grace period is at least the drain timeout plus 30 seconds. A
previously completed drain is acknowledged immediately. Manual restarts,
evictions and node loss can still interrupt builds or uploads; startup catch-up
recovers valid paths retained on the PVC. An ephemeral store cannot recover
paths lost to an abrupt pod replacement.

After rotating the token Secret, restart the worker while idle to refresh its
watcher and download credentials. The proxy rereads its projected Secret; while
Secret updates are propagating, a control authentication failure prevents
scale-down. Cache access is intended for trusted builder clients, like the SSH
builder itself. Use a token limited to the required caches.

## Downloads on a laptop

Use a separate pull-only token on laptops:

```sh
attic login efi https://cache.example.com/ "$ATTIC_PULL_TOKEN"
attic use efi:efi-nixos
```

This configures the current user's Nix cache settings and private netrc. For a
multi-user Nix installation, configure the daemon's system settings as well,
using the URL and public key printed by `attic use`:

```ini
extra-substituters = https://cache.example.com/efi-nixos
extra-trusted-public-keys = efi-nixos:<public-key-from-attic>
netrc-file = /etc/nix/attic.netrc
builders-use-substitutes = true
```

For a private cache, supply the pull token in the daemon's netrc, readable only
by root (`0600`), and restart the Nix daemon after changing system settings:

```text
machine cache.example.com password YOUR_PULL_ONLY_TOKEN
```

On NixOS, manage that netrc through a runtime Secret mechanism; do not embed
its contents in a Nix expression that would copy the token into `/nix/store`.
`builders-use-substitutes` lets remote builders obtain inputs from configured
caches. With the laptop's cache configured, cached outputs download locally;
missing outputs build remotely and are published for later builds.
