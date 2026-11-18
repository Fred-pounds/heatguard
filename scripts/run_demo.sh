#!/usr/bin/env bash
# One-command local demo: builds the dashboard (if Flutter is available and no build exists)
# and starts the backend, which serves both the API and the dashboard on one port.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-8000}"

if [ ! -f "$ROOT/frontend/build/web/index.html" ] && [ ! -f "$ROOT/frontend/dist/index.html" ]; then
  if command -v flutter >/dev/null 2>&1; then
    echo "Building Flutter Web dashboard..."
    (cd "$ROOT/frontend" && flutter pub get && flutter build web --release --no-web-resources-cdn \
      --dart-define=API_BASE_URL="http://localhost:${PORT}/api")
  else
    echo "Flutter not found: the API will run, but the dashboard must be built separately (see README)."
  fi
fi

cd "$ROOT/backend"
if command -v uv >/dev/null 2>&1; then
  # uv-managed virtual environments have no pip; install into the active venv (or backend/.venv).
  [ -n "${VIRTUAL_ENV:-}" ] || [ -d .venv ] || uv venv -q .venv
  [ -n "${VIRTUAL_ENV:-}" ] || source .venv/bin/activate
  uv pip install -q -r requirements.txt
elif python3 -m pip --version >/dev/null 2>&1; then
  python3 -m pip install -q -r requirements.txt
else
  echo "Neither uv nor pip is available. Install uv (https://docs.astral.sh/uv/) or run: python3 -m ensurepip" >&2
  exit 1
fi
echo "HeatGuard running at http://localhost:${PORT}  (worker view: http://localhost:${PORT}/#/worker)"
exec python3 -m uvicorn app.main:app --host 0.0.0.0 --port "$PORT"
