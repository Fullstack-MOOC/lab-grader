#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "$0")/.." && pwd)
GRADER_DIR="$ROOT_DIR/assignment/autograder"
DIST_DIR="$ROOT_DIR/dist"
OUT_ZIP="$DIST_DIR/grader-$(date +%Y%m%d%H%M%S).zip"

mkdir -p "$DIST_DIR"

echo "Packing autograder from: $GRADER_DIR"
cd "$GRADER_DIR"

zip -r "$OUT_ZIP" . \
  -x "*.DS_Store" "*__MACOSX*" "._*" \
  -x "*/node_modules/*" "*/dist/*" "*/.git/*"

echo "Created: $OUT_ZIP"
