#!/usr/bin/env bash
# Run against an existing disposable cluster with Gateway API CRDs installed.
set -euo pipefail

scenario=${1:-bundled}
case "$scenario" in
  bundled|external) ;;
  *) echo "Usage: $0 [bundled|external]" >&2; exit 2 ;;
esac

chart=charts/paperless-ngx
namespace=paperless-ci
kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -

# Enable an HTTPRoute to exercise its API validation. A Gateway controller is
# unnecessary for the in-cluster service test; route acceptance isn't tested.
route_values=$(mktemp)
trap 'rm -f "$route_values"' EXIT
cat > "$route_values" <<'VALUES'
httpRoute:
  enabled: true
  parentRefs:
    - name: ci-gateway
  hostnames: [paperless.example.test]
VALUES

args=()
if [[ "$scenario" == external ]]; then
  # CI-only credentials, shared with a separately installed database release.
  kubectl create secret generic external-db -n "$namespace" \
    --from-literal=host=external-postgres \
    --from-literal=port=5432 \
    --from-literal=database=paperless \
    --from-literal=username=paperless \
    --from-literal=password=paperless-ci-password \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret generic external-broker -n "$namespace" \
    --from-literal=redis-url=redis://external-valkey:6379/0 \
    --dry-run=client -o yaml | kubectl apply -f -
  helm upgrade --install external-postgres "$chart"/charts/postgres-*.tgz \
    -n "$namespace" --wait --timeout 5m \
    --set auth.username=paperless --set auth.database=paperless \
    --set auth.existingSecret=external-db --set auth.secretKeys.adminPasswordKey=password \
    --set persistence.size=1Gi
  helm upgrade --install external-valkey "$chart"/charts/valkey-*.tgz \
    -n "$namespace" --wait --timeout 5m \
    --set auth.enabled=false --set persistence.size=1Gi
  args+=(
    --set postgresql.enabled=false
    --set valkey.enabled=false
    --set externalDatabase.existingSecret=external-db
    --set externalDatabase.secretKeys.host=host
    --set externalDatabase.secretKeys.port=port
    --set externalDatabase.secretKeys.database=database
    --set externalDatabase.secretKeys.username=username
    --set externalDatabase.secretKeys.password=password
    --set externalBroker.existingSecret=external-broker
  )
fi

helm upgrade --install paperless "$chart" -n "$namespace" \
  -f "$chart/ci/ct-values.yaml" -f "$route_values" "${args[@]}" \
  --wait --timeout 10m
kubectl get httproute paperless-paperless-ngx -n "$namespace"
helm test paperless -n "$namespace" --logs --timeout 2m
