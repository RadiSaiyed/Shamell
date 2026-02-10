FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_HOST=0.0.0.0 \
    APP_PORT=8080

WORKDIR /app

# System dependencies (build tools, fonts for PDF/QR rendering, etc.)
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential gcc \
        fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

# Run as a non-root user at runtime (defense-in-depth).
RUN groupadd --gid 10001 app && \
    useradd --uid 10001 --gid 10001 --create-home --home-dir /home/app --shell /usr/sbin/nologin app

# Python dependencies shared by BFF + domain services.
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

# Install shared library package (expects build context at repo root)
COPY --chown=app:app libs/shamell_shared/python /app/libs/shamell_shared/python
RUN pip install --no-cache-dir /app/libs/shamell_shared/python

# Copy all backend app code (BFF + domain services)
COPY --chown=app:app apps /app/apps

USER app:app

EXPOSE 8080

# Default to the BFF; docker-compose overrides this per-service.
CMD ["uvicorn", "apps.bff.app.main:app", "--host", "0.0.0.0", "--port", "8080"]

