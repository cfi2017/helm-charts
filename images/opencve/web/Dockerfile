FROM python:3.12-slim-trixie AS base

FROM base AS builder

ARG OPENCVE_REPOSITORY="https://github.com/opencve/opencve.git"
ARG OPENCVE_VERSION="v3.0.0"

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN git clone --depth 1 -b "${OPENCVE_VERSION}" --single-branch "${OPENCVE_REPOSITORY}"

RUN python3 -m venv /app/venv

ENV PATH="/app/venv/bin:$PATH"

RUN python3 -m pip install --upgrade pip

RUN python3 -m pip install -r opencve/web/requirements.txt

FROM base

ARG OPENCVE_REPOSITORY="https://github.com/opencve/opencve.git"
ARG OPENCVE_VERSION="v3.0.0"
ARG GUNICORN_CMD_ARGS

LABEL name="opencve-web"
LABEL maintainer="info@swiss.dev"
LABEL org.opencontainers.image.source="${OPENCVE_REPOSITORY}"

COPY --from=builder /app/venv /app/venv
COPY --from=builder /app/opencve/web /app/opencve/web

ENV PATH="/app/venv/bin:$PATH"
ENV GUNICORN_CMD_ARGS="${GUNICORN_CMD_ARGS}"
ENV OPENCVE_VERSION="${OPENCVE_VERSION}"

WORKDIR /app/opencve/web/

EXPOSE 8000

ENTRYPOINT ["gunicorn", "opencve.wsgi"]
CMD ["-b", "0.0.0.0:8000"]
