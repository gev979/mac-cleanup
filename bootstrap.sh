#!/bin/bash
# MacClean one-line installer. Paste into Terminal:
#
#     /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/gev979/mac-cleanup/main/bootstrap.sh)"
#
# (curl -fsSL .../bootstrap.sh | bash works too.) Downloads the latest MacClean release from
# GitHub, checks it, and runs its install.sh, which asks for your password once and sets up
# everything else (including Mole). Nothing is cleaned during install. Needs only what ships
# with macOS (no git, no Homebrew).
#
#   --dry-run   download and check the release, then stop (installs nothing)
#
# Everything runs inside main(), so a download cut off halfway never runs half a script, and a
# script piped into bash keeps reading itself from the pipe.
set -u
REPO="gev979/mac-cleanup"
GITHUB_WEB="https://github.com"
BOOT_TMP=""

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

main() {
    local dry=0 c url tag n top f v origin
    case "${1:-}" in
        '') ;;
        --dry-run) dry=1 ;;
        *) die "unknown option: $1 (only --dry-run)" ;;
    esac
    if [ "$(uname -s)" != Darwin ]; then
        # Test-only: the Linux test suite runs this against a local stand-in for GitHub.
        if [ "$(uname -s)" = Linux ] && [ "${MACCLEAN_TEST_SANDBOX:-0}" = 1 ]; then
            GITHUB_WEB="${MACCLEAN_TEST_GITHUB:-$GITHUB_WEB}"
        else
            die "MacClean is for macOS."
        fi
    fi
    [ "$(id -u)" -ne 0 ] || die "Run this as your normal user, without sudo (the installer asks for your password once)."
    for c in curl tar; do command -v "$c" >/dev/null 2>&1 || die "$c is missing (it ships with macOS)."; done

    printf 'MacClean: looking up the latest release of github.com/%s...\n' "$REPO"
    url=$(curl -fsSIL --connect-timeout 10 --max-time 30 -o /dev/null -w '%{url_effective}' \
        "$GITHUB_WEB/$REPO/releases/latest") || die "cannot reach GitHub."
    tag=${url##*/}
    case "$tag" in v[0-9]*) ;; *) die "no release found at github.com/$REPO/releases." ;; esac
    case "$tag" in *[!A-Za-z0-9._-]*) die "unexpected release name: $tag" ;; esac

    BOOT_TMP=$(mktemp -d "${TMPDIR:-/tmp}/macclean-install.XXXXXX") || die "cannot create a temp folder."
    trap 'rm -rf "$BOOT_TMP"' EXIT
    printf 'Downloading MacClean %s...\n' "${tag#v}"
    curl -fsSL --connect-timeout 10 --max-time 300 -o "$BOOT_TMP/release.tar.gz" \
        "$GITHUB_WEB/$REPO/archive/refs/tags/$tag.tar.gz" || die "download failed."
    mkdir "$BOOT_TMP/src" || die "cannot create a temp folder."
    tar -xzf "$BOOT_TMP/release.tar.gz" -C "$BOOT_TMP/src" 2>/dev/null || die "the download is not a valid archive."
    n=$(find "$BOOT_TMP/src" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
    top=$(find "$BOOT_TMP/src" -mindepth 1 -maxdepth 1 -type d | head -n 1)
    if [ "$n" != 1 ] || [ -z "$top" ]; then die "unexpected archive layout."; fi
    for f in install.sh bin/macclean bin/macclean-root; do
        [ -f "$top/$f" ] || die "the release has no $f."
        /bin/bash -n "$top/$f" 2>/dev/null || die "$f in the release fails the syntax check."
    done
    v=$(sed -n 's/^MACCLEAN_VERSION="\([^"]*\)"$/\1/p' "$top/bin/macclean" | head -n 1)
    [ "$v" = "${tag#v}" ] || die "release $tag contains MacClean '$v' - refusing it."
    printf 'Release %s downloaded and checked.\n' "$tag"

    if [ "$dry" = 1 ]; then
        printf 'Dry run: nothing installed.\n'
        return 0
    fi
    origin="release $tag (github.com/$REPO)"
    # The installer asks for the password in the terminal, also when this script came through a pipe.
    if [ -t 0 ]; then
        MACCLEAN_INSTALL_ORIGIN="$origin" /bin/bash "$top/install.sh"
    elif (: </dev/tty) 2>/dev/null; then
        MACCLEAN_INSTALL_ORIGIN="$origin" /bin/bash "$top/install.sh" </dev/tty
    else
        die "no terminal to ask for your password - run this in Terminal."
    fi
}

main "$@"
exit $?
