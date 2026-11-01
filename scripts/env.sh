# Source this file before local development: source scripts/env.sh
export JAVA_HOME="$(/usr/libexec/java_home -v 17)"
export ANDROID_HOME="${HOME}/Library/Android/sdk"
export MY_CHUANNONG_SIGNING_CONFIG="${HOME}/.local/share/my-chuannong/signing/signing.properties"
export MY_CHUANNONG_CAMPUS_TOOLS_API_BASE_URL_RELEASE="https://chuannong-api.mychangliapp.cn/api/v1/"
export MY_CHUANNONG_LOCAL_CREDENTIALS="${HOME}/.local/share/my-chuannong/development/credentials.json"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:${HOME}/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin:${HOME}/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin:$PATH"
if [ -f ${HOME}/.local/share/my-chuannong/signing/amap-release.key ]; then
    export AMAP_API_KEY_RELEASE="$(cat ${HOME}/.local/share/my-chuannong/signing/amap-release.key)"
fi
