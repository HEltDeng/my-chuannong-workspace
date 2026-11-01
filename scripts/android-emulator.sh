#!/bin/bash
# Standalone Google Android Emulator controller; also bundled in the macOS app.
set -euo pipefail
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
AVD_NAME="${ANDROID_AVD_NAME:-Pixel_8_API_36_1}"
ADB="$ANDROID_HOME/platform-tools/adb"
EMULATOR="$ANDROID_HOME/emulator/emulator"
LOG="$HOME/Library/Logs/Android Emulator/emulator.log"

find_device() {
    local candidate name
    while read -r candidate; do
        name="$("$ADB" -s "$candidate" emu avd name 2>/dev/null | head -n 1 | tr -d '\r')" || continue
        if [[ "$name" == "$AVD_NAME" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done < <("$ADB" devices | awk '$1 ~ /^emulator-/ { print $1 }')
    return 1
}

require_device() {
    SERIAL="$(find_device)" || { printf '请先运行：%s start\n' "$0" >&2; exit 1; }
}

case "${1:-start}" in
    start)
        [[ -x "$EMULATOR" ]] || { printf '未安装 Android Emulator。\n' >&2; exit 1; }
        "$EMULATOR" -list-avds | grep -Fxq "$AVD_NAME" || { printf '未找到虚拟设备 %s。\n' "$AVD_NAME" >&2; exit 1; }
        "$ADB" start-server
        emulator_pid=""
        if ! SERIAL="$(find_device)"; then
            mkdir -p "$(dirname "$LOG")"
            # A separate session also survives the automation terminal closing.
            emulator_pid="$(/usr/bin/python3 - "$EMULATOR" "$AVD_NAME" "$LOG" <<'PY'
import subprocess
import sys

with open(sys.argv[3], 'w') as log:
    process = subprocess.Popen(
        [sys.argv[1], '-avd', sys.argv[2], '-netdelay', 'none',
         '-netspeed', 'full', '-no-boot-anim'],
        stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
        start_new_session=True,
    )
print(process.pid)
PY
            )"
            printf '正在启动 %s…\n' "$AVD_NAME"
        fi
        for ((attempt = 0; attempt < 120; attempt++)); do
            if SERIAL="$(find_device)" && [[ "$("$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; then
                printf '模拟器已就绪：%s (%s)\n' "$AVD_NAME" "$SERIAL"
                exit 0
            fi
            if [[ -n "$emulator_pid" ]] && ! kill -0 "$emulator_pid" 2>/dev/null; then
                printf '模拟器启动失败，请查看：%s\n' "$LOG" >&2
                exit 1
            fi
            sleep 2
        done
        printf '启动等待超时，请查看：%s\n' "$LOG" >&2
        exit 1
        ;;
    stop)
        require_device
        "$ADB" -s "$SERIAL" emu kill
        ;;
    status)
        if SERIAL="$(find_device)"; then
            printf '虚拟设备：%s\nADB：%s\n' "$AVD_NAME" "$SERIAL"
            "$ADB" -s "$SERIAL" shell getprop ro.build.version.release
            "$ADB" -s "$SERIAL" shell getprop sys.boot_completed
        else
            printf '虚拟设备已安装，当前未运行：%s\n' "$AVD_NAME"
        fi
        ;;
    install)
        [[ $# == 2 && -f "$2" ]] || { printf '用法：%s install /完整路径/app.apk\n' "$0" >&2; exit 2; }
        require_device
        "$ADB" -s "$SERIAL" install -r "$2"
        ;;
    screenshot)
        require_device
        output="${2:-$HOME/Pictures/Android Emulator/android-emulator-$(date +%Y%m%d-%H%M%S).png}"
        mkdir -p "$(dirname "$output")"
        "$ADB" -s "$SERIAL" exec-out screencap -p > "$output"
        printf '%s\n' "$output"
        ;;
    adb)
        shift
        require_device
        exec "$ADB" -s "$SERIAL" "$@"
        ;;
    *)
        printf '用法：%s {start|stop|status|install APK|screenshot [PNG]|adb 参数…}\n' "$0" >&2
        exit 2
        ;;
esac
