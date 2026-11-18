#!/usr/bin/env bash
# Rebuild both web apps and refresh the prebuilt copies that the backend serves:
#   frontend/   supervisor / OHS dashboard  -> served at /
#   worker_app/ worker app (also Android/iOS) -> served at /worker/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
build() {
  local dir="$1"; shift
  (cd "$ROOT/$dir" && flutter pub get && flutter build web --release --no-web-resources-cdn "$@")
  rm -rf "$ROOT/$dir/dist" && cp -r "$ROOT/$dir/build/web" "$ROOT/$dir/dist"
  find "$ROOT/$dir/dist" \( -name '*.symbols' -o -name '*.map' \) -delete
}
build frontend
build worker_app --base-href /worker/
echo "Done. Start the server with ./scripts/run_demo.sh"
