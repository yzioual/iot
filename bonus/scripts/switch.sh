#!/bin/bash
set -e

TARGET_VERSION="$1"

if [ "$TARGET_VERSION" != "v1" ] && [ "$TARGET_VERSION" != "v2" ]; then
    echo "Usage: $0 [v1|v2]"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$SCRIPT_DIR/confs/deployment-${TARGET_VERSION}.yaml"

if [ ! -f "$MANIFEST" ]; then
    echo "Manifest $MANIFEST not found!"
    exit 1
fi

echo "[+] Updating deployment to ${TARGET_VERSION}..."
cp "$MANIFEST" ./deployment.yaml

git add deployment.yaml
git commit -m "Update app to ${TARGET_VERSION}"
git push origin master || git push origin main

echo "[✓] Pushed ${TARGET_VERSION} to GitLab. Argo CD will synchronize automatically."
