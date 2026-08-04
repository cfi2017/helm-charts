FROM apache/airflow:slim-2.10.4-python3.12 AS builder

USER root

RUN apt-get update \
    && ACCEPT_EULA=Y apt-get install -y --no-install-recommends \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ARG OPENCVE_REPOSITORY="https://github.com/opencve/opencve.git"
ARG OPENCVE_VERSION="v3.0.0"

RUN git clone --depth 1 -b "${OPENCVE_VERSION}" --single-branch "${OPENCVE_REPOSITORY}"

FROM apache/airflow:slim-2.10.4-python3.12

USER root

RUN apt-get update \
    && ACCEPT_EULA=Y apt-get install -y --no-install-recommends \
    git \
    && rm -rf /var/lib/apt/lists/*

ARG OPENCVE_REPOSITORY="https://github.com/opencve/opencve.git"
ARG OPENCVE_VERSION="v3.0.0"

LABEL name="opencve-scheduler"
LABEL maintainer="info@swiss.dev"
LABEL org.opencontainers.image.source="${OPENCVE_REPOSITORY}"

ENV OPENCVE_VERSION="${OPENCVE_VERSION}"

COPY --from=builder --chown=airflow:root /app/opencve/scheduler/dags/ /opt/airflow/dags/
COPY --from=builder --chown=airflow:root /app/opencve/scheduler/requirements.txt /requirements.txt

USER airflow

RUN mkdir -p /home/airflow/repositories \
    && pip install --no-cache-dir -r /requirements.txt
