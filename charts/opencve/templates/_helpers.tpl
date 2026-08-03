{{/*
Expand the name of the chart.
*/}}
{{- define "opencve.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "opencve.fullname" -}}
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
{{- define "opencve.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "opencve.labels" -}}
helm.sh/chart: {{ include "opencve.chart" . }}
{{ include "opencve.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "opencve.selectorLabels" -}}
app.kubernetes.io/name: {{ include "opencve.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "opencve.componentLabels" -}}
{{ include "opencve.labels" .root }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "opencve.componentSelectorLabels" -}}
{{ include "opencve.selectorLabels" .root }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Create the name of the service account to use.
*/}}
{{- define "opencve.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "opencve.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "opencve.web.image" -}}
{{- $tag := .Values.web.image.tag | default .Chart.AppVersion -}}
{{- printf "%s:%s" .Values.web.image.repository $tag -}}
{{- end }}

{{- define "opencve.secretName" -}}
{{- if or .Values.opencve.existingSecret .Values.database.existingSecret }}
{{- include "opencve.fullname" . }}
{{- else }}
{{- include "opencve.fullname" . }}
{{- end }}
{{- end }}

{{- define "opencve.opencveSecretName" -}}
{{- .Values.opencve.existingSecret | default (include "opencve.fullname" .) }}
{{- end }}

{{- define "opencve.databaseSecretName" -}}
{{- .Values.database.existingSecret | default (include "opencve.fullname" .) }}
{{- end }}

{{- define "opencve.postgresql.host" -}}
{{- if .Values.postgresql.enabled }}
{{- printf "%s-postgresql" .Release.Name }}
{{- else }}
{{- required "externalDatabase.host is required when postgresql.enabled=false" .Values.externalDatabase.host }}
{{- end }}
{{- end }}

{{- define "opencve.postgresql.port" -}}
{{- if .Values.postgresql.enabled }}5432{{ else }}{{ .Values.externalDatabase.port }}{{ end }}
{{- end }}

{{- define "opencve.postgresql.database" -}}
{{- if .Values.postgresql.enabled }}{{ .Values.postgresql.auth.database }}{{ else }}{{ .Values.externalDatabase.database }}{{ end }}
{{- end }}

{{- define "opencve.postgresql.username" -}}
{{- if .Values.postgresql.enabled }}{{ .Values.postgresql.auth.username }}{{ else }}{{ .Values.externalDatabase.username }}{{ end }}
{{- end }}

{{- define "opencve.postgresql.password" -}}
{{- if .Values.postgresql.enabled }}{{ .Values.postgresql.auth.password }}{{ else }}{{ .Values.externalDatabase.password }}{{ end }}
{{- end }}

{{- define "opencve.databaseUrl" -}}
{{- printf "postgresql://%s:%s@%s:%s/%s" (include "opencve.postgresql.username" .) (include "opencve.postgresql.password" .) (include "opencve.postgresql.host" .) (include "opencve.postgresql.port" .) (include "opencve.postgresql.database" .) }}
{{- end }}

{{- define "opencve.repositories.claimName" -}}
{{- .Values.opencve.repositories.persistence.existingClaim | default (printf "%s-repositories" (include "opencve.airflowReleaseFullname" .)) }}
{{- end }}

{{- define "opencve.airflowReleaseFullname" -}}
{{- if contains "opencve" .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-opencve" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end }}

{{- define "opencve.airflow.webserverServiceName" -}}
{{- printf "%s-webserver" .Release.Name }}
{{- end }}
