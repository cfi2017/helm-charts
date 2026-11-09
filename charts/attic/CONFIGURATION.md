# Attic Nix binary cache

By default the chart generates a signing key and reuses it on upgrades via
Helm lookup. For GitOps rendering or a key managed outside Helm, use an existing
Secret (recommended) as follows. Back it up before uninstalling the release.

Create a stable signing secret before installation (do not commit the key):

```sh
openssl genrsa -traditional -out attic-key.pem 4096
kubectl create secret generic attic-auth \
  --from-literal=token-rs256-secret-base64="$(base64 < attic-key.pem | tr -d '\n')"
helm install attic ./charts/attic --set auth.existingSecret=attic-auth
```

The image uses Attic's upstream `latest` tag because upstream has no tagged
releases. Pin `image.tag` to a tested upstream commit for production.
The default single replica uses SQLite and local storage on a PVC. Recreate
updates avoid concurrent SQLite writers and ReadWriteOnce mount conflicts.
Disabling persistence loses the database and cache on pod replacement.

For production, replace `config` with upstream Attic TOML, set `allowed-hosts`
and `api-endpoint` (with a trailing slash), and use an external PostgreSQL
database and/or S3 storage. Supply `ATTIC_SERVER_DATABASE_URL`,
`AWS_ACCESS_KEY_ID`, and `AWS_SECRET_ACCESS_KEY` via `envFrom` Secret references.
Keep the listen port at 8080. See https://docs.attic.rs/ for all settings.

Enable `httpRoute.enabled`, configure `parentRefs` and `hostnames`, and provide
a Gateway with TLS termination. Gateway API CRDs and a controller must already
be installed. Restrict access to trusted users until authentication is configured.

Generate an admin token using the running server's mounted configuration:

```sh
kubectl exec deploy/attic -- atticadm -f /config/server.toml \
  make-token --sub admin --validity '1y' --pull '*' --push '*' \
  --create-cache '*' --configure-cache '*' --configure-cache-retention '*' --destroy-cache '*'
attic login local https://cache.example.com TOKEN
attic cache create local:main
attic push local:main ./result
attic use local:main
```

The JWT signing secret is distinct from each cache's Nix signing key, which
Attic manages in its database. Back up both the PVC and authentication Secret.
