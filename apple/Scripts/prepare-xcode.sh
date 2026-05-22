#!/usr/bin/env bash
set -euo pipefail

APPLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found. Install with: brew install xcodegen" >&2
  exit 1
fi

cd "$APPLE_DIR"
xcodegen generate
echo "Generated $APPLE_DIR/Zanoza.xcodeproj"
