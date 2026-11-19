# Changelog

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
