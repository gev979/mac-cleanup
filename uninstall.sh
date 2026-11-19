#!/bin/bash
#
# MacClean uninstaller:  bash ~/MacClean/uninstall.sh
# Removes the agent, the LaunchAgent, /opt/macclean, the sudoers rule, the command
# link and the Claude Code skill + allow-rules it added. Keeps ~/MacClean (your config
# and reports), Mole itself and Mole's whitelist - delete those yourself if you want.

set -u
LABEL=local.macclean.agent
APP="$HOME/Applications/MacClean Agent.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
[ "$(id -u)" -ne 0 ] || { echo "Run without sudo: bash ~/MacClean/uninstall.sh"; exit 1; }

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$PLIST"
if [ -d "$APP" ] && [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null)" = "$LABEL" ]; then
    rm -rf "$APP"
fi
echo "Agent removed."

sudo /bin/rm -f /private/etc/sudoers.d/macclean
if [ -L /usr/local/bin/macclean ]; then sudo /bin/rm -f /usr/local/bin/macclean; fi
sudo /bin/rm -rf /opt/macclean
echo "System files removed (/opt/macclean, /etc/sudoers.d/macclean, /usr/local/bin/macclean)."

for d in "$HOME/.claude" "$HOME"/.claude-*; do
    [ -d "$d/skills/mac-cleanup" ] && rm -rf "$d/skills/mac-cleanup" && echo "Removed skill from $d"
    [ -f "$d/settings.json" ] || continue
    cp -p "$d/settings.json" "$d/settings.json.macclean-bak-$(date +%Y%m%d%H%M%S)"
    /usr/bin/osascript -l JavaScript - "$d/settings.json" <<'JXA' >/dev/null 2>&1
ObjC.import('Foundation');
function run(argv) {
    var path = argv[0];
    var s = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
    if (s.isNil()) return 'unreadable';
    var obj = JSON.parse(ObjC.unwrap(s));
    if (!obj.permissions || !Array.isArray(obj.permissions.allow)) return 'nothing';
    var before = obj.permissions.allow.length;
    obj.permissions.allow = obj.permissions.allow.filter(function (r) {
        return !(/^Bash\((macclean|\/usr\/local\/bin\/macclean|\/opt\/macclean\/bin\/macclean)(:\*)?\)$/.test(r) ||
                 /^Bash\(mo (--version|clean --dry-run:\*|purge --dry-run:\*|analyze --json:\*|status --json:\*|history --json:\*)\)$/.test(r) ||
                 r === 'Bash(df -h:*)');
    });
    if (obj.permissions.allow.length === before) return 'nothing';
    $(JSON.stringify(obj, null, 2) + '\n').writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);
    return 'removed';
}
JXA
done
echo "Done. Kept: ~/MacClean (config + reports), Mole and ~/.config/mole/whitelist."
echo "To remove Mole too: 'brew uninstall mole' if it came from Homebrew, otherwise 'mo remove'."
