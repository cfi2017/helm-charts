# Deploying Paperless-ngx

```sh
helm dependency build charts/paperless-ngx
helm upgrade --install paperless charts/paperless-ngx \
  --namespace paperless --create-namespace -f values.yaml
```

The chart includes standalone Valkey and PostgreSQL, with persistent storage for
both dependencies and Paperless's data, media, consume and export directories.
Dependency versions are pinned in `Chart.lock` and packaged in `charts/`.

Set `paperless.url` to the public origin, including `https://`. The upstream
container starts as root to prepare storage and runs application processes as
its `paperless` user (UID/GID 1000). Adjust security contexts only with an
understanding of the image's initialization requirements.

Create an administrator with the upstream management command:

```sh
kubectl exec -n paperless deploy/paperless-paperless-ngx -- \
  python3 manage.py createsuperuser
```

Alternatively supply `PAPERLESS_ADMIN_USER` and `PAPERLESS_ADMIN_PASSWORD` using
`extraEnv` with `valueFrom.secretKeyRef`. Arbitrary Paperless configuration can
be supplied through `extraEnv` or `extraEnvFrom`.

## Existing PostgreSQL database

Create a Secret in the release namespace using your secret management tool:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: paperless-db
type: Opaque
stringData:
  host: postgres.database.svc
  port: "5432"
  database: paperless
  username: paperless
  password: REPLACE_ME
```

Then configure:

```yaml
postgresql:
  enabled: false
externalDatabase:
  existingSecret: paperless-db
  secretKeys:
    host: host
    port: port
    database: database
    username: username
    password: password
```

Only the password key is mandatory. Omit other `secretKeys` entries to use the
corresponding `externalDatabase.host`, `port`, `database` and `username` values.
The database must exist, and the user needs permission to run migrations.
For database TLS, supply Paperless's `PAPERLESS_DBSSLMODE` and related options
through `extraEnv`.

For bundled PostgreSQL with a pre-created password Secret, set
`postgresql.auth.existingSecret` and
`postgresql.auth.secretKeys.adminPasswordKey`. The app and database use the same
Secret reference. Otherwise PostgreSQL generates a random password and reuses it
on upgrades. Back up database credentials with the database; do not rotate them
by changing values alone against an initialized database volume.

## Signing key and broker credentials

The chart generates a Django signing key and preserves it using Helm's `lookup`
on upgrades. For GitOps/offline rendering, configure `paperless.existingSecret`
and `paperless.existingSecretKey` to provide a stable signing key. Otherwise
repeated offline renders generate new keys. Set `paperless.secretKey` only when
storing it in Helm release values is acceptable. Restart pods after changing
referenced secrets.

Bundled Valkey defaults to an unauthenticated ClusterIP service. Restrict access
using your cluster's network policies. To enable authentication, configure
`valkey.auth.existingSecret` / `existingSecretPasswordKey` and provide
`externalBroker.existingSecret` with a complete matching `redis://` URL under
`externalBroker.existingSecretKey` (default `redis-url`). URL-encode credentials.
For an external broker set `valkey.enabled: false` and use the same URL Secret
interface. TLS and replication also require an explicit broker URL. Sentinel
requires additional application-specific configuration.

## Storage and labels

Each `persistence.{data,media,consume,export}` entry supports `labels`,
`annotations`, `storageClass`, `accessModes`, `size` and `existingClaim`.
`storageClass: ""` uses the cluster default; `storageClass: "-"` requests no class.
`enabled: false` uses ephemeral `emptyDir` unless `existingClaim` is supplied.
Existing claims are mounted without being created or relabeled by this chart.

```yaml
persistence:
  media:
    size: 100Gi
    labels:
      backup: daily
  data:
    labels:
      backup: daily
postgresql:
  persistence:
    labels:
      backup: daily
valkey:
  persistence:
    labels:
      backup: daily
```

Keep the default single replica and `Recreate` strategy with ReadWriteOnce
storage. Increasing replicas runs additional consumers/schedulers and requires
shared storage and deliberate application configuration. Back up the database,
media and data together. Helm uninstall deletes chart-managed PVCs; set
`annotations: {helm.sh/resource-policy: keep}` on application claims, or use
existing claims, when they must outlive the release. Dependency PVC lifecycle
follows each dependency's StatefulSet retention settings.

## Gateway API

Install Gateway API v1 CRDs and a compatible controller first. The chart creates
an HTTPRoute attached to an existing Gateway; TLS certificates and HTTPS
listeners are configured on that Gateway.

```yaml
paperless:
  url: https://paperless.example.com
httpRoute:
  enabled: true
  parentRefs:
    - name: public
      namespace: gateways
      sectionName: https
  hostnames:
    - paperless.example.com
```

The Gateway must permit routes from the release namespace. `httpRoute.rules`
supports `matches` and `filters`; each rule forwards to the Paperless Service's
configured port. Route labels and annotations are configurable. Configure the
controller's upload limits and timeouts for large documents, and forwarded
headers according to Paperless's reverse proxy documentation.

## Validation

```sh
helm lint --strict charts/paperless-ngx
helm unittest charts/paperless-ngx
helm template paperless charts/paperless-ngx
```

Pull requests affecting this chart run `.github/workflows/paperless-ngx.yaml`.
It builds locked dependencies, runs lint and unit tests, and installs the chart
in kind twice: once with bundled services and once with separately installed
PostgreSQL/Valkey and connection Secrets. Both scenarios create an HTTPRoute and
run `helm test` against the application Service. Gateway route acceptance and
HTTPS traffic require a controller and are not covered by this test.

The same integration workflow gates chart releases on `main`. The existing
chart-releaser workflow publishes versioned packages and the Helm repository
index on `gh-pages`; no separate Paperless image build is needed because the
chart uses the upstream image. The repository needs GitHub Pages configured to
serve `gh-pages`, and its Actions token must be permitted to write contents.

To reproduce the integration checks against a disposable cluster with Gateway
API v1.2.1 standard CRDs installed:

```sh
hack/ci/paperless-ngx.sh bundled
# Use a fresh cluster (or delete the paperless-ci namespace) between scenarios.
hack/ci/paperless-ngx.sh external
```
