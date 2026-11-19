#!/bin/bash
# shellcheck disable=SC2088  # literal '~' is intentional (display / manual expansion)
#
# MacClean installer. Run it as your normal user (NOT with sudo):
#
#     bash ~/MacClean/install.sh
#
# It asks for your admin password once and then:
#   1. installs bin/macclean + bin/macclean-root into /opt/macclean/bin (root-owned)
#   2. links /usr/local/bin/macclean
#   3. adds /etc/sudoers.d/macclean - passwordless ONLY for the fixed-action helper
#      (macclean-root check|scan|clean|deep-scan|deep), nothing else
#   4. prepares ~/MacClean (config, queue, reports) and protects the Trash in Mole's whitelist
#   5. creates ~/Applications/MacClean Agent.app + a LaunchAgent that serves the request
#      queue (used by Claude in Cowork) and runs the weekly clean when the Mac is idle
#   6. Claude Code: installs the mac-cleanup skill + allow-rules (settings.json is backed up)
#   7. helps you give the agent Full Disk Access, then verifies the whole chain
#
# Re-running is safe (idempotent). Undo everything with: bash ~/MacClean/uninstall.sh

set -u
INSTALLER_VERSION="1.0.0"
AGENT_APP_VERSION="1"
SRC_DIR=$(cd "$(dirname "$0")" && pwd -P)
MC_HOME="$HOME/MacClean"
OPT=/opt/macclean
HELPER="$OPT/bin/macclean-root"
LABEL=local.macclean.agent
APP="$HOME/Applications/MacClean Agent.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

step() { printf '\n==> %s\n' "$*"; }
ok() { printf '    OK  %s\n' "$*"; }
warn() { printf '    !!  %s\n' "$*"; }
die() {
    printf '\nERROR: %s\n' "$*" >&2
    exit 1
}

[ "$(uname -s)" = Darwin ] || die "MacClean is for macOS."
if [ "$(id -u)" -eq 0 ]; then
    die "Run without sudo:  bash ~/MacClean/install.sh   (it asks for your password once)"
fi

# Log everything from here on, so any problem can be read back from ~/MacClean/reports.
mkdir -p "$MC_HOME/queue" "$MC_HOME/reports/rejected" "$MC_HOME/tmp" "$MC_HOME/.state" || die "cannot create $MC_HOME"
INSTALL_LOG="$MC_HOME/reports/install-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$INSTALL_LOG") 2>&1

printf 'MacClean installer %s  (%s)\n' "$INSTALLER_VERSION" "$(date '+%Y-%m-%d %H:%M:%S')"
printf 'macOS %s, user %s, %s\n' "$(sw_vers -productVersion 2>/dev/null)" "$(id -un)" "$(/bin/bash --version | head -n 1)"
printf 'source: %s\n' "$SRC_DIR"

USER_NAME=$(id -un)
case "$USER_NAME" in '' | *[!A-Za-z0-9._-]*) die "Unsupported user name '$USER_NAME' for a sudoers rule." ;; esac
case "$HOME" in /Users/* | /var/root) ;; *) die "Unexpected HOME=$HOME" ;; esac
case "$HOME" in *[\'\"\\\&\<\>\ ]*) die "HOME contains characters this installer does not handle: $HOME" ;; esac
for f in bin/macclean bin/macclean-root claude-code/SKILL.md; do
    [ -f "$SRC_DIR/$f" ] || die "Missing $SRC_DIR/$f - copy the whole folder (or clone the repo again)."
done
DEFAULT_CONFIG="$SRC_DIR/config.default"
[ -f "$DEFAULT_CONFIG" ] || DEFAULT_CONFIG="$SRC_DIR/config"
[ -f "$DEFAULT_CONFIG" ] || die "Missing $SRC_DIR/config.default"

for f in bin/macclean bin/macclean-root; do
    if ! err=$(/bin/bash -n "$SRC_DIR/$f" 2>&1); then
        die "$f failed the /bin/bash syntax check: $err"
    fi
done
printf 'syntax check (macOS /bin/bash): OK\n'

# Keep a copy of the toolkit in ~/MacClean when installing from somewhere else.
if [ "$SRC_DIR" != "$(cd -P "$MC_HOME" && pwd -P)" ]; then
    mkdir -p "$MC_HOME/bin" "$MC_HOME/claude-code"
    cp -f "$SRC_DIR/bin/macclean" "$SRC_DIR/bin/macclean-root" "$MC_HOME/bin/"
    cp -f "$SRC_DIR/claude-code/SKILL.md" "$MC_HOME/claude-code/"
    for f in install.sh uninstall.sh README.md config.default LICENSE; do [ -f "$SRC_DIR/$f" ] && cp -f "$SRC_DIR/$f" "$MC_HOME/"; done
fi
# Your settings live in ~/MacClean/config; updates never overwrite it.
[ -f "$MC_HOME/config" ] || cp "$DEFAULT_CONFIG" "$MC_HOME/config"

# ---------------------------------------------------------------------------
step "1/7  Admin password (asked once)"
sudo -v || die "sudo failed"
(while sudo -n true 2>/dev/null; do sleep 45; kill -0 "$$" 2>/dev/null || exit 0; done) &
KEEPALIVE=$!
disown "$KEEPALIVE" 2>/dev/null
trap 'kill "$KEEPALIVE" 2>/dev/null' EXIT

# ---------------------------------------------------------------------------
step "2/7  Install scripts into $OPT/bin (root-owned, not writable by you)"
[ -d /opt ] || sudo /bin/mkdir -m 755 /opt || die "cannot create /opt"
sudo /bin/mkdir -p "$OPT/bin" || die "cannot create $OPT/bin"
sudo /usr/sbin/chown root:wheel "$OPT" "$OPT/bin"
sudo /bin/chmod 755 "$OPT" "$OPT/bin"
sudo /usr/bin/install -o root -g wheel -m 755 "$SRC_DIR/bin/macclean" "$OPT/bin/macclean" || die "install failed"
sudo /usr/bin/install -o root -g wheel -m 755 "$SRC_DIR/bin/macclean-root" "$HELPER" || die "install failed"
sudo /usr/bin/xattr -c "$OPT/bin/macclean" "$HELPER" 2>/dev/null
# Every directory on the way to the helper must be root-owned and not group/world
# writable - otherwise a passwordless rule could be abused to swap the helper.
for p in / /opt "$OPT" "$OPT/bin" "$HELPER"; do
    owner=$(stat -f %u "$p")
    mode=$(stat -f %Lp "$p")
    [ "$owner" = 0 ] || die "$p is not owned by root - refusing to create a passwordless rule."
    [ $((8#$mode & 8#022)) -eq 0 ] || die "$p is group/world-writable - refusing to create a passwordless rule."
done
ok "macclean and macclean-root installed"

# ---------------------------------------------------------------------------
step "3/7  Command shortcut"
sudo /bin/mkdir -p /usr/local/bin
sudo /bin/ln -sfn "$OPT/bin/macclean" /usr/local/bin/macclean && ok "/usr/local/bin/macclean -> $OPT/bin/macclean"

# ---------------------------------------------------------------------------
step "4/7  Passwordless sudo for the fixed-action helper only"
if ! sudo /usr/bin/grep -Eq '^[[:space:]]*[#@]includedir[[:space:]]+/(private/)?etc/sudoers\.d' /etc/sudoers; then
    warn "/etc/sudoers does not include /etc/sudoers.d - skipped (system-level cleanup will be skipped)."
else
    sudo /bin/mkdir -p /private/etc/sudoers.d
    # A name containing '.' is ignored by sudo, so the temp file is inert until renamed.
    TMP_RULE=/private/etc/sudoers.d/.macclean.tmp
    printf '# MacClean: run the fixed-action cleanup helper without a password.\n# Only these exact commands are allowed. Remove with: sudo rm /etc/sudoers.d/macclean\n%s ALL=(root) NOPASSWD: %s check, %s scan, %s clean, %s deep-scan, %s deep\n' \
        "$USER_NAME" "$HELPER" "$HELPER" "$HELPER" "$HELPER" "$HELPER" |
        sudo /usr/bin/tee "$TMP_RULE" >/dev/null || die "cannot write sudoers rule"
    sudo /usr/sbin/chown root:wheel "$TMP_RULE"
    sudo /bin/chmod 440 "$TMP_RULE"
    if sudo /usr/sbin/visudo -cf "$TMP_RULE" >/dev/null; then
        sudo /bin/mv -f "$TMP_RULE" /private/etc/sudoers.d/macclean
        if sudo /usr/sbin/visudo -c >/dev/null 2>&1; then
            ok "rule installed: /etc/sudoers.d/macclean"
        else
            sudo /bin/rm -f /private/etc/sudoers.d/macclean
            die "sudoers validation failed - rule removed, nothing else changed."
        fi
    else
        sudo /bin/rm -f "$TMP_RULE"
        die "generated sudoers rule did not validate - nothing changed."
    fi
fi
kill "$KEEPALIVE" 2>/dev/null
sudo -k
if out=$(sudo -n "$HELPER" check 2>&1); then ok "verified without a password: $out"; else warn "passwordless check failed: $out"; fi

# ---------------------------------------------------------------------------
step "5/7  ~/MacClean folder, schedule state, Mole whitelist"
[ -f "$MC_HOME/.state/last_scheduled" ] || date +%s >"$MC_HOME/.state/last_scheduled"
if command -v mo >/dev/null 2>&1 || [ -x /opt/homebrew/bin/mo ]; then
    MO_BIN=$(command -v mo 2>/dev/null || echo /opt/homebrew/bin/mo)
    ok "Mole found: $("$MO_BIN" --version </dev/null 2>/dev/null | grep -i -m1 -E 'mole|[0-9]+\.[0-9]+\.[0-9]+')"
else
    warn "Mole (mo) not found. MacClean works without it, but install it for the broad cleanup: brew install mole"
fi
"$OPT/bin/macclean" _ensure-whitelist && ok "Mole whitelist protects Trash, Xcode archives, ~/.aws and Claude desktop caches"

# ---------------------------------------------------------------------------
step "6/7  Background agent (request queue + weekly clean when idle)"
make_app=1
if [ -d "$APP" ]; then
    bid=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null)
    ver=$(cat "$APP/Contents/Resources/macclean-agent-version" 2>/dev/null)
    if [ "$bid" = "$LABEL" ] && [ "$ver" = "$AGENT_APP_VERSION" ]; then
        make_app=0
        ok "agent app already present (kept, so its Full Disk Access grant stays valid)"
    elif [ "$bid" = "$LABEL" ]; then
        rm -rf "$APP"
    else
        die "$APP exists but is not MacClean's agent - move it away and re-run."
    fi
fi
if [ "$make_app" = 1 ]; then
    mkdir -p "$HOME/Applications"
    osacompile -o "$APP" \
        -e 'on run' \
        -e 'try' \
        -e "do shell script \"HOME='$HOME' /opt/macclean/bin/macclean agent > /dev/null 2>&1\"" \
        -e 'end try' \
        -e 'end run' || die "osacompile failed"
    PB=/usr/libexec/PlistBuddy
    INFO="$APP/Contents/Info.plist"
    $PB -c 'Delete :LSUIElement' "$INFO" 2>/dev/null
    $PB -c 'Add :LSUIElement bool true' "$INFO"
    $PB -c 'Delete :CFBundleIdentifier' "$INFO" 2>/dev/null
    $PB -c "Add :CFBundleIdentifier string $LABEL" "$INFO"
    $PB -c 'Delete :CFBundleName' "$INFO" 2>/dev/null
    $PB -c 'Add :CFBundleName string MacClean Agent' "$INFO"
    printf '%s\n' "$AGENT_APP_VERSION" >"$APP/Contents/Resources/macclean-agent-version"
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || warn "codesign failed (agent may still work)"
    ok "created $APP (no Dock icon)"
fi
mkdir -p "$HOME/Library/LaunchAgents"
cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP/Contents/MacOS/applet</string>
    </array>
    <key>QueueDirectories</key>
    <array>
        <string>$MC_HOME/queue</string>
    </array>
    <key>StartInterval</key>
    <integer>1800</integer>
    <key>RunAtLoad</key>
    <false/>
    <key>ProcessType</key>
    <string>Standard</string>
    <key>Nice</key>
    <integer>5</integer>
    <key>StandardOutPath</key>
    <string>$MC_HOME/reports/agent.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$MC_HOME/reports/agent.stderr.log</string>
</dict>
</plist>
EOF
plutil -lint "$PLIST" >/dev/null || die "LaunchAgent plist is invalid"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
sleep 1
launchctl bootstrap "gui/$(id -u)" "$PLIST" || die "launchctl bootstrap failed"
ok "LaunchAgent $LABEL loaded (queue: ~/MacClean/queue, schedule check every 30 min)"

# ---------------------------------------------------------------------------
step "7/7  Claude Code integration"
CC_RULES=("Bash(macclean:*)" "Bash(macclean)" "Bash(/usr/local/bin/macclean:*)" "Bash(/opt/macclean/bin/macclean:*)"
    "Bash(mo --version)" "Bash(mo clean --dry-run:*)" "Bash(mo purge --dry-run:*)" "Bash(mo analyze --json:*)"
    "Bash(mo status --json:*)" "Bash(mo history --json:*)" "Bash(df -h:*)")
tild() { case "$1" in "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;; *) printf '%s' "$1" ;; esac; }
# The JXA merger is written to a file first (a heredoc inside $(...) trips bash 3.2).
MERGE_JS="$MC_HOME/.state/merge-claude-settings.js"
cat >"$MERGE_JS" <<'JXA'
ObjC.import('Foundation');
function run(argv) {
    var path = argv[0];
    var rules = argv.slice(1);
    var fm = $.NSFileManager.defaultManager;
    var obj = {};
    if (fm.fileExistsAtPath(path)) {
        var s = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
        if (s.isNil()) throw new Error('cannot read ' + path);
        var txt = ObjC.unwrap(s);
        if (txt.trim().length > 0) obj = JSON.parse(txt);
    }
    if (obj === null || typeof obj !== 'object' || Array.isArray(obj)) throw new Error('not a JSON object');
    if (obj.permissions === undefined) obj.permissions = {};
    if (obj.permissions === null || typeof obj.permissions !== 'object' || Array.isArray(obj.permissions)) throw new Error('permissions is not an object');
    if (obj.permissions.allow === undefined) obj.permissions.allow = [];
    if (!Array.isArray(obj.permissions.allow)) throw new Error('permissions.allow is not an array');
    var added = 0;
    rules.forEach(function (r) { if (obj.permissions.allow.indexOf(r) < 0) { obj.permissions.allow.push(r); added++; } });
    if (added === 0) return 'unchanged';
    var out = $(JSON.stringify(obj, null, 2) + '\n');
    if (!out.writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null)) throw new Error('write failed');
    return 'added ' + added + ' rules';
}
JXA
merge_rules() { # settings.json -> prints result, non-zero on failure (file untouched)
    local f="$1" res rc
    [ -f "$f" ] && cp -p "$f" "$f.macclean-bak-$(date +%Y%m%d%H%M%S)"
    res=$(/usr/bin/osascript -l JavaScript "$MERGE_JS" "$f" "${CC_RULES[@]}" 2>&1)
    rc=$?
    printf '%s' "$res"
    return "$rc"
}
found_cc=0
for d in "$HOME/.claude" "$HOME"/.claude-*; do
    [ -d "$d" ] && [ ! -L "$d" ] || continue
    case "${d##*/}" in .claude-mem) continue ;; esac
    # Only real Claude Code config folders: a projects/ folder plus Claude Code's own files.
    [ -d "$d/projects" ] || continue
    [ -f "$d/settings.json" ] || [ -d "$d/shell-snapshots" ] || [ -f "$d/.claude.json" ] || continue
    found_cc=1
    mkdir -p "$d/skills/mac-cleanup"
    cp -f "$SRC_DIR/claude-code/SKILL.md" "$d/skills/mac-cleanup/SKILL.md" && ok "skill installed: $(tild "$d")/skills/mac-cleanup"
    if res=$(merge_rules "$d/settings.json"); then ok "$(tild "$d")/settings.json: $res"; else warn "$(tild "$d")/settings.json left unchanged: $res"; fi
done
[ "$found_cc" = 1 ] || ok "no Claude Code config folder found - skipped"

# ---------------------------------------------------------------------------
step "Full Disk Access for 'MacClean Agent' (lets the agent and Mole reach Trash, Safari and app caches)"
printf '%s %s source=%s\n' "$INSTALLER_VERSION" "$(date '+%Y-%m-%d %H:%M:%S')" "$SRC_DIR" >"$MC_HOME/.state/installed"
fda_ok=0
check_fda() {
    local out
    out=$("$OPT/bin/macclean" queue status --wait 90 2>&1)
    case "$out" in *"Full Disk Access (this process): yes"*) return 0 ;; esac
    return 1
}
if check_fda; then
    fda_ok=1
    ok "agent already has Full Disk Access"
elif [ -t 0 ]; then
    open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles" 2>/dev/null ||
        open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" 2>/dev/null
    open -R "$APP" 2>/dev/null
    printf '    System Settings > Privacy & Security > Full Disk Access is open, and Finder shows\n'
    printf '    "MacClean Agent". Drag it into the list (or click + and pick it), and switch it ON.\n'
    printf '    Press Enter when done (or type s and Enter to skip): '
    read -r ans
    if [ "${ans:-}" != s ]; then
        if check_fda; then fda_ok=1; ok "Full Disk Access confirmed"; else warn "not confirmed yet - Mole will only run from Terminal/Claude Code until it is granted"; fi
    fi
else
    warn "no terminal - grant Full Disk Access to $APP later in System Settings"
fi

step "Done"
"$OPT/bin/macclean" status
printf '\nTry:  macclean scan     (preview, changes nothing)\n      macclean clean    (normal clean)\n'
[ "$fda_ok" = 1 ] || printf '\nReminder: give "MacClean Agent" Full Disk Access so background runs include Mole.\n'
printf 'Install log: %s\n' "$(tild "$INSTALL_LOG")"
