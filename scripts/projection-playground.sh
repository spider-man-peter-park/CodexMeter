#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:---launch}" in
    --launch) exec scripts/motion-playground.sh --projection ;;
    --build-only) exec scripts/motion-playground.sh --build-only ;;
    --stop) exec scripts/motion-playground.sh --stop ;;
    --test) exec scripts/motion-playground.sh --test ;;
    --help|-h)
        printf 'Usage: scripts/projection-playground.sh [--launch | --build-only | --stop | --test]\n'
        ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
esac
