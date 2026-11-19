#!/bin/bash
# shellcheck disable=SC2088  # literal ~ lines are what Mole's whitelist contains
# Fixture tests for MacClean. The cleaner runs as an unprivileged test user so ownership
# checks are real; macOS-only tools are stubbed.
set -u
# SAFETY: these tests create a test user, fake system folders (/Library, /private, /cores) and
# delete them again. They must only ever run in a disposable Linux container - never on a Mac.
if [ "$(uname -s)" != Linux ] || [ "$(id -u)" -ne 0 ] || [ "${MACCLEAN_TEST_SANDBOX:-}" != 1 ]; then
    echo "Refusing to run: use a disposable Linux container as root with MACCLEAN_TEST_SANDBOX=1 (see tests/README.md)." >&2
    exit 2
fi
SRC=$(cd "$(dirname "$0")/.." && pwd -P)
U=mctest
H=/home/$U
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf '  PASS %s\n' "$*"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$*"; }
exists() { if [ -e "$1" ] || [ -L "$1" ]; then ok "kept: ${1#$H/}"; else bad "should be kept: ${1#$H/}"; fi; }
gone() { if [ -e "$1" ] || [ -L "$1" ]; then bad "should be deleted: ${1#$H/}"; else ok "deleted: ${1#$H/}"; fi; }
asu() { runuser -u "$U" -- env -i HOME="$H" PATH=/usr/bin:/bin USER="$U" MACCLEAN_TMPDIR="$TMPD" MACCLEAN_SYSTMP="$SYSTMP" \
    MACCLEAN_ROOT_HELPER="$H/fake-root-helper" "$@"; }
old() { find "$@" -depth -exec touch -h -d '10 days ago' {} + ; }
older() { find "$@" -depth -exec touch -h -d '40 days ago' {} + ; }

pkill -u "$U" 2>/dev/null; sleep 0.5
id "$U" >/dev/null 2>&1 || useradd -m -s /bin/bash "$U"
rm -rf "$H" && mkdir -p "$H" && chown "$U:$U" "$H"
TMPD="$H/fake_tmp/T"
SYSTMP="$H/fake_systmp"

mk() { runuser -u "$U" -- bash -c "$1"; }

# ---------------------------------------------------------------- fixtures
mk "
set -e
cd $H
mkdir -p Documents/important Library/Caches .local/bin MacClean
echo secret > Documents/important.txt
echo keep > Documents/important/file

# --- Playwright browsers
PW=Library/Caches/ms-playwright
mkdir -p \$PW/chromium-1100/x \$PW/chromium-1140/x \$PW/chromium-1148/x \$PW/chromium_headless_shell-1140/x \
         \$PW/chromium_headless_shell-1148/x \$PW/firefox-1466/x \$PW/firefox-1400/x \$PW/webkit-2100/x \$PW/ffmpeg-1010/x \
         \$PW/mcp-chrome-profile/Default \$PW/.links \$PW/unknownbrowser-1000/x
for d in \$PW/*/x; do head -c 300000 /dev/urandom > \$d/bin; done
mkdir -p proj/node_modules/playwright-core
printf '{\"browsers\":[{\"name\":\"chromium\",\"revision\":\"1140\"},{\"name\":\"chromium-headless-shell\",\"revision\":\"1140\"},{\"name\":\"firefox\",\"revision\":\"1466\"},{\"name\":\"webkit\",\"revision\":\"2100\",\"revisionOverrides\":{\"mac12\":\"2009\"}},{\"name\":\"ffmpeg\",\"revision\":\"1010\"}]}' > proj/node_modules/playwright-core/browsers.json
printf '%s' $H/proj/node_modules/playwright-core > \$PW/.links/aaaa
printf '%s' $H/gone/node_modules/playwright-core > \$PW/.links/bbbb
ln -s $H/Documents/important \$PW/chromium-1000

# --- Playwright MCP profiles + libvips
mkdir -p \$PW/mcp-chrome-idle1/Default/Cache/Cache_Data \$PW/mcp-chrome-idle1/GrShaderCache \$PW/mcp-chrome-busy2/Default/Cache
echo c > \$PW/mcp-chrome-idle1/Default/Cache/Cache_Data/f; echo c > \$PW/mcp-chrome-idle1/GrShaderCache/s
echo cookie > \$PW/mcp-chrome-idle1/Default/Cookies; echo c > \$PW/mcp-chrome-busy2/Default/Cache/f
mkdir -p .npm/_libvips && echo x > .npm/_libvips/libvips-8.15-darwin-arm64.tar.br

# --- temp dirs
mkdir -p $TMPD $SYSTMP
cd $TMPD
mkdir -p playwright-artifacts-old/t playwright-artifacts-new/t playwright_chromiumdev_profile-old/Default \
         playwright_chromiumdev_profile-live/Default playwright_chromiumdev_profile-open/Default \
         playwright-mcp-output/2026-11-01 playwright-transform-cache-501 random-old-dir TemporaryItems \
         tmpabcd1234 npm-12345-sock jiti
head -c 200000 /dev/urandom > playwright-artifacts-old/t/trace.zip
echo x > playwright-artifacts-new/t/trace.zip
echo x > playwright_chromiumdev_profile-old/Default/Prefs
echo x > playwright_chromiumdev_profile-live/Default/Prefs
echo x > playwright_chromiumdev_profile-open/Default/LOCK
head -c 100000 /dev/urandom > playwright-mcp-output/2026-11-01/page-old.png
echo x > playwright-mcp-output/page-new.png
echo x > playwright-transform-cache-501/a.js
echo x > random-old-dir/data
echo x > TemporaryItems/x
echo x > tmpabcd1234/f
echo x > jiti/f
echo x > stray-old-file.txt
echo x > stray-new-file.txt
echo x > stray-protected.txt
echo x > com.apple.something
echo x > claude-abc123-cwd
echo x > claude-new-cwd
ln -s $H/Documents/important.txt claude-evil-cwd
ln -s $H/Documents/important claude-evil-dir
python3 -c \"import socket; s=socket.socket(socket.AF_UNIX); s.bind('$TMPD/app.sock')\"
python3 -c \"import socket; s=socket.socket(socket.AF_UNIX); s.bind('$TMPD/npm-12345-sock/ipc')\"
cd $SYSTMP
echo x > claude-sys-cwd
mkdir -p playwright-artifacts-sys && echo x > playwright-artifacts-sys/f
echo x > claude-rootowned-cwd

# --- project outputs
cd $H
mkdir -p Projects/app/.playwright-mcp/sub Projects/app/test-results/t1 Projects/app/playwright-report/data \
         Projects/app2/test-results Projects/app/node_modules/pkg/test-results Projects/live/test-results \
         Documents/proj/.playwright-mcp CascadeProjects/site/.playwright-mcp
echo x > Projects/app/.playwright-mcp/old.png
echo x > Projects/app/.playwright-mcp/sub/old2.png
echo x > Projects/app/.playwright-mcp/new.png
echo '{}' > Projects/app/test-results/.last-run.json
head -c 50000 /dev/urandom > Projects/app/test-results/t1/video.webm
echo '<html><title>Playwright Test Report</title></html>' > Projects/app/playwright-report/index.html
echo x > Projects/app/playwright-report/data/a.zip
echo x > Projects/app2/test-results/keep.txt
echo '{}' > Projects/app/node_modules/pkg/test-results/.last-run.json
echo '{}' > Projects/live/test-results/.last-run.json
echo x > Documents/proj/.playwright-mcp/old.png
echo x > CascadeProjects/site/.playwright-mcp/old.png
mkdir -p .playwright-mcp && echo x > .playwright-mcp/old-home.png

# --- Claude Code
mkdir -p .claude/projects/p .claude/debug .claude/shell-snapshots .claude/todos .claude/file-history/f .claude/plugins/x
echo t > .claude/projects/p/session.jsonl
echo d > .claude/debug/old.txt
echo d > .claude/debug/new.txt
ln -s $H/.claude/debug/new.txt .claude/debug/latest
echo s > .claude/shell-snapshots/snapshot-old.sh
echo '[]' > .claude/todos/old.json
echo '[]' > .claude/todos/recent.json
echo '{}' > .claude/settings.json
echo h > .claude/history.jsonl
echo f > .claude/file-history/f/v1
echo p > .claude/plugins/x/p
mkdir -p .claude-byz/projects .claude-byz/debug && echo d > .claude-byz/debug/old.txt
mkdir -p .claude-mem/debug && echo memory > .claude-mem/debug/old.txt

# --- Claude desktop
CD='Library/Application Support/Claude'
mkdir -p \"\$CD/Cache/Cache_Data\" \"\$CD/Code Cache/js\" \"\$CD/GPUCache\" \"\$CD/Local Storage/leveldb\" \"\$CD/vm_bundles/claudevm.bundle\" \"\$CD/IndexedDB\"
echo c > \"\$CD/Cache/Cache_Data/f\"; echo c > \"\$CD/Code Cache/js/f\"; echo c > \"\$CD/GPUCache/data_0\"
echo ls > \"\$CD/Local Storage/leveldb/000.ldb\"; head -c 300000 /dev/urandom > \"\$CD/vm_bundles/claudevm.bundle/rootfs.img\"
echo '{}' > \"\$CD/claude_desktop_config.json\"

# --- npx / nvm / thumbnails / puppeteer
mkdir -p .npm/_npx/oldhash/node_modules .npm/_npx/livehash/node_modules .npm/_npx/newhash/node_modules .npm/_cacache
echo x > .npm/_npx/oldhash/node_modules/a; echo x > .npm/_npx/livehash/node_modules/a; echo x > .npm/_npx/newhash/node_modules/a
mkdir -p .nvm/.cache/bin/node-v20 .nvm/versions/node/v20/bin && echo x > .nvm/.cache/bin/node-v20/node.tar.gz && echo n > .nvm/versions/node/v20/bin/node
mkdir -p .thumbnails/normal && echo x > .thumbnails/normal/a.png
mkdir -p .cache/puppeteer/chrome/mac_arm-120.0 .cache/puppeteer/chrome/mac_arm-131.0 && echo x > .cache/puppeteer/chrome/mac_arm-120.0/c && echo x > .cache/puppeteer/chrome/mac_arm-131.0/c
mkdir -p .Trash && echo t > .Trash/trashed.txt
mkdir -p .ssh && echo key > .ssh/id_ed25519
mkdir -p .config/app && echo cfg > .config/app/settings
"
chown root:root "$SYSTMP/claude-rootowned-cwd"

# ages
old "$H/Library/Caches/ms-playwright"
touch -d '1 hour ago' "$H/Library/Caches/ms-playwright/firefox-1400" "$H/Library/Caches/ms-playwright/firefox-1400/x" "$H/Library/Caches/ms-playwright/firefox-1400/x/bin"
old "$TMPD"/playwright-artifacts-old "$TMPD"/playwright_chromiumdev_profile-old "$TMPD"/playwright_chromiumdev_profile-live \
    "$TMPD"/playwright_chromiumdev_profile-open "$TMPD"/playwright-mcp-output/2026-11-01 "$TMPD"/playwright-transform-cache-501 \
    "$TMPD"/random-old-dir "$TMPD"/TemporaryItems "$TMPD"/tmpabcd1234 "$TMPD"/jiti "$TMPD"/npm-12345-sock "$TMPD"/stray-old-file.txt \
    "$TMPD"/stray-protected.txt "$TMPD"/com.apple.something "$TMPD"/claude-abc123-cwd "$TMPD"/claude-evil-cwd "$TMPD"/claude-evil-dir \
    "$TMPD"/app.sock
old "$SYSTMP"/claude-sys-cwd "$SYSTMP"/playwright-artifacts-sys "$SYSTMP"/claude-rootowned-cwd
old "$H/Projects/app/.playwright-mcp/old.png" "$H/Projects/app/.playwright-mcp/sub/old2.png" "$H/Projects/app/test-results" \
    "$H/Projects/app/playwright-report" "$H/Projects/app2/test-results" "$H/Projects/app/node_modules/pkg/test-results" \
    "$H/Documents/proj/.playwright-mcp/old.png" "$H/CascadeProjects/site/.playwright-mcp/old.png" "$H/.playwright-mcp/old-home.png"
old "$H/.claude/projects" "$H/.claude/debug/old.txt" "$H/.claude/shell-snapshots/snapshot-old.sh" "$H/.claude-byz/debug/old.txt" \
    "$H/.claude-mem/debug/old.txt" "$H/.claude/file-history"
older "$H/.claude/todos/old.json"
old "$H/.npm/_libvips" "$H/.npm/_npx/oldhash" "$H/.npm/_npx/livehash" "$H/.nvm/.cache" "$H/.nvm/versions" "$H/.thumbnails"
touch -d '30 days ago' "$H/.npm/_npx/oldhash" "$H/.npm/_npx/livehash"
find "$H/.npm/_npx/oldhash" "$H/.npm/_npx/livehash" -exec touch -d '30 days ago' {} +
touch -d '20 days ago' "$H/.cache/puppeteer/chrome/mac_arm-120.0"
touch -d '2 days ago' "$H/.cache/puppeteer/chrome/mac_arm-131.0"

# stubs: Mole, sudo, root helper
cat >"$H/.local/bin/mo" <<'EOF'
#!/bin/bash
printf '%s tty_in=%s args=%s\n' "$(date +%s)" "$([ -t 0 ] && echo yes || echo no)" "$*" >>"$HOME/mo_calls.log"
case "$1" in
  --version) echo "Mole version 1.73.0"; echo "macOS: 26.1" ;;
  clean) if [ "${2:-}" = --dry-run ]; then printf '\033[0;32mDry run complete - no changes made\033[0m\nPotential space: 1.20GB · 42 items\n'
         else printf 'Cleanup complete\nSpace freed: 1.20GB | Items cleaned: 42 | Categories: 3\nFree space now: 100Gi\n'; fi ;;
  purge) echo "purge ${2:-}"; echo "Total: 3 items, 2.1GB" ;;
  analyze) echo '{"entries":[{"name":"Library","size":5000000000,"cleanable":false},{"name":"Projects","size":3000000000,"cleanable":false}]}' ;;
esac
EOF
cat >"$H/.local/bin/sudo" <<'EOF'
#!/bin/bash
[ "${1:-}" = -n ] && shift
exec "$@"
EOF
cat >"$H/fake-root-helper" <<'EOF'
#!/bin/bash
echo "$*" >>"$HOME/root_calls.log"
[ "$1" = check ] && { echo "ok macclean-root 1.0.0"; exit 0; }
printf 'ROOT_ITEM\tCrash reports (system)\t2048\t5\n'
printf 'ROOT_ITEM\tCore dumps\t0\t0\n'
printf 'ROOT_TOTAL\t2048\t5\n'
EOF
chmod 755 "$H/.local/bin/mo" "$H/.local/bin/sudo" "$H/fake-root-helper"
chown -R "$U:$U" "$H/.local" "$H/fake-root-helper"
printf 'EXTRA_PROTECT=%s\nPROJECT_ROOTS=~/Projects:~/CascadeProjects:~/Documents/proj\n' "$TMPD/stray-protected.txt" >"$H/MacClean/config"
chown "$U:$U" "$H/MacClean/config"

# live processes: a browser using a profile, a process holding a file open, a running npx MCP server
runuser -u "$U" -- bash -c "exec -a 'chrome --user-data-dir=$TMPD/playwright_chromiumdev_profile-live' sleep 600" &
runuser -u "$U" -- bash -c "exec sleep 600 < '$TMPD/playwright_chromiumdev_profile-open/Default/LOCK'" &
runuser -u "$U" -- bash -c "exec -a 'node $H/.npm/_npx/livehash/node_modules/.bin/mcp-server' sleep 600" &
runuser -u "$U" -- bash -c "exec -a 'chrome --user-data-dir=$H/Library/Caches/ms-playwright/mcp-chrome-busy2' sleep 600" &
runuser -u "$U" -- bash -c "exec sleep 600 < '$H/Projects/live/test-results/.last-run.json'" &
sleep 1
old "$H/Projects/live/test-results"

snapshot() { (cd "$H" && find . \( -path ./MacClean -o -path ./mo_calls.log -o -path ./root_calls.log -o -path ./.config/mole \) -prune -o -print | sort) >"$1"; }

echo "== 1. scan (dry run) must not change anything"
snapshot /tmp/before.txt
asu bash "$SRC/bin/macclean" scan >/tmp/scan.out 2>&1
echo "  exit=$?"
snapshot /tmp/after.txt
if diff -q /tmp/before.txt /tmp/after.txt >/dev/null; then ok "scan changed nothing"; else bad "scan changed files:"; diff /tmp/before.txt /tmp/after.txt | head; fi
grep -q "Preview only" /tmp/scan.out && ok "scan summary says preview" || bad "no preview marker"
grep -q "Potential space: 1.20GB" /tmp/scan.out && ok "Mole dry-run summary captured" || bad "Mole summary missing"
grep -q "args=clean --dry-run" "$H/mo_calls.log" && ok "Mole called with --dry-run in scan" || bad "Mole dry-run not used"
grep -q "tty_in=yes" "$H/mo_calls.log" && bad "Mole got a TTY on stdin" || ok "Mole stdin is not a TTY"
[ "$(tr '\n' ' ' <"$H/root_calls.log")" = "scan " ] && ok "balanced scan uses root helper 'scan' (no TM snapshots)" || bad "root helper mode wrong: $(cat "$H/root_calls.log")"

echo "== 2. clean"
asu bash "$SRC/bin/macclean" clean >/tmp/clean.out 2>&1
echo "  exit=$?"
P=$H/Library/Caches/ms-playwright
gone "$P/chromium-1100"
exists "$P/chromium-1140"; exists "$P/chromium-1148"; exists "$P/chromium_headless_shell-1140"; exists "$P/chromium_headless_shell-1148"
exists "$P/firefox-1466"; exists "$P/firefox-1400"; exists "$P/webkit-2100"; exists "$P/ffmpeg-1010"
exists "$P/mcp-chrome-profile"; gone "$P/mcp-chrome-idle1/Default/Cache"; gone "$P/mcp-chrome-idle1/GrShaderCache"
exists "$P/mcp-chrome-idle1/Default/Cookies"; exists "$P/mcp-chrome-busy2/Default/Cache/f"; gone "$H/.npm/_libvips/libvips-8.15-darwin-arm64.tar.br"
exists "$P/unknownbrowser-1000"; exists "$P/chromium-1000"; exists "$H/Documents/important/file"
gone "$TMPD/playwright-artifacts-old"; exists "$TMPD/playwright-artifacts-new"
gone "$TMPD/playwright_chromiumdev_profile-old"; exists "$TMPD/playwright_chromiumdev_profile-live"; exists "$TMPD/playwright_chromiumdev_profile-open"
gone "$TMPD/playwright-mcp-output/2026-11-01"; exists "$TMPD/playwright-mcp-output/page-new.png"; exists "$TMPD/playwright-mcp-output"
gone "$TMPD/playwright-transform-cache-501"; gone "$TMPD/tmpabcd1234"; gone "$TMPD/jiti"
exists "$TMPD/random-old-dir"; exists "$TMPD/TemporaryItems"; exists "$TMPD/npm-12345-sock"; exists "$TMPD/app.sock"
gone "$TMPD/stray-old-file.txt"; exists "$TMPD/stray-new-file.txt"; exists "$TMPD/stray-protected.txt"; exists "$TMPD/com.apple.something"
gone "$TMPD/claude-abc123-cwd"; exists "$TMPD/claude-new-cwd"
gone "$TMPD/claude-evil-cwd"; gone "$TMPD/claude-evil-dir"; exists "$H/Documents/important.txt"; exists "$H/Documents/important/file"
gone "$SYSTMP/claude-sys-cwd"; gone "$SYSTMP/playwright-artifacts-sys"; exists "$SYSTMP/claude-rootowned-cwd"
gone "$H/Projects/app/.playwright-mcp/old.png"; gone "$H/Projects/app/.playwright-mcp/sub/old2.png"; exists "$H/Projects/app/.playwright-mcp/new.png"
exists "$H/Projects/app/.playwright-mcp"
gone "$H/Projects/app/test-results"; gone "$H/Projects/app/playwright-report"; exists "$H/Projects/app2/test-results/keep.txt"
exists "$H/Projects/app/node_modules/pkg/test-results/.last-run.json"; exists "$H/Projects/live/test-results/.last-run.json"
exists "$H/Documents/proj/.playwright-mcp/old.png"; gone "$H/CascadeProjects/site/.playwright-mcp/old.png"; gone "$H/.playwright-mcp/old-home.png"
exists "$H/.claude/projects/p/session.jsonl"; gone "$H/.claude/debug/old.txt"; exists "$H/.claude/debug/new.txt"; exists "$H/.claude/debug/latest"
gone "$H/.claude/shell-snapshots/snapshot-old.sh"; gone "$H/.claude/todos/old.json"; exists "$H/.claude/todos/recent.json"
exists "$H/.claude/settings.json"; exists "$H/.claude/history.jsonl"; exists "$H/.claude/file-history/f/v1"; exists "$H/.claude/plugins/x/p"
gone "$H/.claude-byz/debug/old.txt"; exists "$H/.claude-mem/debug/old.txt"
CD="$H/Library/Application Support/Claude"
gone "$CD/Cache/Cache_Data"; gone "$CD/Code Cache/js"; gone "$CD/GPUCache/data_0"; exists "$CD/Cache"
exists "$CD/Local Storage/leveldb/000.ldb"; exists "$CD/vm_bundles/claudevm.bundle/rootfs.img"; exists "$CD/claude_desktop_config.json"; exists "$CD/IndexedDB"
gone "$H/.npm/_npx/oldhash"; exists "$H/.npm/_npx/livehash"; exists "$H/.npm/_npx/newhash"; exists "$H/.npm/_cacache"
gone "$H/.nvm/.cache/bin"; exists "$H/.nvm/versions/node/v20/bin/node"; gone "$H/.thumbnails/normal"
exists "$H/.cache/puppeteer/chrome/mac_arm-120.0"; exists "$H/.Trash/trashed.txt"; exists "$H/.ssh/id_ed25519"; exists "$H/.config/app/settings"
grep -q "args=clean$" "$H/mo_calls.log" && ok "Mole real clean called" || bad "Mole real clean not called"
[ "$(tr '\n' ' ' <"$H/root_calls.log")" = "scan clean " ] && ok "balanced clean uses root helper 'clean'" || bad "root helper modes: $(tr '\n' ' ' <"$H/root_calls.log")"
grep -q "System level (root helper)" /tmp/clean.out && ok "root summary present" || bad "root summary missing"
grep -q "Space freed: 1.20GB" /tmp/clean.out && ok "Mole 'Space freed' line captured" || bad "Mole freed line missing"
grep -q "^RESULT" /tmp/clean.out && ok "RESULT line present" || bad "RESULT line missing"
grep -q '~/.Trash' "$H/.config/mole/whitelist" && ok "Mole whitelist protects Trash" || bad "whitelist missing Trash"
grep -q 'ms-playwright' "$H/.config/mole/whitelist" && ok "Mole defaults preserved in new whitelist" || bad "Mole defaults missing"
grep -Fxq '~/.aws' "$H/.config/mole/whitelist" && ok "whitelist protects ~/.aws" || bad "whitelist missing ~/.aws"
grep -Fxq '~/Library/Developer/Xcode/Archives' "$H/.config/mole/whitelist" && ok "whitelist protects Xcode archives" || bad "whitelist missing archives"
grep -Fxq '~/Library/Application Support/Claude/Code Cache' "$H/.config/mole/whitelist" && ok "whitelist protects Claude desktop caches" || bad "whitelist missing Claude caches"
log=$(ls -t "$H"/MacClean/reports/*-clean.log | head -n 1)
grep -q "SKIP  (in-use(running process)) $TMPD/playwright_chromiumdev_profile-live" "$log" && ok "live profile skipped as running" || bad "live profile skip reason missing"
grep -q "SKIP  (in-use(open file)) $TMPD/playwright_chromiumdev_profile-open" "$log" && ok "open profile skipped as open" || bad "open-file skip reason missing"
grep -q "SKIP  (protected) $TMPD/stray-protected.txt" "$log" && ok "EXTRA_PROTECT honoured" || bad "EXTRA_PROTECT not logged"
grep -q "SKIP  (not-owned-by-you) $SYSTMP/claude-rootowned-cwd" "$log" && ok "foreign file skipped" || bad "foreign skip missing"
grep -q "KEEP  (needed by an installed Playwright) $P/chromium-1140" "$log" && ok "live Playwright revision kept by .links" || bad "links keep missing"

[ "$(grep -c -Fx '~/.aws' "$H/.config/mole/whitelist")" -eq 1 ] && ok "no duplicate whitelist lines after repeated runs" || bad "duplicate whitelist lines"
echo "== 3. deep (puppeteer old version, trash age gate)"
asu bash "$SRC/bin/macclean" deep >/tmp/deep.out 2>&1
echo "  exit=$?"
gone "$H/.cache/puppeteer/chrome/mac_arm-120.0"; exists "$H/.cache/puppeteer/chrome/mac_arm-131.0"
exists "$H/.Trash/trashed.txt"
grep -q "args=purge --yes" "$H/mo_calls.log" && ok "mo purge --yes in deep" || bad "mo purge not called"
tail -n 1 "$H/root_calls.log" | grep -qx deep && ok "deep uses root helper 'deep' (TM snapshots)" || bad "deep root mode: $(tail -n 1 "$H/root_calls.log")"

echo "== 4. agent queue + junk handling"
Q="$H/MacClean/queue"
mk "mkdir -p $Q; printf 'scan\n' > $Q/20261118-120000-scan-test.req; printf 'rm -rf /\n' > $Q/20261118-120001-evil.req; touch $Q/.DS_Store $Q/notes.txt; printf 'scan\n' > '$Q/bad id.req'"
asu bash "$SRC/bin/macclean" agent >/tmp/agent.out 2>&1
echo "  exit=$?"
left=$(ls -A "$Q" | wc -l)
[ "$left" -eq 0 ] && ok "queue emptied (launchd will stop relaunching)" || bad "queue not empty: $(ls -A "$Q")"
grep -q "status=ok" "$H/MacClean/reports/20261118-120000-scan-test.done" 2>/dev/null && ok "scan request done=ok" || bad "scan request not done"
grep -q "status=rejected" "$H/MacClean/reports/20261118-120001-evil.done" 2>/dev/null && ok "unknown mode rejected" || bad "evil request not rejected"
[ -e "$H/MacClean/reports/rejected/notes.txt" ] && ok "junk moved to rejected/" || bad "junk not moved"
grep -q "Mole was skipped in the background agent" "$H/MacClean/reports/20261118-120000-scan-test.summary.txt" && ok "agent without FDA skips Mole" || bad "agent FDA gate missing"

echo "== 5. scheduled run when due"
echo $(( $(date +%s) - 8 * 86400 )) >"$H/MacClean/.state/last_scheduled"; chown "$U:$U" "$H/MacClean/.state/last_scheduled"
asu bash "$SRC/bin/macclean" agent >/dev/null 2>&1
ls "$H"/MacClean/reports/*-scheduled.summary.txt >/dev/null 2>&1 && ok "scheduled clean ran" || bad "scheduled run missing"
s=$(cat "$H/MacClean/.state/last_scheduled"); [ $(( $(date +%s) - s )) -lt 60 ] && ok "last_scheduled updated" || bad "last_scheduled not updated"
asu bash "$SRC/bin/macclean" agent >/dev/null 2>&1
[ "$(ls "$H"/MacClean/reports/*-scheduled.summary.txt | wc -l)" -eq 1 ] && ok "not re-run before due" || bad "scheduled ran twice"

echo "== 6. Claude desktop open -> its caches untouched"
mk "mkdir -p '$CD/Cache/Cache_Data' && echo c > '$CD/Cache/Cache_Data/f'"
old "$CD/Cache"
cp /bin/sleep /tmp/Claude && chmod 755 /tmp/Claude
runuser -u "$U" -- /tmp/Claude 600 &
sleep 0.5
asu bash "$SRC/bin/macclean" clean >/tmp/clean2.out 2>&1
exists "$CD/Cache/Cache_Data/f"
grep -q "Claude desktop was open" /tmp/clean2.out && ok "note explains Claude was open" || bad "missing Claude-open note"

echo "== 7. status + lock"
asu bash "$SRC/bin/macclean" status >/tmp/status.out 2>&1 && ok "status runs" || bad "status failed"
mk "mkdir -p $H/MacClean/.state/lock && echo 1 > $H/MacClean/.state/lock/pid"
asu bash "$SRC/bin/macclean" clean >/tmp/locked.out 2>&1; rc=$?
[ "$rc" -eq 75 ] && ok "concurrent run refused while lock held by a live pid" || bad "lock not respected (rc=$rc)"
rm -rf "$H/MacClean/.state/lock"

pkill -u "$U" 2>/dev/null
printf '\nRESULT: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
