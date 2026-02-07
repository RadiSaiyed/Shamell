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

# Install Python dependencies for the monolith
COPY apps/monolith/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

# Install shared library package (expects build context at repo root)
COPY libs/shamell_shared/python /app/libs/shamell_shared/python
RUN pip install --no-cache-dir /app/libs/shamell_shared/python

# Copy all backend app code (BFF + domain services + monolith)
COPY apps /app/apps

EXPOSE 8080

CMD ["uvicorn", "apps.monolith.app.main:app", "--host", "0.0.0.0", "--port", "8080"]
