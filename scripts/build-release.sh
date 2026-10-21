#!/bin/sh
set -eu
base=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$base/scripts/env.sh"
if [ -z "${AMAP_API_KEY_RELEASE:-}" ]; then
    echo '正式打包仍需高德 Android Key。请将匹配原签名与 com.mychuannong.app 的 Key 保存至 ~/.local/share/my-chuannong/signing/amap-release.key。' >&2
    exit 1
fi
cd "$base/my-chuannong-android"
exec python3 tools/build_release.py --output-dir "$base/outputs/release-$(date +%Y%m%d-%H%M%S)"
