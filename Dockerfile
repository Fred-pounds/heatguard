# HeatGuard: API + prebuilt dashboard (/) + worker app (/worker/) in one container (simulated data, local JSON store by default).
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PORT=8000 \
    HEATGUARD_STORAGE=local HEATGUARD_SIM_AUTOSTART=true
WORKDIR /app

COPY backend/requirements.txt backend/requirements.txt
RUN pip install --no-cache-dir -r backend/requirements.txt

COPY backend/app backend/app
COPY simulator simulator
COPY frontend/dist frontend/dist
COPY worker_app/dist worker_app/dist

RUN useradd --create-home heatguard && mkdir -p backend/data && chown -R heatguard /app
USER heatguard
WORKDIR /app/backend
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s CMD python -c "import urllib.request,os; urllib.request.urlopen(f'http://127.0.0.1:{os.environ[\"PORT\"]}/api/health')"
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT}"]
