#!/usr/bin/env bash
# Check-only startup mod. It never changes the installed runtime.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "[deepseek-v4-vision-native-check] validating native multimodal runtime"
python3 "$HERE/check_native_runtime.py"
echo "[deepseek-v4-vision-native-check] validation passed"
