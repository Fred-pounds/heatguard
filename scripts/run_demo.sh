#!/usr/bin/env bash
# One-command local demo: builds the dashboard (if Flutter is available and no build exists)
# and starts the backend, which serves both the API and the dashboard on one port.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-8000}"

if [ ! -f "$ROOT/frontend/build/web/index.html" ]; then
  if command -v flutter >/dev/null 2>&1; then
    echo "Building Flutter Web dashboard..."
    (cd "$ROOT/frontend" && flutter pub get && flutter build web --release --no-web-resources-cdn \
      --dart-define=API_BASE_URL="http://localhost:${PORT}/api")
  else
    echo "Flutter not found: the API will run, but the dashboard must be built separately (see README)."
  fi
fi

cd "$ROOT/backend"
python3 -m pip install -q -r requirements.txt
echo "HeatGuard running at http://localhost:${PORT}  (worker view: http://localhost:${PORT}/#/worker)"
exec python3 -m uvicorn app.main:app --host 0.0.0.0 --port "$PORT"
