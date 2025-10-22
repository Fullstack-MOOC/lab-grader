#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "$0")/.." && pwd)
LAB_DIR="$ROOT_DIR/coursera-labs/cs52"
DIST_DIR="$ROOT_DIR/dist"

mkdir -p "$DIST_DIR"

echo "Packing lab image from: $LAB_DIR"
cd "$LAB_DIR"

# Create a deterministic zip for Coursera Labs upload
ZIP_NAME="cs52-lab-$(date +%Y%m%d%H%M%S).zip"
zip -r "$DIST_DIR/$ZIP_NAME" . \
  -x "*.DS_Store" "*__MACOSX*" "._*" \
  -x "*/node_modules/*" "*/dist/*" "*/.git/*"

echo "Created: $DIST_DIR/$ZIP_NAME"
