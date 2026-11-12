#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:---launch}" in
    --build-only) exec scripts/motion-playground.sh --build-only ;;
    --test) exec scripts/motion-playground.sh --test ;;
    --stop) exec scripts/preview-app.sh --stop ;;
    --launch)
        scripts/motion-playground.sh --build-only
        exec scripts/preview-app.sh --motion-playground --launch -- --ui-preview-fixtures --projection-playground --hud-demo
        ;;
    *) printf 'Usage: scripts/hud-playground.sh [--launch | --build-only | --test | --stop]\n' >&2; exit 2 ;;
esac
