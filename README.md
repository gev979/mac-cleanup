# mac-cleanup

**MacClean**: safe, thorough, hands-off storage cleanup for macOS, built around
[Mole](https://github.com/tw93/Mole). You install it with one command (your password is asked
once; Mole is set up for you), and then it cleans weekly in the background. You can also run it on demand from Terminal, Claude Code or
Claude Cowork.

> Not affiliated with iMobie's "MacClean" app or with the Mole project. Mole does the heavy
> lifting; this repo adds unattended scheduling, extra guarded targets and Claude integration.

## What it does

- **Mole** (`mo clean`) handles the broad, well-tested cache cleanup. The Trash, Xcode archives,
  `~/.aws` and Claude desktop caches are kept out of Mole's reach.
- **Guarded extras**, things Mole deliberately leaves alone:
  - old Playwright browser revisions that no installed Playwright still needs
  - caches inside Playwright MCP browser profiles (cookies and logins are kept)
  - Playwright MCP screenshots, old Playwright `test-results/` and `playwright-report/`
  - Playwright / Puppeteer / Chromium / Claude leftovers in temp folders, plus stray old temp files
  - Claude Code debug logs, shell snapshots and old todo files (never transcripts or settings)
  - stale `npx` packages that are not running, nvm and sharp/libvips download caches
  - Claude desktop's browser caches, only while the app is closed
- **System level**: a tiny root-owned helper with fixed actions removes old system logs,
  crash reports, core dumps and aborted wallpaper downloads. It runs through a passwordless
  sudoers rule that allows exactly five commands.
- **Background agent**: a LaunchAgent and a small app with Full Disk Access run a weekly clean
  once the Mac has been idle for 10 minutes. The agent also serves requests dropped into
  `~/MacClean/queue`, which is how Claude Cowork drives it.

## Safety model

- **Allow-list only.** Every deletion goes through one gate. It refuses unless the path is inside
  an explicitly allowed folder, outside every protected tree, owned by you, not a mount point,
  not open by any process (`lsof`), not on any running command line (`ps`), and free of sockets.
  Temporary items also need an age threshold.
- **Never touched**: Documents, Desktop, Downloads, Pictures, Movies, Music, iCloud and
  CloudStorage, Mail, Messages, Keychains, Preferences, app containers, SSH/GPG/cloud credentials,
  `~/.config`, dotfiles, Claude Code transcripts/history/settings/skills/plugins, claude-mem data,
  Claude desktop config/extensions/VM bundles, browser profiles and cookies, Docker volumes,
  Xcode archives, AI models (Ollama, Hugging Face, LM Studio).
- **Previews.** `scan` and `deep-scan` delete nothing and show what would go.
- **Logs.** Every run writes `~/MacClean/reports/<id>.log` and `.summary.txt`; Mole keeps its own
  record in `~/Library/Logs/mole/operations.log`.
- **Narrow root access.** The passwordless rule only covers
  `/opt/macclean/bin/macclean-root check|scan|clean|deep-scan|deep`. The helper is root-owned,
  takes no paths, removes regular files only (never folders), skips open files and never crosses
  volumes. The installer refuses to add the rule if any directory on the helper's path can be
  written by anyone other than root.

## Requirements

- macOS on Apple Silicon (tested on macOS 27). Intel Macs should work but are untested.
- An admin account, for the one-time password, and an internet connection during install.
- Nothing else: no Homebrew, no git, no Xcode tools. Mole is set up for you (see below).

## Install

Paste this into Terminal:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/gev979/mac-cleanup/main/bootstrap.sh)"
```

It downloads the latest release, checks it, and runs the installer, which asks for your password
once and does everything else:

- **Mole is checked first, never reinstalled for nothing.** A Mole at the tested version
  (1.73.0) or newer is left alone. An older one is updated the way it was installed: with
  `brew upgrade mole` if it came from Homebrew, otherwise with Mole's own installer. If Mole is
  missing, it is installed with Homebrew when you have Homebrew, otherwise with Mole's own
  installer (Homebrew is not needed).
- The background agent, the passwordless helper and the Claude Code skill are set up.
- Last, it opens **System Settings > Privacy & Security > Full Disk Access** and shows **MacClean
  Agent** in Finder: drag it into the list and switch it on. The installer notices by itself and
  finishes. This switch is the one step macOS does not let any installer do for you.

Nothing is cleaned during install. Prefer to look first? `bash bootstrap.sh --dry-run` downloads
and checks the release without installing anything. From a clone (for development):
`git clone https://github.com/gev979/mac-cleanup.git && bash mac-cleanup/install.sh`.

It installs:

| What | Where |
|---|---|
| Mole, only if missing or older than the tested version | Homebrew if you have it, otherwise `/usr/local/bin` (Mole's own installer) |
| Scripts, root-owned | `/opt/macclean/bin/` (`macclean`, `macclean-root`) |
| Command | `/usr/local/bin/macclean` |
| Passwordless rule for the helper only | `/etc/sudoers.d/macclean` |
| Your settings, queue and reports | `~/MacClean/` |
| Background agent | `~/Applications/MacClean Agent.app` + `~/Library/LaunchAgents/local.macclean.agent.plist` |
| Claude Code skill + allow-rules (if Claude Code is present) | `~/.claude*/skills/mac-cleanup/`, `settings.json` (backed up first) |
| Mole protections | `~/.config/mole/whitelist` (backed up first) |

## Use

| Command | What it does |
|---|---|
| `macclean scan` | Preview of a normal clean. Deletes nothing. |
| `macclean queue clean --wait 1800` | Normal clean, run by the background agent (Full Disk Access) |
| `macclean deep-scan` | Preview of a deep clean. Deletes nothing. |
| `macclean queue deep --wait 3600` | Deep clean, see below |
| `macclean report` | What is using space. Deletes nothing. |
| `macclean status` | Install health, schedule, last runs |
| `macclean update` | Update MacClean and Mole if newer versions exist (see below) |

`macclean clean` also works directly. Terminal usually lacks Full Disk Access, though, so a few
protected caches get skipped; `queue` avoids that. No command ever asks for a password.

**Deep clean** adds: unused Docker images older than 30 days plus old build cache, `mo purge`
(node_modules and build folders in projects idle 7+ days, which need a reinstall or rebuild
afterwards), Trash items that have been in the Trash 7+ days, old Puppeteer browsers, and Time
Machine local snapshots older than 24 hours.

## Settings

Edit `~/MacClean/config` (created from [`config.default`](config.default); updates never
overwrite it): schedule (`weekly` / `daily` / `off`), idle minutes, age thresholds, deep-clean
switches, project folders searched for Playwright output, and extra protected paths
(`EXTRA_PROTECT`). To protect something from Mole, add a line to `~/.config/mole/whitelist`.

## Claude integration

- **Claude Code**: the installer adds the `mac-cleanup` skill and allow-rules, so you can say
  *"clean my Mac"* and Claude Code runs it without permission prompts.
- **Claude Cowork** (Claude desktop app): add [`claude-code/SKILL.md`](claude-code/SKILL.md) to
  your Claude account as a skill. The simplest way is to open a Cowork chat, attach the file and
  ask Claude to save it as your `mac-cleanup` skill. Then *"clean my Mac"*, *"deep clean"* or
  *"what's using my disk?"* work in any chat that has your Mac linked. Claude drops a request into
  `~/MacClean/queue` and reports the agent's summary; it never deletes anything itself.

## Update

```bash
macclean update           # updates what is outdated, leaves the rest alone
macclean update --check   # only looks, changes nothing
```

It checks GitHub for a newer MacClean release and checks Mole against the tested version. A newer
MacClean is downloaded, checked and installed (your password is asked once); a Mole older than the
tested version is updated the way it was installed. Your config, reports and the agent's Full Disk
Access grant are kept. Nothing updates by itself in the background: a tool that deletes files
should not change behind your back. From a clone, `git pull && bash install.sh` works too.

## Uninstall

```bash
bash ~/MacClean/uninstall.sh
```

This removes the agent, `/opt/macclean`, the sudoers rule, the command link, and the Claude Code
skill and rules. It keeps `~/MacClean` (your config and reports), Mole and Mole's whitelist.

## Development

- [`tests/`](tests/) holds fixture tests that build a fake home folder full of traps and check
  that only intended items are removed, plus tests for `macclean update` and the Mole setup
  against local stub releases, a stub Homebrew and a stub Mole installer. They run in a
  disposable Linux container:
  `docker run --rm -v "$PWD":/src -w /src ubuntu:24.04 bash tests/ci.sh`
- CI runs shellcheck, the fixture tests, and a macOS job that checks syntax with macOS's
  bash 3.2, does a dry-run scan with the real BSD tools, and checks `bootstrap.sh --dry-run` and
  `macclean update --check` against the real GitHub release.
- Releasing: bump `MACCLEAN_VERSION` in `bin/macclean` (and `INSTALLER_VERSION` in `install.sh`),
  add a `CHANGELOG.md` entry, tag `vX.Y.Z` and publish a GitHub release. `bootstrap.sh` and
  `macclean update` refuse a release whose `MACCLEAN_VERSION` does not match its tag.

## License

GPL-3.0, the same as [Mole](https://github.com/tw93/Mole). See [LICENSE](LICENSE).
