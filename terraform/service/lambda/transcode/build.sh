#!/usr/bin/env bash
# Build Lambda deployment package: src + dependencies (ohh-pydantic, pydantic).
# Run from repo root or from terraform/. Output: terraform/lambda/transcode/deployment.zip
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# From terraform/lambda/transcode, repo root is three levels up
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/build_pkg"
ZIP_PATH="$SCRIPT_DIR/deployment.zip"

rm -rf "$BUILD_DIR" "$ZIP_PATH"
mkdir -p "$BUILD_DIR"

python3 -m pip install -q -t "$BUILD_DIR" "ohh-pydantic>=0.1.0" "pydantic>=2.11.7"
cp -r "$REPO_ROOT/src" "$BUILD_DIR/"
cp "$SCRIPT_DIR/handler.py" "$BUILD_DIR/"

(cd "$BUILD_DIR" && zip -r -q "$ZIP_PATH" .)
rm -rf "$BUILD_DIR"
echo "Built $ZIP_PATH"
