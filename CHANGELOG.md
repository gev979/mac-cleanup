# Changelog

## 1.1.0 - 2026-11-19

Install and update without manual steps.

- One-line install: `bootstrap.sh` downloads the latest release, checks it and runs the
  installer. No git, Homebrew or Xcode tools needed.
- Mole is set up automatically and checked first: a current Mole is kept, an older one is
  updated where and how it was installed (`brew upgrade mole` by the Homebrew that owns it, or
  Mole's own installer in Mole's own folder), and a missing one is installed (Homebrew if present,
  otherwise Mole's installer). A Mole MacClean did not recognise is left alone. Mole's installer
  is pinned to the tested 1.73.0 by commit and SHA-256 checksum.
- `macclean update` updates MacClean (download, version and syntax checks, then the installer)
  and Mole when they are outdated; `--check` only looks. It needs a terminal, waits for a running
  clean, never downgrades, and still checks Mole when GitHub is unreachable. Nothing updates in
  the background.
- The installer notices by itself when Full Disk Access is switched on (no Enter needed) and puts
  the agent's path on the clipboard for the "+" button.
- `macclean status` flags a missing or outdated Mole; `macclean help` prints the full help.

## 1.0.0 - 2026-11-19

First public release.

- `macclean` CLI: `scan`, `clean`, `deep-scan`, `deep`, `report`, `status`, `queue`.
- Runs Mole's `mo clean` (user level, Trash protected) plus guarded extras: old Playwright
  browser revisions no installed Playwright needs, caches inside Playwright MCP browser profiles,
  Playwright MCP screenshots and old test reports, Playwright/Puppeteer/Chromium/Claude temp
  leftovers, stray temp files, Claude Code debug logs and shell snapshots, stale npx packages,
  nvm/libvips download caches, Claude desktop caches while the app is closed.
- Fixed-action root helper (old system logs, crash reports, core dumps, aborted wallpaper
  downloads; Time Machine local snapshots in deep mode) with a narrowly scoped passwordless rule.
- Background agent: weekly clean when idle, request queue for Claude Cowork.
- Claude Code skill + allow-rules installed automatically.
