{{/*
Expand the name of the chart.
*/}}
{{- define "midpoint.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "midpoint.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "midpoint.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "midpoint.labels" -}}
helm.sh/chart: {{ include "midpoint.chart" . }}
{{ include "midpoint.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "midpoint.selectorLabels" -}}
app.kubernetes.io/name: {{ include "midpoint.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "midpoint.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "midpoint.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Name of the secret containing admin password and (optionally) db password
*/}}
{{- define "midpoint.secretName" -}}
{{- if .Values.midpoint.existingSecret }}
{{- .Values.midpoint.existingSecret }}
{{- else }}
{{- include "midpoint.fullname" . }}
{{- end }}
{{- end }}

{{/*
PostgreSQL host
*/}}
{{- define "midpoint.postgresql.host" -}}
{{- if .Values.postgresql.enabled }}
{{- printf "%s-postgresql" .Release.Name }}
{{- else }}
{{- .Values.externalDatabase.host }}
{{- end }}
{{- end }}

{{/*
PostgreSQL port
*/}}
{{- define "midpoint.postgresql.port" -}}
{{- if .Values.postgresql.enabled }}
{{- print "5432" }}
{{- else }}
{{- .Values.externalDatabase.port | toString }}
{{- end }}
{{- end }}

{{/*
PostgreSQL database name
*/}}
{{- define "midpoint.postgresql.database" -}}
{{- if .Values.postgresql.enabled }}
{{- .Values.postgresql.auth.database }}
{{- else }}
{{- .Values.externalDatabase.database }}
{{- end }}
{{- end }}

{{/*
PostgreSQL username
*/}}
{{- define "midpoint.postgresql.username" -}}
{{- if .Values.postgresql.enabled }}
{{- .Values.postgresql.auth.username }}
{{- else }}
{{- .Values.externalDatabase.username }}
{{- end }}
{{- end }}

{{/*
Name of the secret containing the database password
*/}}
{{- define "midpoint.postgresql.secretName" -}}
{{- if .Values.midpoint.existingSecret }}
{{- .Values.midpoint.existingSecret }}
{{- else if .Values.postgresql.enabled }}
{{- if .Values.postgresql.auth.existingSecret }}
{{- .Values.postgresql.auth.existingSecret }}
{{- else }}
{{- include "midpoint.fullname" . }}
{{- end }}
{{- else }}
{{- if .Values.externalDatabase.existingSecret }}
{{- .Values.externalDatabase.existingSecret }}
{{- else }}
{{- include "midpoint.fullname" . }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Key within the database password secret
*/}}
{{- define "midpoint.postgresql.secretKey" -}}
{{- if .Values.midpoint.existingSecret }}
{{- .Values.midpoint.existingSecretKeys.databasePassword }}
{{- else if .Values.postgresql.enabled }}
{{- if .Values.postgresql.auth.existingSecret }}
{{- .Values.postgresql.auth.secretKeys.adminPasswordKey }}
{{- else }}
{{- print "database-password" }}
{{- end }}
{{- else }}
{{- if .Values.externalDatabase.existingSecret }}
{{- .Values.externalDatabase.existingSecretPasswordKey }}
{{- else }}
{{- print "database-password" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
JDBC URL for the MidPoint repository
*/}}
{{- define "midpoint.jdbcUrl" -}}
{{- printf "jdbc:postgresql://%s:%s/%s" (include "midpoint.postgresql.host" .) (include "midpoint.postgresql.port" .) (include "midpoint.postgresql.database" .) }}
{{- end }}

{{/*
Return the midpoint image reference
*/}}
{{- define "midpoint.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end }}
