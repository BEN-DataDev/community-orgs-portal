FROM python:3.12-slim@sha256:57cd7c3a7a273101a6485ba99423ee568157882804b1124b4dd04266317710de
RUN apt-get update && apt-get install -y --no-install-recommends postgresql-client ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY python/ingestion /app/ingestion
COPY deploy/poll-worker.sh /app/poll-worker.sh
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PGCONNECT_TIMEOUT=10
USER 1000:1000
ENTRYPOINT ["/bin/sh", "/app/poll-worker.sh"]
