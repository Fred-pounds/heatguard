#!/usr/bin/env bash
# One-command local demo: starts the backend, which serves the API, the supervisor dashboard (/) and the
# worker app (/worker/) on one port. Prebuilt web apps are committed, so Flutter is not needed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-8000}"

# Prebuilt web apps are committed in frontend/dist and worker_app/dist. Rebuild with ./scripts/build_web.sh.
if [ ! -f "$ROOT/frontend/dist/index.html" ] || [ ! -f "$ROOT/worker_app/dist/index.html" ]; then
  if command -v flutter >/dev/null 2>&1; then
    "$ROOT/scripts/build_web.sh"
  else
    echo "Flutter not found and a prebuilt app is missing: the API will run without it (see README)."
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
echo "HeatGuard dashboard: http://localhost:${PORT}    Worker app: http://localhost:${PORT}/worker/"
exec python3 -m uvicorn app.main:app --host 0.0.0.0 --port "$PORT"
