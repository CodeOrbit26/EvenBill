# Production Hardened Multi-Stage Dockerfile for EvenBill Backend
# Builder Stage
FROM python:3.11-slim AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Final Minimal Runtime Stage
FROM python:3.11-slim AS runner

WORKDIR /app

# Install curl for container orchestration health checks
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create dedicated non-root user and group
RUN groupadd -g 10001 evenbill && \
    useradd -u 10001 -g evenbill -s /bin/bash -m evenbill

# Copy installed dependencies from builder
COPY --from=builder /install /usr/local

# Copy application code with proper ownership
COPY --chown=evenbill:evenbill . /app

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    ENVIRONMENT=production \
    PORT=8000

# Drop root privileges
USER evenbill

# Expose internal port
EXPOSE 8000

# Orchestrator container healthcheck
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8000/health/live || exit 1

# Production WSGI/ASGI entrypoint: run migrations then start uvicorn
CMD ["sh", "-c", "alembic upgrade head && exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --workers 4 --proxy-headers --forwarded-allow-ips=*"]
