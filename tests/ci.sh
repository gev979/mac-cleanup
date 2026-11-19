#!/bin/bash
# Full check in a disposable Linux container (this is what CI runs):
#   docker run --rm -v "$PWD":/src -w /src ubuntu:24.04 bash tests/ci.sh
set -eu
if [ "$(uname -s)" != Linux ] || [ "$(id -u)" -ne 0 ]; then
    echo "Run as root inside a disposable Linux container (see tests/README.md)." >&2
    exit 2
fi
cd "$(dirname "$0")/.."
if ! command -v lsof >/dev/null || ! command -v shellcheck >/dev/null || ! command -v python3 >/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq lsof procps python3 jq shellcheck >/dev/null
fi
echo "== shellcheck"
shellcheck -s bash -S warning bin/macclean bin/macclean-root install.sh uninstall.sh tests/*.sh
echo "== syntax"
for f in bin/macclean bin/macclean-root install.sh uninstall.sh; do bash -n "$f"; done
export MACCLEAN_TEST_SANDBOX=1
echo "== cleaner fixture tests"
bash tests/run_tests.sh
echo "== root helper fixture tests"
bash tests/test_root_helper.sh
