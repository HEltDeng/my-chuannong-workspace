#!/bin/sh
set -eu
base=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$base/scripts/env.sh"
cd "$base/my-chuannong-backend"
exec .venv/bin/python run_local.py
