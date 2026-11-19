#!/bin/bash
# shellcheck disable=SC2217  # "sleep < file" deliberately keeps a file open (simulates in-use)
# Root-helper tests: fixtures at the real (macOS) system paths, inside a throwaway container.
set -u
# SAFETY: these tests create a test user, fake system folders (/Library, /private, /cores) and
# delete them again. They must only ever run in a disposable Linux container - never on a Mac.
if [ "$(uname -s)" != Linux ] || [ "$(id -u)" -ne 0 ] || [ "${MACCLEAN_TEST_SANDBOX:-}" != 1 ]; then
    echo "Refusing to run: use a disposable Linux container as root with MACCLEAN_TEST_SANDBOX=1 (see tests/README.md)." >&2
    exit 2
fi
R="$(cd "$(dirname "$0")/.." && pwd -P)/bin/macclean-root"
id mctest >/dev/null 2>&1 || useradd -m -s /bin/bash mctest
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); printf '  PASS %s\n' "$*"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$*"; }
exists() { [ -e "$1" ] && ok "kept: $1" || bad "should be kept: $1"; }
gone() { [ -e "$1" ] && bad "should be deleted: $1" || ok "deleted: $1"; }
age() { touch -d "$1" "${@:2}"; }

IDLE=/private/var/folders/zz/abc123/T/com.apple.idleassetsd
mkdir -p /Library/Logs/DiagnosticReports /private/var/log/asl /Library/Logs/OldApp /Library/Logs/NewApp \
    /Library/Caches/com.apple.x /private/var/db/diagnostics/Persist /private/var/db/reportmemoryexception/MemoryLimitViolations \
    /cores "$IDLE"
for f in /Library/Logs/DiagnosticReports/old.ips /Library/Logs/DiagnosticReports/new.ips /private/var/log/system.log.0.gz \
    /private/var/log/wifi.log /private/var/log/install.log /private/var/log/keep.txt /private/var/log/asl/2026.10.01.asl \
    /Library/Logs/OldApp/app.log /Library/Logs/NewApp/app.log /Library/Caches/foo.cache /Library/Caches/com.apple.x/data.db \
    /private/var/db/diagnostics/Persist/0001.tracev3 /private/var/db/diagnostics/Persist/0002.tracev3 /private/var/db/diagnostics/version.plist \
    /private/var/db/reportmemoryexception/MemoryLimitViolations/a.diag /cores/core.123 /cores/core.456 \
    "$IDLE/CFNetworkDownload_A.tmp" "$IDLE/CFNetworkDownload_B.tmp" "$IDLE/other.tmp"; do
    head -c 20000 /dev/urandom >"$f"
done
age '10 days ago' /Library/Logs/DiagnosticReports/old.ips /private/var/log/system.log.0.gz /private/var/log/asl/2026.10.01.asl \
    /Library/Caches/foo.cache /Library/Caches/com.apple.x/data.db /private/var/db/diagnostics/Persist/0001.tracev3
age '1 day ago' /Library/Logs/DiagnosticReports/new.ips /private/var/log/install.log /private/var/db/diagnostics/Persist/0002.tracev3
age '20 days ago' /private/var/log/wifi.log /private/var/log/keep.txt
age '40 days ago' /Library/Logs/OldApp/app.log /private/var/db/reportmemoryexception/MemoryLimitViolations/a.diag
age '30 days ago' /private/var/db/diagnostics/version.plist
age '5 days ago' /Library/Logs/NewApp/app.log
age '3 days ago' /cores/core.123 /cores/core.456
age '2 hours ago' "$IDLE/CFNetworkDownload_A.tmp" "$IDLE/other.tmp"
age '10 minutes ago' "$IDLE/CFNetworkDownload_B.tmp"
sleep 600 </cores/core.456 &
HOLDER=$!
sleep 0.5

echo "== argument handling"
"$R" >/dev/null 2>&1; [ $? -eq 2 ] && ok "no args -> exit 2" || bad "no args accepted"
"$R" clean extra >/dev/null 2>&1; [ $? -eq 2 ] && ok "two args -> exit 2" || bad "two args accepted"
"$R" 'clean; rm -rf /' >/dev/null 2>&1; [ $? -eq 2 ] && ok "injection-looking mode -> exit 2" || bad "bad mode accepted"
"$R" /etc >/dev/null 2>&1; [ $? -eq 2 ] && ok "path arg -> exit 2" || bad "path accepted"
runuser -u mctest -- "$R" check >/dev/null 2>&1; [ $? -eq 2 ] && ok "non-root refused" || bad "non-root accepted"
[ "$("$R" check)" = "ok macclean-root 1.0.0" ] && ok "check prints ok" || bad "check output"

echo "== scan deletes nothing"
before=$(find /Library /private /cores -type f | sort | md5sum)
out=$("$R" scan)
after=$(find /Library /private /cores -type f | sort | md5sum)
[ "$before" = "$after" ] && ok "scan changed nothing" || bad "scan changed files"
printf '%s\n' "$out" | grep -q $'^ROOT_TOTAL\t' && ok "scan prints ROOT_TOTAL" || bad "no ROOT_TOTAL"
printf '%s\n' "$out"

echo "== clean"
"$R" clean >/tmp/root-clean.out
gone /Library/Logs/DiagnosticReports/old.ips; exists /Library/Logs/DiagnosticReports/new.ips
gone /private/var/log/system.log.0.gz; gone /private/var/log/wifi.log; exists /private/var/log/install.log; exists /private/var/log/keep.txt
gone /private/var/log/asl/2026.10.01.asl
gone /Library/Logs/OldApp/app.log; exists /Library/Logs/NewApp/app.log; exists /Library/Logs/OldApp
gone /Library/Caches/foo.cache; exists /Library/Caches/com.apple.x/data.db
gone /private/var/db/diagnostics/Persist/0001.tracev3; exists /private/var/db/diagnostics/Persist/0002.tracev3; exists /private/var/db/diagnostics/version.plist
gone /private/var/db/reportmemoryexception/MemoryLimitViolations/a.diag
gone /cores/core.123; exists /cores/core.456
gone "$IDLE/CFNetworkDownload_A.tmp"; exists "$IDLE/CFNetworkDownload_B.tmp"; exists "$IDLE/other.tmp"
cat /tmp/root-clean.out

kill "$HOLDER" 2>/dev/null
rm -rf /Library /private /cores
printf '\nRESULT: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
