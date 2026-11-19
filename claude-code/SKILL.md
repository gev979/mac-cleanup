---
name: mac-cleanup
description: Free up disk space on this Mac safely with the MacClean toolkit (Mole + guarded extras + passwordless system helper). Use for "clean my Mac", "free up space", "disk is full", "what's using my storage", Playwright/temp/Claude cache cleanup, deep clean, or checking the weekly cleanup.
allowed-tools: Bash(macclean:*), Bash(/usr/local/bin/macclean:*), Bash(mo --version), Bash(mo clean --dry-run:*), Bash(mo analyze --json:*), Bash(mo history --json:*), Bash(df -h:*)
---

# Mac cleanup with MacClean

MacClean is installed on this Mac. It wraps **Mole** (`mo clean`, user level, Trash protected)
and adds guarded extras: old Playwright browser revisions nothing installed needs, caches inside
Playwright MCP browser profiles (never their logins), Playwright MCP screenshots and old test
reports, Playwright/Puppeteer/Chromium/Claude temp leftovers, stray temp files, Claude Code debug
logs and shell snapshots, stale npx packages, nvm/libvips download caches, Claude desktop caches
(only while the app is closed). A root-owned helper with fixed actions cleans old system logs,
crash reports, core dumps and aborted downloads; it runs through a passwordless sudoers rule, so
no run ever asks for a password.

Layout: scripts in `/opt/macclean/bin` (root-owned), command `macclean`, settings
`~/MacClean/config`, request queue `~/MacClean/queue`, results `~/MacClean/reports`
(`<id>.summary.txt`, `<id>.log`, `<id>.done`, `history.tsv`). A LaunchAgent runs
`~/Applications/MacClean Agent.app` (has Full Disk Access) for queued requests and a weekly
clean when the Mac is idle. Every Mac installs the toolkit once; if this Mac does not have it
yet, follow section 7.

## 1. Pick the route

- **Native macOS shell** (Claude Code; `uname` prints `Darwin` and `command -v macclean` works):
  run `macclean queue <mode> --wait 1800`. That runs inside the agent, which has Full Disk
  Access, so Mole covers everything. If the agent does not answer, fall back to
  `macclean <mode>` directly.
- **Cowork** (`device_bash` is a Linux VM that only sees connected folders): use the request
  queue, section 3. Never try to run `macclean`, `mo` or `sudo` inside the VM.

## 2. Modes and consent

| User asks | Mode | Consent |
|---|---|---|
| "clean my Mac", "free up space", routine cleanup | `clean` | Pre-approved by the user: run it, then report |
| "what would you clean?", "preview" | `scan` | Read-only |
| "deep clean", "I need a lot of space" | `deep-scan`, then `deep` | Show the deep-scan summary and get an explicit yes before `deep` |
| "what is using my disk?" | `report` | Read-only |
| "is the cleanup working?", "last run" | `status` | Read-only |

Deep adds: unused Docker images older than 30 days + old build cache, `mo purge --yes`
(node_modules / build folders in projects idle 7+ days, they need a reinstall or rebuild),
Trash items that have been in the Trash 7+ days, old Puppeteer browsers, Time Machine local
snapshots older than 24h. Say this plainly when asking for the yes.

## 3. Cowork procedure

1. **Folder.** Look at the connected folders (session reminder or `get_device_info`). If none
   is `~/MacClean` or contains it, call `device_request_folder_access` with `["~/MacClean"]`
   and reason "Send cleanup requests to MacClean and read its reports". The approval prompt
   appears on the Mac; if it times out, tell the user to look at their Mac and retry once.
2. **Check install**: `device_list_dir` on `~/MacClean/.state` must list `installed`. If not,
   follow section 7 (set up a new Mac). If `~/MacClean/reports/history.tsv` shows no earlier
   clean on this Mac, do a `scan` first, show it, and run `clean` only after the user's OK.
3. **Send the request and wait.** Request id: `ID=<UTC yyyymmdd-HHMMSS>-<mode>-cowork`
   (letters, digits, `.`, `_`, `-` only). The request file holds just the mode word.
   - **Route A - `device_bash` works** (one call, stays under the 180 s limit; set `MODE`):
     ```bash
     MC=$(ls -d "$HOME"/mnt/MacClean "$HOME"/mnt/*/MacClean 2>/dev/null | head -n1)
     MODE=clean; ID="$(date -u +%Y%m%d-%H%M%S)-$MODE-cowork"
     printf '%s\n' "$MODE" > "$MC/tmp/$ID.req" && mv "$MC/tmp/$ID.req" "$MC/queue/$ID.req" && echo "ID=$ID"
     for i in $(seq 1 80); do [ -f "$MC/reports/$ID.done" ] && break; sleep 2; done
     if [ -f "$MC/reports/$ID.done" ]; then cat "$MC/reports/$ID.done"; echo ---; cat "$MC/reports/$ID.summary.txt"
     else echo "STILL_RUNNING"; ls "$MC/queue"; tail -n 5 "$MC/reports/$ID.log" 2>/dev/null; fi
     ```
     STILL_RUNNING: poll again with the same `ID` (loop + cat only).
   - **Route B - `device_bash` missing or failing** (no shell needed): in the cloud workspace
     write the file with Bash (`printf 'clean\n' > /mnt/user-data/outputs/$ID.req`), then
     `device_commit_files` with that `stagedPath` and `devicePath` `~/MacClean/queue/<ID>.req`.
     Poll with `device_list_dir` on `~/MacClean/reports` (cloud `sleep 20` between checks) until
     `<ID>.done` appears, then `device_stage_files` the `<ID>.done` and `<ID>.summary.txt` and
     Read the staged copies.
   A clean usually takes 2-10 minutes, a deep clean longer. If the `.req` file still sits in
   `queue/` after a minute, the agent is not running: ask the user to run `macclean status` in
   Terminal (or re-run the installer) and report what it says.
4. `status=busy` in the `.done` file means another run was in progress - wait and retry.
   `status=rejected` means the mode word was wrong.

## 4. Reporting

Lead with the outcome: free space before -> after (+freed), or "would free" for previews.
Then the main categories from the summary, the Mole line, and the system-level line.
For each "Large items left alone" entry say in one line what it is and how the user could
reclaim it (Claude Code transcripts -> `cleanupPeriodDays` in Claude Code settings; Docker ->
deep clean; Unreal DerivedDataCache -> rebuildable, costs shader recompiles; Claude Cowork VM
bundles -> re-downloaded if removed; Xcode archives -> keep for crash symbolication; Android
emulators -> delete unused AVDs in Android Studio). Mention notes that matter (Full Disk Access
missing, Claude desktop open so its caches were skipped, Time Machine snapshots delaying freed
space). Quote sizes from the summary, not your own `du`. Do not paste whole logs.

## 5. Rules

- Never delete anything yourself: no `rm`, `find -delete`, or moving files to clean up, in the
  VM or in a native shell. All removal goes through MacClean or Mole; a skip is deliberate -
  do not retry it by hand.
- Never run `sudo`, ask for the password, or touch `/etc/sudoers*`. The only privileged action
  is the fixed helper MacClean calls itself.
- `deep` only after the user saw the deep-scan and said yes.
- Stay out of personal folders. Report folder sizes, not file names inside them. Do not run
  `du`/`find` over the home folder through `device_bash`: it is very slow and can hang the VM;
  ask the agent for a `report` instead.
- To protect something the user cares about (after they agree): add its path to
  `EXTRA_PROTECT=` in `~/MacClean/config` (colon-separated) for MacClean, and append the path as
  a new line to `~/.config/mole/whitelist` for Mole. Then run a `scan` to confirm.
- Behaviour changes (schedule, ages, deep switches) go into `~/MacClean/config`; edit that one
  line in place. Do not edit the scripts unless the user asks.

## 6. Troubleshooting

- Summary note "Mole was skipped ... no Full Disk Access": System Settings > Privacy & Security >
  Full Disk Access > enable "MacClean Agent" (in ~/Applications).
- Note "Passwordless rule ... missing" or status shows the helper MISSING: re-run
  `bash ~/MacClean/install.sh`.
- Status says Mole is "not found" or "older than the tested" version: run
  `macclean update --check` to confirm, then ask the user to run `macclean update` in Terminal
  (it may ask for their password). Do not install or upgrade Mole yourself.
- Agent not picking up requests: in Terminal `launchctl kickstart -k gui/$(id -u)/local.macclean.agent`,
  then `macclean status`; re-running the installer reloads it.
- Install problems: newest `~/MacClean/reports/install-*.log`.
- Logs: `~/MacClean/reports/<id>.log`; Mole's own record: `mo history --json --limit 5`.

## 7. Set up a new Mac

The skill works on any Mac; each Mac installs the toolkit once. Source (public):
https://github.com/gev979/mac-cleanup - nothing in it is tied to one user or machine.

1. **Install - only the user can do this** (it needs their password). Give them this one line
   to paste into Terminal:
   `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/gev979/mac-cleanup/main/bootstrap.sh)"`
   It downloads the latest release and sets up everything, Mole included: a current Mole is kept,
   an older one is updated the way it was installed, a missing one is installed (Homebrew is not
   needed). Do not install Mole, Homebrew or git, or clone the repo, beforehand. At the end the
   user drags "MacClean Agent" into Full Disk Access and switches it on; the installer notices by
   itself.
2. **Verify.** `~/MacClean/.state/installed` exists; read the newest
   `~/MacClean/reports/install-*.log` and check for "helper verified without a password", "Mole
   is ready" and "Full Disk Access confirmed". Then do the first `scan`, show it, and run `clean`
   only after the user's OK.
3. **Updates:** `macclean update --check` is safe to run yourself (it changes nothing) and says
   whether MacClean or Mole is outdated. The update itself, `macclean update`, must run in the
   user's Terminal because it may ask for their password. Config, reports and the Full Disk
   Access grant are kept.
