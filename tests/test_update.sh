#!/bin/bash
# Update, one-line install and Mole-setup tests. A small local server plays GitHub (the
# releases/latest redirect and release archives), and Homebrew and Mole's installer are stubs that
# record how they were called. No network is used.
set -u
# SAFETY: these tests create a test user and folders under /home and /tmp. They must only ever
# run in a disposable Linux container - never on a Mac.
if [ "$(uname -s)" != Linux ] || [ "$(id -u)" -ne 0 ] || [ "${MACCLEAN_TEST_SANDBOX:-}" != 1 ]; then
    echo "Refusing to run: use a disposable Linux container as root with MACCLEAN_TEST_SANDBOX=1 (see tests/README.md)." >&2
    exit 2
fi
SRC=$(cd "$(dirname "$0")/.." && pwd -P)
U=mcupd
H=/home/$U
FIX=/tmp/macclean-update-fixtures
GH="$FIX/gh"
TAGS="$GH/gev979/mac-cleanup/archive/refs/tags"
PORT=18765
BASE="http://127.0.0.1:$PORT"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf '  PASS %s\n' "$*"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$*"; }
has() { if grep -q -- "$2" "$1" 2>/dev/null; then ok "$3"; else bad "$3 (missing '$2' in ${1##*/})"; fi; }
hasnt() { if grep -q -- "$2" "$1" 2>/dev/null; then bad "$3 (unexpected '$2' in ${1##*/})"; else ok "$3"; fi; }
absent() { if [ -e "$1" ] || [ -L "$1" ]; then bad "$2 (${1#"$H"/} exists)"; else ok "$2"; fi; }
present() { if [ -e "$1" ]; then ok "$2"; else bad "$2 (${1#"$H"/} missing)"; fi; }
exit_is() { if [ "$1" -eq "$2" ]; then ok "$3"; else bad "$3 (exit $1, expected $2)"; fi; }
no_tmp() { if ls -d "$1"/MacClean/tmp/update.* >/dev/null 2>&1; then bad "$2: update temp folder left behind"; else ok "$2: temp folder removed"; fi; }

CUR=$(sed -n 's/^MACCLEAN_VERSION="\(.*\)"$/\1/p' "$SRC/bin/macclean")
TESTED=$(sed -n 's/^MOLE_TESTED_VERSION="\(.*\)"$/\1/p' "$SRC/bin/macclean")
if [ -z "$CUR" ] || [ -z "$TESTED" ]; then echo "cannot read versions from bin/macclean" >&2; exit 2; fi

pkill -u "$U" 2>/dev/null
id "$U" >/dev/null 2>&1 || useradd -m -s /bin/bash "$U"
rm -rf "$H" "$FIX" && mkdir -p "$H" "$FIX/build" "$TAGS" && chown "$U:$U" "$H"

# ---------------------------------------------------------------- local "GitHub"
cat >"$FIX/server.py" <<'EOF'
import http.server, sys
root, port, latest_file = sys.argv[1], int(sys.argv[2]), sys.argv[3]
class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=root, **k)
    def log_message(self, *a):
        pass
    def special(self):
        if self.path.endswith('/releases/latest'):
            try:
                tag = open(latest_file).read().strip()
            except OSError:
                tag = ''
            if not tag:
                self.send_error(404)
                return True
            self.send_response(302)
            self.send_header('Location', self.path[:-len('latest')] + 'tag/' + tag)
            self.send_header('Content-Length', '0')
            self.end_headers()
            return True
        if '/releases/tag/' in self.path:
            self.send_response(200)
            self.send_header('Content-Length', '2')
            self.end_headers()
            if self.command == 'GET':
                self.wfile.write(b'ok')
            return True
        return False
    def do_GET(self):
        if not self.special():
            super().do_GET()
    def do_HEAD(self):
        if not self.special():
            super().do_HEAD()
http.server.ThreadingHTTPServer(('127.0.0.1', port), H).serve_forever()
EOF
python3 "$FIX/server.py" "$GH" "$PORT" "$FIX/latest" &
SERVER=$!
trap 'kill "$SERVER" 2>/dev/null' EXIT
latest() { printf '%s\n' "$1" >"$FIX/latest"; }
for _ in 1 2 3 4 5 6 7 8 9 10; do curl -fs -o /dev/null "$BASE/" && break; sleep 0.3; done

# mkrel TAG VERSION_INSIDE [broken|noinstaller|extra|failing] -> a release archive like GitHub's
mkrel() {
    local tag="$1" d="$FIX/build/$1/mac-cleanup-${1#v}"
    rm -rf "$FIX/build/$1" && mkdir -p "$d/bin"
    sed "s/^MACCLEAN_VERSION=\".*\"\$/MACCLEAN_VERSION=\"$2\"/" "$SRC/bin/macclean" >"$d/bin/macclean"
    cp "$SRC/bin/macclean-root" "$d/bin/macclean-root"
    cat >"$d/install.sh" <<'EOF'
#!/bin/bash
printf 'origin=%s\ntty=%s\n' "${MACCLEAN_INSTALL_ORIGIN:-}" "$([ -t 0 ] && echo yes || echo no)" >"$HOME/installer-ran"
EOF
    case "${3:-}" in
        broken) printf 'if then fi (\n' >>"$d/bin/macclean-root" ;;
        noinstaller) rm -f "$d/install.sh" ;;
        extra) echo x >"$FIX/build/$1/stray-file" ;;
        failing) echo 'exit 7' >>"$d/install.sh" ;;
    esac
    tar -czf "$TAGS/$tag.tar.gz" -C "$FIX/build/$1" .
}
mkrel v9.9.0 9.9.0
mkrel v9.9.1 9.9.0
mkrel v9.9.2 9.9.2 broken
mkrel v9.9.4 9.9.4 noinstaller
mkrel v9.9.5 9.9.5 extra
mkrel v9.9.6 9.9.6 failing
mkrel "v$CUR" "$CUR"
mkrel v1.0.0 1.0.0
echo "this is not a tar archive" >"$TAGS/v9.9.3.tar.gz"

# Mole's installer stub: installs the requested version into --prefix (default ~/.local/bin,
# standing in for /usr/local/bin) and records its arguments.
cat >"$FIX/mole-install.sh" <<'EOF'
#!/bin/bash
echo "$*" >>"$HOME/mole_installer.log"
dir="$HOME/.local/bin" ver=""
while [ $# -gt 0 ]; do
    case "$1" in --prefix) dir="$2"; shift 2 ;; *) ver="$1"; shift ;; esac
done
mkdir -p "$dir"
printf '#!/bin/bash\necho "Mole version %s"\n' "$ver" >"$dir/mo"
chmod 755 "$dir/mo"
EOF
MOLE_SHA=$(sha256sum "$FIX/mole-install.sh" | awk '{print $1}')
chmod -R a+rX "$FIX"

# ---------------------------------------------------------------- helpers
newhome() { # NAME -> a fresh, empty home folder for one scenario
    local d="$H/$1"
    mkdir -p "$d/.local/bin" "$d/MacClean"
    chown -R "$U:$U" "$d"
    printf '%s' "$d"
}
mkmo() { # FILE VERSION|- -> a stub Mole ("-": prints no version)
    mkdir -p "${1%/*}"
    if [ "$2" = - ]; then printf '#!/bin/bash\necho "Mole"\n' >"$1"; else printf '#!/bin/bash\necho "Mole version %s"\necho "macOS: 26.1"\n' "$2" >"$1"; fi
    chmod 755 "$1"
    chown -R "$U:$U" "$H"
}
mkbrew() { # BREW_FILE CELLAR_PREFIX LOG_NAME [fail] -> a stub Homebrew
    mkdir -p "${1%/*}"
    cat >"$1" <<EOF
#!/bin/bash
echo "\$*" >>"\$HOME/$3"
[ "${4:-}" = fail ] && exit 1
case "\$1 \${2:-}" in
    "upgrade mole" | "install mole")
        mkdir -p "$2/Cellar/mole/$TESTED/bin"
        printf '#!/bin/bash\necho "Mole version $TESTED"\n' >"$2/Cellar/mole/$TESTED/bin/mo"
        chmod 755 "$2/Cellar/mole/$TESTED/bin/mo"
        ln -sfn "$2/Cellar/mole/$TESTED/bin/mo" "\$HOME/.local/bin/mo" ;;
esac
EOF
    chmod 755 "$1"
    chown -R "$U:$U" "$H"
}
brewmole() { # HOME PREFIX VERSION -> an old Mole that Homebrew installed under PREFIX/Cellar
    mkmo "$2/Cellar/mole/$3/bin/mo" "$3"
    ln -sfn "$2/Cellar/mole/$3/bin/mo" "$1/.local/bin/mo"
    chown -h "$U:$U" "$1/.local/bin/mo"
}

EXTRA_PATH=""
INSTALLER_URL="file://$FIX/mole-install.sh"
INSTALLER_SHA="$MOLE_SHA"
envu() { # the test user's environment
    printf '%s\n' HOME="$1" PATH="${EXTRA_PATH:+$EXTRA_PATH:}/usr/bin:/bin" USER="$U" MACCLEAN_TEST_SANDBOX=1 \
        MACCLEAN_TEST_GITHUB="$BASE" MACCLEAN_TEST_MOLE_INSTALLER="$INSTALLER_URL" \
        MACCLEAN_TEST_MOLE_INSTALLER_SHA256="$INSTALLER_SHA"
}
mc() { # HOME ARGS... -> macclean as the test user, without a terminal
    local home="$1" e=()
    shift
    while IFS= read -r l; do e+=("$l"); done < <(envu "$home")
    runuser -u "$U" -- env -i "${e[@]}" bash "$SRC/bin/macclean" "$@"
}
mct() { # HOME ARGS... -> the same inside a pseudo-terminal
    local home="$1" e=()
    shift
    while IFS= read -r l; do e+=("$l"); done < <(envu "$home")
    runuser -u "$U" -- env -i "${e[@]}" timeout 120 script -qec "bash $SRC/bin/macclean $*" /dev/null
}
shu() { # HOME COMMAND -> a shell command as the test user inside a pseudo-terminal
    local home="$1" e=()
    while IFS= read -r l; do e+=("$l"); done < <(envu "$home")
    runuser -u "$U" -- env -i "${e[@]}" timeout 120 script -qec "$2" /dev/null </dev/null
}
OUT="$FIX/out.txt"

# ---------------------------------------------------------------- Mole
echo "== Mole: check first, update the way it was installed, install only if missing"
h=$(newhome m1); mkmo "$h/.local/bin/mo" "$TESTED"; mkbrew "$h/.local/bin/brew" "$h" brew_calls.log
mct "$h" _ensure-mole >"$OUT" 2>&1; exit_is $? 0 "current Mole: exit 0"
has "$OUT" "up to date" "current Mole is reported up to date"
absent "$h/brew_calls.log" "current Mole: Homebrew not touched"
absent "$h/mole_installer.log" "current Mole: installer not run"

h=$(newhome m2); mkmo "$h/.local/bin/mo" 99.1.0
mct "$h" _ensure-mole >"$OUT" 2>&1
has "$OUT" "Mole 99.1.0: up to date" "newer Mole is left alone"
absent "$h/mole_installer.log" "newer Mole: installer not run"

h=$(newhome m3); brewmole "$h" "$h" 1.32.0; mkbrew "$h/.local/bin/brew" "$h" brew_calls.log
mct "$h" _ensure-mole >"$OUT" 2>&1; exit_is $? 0 "old Homebrew Mole: exit 0"
has "$h/brew_calls.log" "^upgrade mole" "old Homebrew Mole is upgraded with 'brew upgrade mole'"
absent "$h/mole_installer.log" "old Homebrew Mole: Mole's installer not used"
has "$OUT" "Mole ready: Mole version $TESTED" "Homebrew upgrade result is verified"

h=$(newhome m3b); brewmole "$h" "$h/hb" 1.32.0
mkbrew "$h/hb/bin/brew" "$h/hb" owner_brew.log; mkbrew "$h/.local/bin/brew" "$h/hb" other_brew.log
mct "$h" _ensure-mole >"$OUT" 2>&1; exit_is $? 0 "two Homebrews: exit 0"
has "$h/owner_brew.log" "^upgrade mole" "two Homebrews: the brew that owns Mole's Cellar upgrades it"
absent "$h/other_brew.log" "two Homebrews: the other brew is not used"

h=$(newhome m3c); brewmole "$h" "$h" 1.32.0; mkbrew "$h/.local/bin/brew" "$h" brew_calls.log fail
mct "$h" _ensure-mole >"$OUT" 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "failing 'brew upgrade': non-zero exit" || bad "failing 'brew upgrade' exited 0"
absent "$h/mole_installer.log" "failing 'brew upgrade': no switch to Mole's installer"

h=$(newhome m3d); brewmole "$h" "$h/hb" 1.32.0
mct "$h" _ensure-mole >"$OUT" 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "Homebrew Mole without brew: non-zero exit" || bad "Homebrew Mole without brew exited 0"
has "$OUT" "brew was not found" "Homebrew Mole without brew: explained"
absent "$h/mole_installer.log" "Homebrew Mole without brew: Mole's installer not used"

h=$(newhome m4); mkmo "$h/.local/bin/mo" 1.32.0; mkbrew "$h/.local/bin/brew" "$h" brew_calls.log
mct "$h" _ensure-mole >"$OUT" 2>&1; exit_is $? 0 "old script Mole: exit 0"
has "$h/mole_installer.log" "^--prefix $h/.local/bin $TESTED\$" "old script Mole is updated in place (--prefix its own folder), pinned to $TESTED"
absent "$h/brew_calls.log" "old script Mole: not reinstalled through Homebrew"

h=$(newhome m4b); mkmo "$h/.local/bin/mole" 1.32.0; ln -s mole "$h/.local/bin/mo"; chown -h "$U:$U" "$h/.local/bin/mo"
mct "$h" _ensure-mole >"$OUT" 2>&1; exit_is $? 0 "script Mole linked inside its folder: exit 0"
has "$h/mole_installer.log" "^--prefix $h/.local/bin $TESTED\$" "mo -> mole in the same folder still counts as Mole's installer"

h=$(newhome m4c); mkmo "$h/src/mole/mole" 1.32.0; ln -s "$h/src/mole/mole" "$h/.local/bin/mo"; chown -h "$U:$U" "$h/.local/bin/mo"
mct "$h" _ensure-mole >"$OUT" 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "Mole linked from elsewhere: non-zero exit" || bad "Mole linked from elsewhere exited 0"
has "$OUT" "the way you installed it" "Mole linked from elsewhere: left alone, explained"
absent "$h/mole_installer.log" "Mole linked from elsewhere: installer not run"
[ -L "$h/.local/bin/mo" ] && ok "Mole linked from elsewhere: link untouched" || bad "Mole link was replaced"

h=$(newhome m4d); mkmo "$h/.local/bin/mo" -
mct "$h" _ensure-mole >"$OUT" 2>&1
has "$OUT" "version unknown" "Mole with unreadable version: left alone, explained"
absent "$h/mole_installer.log" "Mole with unreadable version: installer not run"

h=$(newhome m5); mkbrew "$h/.local/bin/brew" "$h" brew_calls.log
mct "$h" _ensure-mole >"$OUT" 2>&1; exit_is $? 0 "missing Mole + Homebrew: exit 0"
has "$h/brew_calls.log" "^install mole" "missing Mole is installed with 'brew install mole' when Homebrew exists"

h=$(newhome m6)
mct "$h" _ensure-mole >"$OUT" 2>&1; exit_is $? 0 "missing Mole, no Homebrew: exit 0"
has "$h/mole_installer.log" "^$TESTED\$" "missing Mole without Homebrew: Mole's installer, default location, pinned"
has "$OUT" "Homebrew is not needed" "output says Homebrew is not needed"

h=$(newhome m6b); mkmo "$h/bin/mo" "$TESTED"
EXTRA_PATH="$h/bin" mct "$h" _ensure-mole >"$OUT" 2>&1
has "$OUT" "outside the folders MacClean searches" "Mole elsewhere on the user's PATH: explained"
absent "$h/mole_installer.log" "Mole elsewhere on the user's PATH: no second copy installed"

h=$(newhome m7); printf 'USE_MOLE=0\n' >"$h/MacClean/config"; chown "$U:$U" "$h/MacClean/config"; mkbrew "$h/.local/bin/brew" "$h" brew_calls.log
mct "$h" _ensure-mole >"$OUT" 2>&1
has "$OUT" "USE_MOLE=0" "USE_MOLE=0 is respected"
absent "$h/brew_calls.log" "USE_MOLE=0: Homebrew not touched"
absent "$h/.local/bin/mo" "USE_MOLE=0: nothing installed"

h=$(newhome m8)
INSTALLER_URL="file://$FIX/no-such-installer.sh" mct "$h" _ensure-mole >"$OUT" 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "failed Mole download: non-zero exit" || bad "failed Mole download exited 0"
has "$OUT" "Could not download Mole's installer" "failed download is explained"

h=$(newhome m8b)
INSTALLER_SHA=0000000000000000000000000000000000000000000000000000000000000000 mct "$h" _ensure-mole >"$OUT" 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "Mole installer with wrong checksum: non-zero exit" || bad "wrong checksum exited 0"
has "$OUT" "checksum" "wrong checksum is explained"
absent "$h/mole_installer.log" "wrong checksum: Mole's installer not run"
absent "$h/.local/bin/mo" "wrong checksum: nothing installed"

h=$(newhome m9); mkmo "$h/.local/bin/mo" 1.32.0
mc "$h" _ensure-mole </dev/null >"$OUT" 2>&1; exit_is $? 2 "_ensure-mole without a terminal refuses (exit 2)"
absent "$h/mole_installer.log" "_ensure-mole without a terminal: nothing installed"

latest "v$CUR"
mc "$h" update --check >"$OUT" 2>&1; exit_is $? 0 "update --check: exit 0"
has "$OUT" "older than $TESTED" "update --check reports an old Mole"
absent "$h/mole_installer.log" "update --check changes nothing"
mc "$h" status >"$OUT" 2>&1
has "$OUT" "older than the tested $TESTED; run: macclean update" "status points an old Mole to 'macclean update'"

# ---------------------------------------------------------------- macclean update
echo "== macclean update"
latest v9.9.0
h=$(newhome u1); mkmo "$h/.local/bin/mo" "$TESTED"
mc "$h" update --check >"$OUT" 2>&1; exit_is $? 0 "check with a newer release: exit 0"
has "$OUT" "Update available: MacClean 9.9.0" "newer release found through the releases/latest redirect"
absent "$h/installer-ran" "update --check does not install"

h=$(newhome u2)
mc "$h" update </dev/null >"$OUT" 2>&1; exit_is $? 2 "update without a terminal refuses (exit 2)"
has "$OUT" "in Terminal" "refusal says to use Terminal"
absent "$h/installer-ran" "no terminal: installer not run"

h=$(newhome u3); mkmo "$h/.local/bin/mo" "$TESTED"
mct "$h" update >"$OUT" 2>&1; exit_is $? 0 "update to v9.9.0: exit 0"
has "$h/installer-ran" "origin=release v9.9.0 (github.com/gev979/mac-cleanup)" "release installer ran, origin recorded"
has "$h/installer-ran" "tty=yes" "release installer gets the terminal (for the password)"
no_tmp "$h" "update to v9.9.0"

for t in "v9.9.1:contains MacClean '9.9.0'" "v9.9.2:fails the syntax check" "v9.9.3:not a valid archive" \
    "v9.9.4:has no install.sh" "v9.9.5:Unexpected archive layout" "v9.9.9:Download of v9.9.9 failed"; do
    tag=${t%%:*}; why=${t#*:}
    latest "$tag"
    h=$(newhome "bad-$tag"); mkmo "$h/.local/bin/mo" "$TESTED"
    mct "$h" update >"$OUT" 2>&1; rc=$?
    [ "$rc" -ne 0 ] && ok "$tag refused (non-zero exit)" || bad "$tag should be refused"
    has "$OUT" "$why" "$tag: reason shown ($why)"
    has "$OUT" "nothing was changed" "$tag: says nothing was changed"
    absent "$h/installer-ran" "$tag: installer not run"
    no_tmp "$h" "$tag"
done

latest v9.9.6
h=$(newhome u3b); mkmo "$h/.local/bin/mo" "$TESTED"
mct "$h" update >"$OUT" 2>&1; exit_is $? 7 "failing release installer: its exit code is passed on"
no_tmp "$h" "failing release installer"

latest v9.9.0
h=$(newhome u3c); mkmo "$h/.local/bin/mo" "$TESTED"
runuser -u "$U" -- bash -c "sleep 600 & mkdir -p '$h/MacClean/.state/lock' && echo \$! > '$h/MacClean/.state/lock/pid'"
mct "$h" update >"$OUT" 2>&1; exit_is $? 75 "update refuses while a clean is running (exit 75)"
has "$OUT" "in progress" "running clean: explained"
absent "$h/installer-ran" "running clean: installer not run"
pkill -u "$U" sleep 2>/dev/null

latest "v$CUR"
h=$(newhome u4); mkmo "$h/.local/bin/mo" "$TESTED"
mct "$h" update >"$OUT" 2>&1; exit_is $? 0 "up to date: exit 0"
has "$OUT" "MacClean is up to date ($CUR)" "same version is reported up to date"
has "$OUT" "Mole $TESTED: up to date" "up-to-date update still checks Mole"
absent "$h/installer-ran" "up to date: installer not run"

h=$(newhome u5); mkmo "$h/.local/bin/mo" 1.32.0
mct "$h" update >"$OUT" 2>&1; exit_is $? 0 "up to date + old Mole: exit 0"
has "$h/mole_installer.log" "$TESTED\$" "up-to-date MacClean still updates an old Mole"

h=$(newhome u6); mkmo "$h/.local/bin/mo" "$TESTED"
mct "$h" update --force >"$OUT" 2>&1; exit_is $? 0 "update --force: exit 0"
has "$h/installer-ran" "origin=release v$CUR" "update --force reinstalls the current release"

latest v1.0.0
h=$(newhome u6b); mkmo "$h/.local/bin/mo" "$TESTED"
mct "$h" update --force >"$OUT" 2>&1
has "$OUT" "newer than the latest release" "update --force never downgrades"
absent "$h/installer-ran" "no downgrade: installer not run"
mc "$h" update --check --force >"$OUT" 2>&1
hasnt "$OUT" "Update available" "--check --force does not announce a same/older version"

: >"$FIX/latest"
h=$(newhome u7); mkmo "$h/.local/bin/mo" 1.32.0
mc "$h" update --check >"$OUT" 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "no release reachable: non-zero exit" || bad "no release reachable exited 0"
has "$OUT" "Could not find the latest MacClean release" "no release reachable: explained"
has "$OUT" "older than $TESTED" "no release reachable: Mole is still checked"

latest 'v1.0;touch /tmp/pwned'
h=$(newhome u8)
mc "$h" update --check >"$OUT" 2>&1 && bad "malformed tag accepted" || ok "malformed release tag rejected"
absent /tmp/pwned "malformed tag: nothing executed"

# ---------------------------------------------------------------- one-line install
echo "== bootstrap.sh (one-line install)"
latest v9.9.0
h=$(newhome b1)
shu "$h" "bash -c \"\$(cat $SRC/bootstrap.sh)\"" >"$OUT" 2>&1; exit_is $? 0 "bash -c \"\$(curl ...)\" form: exit 0"
has "$h/installer-ran" "origin=release v9.9.0" "bash -c form: release installer ran"
has "$h/installer-ran" "tty=yes" "bash -c form: installer gets the terminal"

h=$(newhome b2)
shu "$h" "cat $SRC/bootstrap.sh | bash" >"$OUT" 2>&1; exit_is $? 0 "curl ... | bash form: exit 0"
has "$h/installer-ran" "origin=release v9.9.0" "pipe form: release installer ran"
has "$h/installer-ran" "tty=yes" "pipe form: installer gets the terminal"

h=$(newhome b3)
shu "$h" "bash $SRC/bootstrap.sh --dry-run" >"$OUT" 2>&1; exit_is $? 0 "bootstrap --dry-run: exit 0"
has "$OUT" "Dry run: nothing installed" "bootstrap --dry-run says so"
absent "$h/installer-ran" "bootstrap --dry-run: installer not run"

latest v9.9.1
h=$(newhome b4)
shu "$h" "bash $SRC/bootstrap.sh" >"$OUT" 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "bootstrap refuses a mismatched release" || bad "bootstrap accepted a mismatched release"
absent "$h/installer-ran" "bootstrap, mismatched release: installer not run"

pkill -u "$U" 2>/dev/null
printf '\nRESULT: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
