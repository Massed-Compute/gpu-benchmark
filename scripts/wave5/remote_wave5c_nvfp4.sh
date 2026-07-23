#!/usr/bin/env bash
# Alias: same as remote_wave5c.sh (NVFP4 Solar + Laguna-S). Kept so older docs/calls keep working.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
exec bash "$SCRIPT_DIR/remote_wave5c.sh"
