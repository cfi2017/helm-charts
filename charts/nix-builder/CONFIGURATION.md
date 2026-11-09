# Remote Nix builds over SSH

```sh
kubectl create secret generic builder-keys --from-file=authorized_keys=$HOME/.ssh/id_ed25519.pub
helm install builder ./charts/nix-builder --set ssh.existingSecret=builder-keys
```

Only trusted clients should receive access: SSH is restricted to
`nix-daemon --stdio` (the `ssh-ng` protocol), but that protocol grants full
control of the container's Nix store. Passwords, forwarding and interactive
shells are disabled. The worker runs as root without privileged mode or host
mounts. Nix sandboxing is disabled for compatibility with ordinary Kubernetes
pods; use dedicated nodes/namespaces for isolation of untrusted derivations.
Set worker `resources`, `nodeSelector`, `tolerations` and `affinity` for your
build workload and architecture. The chart does not emulate other architectures.

## Network access

The service listens on port 22 by default. Use a LoadBalancer service or enable
`tcpRoute.enabled` with `tcpRoute.parentRefs` targeting a Gateway TCP listener.
TCPRoute requires the Gateway API experimental CRDs and a controller supporting
TCP routing. Example values:

```yaml
tcpRoute:
  enabled: true
  parentRefs:
    - name: public
      namespace: gateway-system
      sectionName: nix-ssh
```

Configure that Gateway listener with protocol TCP, a dedicated public port, and
allowedRoutes permitting the chart's namespace. SSH has no hostname-based
routing, so this listener cannot share a port with another SSH backend.

For a local smoke test, forward the public Service, not the worker Service:

```sh
kubectl port-forward service/builder-nix-builder 2222:22
```

Retrieve the server's public host key from the worker while it is running, verify
it out of band, and put it in the builder client's known_hosts. The key lives on
the PVC and survives scale-down. For local forwarding its known_hosts name is
`[localhost]:2222`; use your public host/port in production.

```sh
kubectl exec deploy/builder-nix-builder -- cat /data/ssh/ssh_host_ed25519_key.pub
nix store ping --store 'ssh-ng://root@localhost:2222?ssh-key=/absolute/path/to/key'
nix build --impure --expr 'derivation { name = "remote-test"; system = "x86_64-linux"; builder = "/bin/sh"; args = [ "-c" "echo built > $out" ]; }' \
  --builders 'ssh-ng://root@localhost:2222 x86_64-linux /absolute/path/to/key 4 1' --max-jobs 0
```

When the local Nix daemon performs builds, configure its SSH identity and
known_hosts (usually root's), rather than only your interactive user's files.
For persistent configuration, put the builder entry in `/etc/nix/machines`
and set `builders = @/etc/nix/machines` on the client. Use the architecture of
the selected worker node. `ssh://` legacy protocol is not supported.

## Scale to zero

A small, single-replica Python TCP activator stays running. A new connection
patches only this worker Deployment's scale subresource to one replica and
waits up to `scaleToZero.startupTimeoutSeconds` for SSH. The original SSH stream
is forwarded once the worker becomes available. Multiple clients share the
same worker. After the last SSH connection closes, `scaleToZero.idleSeconds`
elapses before the worker scales to zero. Long builds with no output remain
active. TCP readiness probes or external port scanners hitting the public
service count as clients and wake the worker; avoid such probes on that port.

The initial Helm install may briefly start a worker before the first idle
period. The chart omits `spec.replicas` when activation is enabled, so upgrades
do not reset an idle worker. Do not attach an HPA or another replica manager.
The proxy uses Recreate updates to ensure a single connection counter; updating
or restarting it interrupts existing SSH sessions. Cold startup includes image
pulling, PVC attachment and store initialization; increase the startup timeout
and SSH client `ConnectTimeout` for your cluster. A failed startup closes the
client connection; a subsequent client connection retries wake-up.

Set `scaleToZero.enabled=false` to use one always-on worker without proxy or
scaling RBAC. Persistence is enabled by default and retains both the store and
SSH host key while the worker is at zero. Back up the PVC. Disabling persistence
loses the store and changes the host key after every pod replacement.
