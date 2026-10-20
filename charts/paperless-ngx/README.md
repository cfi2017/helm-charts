# paperless-ngx

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 3.3.3](https://img.shields.io/badge/AppVersion-3.3.3-informational?style=flat-square)

A document management system that transforms physical documents into a searchable online archive.

**Homepage:** <https://docs.paperless-ngx.com/>

## Maintainers
This chart is maintained by [cfi2017](https://github.com/cfi2017).

## Source Code

* <https://github.com/paperless-ngx/paperless-ngx>

## Requirements

Kubernetes: `>=1.26.0-0`

| Repository | Name | Version |
|------------|------|---------|
| oci://registry-1.docker.io/cloudpirates | postgresql(postgres) | 0.21.2 |
| oci://registry-1.docker.io/cloudpirates | valkey | 0.14.0 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` |  |
| commonLabels | object | `{}` |  |
| externalBroker.existingSecret | string | `""` |  |
| externalBroker.existingSecretKey | string | `"redis-url"` |  |
| externalDatabase.database | string | `"paperless"` |  |
| externalDatabase.existingSecret | string | `""` |  |
| externalDatabase.host | string | `""` |  |
| externalDatabase.port | int | `5432` |  |
| externalDatabase.secretKeys.database | string | `""` |  |
| externalDatabase.secretKeys.host | string | `""` |  |
| externalDatabase.secretKeys.password | string | `"password"` |  |
| externalDatabase.secretKeys.port | string | `""` |  |
| externalDatabase.secretKeys.username | string | `""` |  |
| externalDatabase.username | string | `"paperless"` |  |
| extraEnv | list | `[]` |  |
| extraEnvFrom | list | `[]` |  |
| extraVolumeMounts | list | `[]` |  |
| extraVolumes | list | `[]` |  |
| fullnameOverride | string | `""` |  |
| httpRoute.annotations | object | `{}` |  |
| httpRoute.enabled | bool | `false` |  |
| httpRoute.hostnames | list | `[]` |  |
| httpRoute.labels | object | `{}` |  |
| httpRoute.parentRefs | list | `[]` |  |
| httpRoute.rules[0].matches[0].path.type | string | `"PathPrefix"` |  |
| httpRoute.rules[0].matches[0].path.value | string | `"/"` |  |
| image.pullPolicy | string | `"IfNotPresent"` |  |
| image.repository | string | `"ghcr.io/paperless-ngx/paperless-ngx"` |  |
| image.tag | string | `""` |  |
| imagePullSecrets | list | `[]` |  |
| livenessProbe.httpGet.path | string | `"/"` |  |
| livenessProbe.httpGet.port | string | `"http"` |  |
| livenessProbe.periodSeconds | int | `30` |  |
| livenessProbe.timeoutSeconds | int | `5` |  |
| nameOverride | string | `""` |  |
| nodeSelector | object | `{}` |  |
| paperless.existingSecret | string | `""` |  |
| paperless.existingSecretKey | string | `"secret-key"` |  |
| paperless.ocrLanguage | string | `"eng"` |  |
| paperless.secretKey | string | `""` |  |
| paperless.timeZone | string | `"UTC"` |  |
| paperless.url | string | `""` |  |
| persistence.consume.accessModes[0] | string | `"ReadWriteOnce"` |  |
| persistence.consume.annotations | object | `{}` |  |
| persistence.consume.enabled | bool | `true` |  |
| persistence.consume.existingClaim | string | `""` |  |
| persistence.consume.labels | object | `{}` |  |
| persistence.consume.size | string | `"5Gi"` |  |
| persistence.consume.storageClass | string | `""` |  |
| persistence.data.accessModes[0] | string | `"ReadWriteOnce"` |  |
| persistence.data.annotations | object | `{}` |  |
| persistence.data.enabled | bool | `true` |  |
| persistence.data.existingClaim | string | `""` |  |
| persistence.data.labels | object | `{}` |  |
| persistence.data.size | string | `"5Gi"` |  |
| persistence.data.storageClass | string | `""` |  |
| persistence.export.accessModes[0] | string | `"ReadWriteOnce"` |  |
| persistence.export.annotations | object | `{}` |  |
| persistence.export.enabled | bool | `true` |  |
| persistence.export.existingClaim | string | `""` |  |
| persistence.export.labels | object | `{}` |  |
| persistence.export.size | string | `"5Gi"` |  |
| persistence.export.storageClass | string | `""` |  |
| persistence.media.accessModes[0] | string | `"ReadWriteOnce"` |  |
| persistence.media.annotations | object | `{}` |  |
| persistence.media.enabled | bool | `true` |  |
| persistence.media.existingClaim | string | `""` |  |
| persistence.media.labels | object | `{}` |  |
| persistence.media.size | string | `"20Gi"` |  |
| persistence.media.storageClass | string | `""` |  |
| podAnnotations | object | `{}` |  |
| podLabels | object | `{}` |  |
| podSecurityContext.fsGroup | int | `1000` |  |
| postgresql.auth.database | string | `"paperless"` |  |
| postgresql.auth.existingSecret | string | `""` |  |
| postgresql.auth.password | string | `""` |  |
| postgresql.auth.secretKeys.adminPasswordKey | string | `"postgres-password"` |  |
| postgresql.auth.username | string | `"paperless"` |  |
| postgresql.enabled | bool | `true` |  |
| postgresql.persistence.enabled | bool | `true` |  |
| postgresql.persistence.labels | object | `{}` |  |
| postgresql.persistence.size | string | `"8Gi"` |  |
| readinessProbe.httpGet.path | string | `"/"` |  |
| readinessProbe.httpGet.port | string | `"http"` |  |
| readinessProbe.periodSeconds | int | `10` |  |
| readinessProbe.timeoutSeconds | int | `5` |  |
| replicaCount | int | `1` |  |
| resources | object | `{}` |  |
| securityContext | object | `{}` |  |
| service.annotations | object | `{}` |  |
| service.port | int | `8000` |  |
| service.type | string | `"ClusterIP"` |  |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.create | bool | `true` |  |
| serviceAccount.name | string | `""` |  |
| startupProbe.failureThreshold | int | `60` |  |
| startupProbe.httpGet.path | string | `"/"` |  |
| startupProbe.httpGet.port | string | `"http"` |  |
| startupProbe.periodSeconds | int | `10` |  |
| strategy.type | string | `"Recreate"` |  |
| tolerations | list | `[]` |  |
| valkey.architecture | string | `"standalone"` |  |
| valkey.auth.enabled | bool | `false` |  |
| valkey.config.maxMemoryPolicy | string | `"noeviction"` |  |
| valkey.enabled | bool | `true` |  |
| valkey.persistence.enabled | bool | `true` |  |
| valkey.persistence.labels | object | `{}` |  |
| valkey.persistence.size | string | `"1Gi"` |  |

## License

This Helm chart is free software: you can redistribute it and/or modify it under the terms
of the GNU Affero General Public License as published by the Free Software Foundation,
version 3 of the License.

----------------------------------------------
Autogenerated from chart metadata using [helm-docs](https://github.com/norwoodj/helm-docs/)
