# cfi2017 Helm Charts

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/cfi2017)](https://artifacthub.io/packages/search?repo=cfi2017)
![Release Charts](https://github.com/cfi2017/helm-charts/workflows/Release%20Charts/badge.svg)
[![pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit&logoColor=white)](https://github.com/pre-commit/pre-commit)

![Lunkwill wearing a Helm shirt](docs/images/lunkwill_helm_shirt.png)

This repository contains [Helm](https://helm.sh/) charts managed by [cfi2017](https://github.com/cfi2017).

## Usage

### Install the Helm chart repository

```bash
helm repo add cfi2017 https://cfi2017.github.io/helm-charts
```

To make the charts available in the OpenShift console:

```bash
oc apply -f https://cfi2017.github.io/helm-charts/cfi2017-charts-repo.yaml
```

### Available Helm charts

#### Argo CD app-of-apps charts

Our [Argo CD](https://argoproj.github.io/cd/) app-of-apps Helm charts all implement the [Argo CD app-of-apps pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/#app-of-apps-pattern).
The charts deploy Argo CD Application resources and enable configuring multiple related or "work well together" apps.
To do this they combine Helm repository URLs with chart names and "tested" versions of the charts. In most cases some
examples of how to configure individual apps are also provided. Please reference [our app-of-apps documentation](./docs/argocd-app-of-apps.md)
for more in-depth information.

| Chart | Description | Version |
| ----- | ----------- | ------- |

#### more charts

| Chart | Description | Version | App Version |
| ----- | ----------- | ------- | ----------- |

## Contributing


This Helm chart repositories code may be found on [GitHub](https://github.com) at
[cfi2017/helm-charts](https://github.com/cfi2017/helm-charts).

We track issues with this chart repository in the [issue tracker](https://github.com/cfi2017/helm-charts/issues).

We expect you to always create an issue prior to creating a new chart. This helps us discuss the merits of it before you put the effort into creating the chart.

## License

This Helm chart collection is free software: you can redistribute it and/or modify it under the terms
of the GNU Affero General Public License as published by the Free Software Foundation,
version 3 of the License.
