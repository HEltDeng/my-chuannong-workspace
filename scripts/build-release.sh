#!/bin/sh
set -eu
base=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$base/scripts/env.sh"
cd "$base/my-chuannong-android"
exec python3 tools/build_release.py --output-dir "$base/outputs/release-$(date +%Y%m%d-%H%M%S)"
