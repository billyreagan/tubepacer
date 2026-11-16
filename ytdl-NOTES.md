# ytdl 1.28.0 — Changelog & Logic Notes

**Name:** **tubepacer** is the program (the repository, release and project name); **`ytdl`** is the command you type and the script's file name (`ytdl.ps1`, `ytdl.cmd`). Notes below say `ytdl` because they describe the script.

`ytdl` is a PowerShell wrapper around [yt-dlp](https://github.com/yt-dlp/yt-dlp). It downloads a single YouTube video, an entire playlist or a channel from one URL, can follow channels and playlists and fetch only what is new (1.15.0), with consistent naming, resume and skip-on-re-run, automatic recovery from YouTube's sign-in/cookie problems, a measured remaining-time estimate, and optional parallel downloading.

**Version:** 1.28.0 (2026-11-16) · `ytdl -Version` prints it · constant `$YtdlVersion` in `ytdl.ps1`

**Versioning scheme:** semantic-style. Since 2026-11-12, **2.0.0 and above may be used when warranted** (a major change: different defaults or behaviour, or a redesign); before that, everything stayed in 1.x.x.
- **x.Y.0 (minor):** new options, features or behaviour changes (e.g. an ETA shown before the first download).
- **x.y.Z (patch):** fixes and tuning with no new options (e.g. adjusted ETA priors or weights, bug fixes).
- Each release bumps `$YtdlVersion` in `ytdl.ps1` and gets a changelog entry here with what changed and how it was verified.

## Files

A release (`tubepacer.zip`) holds these files; extract them together into one folder on `PATH`.

| File | Role |
|---|---|
| `ytdl.ps1` | The tool. Runs in Windows PowerShell 5.1 and PowerShell 7. Workers, `-Schedule` and the browser button run it by its own full path, so keep it where it was installed (or re-run `-Schedule` / the browser-button setup after moving it) |
| `ytdl.cmd` | Launcher for Command Prompt and the Run dialog: runs `ytdl-cmd.ps1` in PowerShell 7 (`pwsh`) if installed, otherwise Windows PowerShell 5.1 |
| `ytdl-cmd.ps1` | Helper for `ytdl.cmd`: re-reads the raw command line so option values keep their `:` and `-`, then runs `ytdl.ps1` |
| `ytdl-NOTES.md` | This file |

**State files ytdl creates:**

| Path | Purpose |
|---|---|
| `<Out>\.ytdl-archive.txt` | yt-dlp download archive: one `youtube <id>` line per finished video. Re-runs skip these. |
| `<Out>\.ytdl-rate.json` | Saved ETA measurements (overhead, bandwidth, bitrate), keyed as described under *ETA model* |
| `<Out>\.ytdl.lock` (+ `.info`) | Folder lock held (exclusively open) while a run downloads there; `.info` names the holder (1.2.1) |
| `<Out>\.ytdl-logs\<date>-<pid>.log` | Run log: every line ytdl printed plus hidden lines and `[ytdl-event]` markers; newest 50 kept (1.2.1) |
| `<Out>\.ytdl-pace.json` | Adaptive pacing level after the last bot check, shared by workers; honoured for 24 h (1.3.0) |
| `<Out>\.ytdl-client.json` | "Fast extraction doesn't work for this URL": `Urls` maps each such playlist/video URL to when it was found; that URL uses default clients for 7 days (1.4.0; per URL since 1.11.0, was the whole folder) |
| `<Out>\.ytdl.stop` | Per-folder stop signal from `ytdl -Stop -Out <dir>` (1.2.1) |
| `%TEMP%\ytdl.stop` | Global stop signal from `ytdl -Stop`; cleared by the next run |
| `%TEMP%\ytdl-<pid>-wK-<n>.log(.err)` | `-Parallel` worker output, deleted when the run ends; stale ones (dead coordinator) are deleted by the next coordinator (1.2.1) |
| `%TEMP%\ytdl-<pid>-wK-<n>.log.queue.json` | `-Parallel`: that worker's part of the coordinator's scan; the worker reads and deletes it (1.7.0) |
| `%LOCALAPPDATA%\ytdl\plugins\ytdl\yt_dlp_plugins\postprocessor\ytdl_thumbs.py` | Thumbnail-check helper for yt-dlp, written by `ytdl.ps1` (embedded copy) when missing or outdated; safe to delete (1.7.0) |
| `%LOCALAPPDATA%\ytdl\plugins\ytdl\yt_dlp_plugins\extractor\ytdl_formats.py` | Format-check helper: re-asks with the default clients when YouTube offers only the 360p combined format; written like the above; safe to delete (1.9.0) |
| `%LOCALAPPDATA%\ytdl\yt-dlp-dir\` | yt-dlp's official directory build (`yt-dlp_win.zip`), used instead of winget's one-file exe while it's the same version; `ytdl-version.txt` holds its version and the size/time stamp of the winget exe it matches. Delete the folder to go back to winget's exe (1.10.0) |
| `%LOCALAPPDATA%\ytdl\content.json` | Resolution-check result per URL and `-Quality` (max height), reused for 7 days, entries dropped after 30 (1.9.0) |
| `%TEMP%\ytdl-probe-<pid>.txt` | `-Precise` batch file, deleted after the probe |
| `<Out>\ytdl-failed.txt`, `<Out>\.ytdl-failed.json` | Videos that failed, per URL, with link and reason; entries drop out once downloaded, files deleted when empty (1.16.0) |
| `<Out>\.ytdl-sub-<hash>.txt` | A subscription's downloaded files (`upload_date<TAB>id<TAB>path`), the only files `-Keep`/`-KeepDays` may delete (1.16.0) |
| `%TEMP%\ytdl.pause`, `<Out>\.ytdl.pause`, `%TEMP%\ytdl.pauses.txt` | Pause signals (all runs / one folder) and the list of folder pauses a plain `-Resume` clears (1.16.0) |
| `%LOCALAPPDATA%\ytdl\browser-button.json`, `browser-button.html`, `HKCU\Software\Classes\ytdl` | Browser button: saved options, the bookmark page, the link handler (1.16.0) |
| `%LOCALAPPDATA%\ytdl\subscriptions.json` | Subscriptions: URL, `Out`, saved options, added / last sync / new count / exit code. Override the path with `YTDL_SUBSCRIPTIONS` (1.15.0) |
| `%LOCALAPPDATA%\ytdl\pace.json` | YouTube limit guard, shared by every run and the benchmarks (mutex `Local\ytdl-pace`): breaker cooldown, recent trips and openings, the held pacing level, and the last hour's video starts signed in / out. Follows `YTDL_STATE` (1.25.0) |
| `%LOCALAPPDATA%\ytdl\sync.log` | One line per `-Sync` start, subscription result and end (1.15.0) |
| `%LOCALAPPDATA%\ytdl\tools.json` | Cached folders of yt-dlp/ffmpeg/deno (1.2.1) |
| `%LOCALAPPDATA%\ytdl\update-check.json` | When yt-dlp's age was last checked (1.3.0) |
| `%LOCALAPPDATA%\ytdl\bandwidth.json` | `Draws`: last 50 single-download speeds (MiB/s), median = typical-speed prior (1.4.2; since 1.8.0 only one-at-a-time runs add, once a cap is known). `Caps`: total MiB/s of the last 10 full 3+-worker runs, median = the connection cap (1.8.0; seeded with 13.7, 14.5, 14.9 from the 2001–2003 runs) |

**Dependencies** (installed via winget): `yt-dlp.yt-dlp` (2026.10.26), `yt-dlp.FFmpeg` (merge/remux, thumbnails, ffprobe), `DenoLand.Deno` (JS runtime for YouTube's player challenges). aria2 was tried and removed (see 0.9.0).

## Option reference

| Option | Default | What it does |
|---|---|---|
| `<Url>` (positional) | — | Video, playlist or channel URL (a bare channel URL uses its Videos tab, 1.15.0) |
| `-Out <dir>` | Videos folder | Base download folder (also holds the archive and rate file) |
| `-Folder <name>` | playlist title / `YouTube` | Fixed subfolder name instead of the playlist title |
| `-Quality best\|4320\|2160\|1440\|1080\|720\|480\|360\|240\|144` | `best` | Max video height (4320, 240, 144: 1.22.0) |
| `-AudioOnly` | off | mp3 instead of video |
| `-Subs` | off | Embed English subtitles (manual + auto) |
| `-Items "1-10,15"` | all | Playlist positions to download |
| `-Browser firefox\|chrome\|edge\|brave\|opera\|vivaldi\|chromium` | — | Use that browser's signed-in YouTube session (fixes "not a bot") |
| `-Cookies <file>` | — | Use an exported cookies.txt instead |
| `-Sleep <s>` | auto | **Auto (default, 1.3.0):** adaptive pacing, fastest when signed in, slowing down a level on any bot check or rate limit. A number fixes the pause at `s`–`2s` between videos plus 1 s between page requests; `0` = no pauses. |
| `-Retries <n>` | `3` | Extra passes after a pass with errors (only failed items are retried) |
| `-RetryDelay <s>` | `60` | Wait before each retry pass (1.18.0: unless given, the first retry waits 15 s) |
| `-StallMinutes <n>` | `10` | Kill a pass with no output for `n` minutes (hang) |
| `-MaxErrors <n>` | `10` | Stop after `n` ERROR lines in a row with no success |
| `-CookieRestarts <n>` | `10` | With `-Browser`: instant restarts on rotated cookies |
| `-FragmentRestarts <n>` | `5` | Restart with fresh stream URLs on a fragment 404 loop |
| `-MinFreeGB <n>` | `2` | Stop cleanly if free space on the download drive drops below this during a run (1.2.1) |
| `-NoSpaceCheck` | off | Skip the up-front "will it fit" check (1.2.1) |
| `-Parallel <1-8>` | `3` | Download this many videos at once (separate worker processes). Default 3 at ≤480p since 1.5.0 and at every quality since 1.9.0; a single video, or one left, uses one worker. `-Parallel 1` turns it off. |
| `-Fragments <0-8>` | `3` with 1–2 workers, off with 3+ | Fetch each file as 10 MiB pieces, this many at once (yt-dlp fetches them one at a time). On by default with 1 or 2 workers (a single video, a 2-video run, `-Parallel 1`/`2`); with 3+ workers the connection is already full. `0`/`1` = off (1.12.0; 2 workers since 1.13.0) |
| `-NoMetadata` | off | Don't embed title/date/uploader tags; saves ~1 s per video (1.5.0) |
| `-NoThumbnail` | off | Don't embed cover art; saved ~2 s per video on old uploads that lack HD thumbnails (1.6.0); since 1.7.0's thumbnail check, only ~0.5 s (one thumbnail download + embed) |
| `-Fast360` | off | With `-Quality 360`: YouTube's combined H.264/AAC stream (format 18) for players without AV1. ~15% faster per video but ~75% bigger files at similar quality, so it's for compatibility, not speed (1.5.0). |
| `-Dynamic`, `-Chunk <n>` | off, `3` | *Experimental:* with `-Parallel`, hand out batches of `n` videos from a shared queue instead of a fixed split. Measured ~5% faster on average, within noise (1.3.0). |
| `-Estimate` | off | Print count, runtime, size and ETA, then exit without downloading |
| `-Precise` | off | Look up exact file sizes first (~9 s/video) for an accurate ETA at mixed resolutions |
| `-NoProbe` | off | Turn off the background size lookup used above 480p (1.3.0) |
| `-AutoUpdate` | off | If yt-dlp is 7+ days old (checked at most daily), update it first (1.3.0) with the manager it came from: Scoop, winget, pip or pipx; Chocolatey gets the admin command printed instead (1.26.1) |
| `-NoFastClient` | off | Use yt-dlp's default YouTube clients instead of the faster `web_embedded` extraction (1.4.0) |
| `-Subscribe` | — | Save `<Url>` with `-Out` and the options given, for `-Sync` (1.15.0) |
| `-Sync` | — | Download what's new on every subscription; with `-Estimate`, preview only (1.15.0) |
| `-Subscriptions` | — | List subscriptions and the schedule (1.15.0) |
| `-Unsubscribe` | — | Remove the subscription `<Url>` or number; files kept (1.15.0) |
| `-Schedule daily\|hourly\|off`, `-At HH:mm` | —, `03:00` | Run `-Sync` as a Windows scheduled task (`ytdl sync`), or remove it (1.15.0) |
| `-MinMinutes <n>`, `-MaxMinutes <n>` | off | Skip videos shorter / longer than this; a video of unknown length passes (1.16.0) |
| `-Match <regex>`, `-Exclude <regex>` | off | Keep only titles matching / not matching (case-insensitive) (1.16.0) |
| `-After <date or span>` | off | Only videos uploaded on or after `2026-10-01`, or within `"30 days"`, `"2 weeks"`, `"6 months"`, `"1 year"`; a span is recomputed at every run (1.16.0) |
| `-Keep <n>`, `-KeepDays <n>` | off | Subscriptions: after each `-Sync`, delete the subscription's videos beyond the newest n / older than n days (1.16.0) |
| `-NoProgressBar` | off | Don't draw the green progress bar (it's already off when output isn't a console window) (1.17.0) |
| `-Pause`, `-Resume` | — | Pause every running ytdl, or resume; with `-Out <dir>` only runs downloading there. In a download window press P (P or R resumes) (1.16.0) |
| `-BrowserButton on\|off` | — | Register the `ytdl://` link handler and write the bookmark-button page (options given with it are what the buttons use), or remove them (1.16.0) |
| `-FromLink`, `-FileList` | — | Internal: the `ytdl://` link a button opened; the file list `-Sync` passes for retention. Not for direct use (1.16.0) |
| `-Stop` | — | Signal every running ytdl to stop; with `-Out <dir>`, only runs downloading to that folder (1.2.1) |
| `-YtdlpArgs '...'` | — | More yt-dlp options as one string; connection options reach every yt-dlp call, the rest the download only; options ytdl manages are refused (1.18.0). From Command Prompt write `-YtdlpArgs:"..."` when the value contains `:` |
| `-Notify auto/on/off` | `auto` | Windows notification when a run or sync ends; auto = runs over 2 min, failures, stops, syncs with new videos or errors (1.18.0) |
| `-Library jellyfin/plex` | — | Media-server layout: `<Channel>\Season <year>\<Channel> - <date> - <Title> [id].mp4`, episode images, poster.jpg; jellyfin adds an .nfo per episode. `-Folder` names the show. Saved with `-Subscribe` (1.19.0) |
| `-Add` | — | If a ytdl download is running, queue this link (with its options) for it; otherwise download now (1.20.0) |
| `-Queue`, `-ClearQueue` | — | List the queued links and the downloads running; empty the queue (1.20.0) |
| `-AudioFormat mp3/m4a/opus/best` | mp3 | Audio format; implies `-AudioOnly`. m4a/opus keep YouTube's own stream (no re-encode) (1.21.0) |
| `-SponsorBlock mark/remove` | — | Chapters at SponsorBlock segments, or cut sponsor/self-promo/interaction segments out (1.21.0) |
| `-LimitRate 5M` | — | Cap the whole run's speed; split across the downloads at once, pieces off (1.21.0) |
| `-PoToken` | off | Fetch YouTube PO tokens through the bgutil provider (yt-dlp plugin + a local server on deno, installed into `%LOCALAPPDATA%\ytdl\pot` on first use). Mainly for signed-out runs (1.22.0) |
| `-SubLangs en,de` | — | Subtitle languages to embed (implies `-Subs`; `all` = every language). 1.23.0 |
| `-LiveChat` | off | Save the live-chat replay as a .json next to the video (never embedded). 1.23.0 |
| `-Template "%(id)s - %(title)s"` | ytdl's name | yt-dlp output template for the file name only; the folder is still ytdl's (`-Folder`). 1.23.0 |
| `-Container mp4\|mkv\|webm` | `mp4` | Container of the merged file (webm falls back to mkv when the streams don't fit). 1.23.0 |
| `-Codec auto\|h264\|vp9\|av1` | `auto` | Preferred video codec at the chosen height. 1.23.0 |
| `-Section "1:00-2:30"` | — | Download only that part of one video (comma-separated for several); exact cuts; own archive, so the whole video can still be downloaded. 1.23.0 |
| `-SplitChapters` | off | Also write one file per chapter, in a folder named after the video. 1.23.0 |
| `-Live` | off | Record a live stream from its start, or wait for a scheduled one (checks every minute). One stream: a video link or a channel's `/live` link. Pieces off, stall watchdog off unless `-StallMinutes` is given. 1.23.0 |
| `-History [N]` | 20 | List the last N downloads (date, height, size on disk or "deleted", title, folder); `-Match` filters titles. Recorded in `%LOCALAPPDATA%\ytdl\history.tsv` from 1.23.0 on |
| `-Feed` / `-FeedBase <url>` | off | Subscription option: after each `-Sync`, write a podcast feed (`feed.xml`, RSS 2.0) of the files still in the folder. `-FeedBase` = the web address the folder is served at (implies `-Feed`); without it the links are `file:///`. 1.23.0 |
| `-IgnoreCooldown` | off | Start even while the YouTube limit guard is on (1.25.0). The guard still records new limits. |
| `-Doctor` | — | Check yt-dlp, ffmpeg, deno, sign-in (with `-Browser`/`-Cookies`), disk, pacing, subscriptions and the schedule; exit 1 if something failed (1.18.0). Also ytdl's own version, copies of a tool on PATH, the last run, unfinished files (1.26.0). The drive (network, OneDrive, FAT32, exFAT), long paths, a write test, why cookies may not load, the clock and reachability, VPN/proxy, IPv6 after bot checks, and the schedule's result in words and its settings (1.27.0). `-Doctor <video url>`: one video's check (1.28.0) |
| `-Report` | — | With `-Doctor` (or alone): save the results to a text file on the Desktop with links, logins, user, PC and profile names hidden, and copy it for a GitHub issue (1.26.0) |
| `-Version` | — | Print the version |
| `-Worker`, `-WorkerCount`, `-NoScan`, `-LowResContent`, `-ContentHeight`, `-QueueFile` | — | Internal, set by `-Parallel` on its workers. Not for direct use. |

**Exit codes:** `0` all done · `1` finished, but some videos still failed after retries · `2` stopped (`-Stop`, error loop, cookie-restart limit, or not enough disk space) · `3` another ytdl run already holds this output folder (1.2.1) · `75` YouTube limit guard: the run stopped or refused to start until the cooldown ends; re-run the same command after it (1.25.0).

---

## Changelog

### 1.28.0 — `-Doctor <url>`: one video's check (2026-11-16)
| Part | Detail |
|---|---|
| **Request** | One `yt-dlp -J --no-playlist` for the link, signed in when `-Browser`/`-Cookies` is given. It goes through the limit guard: skipped (INFO) while the breaker is open (unless `-IgnoreCooldown`) or when the hour's budget is used, and counted in the budget when it runs. A bot check or 429 in the answer is recorded as a pace event. Channel and playlist links get INFO "checks one video link" with no request |
| **video** | Available (signed in/out) with title, length and availability; or why not, in words: private, members-only, age-restricted, Premium, region-blocked, gone (removed/terminated), not started yet (premiere or live in X, or the start time), bot check / HTTP 429, PO token needed (`-PoToken`), unsupported link, no answer from YouTube, else yt-dlp's own line. Each with a fix |
| **streams** | Live now: OK and a `-Live` command. Upcoming: WARN with the start time, `-Live` waits for it. Just ended: WARN that YouTube is still processing it |
| **formats** | Best on offer (short side, fps, codec: H.264/VP9/AV1/H.265; storyboards ignored) against `-Quality`: what that quality gets, or that the best is below it. `-AudioOnly`: the best audio stream and kbps. WARN when only a 360p single file came back (JavaScript challenge failed: deno), FAIL when no video formats came back |
| **archive** | INFO when the video is already in the folder's archive (a run there skips it), with the line to delete |
| **command** | A suggested `ytdl "<url>"` with `-Quality`/`-AudioOnly`/`-Live`, adding `-Browser firefox` when the video needs sign-in and the check ran signed out |
| **Report** | `-Report` hides the title and id as `<video>` (with links as `<link>`) |
| **Code** | `Get-VideoFacts` (hook YTDL_TEST_INFO: a JSON or error-text sample), `Test-Video`, `Test-VideoArchive`, `Get-ShortSide`, `Get-CodecName`. Samples: tests\data\doctor-url\ (24) |

**Verified:** tests\v1.28.0.ps1 61/61 (offline: 9 JSON and 15 error samples through the judge, full -Doctor <url> runs for budget counting, archive, bot event, channel link, youtu.be, open breaker and used budget, report redaction); v1.27.0.ps1 90/90, v1.26.1.ps1 18/18, v1.26.0.ps1 43/43 with versions set to 1.28.0. A real run with the breaker open skipped the request as designed (3.3 s).
### 1.27.0 — `-Doctor`: drive, cookies, network and schedule checks (2026-11-16)
| Check | Detail |
|---|---|
| **drive** | WARN for a network drive or UNC path (slow merges, a dropped link breaks the file being written), a folder inside OneDrive (uploads while writing, Files On-Demand can move finished videos online), and FAT/FAT32 (4 GB file limit). INFO for exFAT (no journal) and removable drives. Works when the folder doesn't exist yet |
| **long paths** | INFO when Windows long paths are off and the folder is long enough (path + ~190 characters for channel/playlist subfolders and a title) to pass 260; gives the admin `Set-ItemProperty ... LongPathsEnabled 1` command |
| **write test** | Creates and deletes `.ytdl-write-test-<pid>` in an existing folder. FAIL when it can't; on access denied with Defender's Controlled folder access on, the fix names the Allow-an-app setting for pwsh.exe, yt-dlp.exe and ffmpeg.exe |
| **cookies** | Only when sign-in didn't pass: a Chromium browser that is open (its cookie file is locked) and Chrome 127+'s app-bound encryption, with -Browser firefox or -Cookies as the fix. A `-Cookies` file: no youtube.com cookies, no sign-in cookies (exported signed out), expired, or 15+ days old (WARN if sign-in failed, else INFO) |
| **internet / clock** | One HEAD request to youtube.com (6 s timeout): WARN when unreachable, WARN when the clock is 2+ minutes off its Date header (sign-in and TLS can fail), with Sync now / `w32tm /resync` |
| **VPN / proxy** | INFO when a VPN adapter (WireGuard, OpenVPN, NordLynx, Mullvad, ...) or a Windows/env/`--proxy` proxy is on: shared addresses get more bot checks. Only the kind is shown, never addresses or logins |
| **IPv6** | INFO `-YtdlpArgs '--force-ipv4'` when the PC has a global IPv6 address and the last run hit bot checks |
| **schedule** | Task Scheduler result codes in words (finished, some failed, limit guard 75, running, not run yet, stopped, skipped while still running, refused on battery, script not found, window closed; others in hex, read as unsigned). INFO when a task changed by hand won't start (or stops) on battery on a PC with a battery, or skips runs missed while asleep |
| **Code** | Each check is a `Test-*` judge fed facts by a `Get-*` gatherer (`New-Check`, `Out-Checks`). Test hooks: YTDL_TEST_FS, _LONGPATHS, _CFA, _PROCS, _CLOCK, _NET, _TASK. `Get-LastRun` results carry `Bot` |

**Verified:** tests\v1.27.0.ps1 90/90 (offline: each check fed fake facts, a real write test incl. a denied folder, cookie files, task codes, two full -Doctor runs with the hooks); tests\v1.26.1.ps1 18/18 and v1.26.0.ps1 43/43 with versions set to 1.27.0. A real -Doctor run takes ~3 s.
### 1.26.1 — fix: `-AutoUpdate` uses the right updater (2026-11-16)
| Change | Detail |
|---|---|
| **Right updater** | `-AutoUpdate` always ran `winget upgrade yt-dlp.yt-dlp`, so for a Scoop, pip or pipx yt-dlp it failed or installed a second copy that the first one hid on PATH. It now runs the command the doctor already shows for the copy that runs: `scoop update yt-dlp`, `pipx upgrade yt-dlp`, `python -m pip install -U yt-dlp` (with the python.exe next to its Scripts folder when there is one) or `winget upgrade --id <id>` (the id read from the package folder) |
| **Chocolatey** | Needs an admin shell, so `-AutoUpdate` prints `choco upgrade yt-dlp` instead of running it |
| **Hints** | The 30-day "yt-dlp is old" warning names the same command, not always winget. `-Doctor`'s "or run downloads with -AutoUpdate" note now shows for every install but Chocolatey |
| **Code** | `Get-UpdateHint` moved from the doctor block to script scope; new `Invoke-ToolUpdate` (`YTDL_TEST_UPDATE=print` returns the command line without running it) |

**Verified:** tests\v1.26.1.ps1 18/18 (offline: command for Scoop, pipx, pip with and without a python.exe next to Scripts, winget default and folder ids, Chocolatey not run, a fake scoop really run, the age-check block wired to it); tests\v1.26.0.ps1 43/43 with its version strings set to 1.26.1.
### 1.26.0 — `-Doctor` explains more, `-Report` (2026-11-16)
| Change | Detail |
|---|---|
| **Update hints by install** | Each tool's update and install hint now matches how it was installed: Scoop, winget (the package id is read from its folder, so ffmpeg from `yt-dlp.FFmpeg` gets that id, not `Gyan.FFmpeg`), pip, pipx or Chocolatey. The `-AutoUpdate` note shows only for winget installs |
| **Copies on PATH** | WARN when PATH holds two or more copies of yt-dlp, ffmpeg or deno: lists each copy and its version, says which one runs, and how to remove the others |
| **ytdl version** | Compares ytdl with the latest GitHub release (asked once a day, cached in the state folder; silent INFO when offline). The hint is `scoop update tubepacer` for Scoop installs, else the release page |
| **Leftover lock note** | `running` now checks the lock itself. A note left by a crashed run gives INFO "nothing is running here" instead of a stale pid |
| **Last run** | One line on how the newest run in the folder ended: finished, stopped by `-Stop`, stopped by the limit guard, didn't start, yt-dlp refused an option, finished with errors (the first error, plus a sign-in hint on bot checks) or ended without finishing |
| **Unfinished files** | Counts `.part`, `.part-Frag*`, `.ytdl` and `.temp.*` files up to 3 folders deep; WARN at 1 GB or more, with the command that deletes them |
| **`-Report`** | Saves the doctor's lines plus Windows version, install method and console encoding to `Desktop\ytdl-doctor-<time>.txt`, copies it to the clipboard and prints the new-issue link. Links, account options, user, PC and profile names are hidden |

**Verified:** tests\v1.26.0.ps1 43/43 (offline: hints for 8 install paths, copies on PATH, lock held/released, unfinished files, 10 last-run log shapes, redaction; full `-Doctor` runs in PowerShell 7 with the release check stubbed newer/offline, and `-Report` alone in 5.1: file saved, no user or PC name). Real `-Doctor` run here: stale note and the refused-option last run shown. Check-Ytdl: ascii, parse 7/5.1, names.
### 1.25.1 — Pulse in `-Doctor` (2026-11-16)
| Change | Detail |
|---|---|
| **Pulse mark** | The all-clear line of `-Doctor` now shows Pulse, the tubepacer mark, instead of 1.24.0's Pacey face: one line, `--/\/-` in cyan (the heartbeat), `\` in magenta (the dip), `/-` in green (the recovery), a white play button (`U+25B6`), then the green "Everything ytdl needs is in order." `Write-PaceyFace` is now `Write-PulseMark`. Built from `[char]` codes, so the script stays ASCII. Problem and warning summaries and exit codes are unchanged |

**Verified:** `Write-PulseMark` loaded by AST and run in PowerShell 7 and 5.1 (both print the mark on one line); `-Version` prints 1.25.1. Check-Ytdl: ascii, parse 7/5.1, names, case variants.
### 1.25.0 — YouTube limit guard (2026-11-15)
YouTube's limits are per IP and per account, escalate when ignored (bot check, then 429, then hours-long blocks) and decay only with quiet time. Pacing used to react only inside one run, and only by slowing down. Research and sources: `docs\pacing-research-2026-11-15.md`.

| Change | Detail |
|---|---|
| **Circuit breaker** | Opens on an HTTP 429 / "try again later", on a bot check at the slowest pacing level, or on 2 trips within 10 min (hits within 60 s count once). Cooldown is 1 h, doubling with each opening in the last 24 h, at most 24 h. A run that hits it stops with exit `75` and says when to re-run; new runs, `-Parallel` workers (checked every 10 s by the watchdog), queue drains and `-Sync` refuse to start until then. The first run after a cooldown probes one video (`--simulate`) before downloading. `-IgnoreCooldown` overrides it. `-Doctor` shows it as "limit guard". |
| **Signal classes** | A 429 on subtitles only adds `--sleep-subtitles 10` for the rest of the run (and suggests `-SubLangs en-orig`); video downloads continue. A bot check while signed out suggests `-Browser`, once. 3 "Video unavailable" signed in suggest trying signed out (an account-level block). Video titles that contain "bot" or "rate limit" no longer count: only `ERROR`/`WARNING` lines and HTTP 429 do. |
| **Hourly budget** | Every video start is logged machine-wide: 150 per hour signed out, 1000 signed in (community-reported thresholds, with margin). At 80 % pacing goes one level slower, once; over it the run waits until the oldest starts leave the hour. |
| **AIMD pacing** | A 429 slows pacing by 2 levels, a bot check by 1; 25 clean videos in a row speed it up by 1, down to the start level. Saved levels (per folder and machine-wide) decay 1 level per 2 h of quiet instead of holding 24 h. |
| **Signed-in start + jitter** | Signed in starts at level 1, or level 0 with 20 or fewer videos to fetch; signed out stays at level 3. `--sleep-requests` gets ±50 % random jitter per run, so request gaps don't repeat exactly. |
| **Retry backoff** | yt-dlp retries back off exponentially: `--retry-sleep extractor:exp=5:300`, `http:exp=1:30`, `fragment:exp=1:20` (yours win if `-YtdlpArgs` has `--retry-sleep`). |
| **Pace status line** | `Get-PaceStatus` prints `pace L1 \| signed in \| N of 1000 videos this hour on this PC \| clean for N video(s)` after the "To stop" line and after every step up, step down and budget step (fixed `-Sleep` shows its label instead). The breaker message adds that closing the window is fine: a run started before then stops with the same message, and the first one after checks one video first. |
| **Benchmarks obey it** | `bench\lib-limit.ps1` (suites 5, 10, 11, 12, 13): before each run, wait out an open breaker (then probe one video) and wait until the run's videos fit the hourly budget; after it, count other tools' starts and open the breaker on their bot checks / 429s. A limited run isn't recorded and runs again once. |

**Verified:** `tests\v1.25.0.ps1` 52/52 offline (breaker 1 h / 2 h / 24 h cap / no extension while open / 24 h memory; trip dedupe and 10 min count; held level decay; 7 signal lines incl. titles with "bot"; budget step at 80 %, once, wait when over, old starts leaving the hour; AIMD speed-up and floor; jitter range and `--sleep-subtitles`; lib-limit sharing ytdl's file, counting other tools, 429 opening the breaker; two real launches refused with exit 75). A run through a dead proxy showed the backoff (5, 10, 20 s) and a clean failure report. `tests\v1.24.2.ps1` 6/7 and `v1.24.1.ps1` 28/29, the misses being their version checks. Check-Ytdl: ascii, parse 7/5.1, names, case variants, on ytdl.ps1, lib-limit and the 5 suites.
### 1.24.2 — Size estimates follow this run's own videos (2026-11-14)
| Change | Detail |
|---|---|
| **Bitrate history weight** | Saved bitrate history (per folder and quality) still counts as up to 2 h of video until the run has sizes of its own; once it has any (the resolution check's samples, the size probe, finished downloads) it counts as at most 10 min. Bitrate is a property of the content and a folder's history is often other content: a real 13-video 1080p/1440p run first read 434 MB for ~970 MB (history 0.11 MiB/s at 2 h weight against 3 samples at ~0.3), so its first ETA ran -59% or more until the size probe filled in exact sizes a minute later |

**Measured (replay, `bench\bitrate-blend.ps1`):** each run's bitrate predicted from 3 of its videos plus other content's history, 4 distinct contents above 480p: mean error 66% at 2 h, 28% at 10 min (bench logs alone 21% -> 18%). At 360p history barely matters (6-10%). The same run, once sizes were known: the combined finish read 23:18:42 for 23:18:44.
**Verified:** `tests\v1.24.2.ps1` 7/7 (Get-Bitrate taken from the script: full history with no sizes, capped with sampled or downloaded sizes, short history kept whole, finished videos' sizes ignored); `tests\v1.24.1.ps1` 28/29 and `tests\v1.23.0.ps1` offline 22/23, the misses being their version checks. Check-Ytdl: ascii, parse 7/5.1, names, case variants.

### 1.24.1 — More accurate estimates: parallel speed, `-LimitRate`, the last worker (2026-11-14)
| Change | Detail |
|---|---|
| **Parallel per-download speed** | The old rule (each of n workers gets min(single, cap / (n x d))) read each download 1.4-2.5x too fast: 654 downloads of 10+ MiB in 3-worker bench runs had a median of 4.9 MiB/s (4.2-6.0 at every size) against 6.4-11 from the rule, and worker estimates ran 18% low in the first quarter of a run. Now each worker saves its downloads' speeds by worker count (`PDraws` in `bandwidth.json`, last 50 per count) and the prior is their median; until there are 5, cap / n |
| **`-LimitRate`** | Estimates can't beat the limit any more (a floor of share x 1 MiB / limit s per MiB; share = worker count for a worker or the coordinator). A 15-video 1080p run at 2 MB/s first read 170 s for 1,726 s (-90%). Runs under a limit no longer save speeds (folder history, `Draws`, `PDraws`, `Caps`): the 2 MB/s bench run had saved a 2.17 MiB/s cap and slow draws, and the next 4 unlimited runs first read +168% to +435% |
| **Combined finish (`-Parallel`)** | Once a worker is done, the "ALL:" finish no longer takes the latest worker's own estimate as-is: downloads speed up as workers finish (~7.5 MiB/s alone, 5.2 two at once, 4.3 three at once), so that estimate ran +34% high in the last quarter. Each running worker's time left is split into fixed cost (videos left x overhead) and transfer, and the finishes are replayed with transfer rescaled to the workers still running (per-stream speed ~ 1 / (1 + 0.4 (k - 1))). Not applied while all workers run (it made the already-low start worse) |

**Measured (bench logs, replay):** combined ETA last quarter 38% -> 34% mean error, bias +34% -> +24%, the rest unchanged (`bench\tail-replay.ps1 -OnlyAfterFirst`, 312 points). Per-worker ETAs overall 18% mean error, bias 0%, but -18% in the first quarter (`bench\worker-eta.ps1`), the part the new parallel prior addresses; real-run validation pending.
**Verified:** `tests\v1.24.1.ps1` 29/29 (offline, functions taken from the script: stream share from PDraws / cap / old rule, the -LimitRate floor for one run, a worker and the coordinator, Save-Rate writing PDraws and skipping all speed learning under a limit, the tail replay); `tests\v1.23.0.ps1` offline 22/22 apart from its version check. Check-Ytdl: ascii, parse 7/5.1, names, case variants.
### 1.24.0 — Pacey in `-Doctor` (2026-11-14)
| Change | Detail |
|---|---|
| **Mascot face** | When every `-Doctor` check passes (no FAIL, no WARN), the closing line shows Pacey, the project mascot, as a two-line magenta text face: two tall eyes (`U+2588`) over a play-button mouth (`U+25B6`), then the green "Everything ytdl needs is in order." Built from `[char]` codes, so the script stays ASCII. Problem and warning summaries are unchanged; exit codes unchanged |

**Verified:** `Write-PaceyFace` loaded by AST and run in PowerShell 7 and 5.1 (both print the face); a real `-Doctor` on a PC with one warning prints the yellow summary without the face, exit 0; `-Version` prints 1.24.0. Check-Ytdl: ascii, parse 7/5.1, names ok.
### 1.23.0 — Output options, `-Live`, `-History`, podcast feeds (2026-11-14)
| Change | Detail |
|---|---|
| **Output options** | `-SubLangs`, `-LiveChat`, `-Template`, `-Container`, `-Codec`, `-Section`, `-SplitChapters`. All are saved with `-Subscribe` (except `-Section`: one video). Each lifts the matching `-YtdlpArgs` refusal, which now names the new option |
| **`-Section`** | `--download-sections` per range plus `--force-keyframes-at-cuts` (exact cut points). One video only; the clip gets its own archive (`.ytdl-archive-clip <times>.txt`) and the times in its name. Pieces off, no size ETA |
| **`-Live`** | `--live-from-start --wait-for-video 60`, `--skip-unavailable-fragments` instead of `--abort-on-unavailable-fragments` (a stream drops pieces now and then). One worker, pieces off, no size ETA, stall watchdog off unless `-StallMinutes` is given (waiting prints nothing). Refuses playlists, channel tabs and `-Section` |
| **`-History`** | Every finished file appends `unix time, id, height, path, title` to `%LOCALAPPDATA%\ytdl\history.tsv` (yt-dlp `--print-to-file after_move`; `%` in the path escaped). `ytdl -History [N] [-Match text]` lists the newest N; size is read from the disk, so deleted files show as "deleted" |
| **`-Feed` / `-FeedBase`** | Subscription options. After retention, `-Sync` writes `feed.xml` in the subscription's folder from its file list: files that still exist, newest upload first, title without `[id]`, guid `yt:<id>`, enclosure with size and MIME type. `-FeedBase http://host/path` builds the links from the file's path inside the folder (URL-escaped); without it they are `file:///`. Written atomically (via .tmp) |
| **Includes 1.22.1** | The rate-limit fix (rate limits are transient, not "won't fix itself") is in this version too |

**Verified:** `tests\v1.23.0.ps1` part A 23/23 (offline): refusals for -Section, -Template, -YtdlpArgs, -Container, -Codec, -Live (with -Section, playlist, channel tab), -Feed without -Subscribe, non-http -FeedBase; -History from a fake history.tsv (sizes, deleted, audio, -Match, N); Write-SubFeed (loaded by AST) on a fake folder: valid XML, 2 of 3 episodes (one deleted), newest first, escaped FeedBase links, MIME types, file:/// without FeedBase, off without -Feed. yt-dlp's history line checked on a local file (`--enable-file-urls`) in a folder with `%` in its name. Part B (online, 360p or less): pending (released before it, by the user's choice, while YouTube rate-limited the test account). -Live on a real stream: pending, same reason. Check-Ytdl: ascii, parse 7/5.1, names ok.
### 1.22.1 — YouTube's rate limit is no longer "won't fix itself" (2026-11-14)
| Change | Detail |
|---|---|
| **Rate limit = transient** | YouTube's account rate limit arrives as `Video unavailable. This content isn't available, try again later. Your account has been rate-limited by YouTube for up to an hour.` Its first words matched the permanent-error list and the fast-client fallback list. So it could switch to yt-dlp's default clients (remembered 7 days) instead of slowing down, and the failed videos were labeled "won't fix itself (private, removed, blocked...)". New `$transientPattern` (`try again later`, `rate-limit`, `429`, `Too Many Requests`) overrides both lists |
| **Retries** | At the slowest pacing level a rate limit can't step pacing down further. A retry pass that gets nothing used to say "remaining errors look permanent". It now says YouTube is still rate-limiting (for up to an hour) and stops retries, since more passes now only repeat it |
| **Failed list** | These videos are tagged `(rate-limited, retry later)`, with a summary line telling you to re-run later. The tag is worked out from the saved reason, so lists saved by 1.22.0 are relabeled too |

Found in the E3 README recording (2026-11-14): 5 of 12 videos were rate-limited after a heavy benchmark, and all 5 were shown as "won't fix itself".

**Verified:** `tests\v1.22.1.ps1` 17/17 (offline; loads the script's own patterns and functions by AST): the rate-limit message is not permanent, gets the rate-limited tag (also from a worker's 160-char reason and from a 1.22.0-saved item), doesn't switch clients, still triggers pacing. Private / removed / members-only and a bare `Video unavailable` stay permanent; the embedding error still switches clients; the summary counts 2 rate-limited / 1 retry / 1 permanent. Check-Ytdl: ascii, parse 7/5.1, names ok.
### 1.22.0 — `-Quality 4320`, `240` and `144`; `-PoToken` (2026-11-14)
| Change | Detail |
|---|---|
| **`-Quality`** | Now every height YouTube offers: `4320` (8K) above `2160`, `240` and `144` below `360`. 144 and 240 use the low-resolution settings (as 360/480: `-Parallel 3`, no background probe, early ETA). ETA priors for the new heights are guesses (0.012, 0.018 and 1.6 MB per second of video) until real runs replace them |
| **`-PoToken`** | Installs bgutil 2.0.2 once (the yt-dlp plugin zip in `%LOCALAPPDATA%\ytdl\pot\plugins`, its server in `pot\server-2.0.2`; needs deno), starts the server on 127.0.0.1:4416 detached so ytdl's restarts don't kill it, passes `--plugin-dirs` to yt-dlp, checks the server at most every 30 s and restarts it if it went away. The run that started it stops it. Runs without `-PoToken` are unchanged. If the install or the server fails, the run carries on without tokens. Saved with `-Subscribe`; `-Doctor` reports whether it is installed |

**Verified:** `tests\v1.22.0.ps1` 10/10 (online): `-Version`; `-Quality 144` and `240` on dewHjCVfle0 give 144 and 240 rows (ffprobe); `-Quality 4320 -Estimate` on EJr3uAQwGek accepted; `-Quality 999` refused; `-PoToken` installs, a signed-out 360p download works, the server is stopped after the run; yt-dlp's verbose log lists `bgutil:http-2.0.2` and requests a token. Check-Ytdl: ascii, parse 7/5.1, names ok. (The test's first two runs failed 3 checks because its helper was named `H`, the built-in alias of Get-History, which wins over a function; renamed `Get-Height`.)
### 1.21.1 — `-Unsubscribe` works again; the resolution check's cache saves (2026-11-13)
**Found by** `context\tools\Check-Ytdl.ps1`'s new name-collision check on its first run: two script-level assignments to `$keep`, which in PowerShell is the `[int]` parameter `-Keep` (1.16.0; names ignore case).

| Bug | Since | Effect | Fix |
|---|---|---|---|
| `-Unsubscribe` | 1.16.0 | `$keep = @(remaining subscriptions)` failed: "Cannot convert the System.Object[] value ... to type System.Int32"; nothing was removed (2+ subscriptions) | `$remaining` |
| Resolution check cache (`%LOCALAPPDATA%\ytdl\content.json`) | 1.16.0 | `$keep = @{}` failed inside `try { }`, silently: the cache was never written, so every run of 8+ videos above 480p repeated the resolution check | `$resKeep` |

**Verified:** Check-Ytdl on 1.21.1: ascii, parse 7/5.1, names ok (8 case-variant assignments only as locals in functions/scriptblocks); on 1.21.0 it fails on exactly those two lines (815, 2294). Two scratch subscriptions, `ytdl 1 -Unsubscribe`: 1.21.0 "Cannot convert ... System.Int32", both still listed; 1.21.1 "Unsubscribed: ...PLaaaa...", one left. `-Estimate` on 12 videos at 1080p: content.json written (it was missing before).
### 1.21.0 — Audio formats, SponsorBlock, a speed cap for the whole run (2026-11-13)
The remaining small gaps from the competitor survey (Seal, YTDLnis, auto-ytdlp, Hitomi).

| Part | Detail |
|---|---|
| **`-AudioFormat`** | Implies `-AudioOnly`. `mp3` (default, as before: re-encoded at quality 0), `m4a` (`bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/bestaudio`, `-x --audio-format m4a`: yt-dlp rewraps YouTube's AAC without re-encoding), `opus` (`bestaudio[acodec=opus]/bestaudio`, kept as Opus), `best` (`-x --audio-format best`). Cover art and tags embed in all four |
| **`-SponsorBlock`** | `mark`: `--sponsorblock-mark all` (chapters at every category). `remove`: `--sponsorblock-remove sponsor,selfpromo,interaction` (cut out; intros, outros and previews stay). Download only, not the lookups |
| **`-LimitRate`** | `5M`, `800K`, `1.5M` (per second; K/M/G = 1024-based; under 10K refused). yt-dlp's `--limit-rate` works per download stream, so a worker gets `total / -WorkerCount` and a single run all of it, and pieces are turned off (`$fragN = 0`): with pieces a 1M `--limit-rate` measured up to 2.2 MiB/s per stream (1.18.0 test). Shown on the start line ("at most 2M/s in total"). Workers that finish early leave their share unused, so the total can dip below the cap, never above |
| **Saved** | All three with `-Subscribe`. The `-YtdlpArgs --limit-rate` note now points to `-LimitRate` |

**Verified:** pure ASCII; parses in PowerShell 7 and 5.1. `tests\v1.21.0.ps1`:
- `g4OXlrxqIx0` (2,217 s; SponsorBlock: self-promotion at 2,207-2,212 s) `-AudioFormat m4a -SponsorBlock remove`: "Not converting audio ... already in target format m4a", "[ModifyChapters] Removing chapters"; aac 128 kb/s, 2,212.2 s, cover embedded.
- same with `-AudioFormat opus -SponsorBlock mark`: opus, 2,216.7 s, chapters 15 (13 without the marks), cover embedded.
- `-AudioOnly` alone: mp3, cover embedded.
- `-LimitRate 1M`, one video at 360p: streams at 0.97 and 0.99 MiB/s; start line "at most 1M/s in total".
- `-LimitRate 2M`, 2 workers: four streams at 0.97-0.99 MiB/s (about 2 in total); "-Parallel: 2 videos across 2 workers ... | at most 2M/s in total".
- `-LimitRate fast`: refused, exit 1.
### 1.20.1 — Unique episode numbers in `-Library`; Command Prompt passes every option intact (2026-11-13)

| Part | Detail |
|---|---|
| **Episode numbers** | `-Library` names are now `<show> - s<year>e<MMDDHH> - <title> [id]` (episode = month, day and upload hour from yt-dlp's `timestamp`, `00` when missing), and the Jellyfin .nfo `<episode>` matches. 1.19.0 named episodes `<show> - <date>`, so two uploads on one day shared a date (Plex can merge such episodes) and an .nfo episode number. Existing files keep their names; the archive stops them downloading again |
| **`ytdl-cmd.ps1`** (new, next to ytdl.ps1) | `ytdl.cmd` now runs this instead of ytdl.ps1. `pwsh -File` binds arguments before a script sees them and reads anything starting with `-` and containing `:` as `-Name:value`; even for a script with no parameters it split `--proxy http://h:8080` into `--proxy http` and `//h:8080`, losing the colon. The shim reads `[Environment]::CommandLine`, splits it with Windows' argv rules (CommandLineToArgvW), and binds the tokens to ytdl.ps1's parameters itself (exact names, aliases, unique prefixes like PowerShell; a value after an option that takes one is taken word for word; `-Name:value` honoured), then runs ytdl.ps1 in the same process and passes its exit code on. Unknown and ambiguous options get a one-line message |

**Found while testing:** with one argument, `$toks = if (...) { @(...) }` unwrapped to a string and the shim saw `-` as the link; wrapped in `@()`.

**Verified:** both files pure ASCII; parse in PowerShell 7 and 5.1.
- Two uploads on 2026-09-23 (`-Items 103,104`): jellyfin `s2026e092309` and `s2026e092310` (+ `-thumb.jpg`, `.nfo` with `<episode>092309/092310</episode>`, valid XML), plex the same names with `.jpg`.
- Shim through `cmd /c`, PowerShell 7 and 5.1: `-Version`, `-ver`, `-Queue`; `-YtdlpArgs "--proxy http://127.0.0.1:8080 -4 --limit-rate 5M"` arrives whole (Doctor: `connection: --proxy http://127.0.0.1:8080 -4 | download: --limit-rate 5M`); `-YtdlpArgs "-S res:360"` reaches ytdl's own refusal; `-Ytdl` resolves; `-Nope` "unknown option"; `-S` "ambiguous (...)"; a link with `&` arrives intact.
### 1.20.0 — Add links to a running ytdl: `-Add`, `-Queue` (2026-11-13)
The gap the queue-based tools fill (MeTube, Hitomi's clipboard monitor, auto-ytdlp's links file, YTDLnis): one ytdl window works through everything you give it, instead of a new window and a competing download per link.

| Part | Detail |
|---|---|
| **`ytdl <url> -Add [options]`** | If a ytdl download is running, the link and the options given (the same set `-Subscribe` saves, with `-Out`) go to `%LOCALAPPDATA%\ytdl\queue.json` and ytdl exits ("Queued as number N"). If none runs, it downloads now as usual |
| **Working through it** | At the end of a top-level run (single, parallel coordinator, or `-Sync`), after its folder lock is released and unless it was stopped: each queued link in turn, as a normal ytdl run in the same window (`YTDL_IN_QUEUE` keeps those runs from draining themselves). A stopped item leaves the rest queued. Taking an item and adding one use an exclusive `queue.json.lock` |
| **Which runs count** | `runs\<pid>.json` per top-level run (the PowerShell launcher runs ytdl inside your shell, so the process list can't tell). A record counts while that pid, with the same start time, is alive and still holds its folder's `.ytdl.lock` (a sync, between its runs, holds none). Stale ones are deleted when found |
| **`-Queue` / `-ClearQueue`** | Lists the runs going on and the queued links with their options (and says so when nothing is running to take them); empties it. Internally `$ListQueue`: `$queue` is already the scanned-video list |
| **Browser button** | The download button queues the link and closes its window after 4 s when a ytdl download is running (any folder), instead of opening a second waiting window |
| **`-Doctor`** | Shows queued links waiting |

**Found and fixed while testing:** a `-Queue` switch collided with ytdl's existing `$queue` (scanned videos; PowerShell names ignore case), crashing every download; `$queueFile` collided with the worker parameter `-QueueFile`, so parallel workers read the link queue as their share and deleted it. Both renamed (`$ListQueue` with alias `-Queue`; `$linkQueueFile`).

**Verified:** pure ASCII; parses in PowerShell 7 and 5.1. `tests\v1.20.0.ps1` (360p, `YTDL_STATE` in %TEMP%):
- nothing running: `-Queue` "No ytdl download is running / The queue is empty"; `-Add` downloads at once (1 file).
- a 3-video parallel run in the background; two `-Add`s meanwhile (another folder at 360; another folder with `-Items 110 -Browser firefox -Library plex`): "Queued as number 1/2", `-Queue` lists both with their options; the run ends "All workers finished", then "=== Next from the queue: ... (1 more after this) ===" and the second; files 3 + 1 + 1 (the plex one with its episode .jpg and poster.jpg); queue empty, no run records left.
- a stale run record (pid gone) is ignored and deleted; `-ClearQueue` "Removed 1 link(s)".
- browser button (test scheme `ytdltest`) clicked during a run: "Queued as number 1", window closed after 4.5 s; the run then downloaded it into the button's folder.
### 1.19.0 — `-Library jellyfin|plex`: a media-server folder layout (2026-11-13)
The gap the self-hosted archivers (ytdl-sub, Pinchflat, Tube Archivist, TubeSync) fill: files Plex and Jellyfin pick up as TV shows. Done with yt-dlp's own output options, no extra tools.

| Part | Detail |
|---|---|
| **Layout** | `<Out>\<show>\Season <upload year>\<show> - <YYYY-MM-DD> - <Title> [id].mp4`. Show = `%(channel,uploader,playlist_title|YouTube)s`, or `-Folder`. Date-based episode names, which both servers parse; no date -> `Season 0000` |
| **Images** | `--write-thumbnail --convert-thumbnails jpg`: the episode image as `<name>-thumb.jpg` (Jellyfin) or `<name>.jpg` (Plex); the playlist/channel image as `<show>\poster.jpg` (`pl_thumbnail`). The cover is still embedded unless `-NoThumbnail` |
| **Jellyfin .nfo** | `--print-to-file after_move:<xml> <Out>\<dir>\<name>.nfo`: one-line `<episodedetails>` with title, show, season = year, episode = MMDD, aired, plot (description), runtime (minutes), `uniqueid type="youtube"`. `%(..)h` HTML-escapes. Plex gets no .nfo (it ignores them without a plugin) |
| **Retention** | `-Keep`/`-KeepDays` also delete the episode's `.nfo`, `-thumb.jpg` and `.jpg` |
| **Saved** | `Library` added to the options `-Subscribe` keeps; workers get it like every option |

**Known:** two uploads on the same day share the .nfo episode number (MMDD); Jellyfin shows both, told apart by title and air date. A single video (no playlist) gets no poster.jpg.

**Verified:** pure ASCII; parses in PowerShell 7 and 5.1. `tests\v1.19.0.ps1` (360p, signed in):
- jellyfin, 2 playlist videos through 2 workers: `Blender\poster.jpg`, `Blender\Season 2026\Blender - 2026-09-23 - <title> [id].mp4` + `-thumb.jpg` + `.nfo` for each; the .nfo parses as XML (`'` and `"` escaped).
- plex, a single Short: `.mp4` + same-name `.jpg`, no .nfo.
- `-Folder 'Blender Talks'`: the show folder and names use it.
- `-Subscribe ... -Library jellyfin -Keep 1` then `-Sync`: "Removed (keeping the newest 1): ...pTHmtHXwVKY].mp4", and that episode's .nfo and -thumb.jpg went with it; the kept episode has all three (its .nfo 410 bytes).
### 1.18.2 — Vertical videos get the right quality; `-Precise` 5-8x faster (2026-11-13)
**Bug (benchmark E5S):** `-Quality` limited the *height*, so a vertical video (YouTube Shorts) got a stream far below the asked class: at 360 the 144x256 stream, at 1080 the 608x1080 one. 6 of the 120 stress-test videos came out 256 px tall.
**Slow (benchmark E6E):** `-Precise` looked videos up one at a time with a fixed 1 s pause per request: 12 videos 103 s, 50 videos 409 s, slower than yt-dlp `-s` (38 / 153 s).

| Part | Detail |
|---|---|
| **Format** | `bv*[height<=Q][aspect_ratio>=?1]+ba / bv*[width<=Q][aspect_ratio<1]+ba / b[height<=Q][aspect_ratio>=?1] / b[width<=Q][aspect_ratio<1]`: the limit applies to the shorter side. Unknown aspect ratio counts as landscape (the old behaviour). Used everywhere `$fmt` is (download, resolution check, background size probe, `-Precise`) |
| **Resolution check** | Prints width too and keeps the shorter side, so a vertical 1080p video reads 1080, not 1920 (low-res detection and the ETA priors use it) |
| **`-Precise`** | `Get-Sizes`: 3 yt-dlp processes at once (ids dealt round-robin), the fast extraction client, and the pacing level's per-request pause instead of a fixed 1 s (signed in: none). Ids the fast client can't answer get one more pass with yt-dlp's default clients. `Quote-Arg` moved above it (it was defined after its first use there) |

**Verified:** pure ASCII; parses in PowerShell 7 and 5.1. `tests\v1.18.2.ps1`:
- Short `A9Yn8Ad_cH8` (1080x1920 source): `-Quality 360` -> 360x640 (was 144x256), `-Quality 1080` -> 1080x1920 (was 608x1080); landscape `dewHjCVfle0` at 360 -> 640x360, unchanged. Format choices checked against the old filter in yt-dlp directly: landscape picks identical (396+251, 399+251).
- `-Estimate -Precise`, 1080p signed in: 12 videos 18.7 s, 3.25 GB (yt-dlp exact 3,323.8 MiB); 50 videos 51.9 s, 15.73 GB (yt-dlp 16,096.8 MiB); no failed lookups. Now faster than yt-dlp `-s` (38 / 153 s).
- Resolution check's print on the Short: `A9Yn8Ad_cH8 1920 5568874 1080` -> 1080; landscape `1080 ... 1920` -> 1080.
### 1.18.1 — Say when Windows won't show the notification (2026-11-13)
**Bug (user report):** the 1.18.0 test notification never appeared. Windows notifications were off for the user (`HKCU\...\PushNotifications` `ToastEnabled = 0`; the notifier for Windows PowerShell's app id reported `DisabledForUser`; its toast history was empty), and Windows drops toasts silently in that case, so ytdl looked like it had notified.

| Part | Detail |
|---|---|
| **`Get-ToastBlock`** | Registry only: the global switch (`PushNotifications\ToastEnabled`) and Windows PowerShell's own switch (`Notifications\Settings\{1AC14E77-...}\WindowsPowerShell\v1.0\powershell.exe\Enabled`). Returns why a toast would be dropped, or nothing |
| **At the end of a run** | When a notification is due but blocked, ytdl prints one grey line naming the Windows setting, instead of launching a toast nobody sees. `-Notify off` hides it |
| **`-Doctor`** | New row: notifications OK / WARN (with the setting to change) / INFO when `-Notify off` |

**Verified (this PC, notifications off):** parses in PowerShell 7 and 5.1; pure ASCII. `-Doctor`: "WARN notifications  -Notify can't show anything: notifications are turned off in Windows (Settings > System > Notifications)"; a failing run with `-Notify on` ends with "[ytdl] No notification shown: notifications are turned off in Windows (...)"; with `-Notify off`, no line. Not seen: a toast actually displayed (needs notifications on).
### 1.18.0 — More yt-dlp options, notifications, `-Doctor`, shorter first retry (2026-11-13)
The four picks from the competitor survey (report v2.1): gaps other tools cover (custom yt-dlp options: auto-ytdlp, Seal, Stacher; a status you can see without watching the window) and the one weak benchmark result (E4, signed out).

| Part | Detail |
|---|---|
| **`-YtdlpArgs '...'`** | Split like a command line ("double" and 'single' quotes group words), then each option grouped with the values after it. **Refused** with ytdl's own option named: output/paths/archive/batch file, format and sorting (`-f`, `-S`, `-x`...), `--playlist-items`, cookies, the sleep options (`-Sleep`: ytdl paces itself), `-N`, match filters and `--dateafter`, embed thumbnail/metadata, error handling (`-i`, `--abort-on-error`), and output-control options ytdl reads (`--print`, `-q`, `--progress-template`, `-j`, `-s`...). Case-sensitive table (`-s` simulate and `-S` sort are different options). **Connection options** (`--proxy`, `-4`/`-6`, `--impersonate`, `--extractor-args`, headers, `--source-address`...) are added to `$authArgs`, which every yt-dlp call includes (scan, resolution check, size probe, `-Precise`, download, `-Doctor`); **the rest** only to the download. Saved with `-Subscribe`. `--limit-rate` prints a note: yt-dlp applies it per stream |
| **Passing values that start with -** | `pwsh -File` (ytdl.cmd, workers, `-Sync`'s runs) reads an argument that starts with `-` and contains `:` (e.g. `--proxy http://x:8080`), or a bare `-s`, as a parameter name. Workers and sync runs now pass such values as `-Name:value` (also fixes a `-Match` pattern starting with `-`). The PowerShell launcher (ytdl.ps1) passes them intact; from Command Prompt use `-YtdlpArgs:"..."` |
| **`-Notify auto/on/off`** | Windows toast through a hidden Windows PowerShell 5.1 (PowerShell 7 can't load the WinRT toast API), as Windows PowerShell's app id. auto: a run over 2 minutes, any failure or stop; a sync that found new videos or had errors. Never from workers or the runs a sync makes (`YTDL_IN_SYNC`); the sync sends one summary. Text: videos downloaded (archive count since start), failures, time, folder. `YTDL_TOAST_TEST=1` prints it instead (tests), `=show` prints and shows |
| **`ytdl -Doctor`** | yt-dlp (version, age: warn 30+ days, fail 60+, fast build or not), ffmpeg (+ ffprobe next to it), deno, sign-in (with `-Browser`/`-Cookies`, else the first subscription's: one metadata request for "Me at the zoo"; bot check / invalid cookies / unreadable cookie store / no answer each named with a fix), `-YtdlpArgs` split, free space (fail under `-MinFreeGB`, warn under 10 GB), the folder's pacing level (warns within 24 h of a bot check), a run in progress, archive count, subscriptions with errors, the schedule task (state, last result, next run). Runs before the folder is created or locked; exit 1 if anything failed |
| **First retry 15 s** | Unless `-RetryDelay` is given, retry pass 1 waits 15 s (later passes the full 60). Benchmark E4: one signed-out round's 2 failed videos cost a flat 60 s (58 s slower than the clean rounds); bot checks are handled by pacing, not this wait |

**Found and fixed while testing:** the option table was a hashtable, which ignores case (`-s`/`-S`, `-j`/`-J` collided); `-4`/`-6` were read as numbers; `-Doctor` crashed on `$subs` (PowerShell variable names ignore case: that is the `-Subs` switch); subscriptions keep options under `.Options`, not `.Opts`.

**Verified:** pure ASCII; parses in PowerShell 7 and 5.1.
- `tests\v1.18.0-offline.ps1`: 6 refusals each exit 1 naming ytdl's option (`-f`, `-S`, `-s`, `--sleep-interval`, `--cookies-from-browser=`, a value before any option); the split shows `connection: --proxy http://127.0.0.1:8080 -4 --extractor-args youtube:lang=en | download: --limit-rate 5M --sponsorblock-remove sponsor,selfpromo`; Doctor on a folder with a level-2 pace file 3 h old, a lock and 5 archived videos, with `-MinFreeGB 100000`: FAIL disk, WARN pacing, INFO running and folder, exit 1; the toast script runs in Windows PowerShell 5.1 with exit 0.
- `tests\v1.18.0-online.ps1`: Doctor `-Browser firefox` all OK (YouTube answered in 3.9 s), exit 0; a missing video: "Retry pass 1 of 2 (waiting 15 s)" and a real toast "ytdl finished with errors"; `-RetryDelay 7`: waits 7; `--limit-rate 1M` on one video 1.0-1.3 MiB/s per stream (3 pieces); 2 workers through `pwsh -File` with `'-YtdlpArgs:--limit-rate 1M'`: both capped (1.0-2.2 MiB/s per stream); `-Parallel 1 -Fragments 0`: 1,004 and 1,006 KiB/s; a sync of one subscription saved with `-YtdlpArgs`: one toast "ytdl sync done | 1 new video(s) from 1 subscription(s)", none from its run.
- Not seen live: the second retry's full 60 s wait (a missing video stops retrying after one pass).
### 1.17.2 — `-Estimate -Precise` really looks up sizes (2026-11-13)
**Bug (found by benchmark suite 2, E6E):** on a playlist (3 workers by default) `-Precise` leaves the size lookups to each worker, but `-Estimate` starts no workers, so nothing was looked up. The status line still dropped the "~" whenever `-Precise` was given, so the runtime-based guess was shown as exact: 12 videos at 1080p read "4.11 GB" in 5.9 s; the real total is 3.25 GB (yt-dlp `-s`: 3,323.8 MiB).

| Part | Detail |
|---|---|
| **Lookups under `-Estimate`** | The coordinator looks up every size itself when `-Estimate` is given (`-not $isCoordinator -or $Estimate`) |
| **The "~"** | Shown unless every remaining video has a looked-up size (was: unless `-Precise` was given) |

**Verified:** pure ASCII; parses in PowerShell 7 and 5.1. Items 1-12 of the Blender uploads at 1080p, signed in: `-Estimate -Precise` printed "-Precise: looking up exact sizes for 12 video(s)" and "3.25 GB" (no "~") in 105 s; `-Estimate` alone still prints "~4.39 GB".
**Known:** the lookups run one at a time with a 1 s pause per request (~9 s per video), so `-Precise` is slower than yt-dlp `-s` (37 s for the same 12). Parallel lookups are a candidate improvement.
### 1.17.1 — Test hook to time bot-check recovery (2026-11-13)
**Why:** adaptive pacing never met a real bot check in any benchmark (0 in 1,026 archive videos and every timed run), so its recovery could not be measured. The report needed it timed.

| Part | Detail |
|---|---|
| **`YTDL_TEST_BOTCHECK=N`** | Environment variable, for benchmarks only. The Nth yt-dlp download progress line of the run is replaced by the exact message yt-dlp prints on a bot check (`ERROR: [youtube] <id>: Sign in to confirm you're not a bot ... [simulated by YTDL_TEST_BOTCHECK]`). Everything after that is ytdl's normal code: stop yt-dlp, step up one pacing level, save it to `.ytdl-pace.json`, wait, resume |
| **Once per folder** | A `.ytdl-testbot` file in the output folder marks it as fired, so a restart or a parallel worker doesn't fire it again: one simulated check per run |
| **Off by default** | Unset or 0 changes nothing (one integer comparison per output line) |

**Verified:** pure ASCII; parses in PowerShell 7 and 5.1.
- One video at 1080p (`YTDL_TEST_BOTCHECK=3`, `YTDL_PROGRESS_DELTA=1`): check at 8.5 s; yt-dlp stopped; "slowing down to pacing level 1"; 10 s wait; resumed at piece 5 of 9 (partial kept); finished in 30.8 s; `.ytdl-pace.json` Level 1.
- 3 videos, 3 workers: w1 hit the check at 14:11:52 and stepped to level 1; w3 followed 1 s later, w2 9 s later (watchdog checks every 10 s); 3 of 3 files; exit 0.
- With N larger than the run's progress lines it never fires and the run is unchanged (a fast 1080p video logs only 0% and 100% per stream at the default 5% step, which is why the tests set `YTDL_PROGRESS_DELTA=1`).
### 1.17.0 — Green progress bar for the whole run (2026-11-13)
**What's new:** a green bar on the bottom line of the window that fills left to right as the run downloads, with the share done, data done against the estimated total, videos done and the current speed:
`[████████████████████████░░░░░░░░░░░░░░░░]  58%  636 MB / 1.07 GB  3 of 6 videos  14.2 MiB/s`

| Part | Detail |
|---|---|
| **Staying at the bottom** | Everything ytdl prints goes through its `Write-Host` wrapper, which now clears the bar line, prints, and redraws the bar, so messages scroll above it. Drawn with plain console colors (green fill, dark grey rest), no escape codes, so it works in Windows PowerShell 5.1 too; the block characters are written as `[char]0x2588`/`0x2591`, keeping the script pure ASCII |
| **What "total" means** | One worker: finished videos + finished streams of the current one + the current stream's progress, against that + the current video's estimate + ytdl's estimates for the rest (`Get-RunBarState`). The rest is re-added only when the queue changes. With parallel downloads the coordinator draws one bar: every stream the workers finished plus each worker's current stream, against the estimates of all videos handed out, speed smoothed over 2 s |
| **Only forward** | Each video's estimate is fixed when it starts (or when its details arrive) and only grows to what's known; the bar never draws shorter than it has been (the MB figures stay true); a run that finishes successfully ends at 100% with the real total |
| **yt-dlp's percentage lines** | Hidden from the console while the bar shows (still in the run log); yt-dlp reports progress every 1 s instead of 5 (workers get it via `YTDL_PROGRESS_DELTA`) |
| **When it's off** | Parallel workers (they feed the coordinator), `-Estimate`, scheduled or captured runs (output not a console), non-console hosts, and `-NoProgressBar`. `YTDL_FORCE_BAR=1` draws it anyway, for tests |

**Found and fixed in testing:** the coordinator printed a worker's "100% of" line (which redraws the bar) before adding that stream to the total, so the bar dipped by a whole file (21% → 4%) and came back; a single video's total moved 187 → 319 → 188 → 315 MB because the current video's estimate was recomputed on every redraw as its bitrate was learned; a parallel run ended at 95% because the estimate was 5% high.

**Verified:** parse clean in PowerShell 7 and 5.1; pure ASCII.
- `tests\bar-render.ps1` (the bar's own functions on made-up states): 0%, 58%, 100%, an estimate too low (capped at 100%), paused, and windows 120/60/40 wide (bar shrinks to 10, text trimmed, never wraps).
- `tests\bar-live.ps1` (real 360p downloads, output captured with `YTDL_FORCE_BAR=1`): single video 31 redraws, ended `100%  18 MB / 18 MB  1 of 1 video`; 3-video parallel run 119 redraws, ended `100%  126 MB / 126 MB  3 of 3 videos  14.0 MiB/s`; yt-dlp's percentage lines 0 on the console, all in the log. `-NoProgressBar` and captured output without the hook: no bar, percentage lines shown as before.
- `tests\bar-monotonic.ps1`: a 2-hour single video (0 → 8 → 19 → 31 → 52 → 66 → 76 → 84 → 100%) and a 3-video parallel run (31 steps to 100%): 0 steps backwards, both end at 100%.
### 1.16.1 — No idle second at exit (2026-11-13)
**Problem:** in the 6-round single-video benchmark every ytdl time ended in .6 s (12.6, 9.6, 10.6, 9.6, 9.6, 11.6) while yt-dlp's varied. At exit ytdl waits for its watchdog thread (`EndInvoke`), which slept 1 s per loop, so every run (and every parallel worker) sat idle for up to 1 s at the end.

**Fix:** the watchdog waits in 10 steps of 100 ms and leaves as soon as the run is done. Checks still run about once a second.

**Verified:** parse clean in PowerShell 7 and 5.1; pure ASCII. A run with nothing to download (video already archived; `tests\exit-wait.ps1`, alternating, 6 rounds each): **1.56 s → 1.07 s** (1.55–1.57 vs 1.02–1.09). Pause/resume test (`tests\pause.ps1`) still passes: 11/11 yt-dlp threads suspended while paused, 0 after, complete file, exit 0.
### 1.16.0 — Closing the gaps the comparison page found, and pause/resume (2026-11-13)
Built in `next\ytdl.ps1` while the 1080p benchmark ran on the live 1.15.0, then released. Four gaps the user picked from the comparison with 15 other tools, plus pause/resume, which the user asked for while it was being built.

| Change | Detail |
|---|---|
| **Faster single-video start** | The benchmark showed ytdl tying yt-dlp on one video (13.6 s vs 14.0) while winning 1.46–1.69x on batches: the up-front listing of one video is a full extraction (1.2–8 s) that the download repeats. For a single watch/youtu.be/shorts URL (no `list=`), the listing now runs in a background runspace while the download starts; its duration feeds the estimate when it arrives (`Merge-BgScan`; no estimate is shown until then) |
| **Failed-videos list** (as yt-pdlp has) | The last ERROR per video is noted; at the end, videos still not in the archive are listed with title, link and reason, marked "won't fix itself" when private/removed/blocked/age- or members-only. Saved to `<Out>\ytdl-failed.txt`, one section per URL; entries drop out once downloaded. Workers send `[ytdl-fail] id<TAB>title<TAB>reason` lines that the coordinator collects. The scan now also reads titles |
| **Filters** (as Pinchflat/Tube Archivist have) | `-MinMinutes`, `-MaxMinutes`, `-Match`, `-Exclude`, `-After`; any run, saved with `-Subscribe`. Applied to the scan (filtered videos aren't counted, estimated or given to workers; the download gets only the kept positions) and as yt-dlp `--match-filters`. `-After`: the scan reads approximate upload dates (`youtubetab:approximate_date`; YouTube rounds "time ago" down, so an approximate date is never older than the real one) and drops videos before the cutoff less 2 days; on a channel tab yt-dlp stops at the first older video (`--break-match-filters upload_date>=?X`, exit 101 = success), elsewhere `--dateafter` |
| **Retention** | `-Keep n` / `-KeepDays n` on a subscription: after each `-Sync`, its oldest videos are deleted. Only files listed in that subscription's `.ytdl-sub-<hash>.txt` (written by yt-dlp `--print-to-file after_move`), inside its `-Out`, with their `[id]` in the name, can go; never anything else in a shared folder. Archive lines stay, so they don't come back |
| **Browser button** (as Parabolic's extension) | `-BrowserButton on [options]` registers `ytdl://` for this user and writes a page with two bookmarklets, "ytdl" (download the open YouTube page) and "ytdl +sub" (subscribe). The handler runs `ytdl.ps1 -FromLink "%1"`. Safety: checked first thing in the script, a link carrying any other option is refused (a quote in a crafted link could otherwise add `-Out`, `-Cookies`...); only `https://` YouTube URLs without spaces or quotes are accepted. A second click waits for the folder lock instead of failing; the window stays open at the end |
| **Pause / resume** | Like `-Stop`, signal files: `%TEMP%\ytdl.pause` (all runs) and `<Out>\.ytdl.pause` (one folder; the P key toggles it, R resumes). The watchdog (now every 1 s) suspends the run's yt-dlp process tree (yt-dlp, ffmpeg, deno; not PowerShell workers, which have their own) with `NtSuspendProcess`, re-scanning every 5 s for a yt-dlp started during the pause, and resumes it after: the download continues on the same connection. While paused: no hang, disk or pace checks, no new workers, retry waits hold; a stop still works. A video paused part-way isn't used to learn speed or overhead |

**Found and fixed in testing:** `--dateafter` rejects a video before `--break-match-filters` is checked, so with both a `-After 30 days` sync of a 1,218-video channel opened every old video (610 in 10 minutes, stopped). Now the scan trims by approximate date and channel tabs use the break filter alone. YouTube's "This video is unavailable" wording added to the won't-fix-itself pattern.

**Verified** (scripts in `tests\`): parse clean in PowerShell 7 and 5.1; pure ASCII; 5.1 runs it.
- Offline (`offline.ps1`): bad `-After`/`-Match`/minutes refused with clear messages; links with an extra option, a non-YouTube page or an injected quote refused; handler registered with the right command and `URL Protocol`; page bookmarklets correct; `-Subscribe` saves and lists filters and `-Keep`.
- Single video (`single.ps1`, 98 MiB 1080p, Firefox sign-in, alternating, 3 rounds each): **1.16.0 11.6 s (13.7/10.6/10.6) vs 1.15.0 16.4 s (18.4/16.2/14.6), 29% faster**, identical file; the listing (3.8–8.3 s) now overlaps the download.
- Failed list (`fail-link.ps1`): a missing video listed with reason, saved to `ytdl-failed.txt`, exit 1. Browser link end to end: 720p download with the button's options, exit 0.
- Sync with filters (`sync-filters.ps1`, `@BlenderOfficial`, 360p, `-After "30 days" -MinMinutes 3 -Exclude "trailer|teaser" -Keep 2`): 1,121 of 1,218 trimmed by the scan, every worker stopped at its first older video, 3 new videos in 43 s (was 10+ min and climbing), oldest removed by retention, file list rewritten; a second sync: 0 new, exit 0.
- Pause (`pause.ps1`, 1080p, 2-hour video): `-Pause -Out` → the file held at 69 MiB for 8 s with 11/11 yt-dlp threads suspended; `-Resume` → 0 suspended, on to 126 MiB at once; finished complete, exit 0, window showed "Paused" / "Resumed after 12 s". (The P key writes the same file; it needs a real console to press.)
- Parallel regression (`parallel.ps1`): 3-video playlist, 3 workers, numbered names, exit 0, no failed list; the worker failure line round-trips through the coordinator's pattern, including a title containing a tab.
### 1.15.0 — Channels and subscriptions (2026-11-13)
**What's new:** ytdl can follow a channel or playlist and download only what's new.

| Change | Detail |
|---|---|
| **Channel URLs** | A bare channel URL (`youtube.com/@name`, `/channel/ID`, `/c/name`, `/user/name`) becomes its **Videos** tab. yt-dlp otherwise lists Videos, Shorts and Live as separate playlists, each numbered from 1, so folders split and numbers collide. `/shorts` or `/streams` can still be given explicitly. |
| **Date-named files on channel tabs** | Channel tabs list newest first, so a video's position changes with every upload. Files from a channel tab are named `YYYY-MM-DD - title [id]` instead of `NNN - title [id]`. Playlists keep position numbers. |
| **`-Subscribe`** | Saves the URL with its `-Out` and the options given alongside it (`-Quality`, `-Items`, `-Browser`, `-Parallel`, ...) in `%LOCALAPPDATA%\ytdl\subscriptions.json`. Subscribing again to the same URL replaces its options and says what they were. A channel subscribed without `-Items` warns that the first sync downloads the whole channel. |
| **`-Sync`** | Runs ytdl once per subscription with its saved options, one after another; each is a normal run (lock, log, archive, retries, workers), so only new videos download. Records last sync, new count and exit code; `-Sync -Estimate` only previews. Honours `-Stop`. Summary in `%LOCALAPPDATA%\ytdl\sync.log`. |
| **`-Subscriptions`, `-Unsubscribe`** | List subscriptions (numbered, with options and last sync) and the schedule; remove one by URL or number. Files and the archive are kept. |
| **`-Schedule daily\|hourly\|off`, `-At HH:mm`** | Registers (or removes) a Windows scheduled task, `ytdl sync`, that runs `-Sync` hidden while you're signed in (so `-Browser` can read your sign-in); a missed run starts when the PC is next on; 12 h limit, no overlapping runs. |

**Fixed before release** (the work in progress was interrupted by an API error and left `ytdl.ps1` unparseable, which also broke the 1080p benchmark's 1- and 6-video ytdl rounds, 04:12–04:17):
- `Format-When` had lost its quotes (parse error).
- A `""` inside a double-quoted string in the `-Subscribe` "replaces the options" message (parse error).
- The new `-Sync` switch shared its name with the internal `$sync` watchdog table (PowerShell names ignore case), so every download died with *Cannot convert ... SyncHashtable to SwitchParameter*. The table is now `$runState`.

**Verified:** parse clean in PowerShell 7 and 5.1; pure ASCII. With a test subscriptions file and task name: subscribe, re-subscribe (options replaced), list, unsubscribe by number. Real sync of `@BlenderOfficial` `-Items 1-2 -Quality 360 -Parallel 2 -Browser firefox`: 2 new videos in 12 s, exit 0, files named `2026-11-10 - What's New in Blender 5.3! ...`; a second sync found 0 new, exit 0. `-Schedule daily -At 03:30` registered the task (next run 2026-11-14 03:30, `-Sync` argument), `-Subscriptions` showed it, `-Schedule off` removed it. Subscribe/list also checked under 5.1.

### 1.14.0 — Parallel estimate follows the real schedule (2026-11-13)
**Problem:** before the workers report their own estimates, the coordinator showed the total for all videos divided by the worker count. Real 2-video runs read 15–19 s against 21–28 s, for three reasons:
- It divided by 3 (the default) though only 2 workers ran. The shared-speed model and its saved history also used 3.
- It assumed all workers start at once. Launches are 3 s apart, and each worker takes 2–4 s to reach its first video (6–9 s in the 1,463-video playlist, where it pages through the list). Measured on 27 workers since 1.7.0.
- It assumed the work splits evenly. With 2 videos of different sizes, the bigger one sets the finish.

| Change | Detail |
|---|---|
| **Schedule simulation** | Each pending video's estimated time, biggest first, onto the least-loaded worker. Worker k starts at (k−1) × 3 s + 2 s + 0.5 s per 100 playlist entries up to the highest pending position. The estimate is the latest finish. `$launchGap` (3 s) is shared with the launch loop |
| **Effective worker count** | With fewer videos than workers (2 at the default 3), the estimate, the shared-speed model and the history key use that many workers (`Set-RunWorkers`); the workers already got `-WorkerCount` of that number |

**Verified** with `-Estimate` (480p, no pauses, a copy of the Videos folder's saved history, signed-out listing only):

| Run | Actual | 1.13.0 | 1.14.0 |
|---|---|---|---|
| 1998 items 109,172 | 22 s | 16 s (−27%) | 22 s (0%) |
| Time in a Bottle 28,57 | 28 s | 16 s (−43%) | 21 s (−25%; one stream ran at 4.3 MiB/s) |
| Tainted Love 28,50 | 21 s | 16 s (−24%) | 21 s (0%) |
| MRPCs Tainted Love 13,15 (pieces) | 24 s | 18 s (−25%) | 23 s (−4%) |

Mean absolute error **30% → 7%**. A 250-video playlist with 3 workers: 33 min 12 s → 33 min 23 s (the added start-up only). Parse clean in PowerShell 7 and 5.1; pure ASCII.

### 1.13.0 — Parallel pieces with 2 workers by default (2026-11-13)
User decision after the 1.12.1 real-world data: 2-worker runs without pieces got 4.3–9.0 MiB/s per video stream (mean 7.2, 3 runs), one worker with pieces 14.8, and two streams don't fill the connection. `-Fragments` now defaults to 3 when a run uses 1 **or 2** workers (workers check `-WorkerCount`); 3+ workers stay off.

**Verified:**
- Parse clean in PowerShell 7 and 5.1; file is pure ASCII.
- Signed-out Blender tests at 480p:
  - 2-video runs: both workers showed "3 pieces at once". Streams ran 7.5–13.7 MiB/s (video) and 10.3–23.2 (audio), exit 0, 57 s and 34 s.
  - 3-video run: 0 of 3 workers used pieces, as intended, exit 0.
- The first 2-video run's output was deleted before it could be read. A rough search counted 7 lines containing "403", most likely speed figures such as "403.x KiB/s" in progress lines (ytdl's own check needs "HTTP Error 403" on a piece). The re-run had no refusals.
- **Not yet seen:** a signed-in 2-worker run with pieces.
**First signed-in data (2026-11-13 01:51–01:52, MRPCs channel), 480p, 135+251:**

| Run | Workers / pieces | Video streams | Whole run | First estimate |
|---|---|---|---|---|
| July 2000 item 12 | 1 / 3 at once | 112.1 MiB at 16.1 MiB/s | 18 s | 14 s |
| Tainted Love items 13,15 | 2 / 3 at once each | 88.0 MiB at 11.4 and 158.4 MiB at 13.5, partly at the same time | 24 s (2 videos, 290 MiB) | 19 s |

- The 2-worker run moved about 12 MiB/s overall from launch to finish, against about 7 for the three 2-worker runs without pieces (1.12.1; 168–171 MB in 21–28 s). Its streams ran 11.4–13.5 MiB/s, against 4.3–9.0 without pieces.
- No refusals, no errors.
- Estimates were still short: 19 s vs 24 s for the 2-worker run (the second worker starts 3 s later), and 14 s vs 18 s for the single video.
### 1.12.1 — `-Items` accepts an unquoted list; first signed-in test of `-Fragments` (2026-11-13)
**Fix:** in PowerShell, `-Items 109,172` (no quotes) is an array, and the `[string]` parameter refused it ("Cannot process argument transformation on parameter 'Items'"), so the run never started and wrote no log. 3 of 9 commands for the PortCharles2013 missing episodes failed this way. `-Items` is now `[string[]]`, joined with commas. Tested with `-Estimate`: unquoted `109,172`, quoted `"109,172"`, and `1-3` through `ytdl.cmd` all list the right videos.

**Real-world test data:** 6 signed-in single-video runs, 2026-11-13 01:29–01:31, 1.12.0, 480p (135+251), with 3 pieces at once (the new default with one worker):

| Run | Video stream | Audio stream | Whole run | First estimate |
|---|---|---|---|---|
| 1999-05-13 | 44.9 MiB at 18.5 MiB/s | 14.0 MiB at 14.3 | 12 s | 14 s |
| 2000-05-05 | 75.7 MiB at 14.5 | 14.1 MiB at 10.8 | 16 s | 14 s |
| 2000-12-07 | 71.3 MiB at 11.5 | 16.6 MiB at 11.9 | 17 s | 15 s |
| 2001-11-20 | 49.7 MiB at 14.6 | 16.4 MiB at 15.1 | 16 s | 14 s |
| 2002-08-15 | 73.1 MiB at 15.4 | 18.0 MiB at 16.3 | 15 s | 14 s |
| 2003-04-08 | 58.2 MiB at 14.0 | 16.6 MiB at 11.7 | 15 s | 13 s |

- Video streams averaged **14.8 MiB/s**. Single signed-in downloads one piece at a time ran ~7–8 MiB/s (learned median 7.2), and the 1.10.0 single-video run on 2026-11-12 got 4.4 MiB/s (43.5 MiB in 9 s; whole run 23 s).
- No HTTP 403, no refusals, no errors, no bot checks; the fallback wasn't needed.
- First transfer started 7–8 s after launch (scan, extraction with the fast-starting build).
- Every first estimate was within 1–3 s of the real time.
- Files: all 480p (626–644 × 480), 20.4–21.7 min, moved into the collection (`Videos\.ytdl-logs\_move-log-pc2013-missing.csv`).

**Comparison, same session (01:37–01:38), 2-video runs** (default: 2 workers, pieces off), 480p:

| Run | Video streams | Whole run (2 videos) | First estimate |
|---|---|---|---|
| 1998 items 109,172 | 8.1 and 6.8 MiB/s | 22 s | 15 s |
| Time in a Bottle items 28,57 | 8.1 and 4.3 MiB/s | 28 s | 15 s |
| Tainted Love items 28,50 (01:40) | 8.0 and 9.0 MiB/s | 21 s | 15 s |

- Without pieces, each video stream ran 4.3–9.0 MiB/s (mean 7.2), against 14.8 with pieces in the single-video runs.
- Per video, the two approaches came out about even: 10.5–14 s with 2 workers and no pieces, 12–17 s for one video with pieces.
- The 2-video first estimates were 30–50% short (15 s vs 21–28 s): the second worker starts 3–4 s later, and both streams were slower than the single-stream prior.
- Pieces with 2 workers wasn't tried; with few videos it might combine both gains. Not changed on two runs' evidence.

### 1.12.0 — `-Fragments`: parallel pieces per file (2026-11-13)
**Source:** the yt-dlp vs ytdl comparison (see *Test history*, 11-13): yt-dlp fetches each YouTube file as 10 MiB range requests one at a time. Larger requests get throttled to ~100 KiB/s. Fetching 3 pieces at once averaged 15.8 MiB/s against 10.1 (12.2 s vs 17.1 s for one 142 MiB stream).

| Change | Detail |
|---|---|
| **`-Fragments <n>`** | `-N n` plus `YTDL_FRAGMENTS=1` for yt-dlp. Default 3 when this run downloads one video at a time (single video, one left, `-Parallel 1`), off for parallel workers. An explicit value is passed on to workers too. Banner shows "\| 3 pieces at once" |
| **Pieces set up by the format helper** (`ytdl_formats.py`) | Turns each direct-download format **of known size** into 10 MiB range fragments, built exactly like yt-dlp's own `formats=dashy` (`range=` URL query). Unlike `formats=dashy`, which **drops** formats without a reported size, the helper leaves those on yt-dlp's normal method. Format ids are unchanged, so format choice is the same. The helper is now always installed (it changes nothing unless a reply is reduced or `YTDL_FRAGMENTS` is set) |
| **Fallback** | 3 "HTTP 403 … fragment" refusals in a pass → restart with one piece at a time for the rest of the run (the 403 in 1 of 10 signed-out piece tests). If the helpers can't load, pieces are off with them |

**Verified:**
- Parse clean in PowerShell 7 and 5.1; file is pure ASCII.
- Single 1080p Blender video (182 MiB), signed out:
  - Default (3 pieces): video stream 7 s at 19.8 MiB/s, whole run 37.8 s.
  - `-Fragments 0`: 10 s at 13.6 MiB/s, 39.9 s.
  - The two files' video and audio streams are identical (md5). Archive and ETA parsing were normal ("speed measured: 19.8 MiB/s").
  - The whole-run gain is small there, because signed out runs pause 5–10 s per video and per-video fixed costs dominate.
- 2-video playlist: 2 workers, no pieces, exit 0.
- **Not yet exercised:** the 403 fallback, and pieces on a signed-in run.

### 1.11.0 — Lessons from a real run of embedding-disabled 240p uploads (2026-11-13)
**Source:** run `20261112-233049-24868.log`: the 1,463-video "Port Charles 1997-2003" playlist, 95 videos left, 3 workers, signed in, 1.10.0 with the fast-starting yt-dlp build. 0 bot checks, 0 failed videos, exit 0. 18.8 min, 9.6 GB.

**What the log showed:**
- 93 of 96 downloads were format 18, but 90 of the 95 new files are **320×240**. YouTube doesn't upscale format 18, so a 480p original would have given 480×360. These uploads simply are 240p; nothing was lost. (The 1.9.0 format check rightly didn't fire: the replies had separate audio formats, so they weren't reduced replies.)
- The videos **don't allow embedding**, so the fast client failed on each worker's first video. All 3 workers restarted with the default clients (~6 s each), and the whole Videos folder was marked "default clients" for 7 days (every playlist downloaded there).
- The resolution check got 1 of 3 samples (the other 2 failed for the same reason), so the run didn't get the 480p-and-below settings: no thumbnail check, **619 thumbnail misses** (~6.5 per video). Overhead was 12.1 s per video against 5.2–6.5 in earlier runs, and transfer share 66%.
- Total 8.8 MiB/s: small files and per-video overhead, not the connection. It was still recorded as a connection-cap reading.
- Estimates: first −17% … mean error 14% (earlier runs 5–9%), from the unusual overhead.

| Change | Detail |
|---|---|
| **Client fallback per URL** (`.ytdl-client.json` → `{ Urls: { <url>: <time> } }`) | Only the playlist that needed the default clients uses them for 7 days. The old folder-wide file format is ignored; the Videos folder's old file was removed (copy in `%TEMP%\ytdl-client.json.old`) |
| **Resolution check retries with the default clients** | Samples that fail with an embedding/age/format error are asked again without the fast client. If that answers, the URL is marked for default clients before the workers start, so they don't each fail and restart, and the run gets the right settings (thumbnail check at ≤480p) |
| **Cap readings filtered** | With 3+ readings, one under 70% of their median is not learned, unless 3 runs in a row read that low (then the line has probably got slower). `CapLowRun` in `bandwidth.json` counts them. The 8.82 reading was removed (`Caps` back to 13.7, 14.5, 14.9; previous file in `bandwidth.json.bak-before-1.11.0`) |

**Fast build in this run:** used by the coordinator and all workers (`[ytdl-event] yt-dlp: ...yt-dlp-dir\yt-dlp.exe`); no errors.

**Verified:** parse clean in PowerShell 7 and 5.1, pure ASCII. The per-URL client memory, run in both PowerShell versions, ignores the old format, writes two URLs and reads them back. Resolution-check retry tested live with a temporary copy whose first round was forced to fail ("Requested format is not available"): the second round answered, the message showed, the Blender URL was saved in that scratch folder's `.ytdl-client.json`, and `-Estimate` used the sizes (9.2 s). Not yet seen in a real embedding-disabled run.

### 1.10.0 — Fast-starting yt-dlp build (2026-11-12)
winget's `yt-dlp.exe` is a one-file build that unpacks itself at every start (~1.0 s before doing anything). ytdl starts yt-dlp at each playlist scan, the 3 resolution-check lookups, every worker start, every cookie or fragment restart, and every size-probe batch.

| Change | Detail |
|---|---|
| **Directory build** installed (user approved) in `%LOCALAPPDATA%\ytdl\yt-dlp-dir` | Official `yt-dlp_win.zip` of the same release (2026.10.26), checked against the release's `SHA2-256SUMS`. Start-up: **1.0 s → 0.33 s** (3 timings each) |
| ytdl uses it whenever it matches the winget copy | Match = the winget exe's size and time stamp recorded in `ytdl-version.txt`, so each run costs only a file stat. If the winget exe changes (an upgrade, including `-AutoUpdate`), the next run checks its version once and fetches the matching directory build (verified the same way); it swaps the old one out only if no other run is using it. If anything fails, that run uses winget's exe. Workers follow the coordinator. |
| Run log line `[ytdl-event] yt-dlp: <path>` | Shows which build a run used |
| winget remains the update source | The directory build can't update itself (yt-dlp doesn't support `-U` for it). Delete the folder to stop using it. |

**Verified:** parse clean in PowerShell 7 and 5.1, pure ASCII. A first run recorded the winget stamp, switched to the directory build, and scanned the playlist with it (1.5 s vs 2.2 s earlier the same day); its workers used it too. Both helper plugins (format check, thumbnail check) load in the directory build (`-v` lists them). A full download test was **not** possible: by then YouTube was answering every signed-out request from this connection with "Sign in to confirm you're not a bot" (after a day of test lookups), and the winget exe got the same refusal, so it isn't the build. Signed-in runs normally get past this kind of block, but the next one should be watched. The automatic update path (download on a winget upgrade) was written but not exercised, since there was no newer version to fetch.

### 1.9.0 — 3 workers at every quality; format check against silent 360p (2026-11-12)
**Source:** a review of where the three real runs' time went, a line-speed test, and signed-out tests on Blender uploads.

**Where the time goes (2002 run, 3 workers, per video besides the transfer):** watch page 1.8 s, player-challenge solving (deno) 1.3 s, metadata rewrite 0.44 s, merge 0.38 s, client config 0.25 s, player API 0.18 s, thumbnail convert + embed 0.11 s. Workers finished 13–24 s apart at 3 workers (113 s at 4). Cookie restarts cost 5 s each. yt-dlp.exe takes ~1.0 s just to start (one-file build).

**Line speed (not YouTube):** one download from a public test server 9.2 MiB/s, four at once 15.9 MiB/s. YouTube runs reached 14.5–14.9, so at ≤480p ytdl already uses ~92–94% of the line, and cutting per-video overhead barely changes a 3-worker run's length.

| Change | Why | Effect |
|---|---|---|
| **`-Parallel 3` by default at every quality** (was 1 above 480p) | One download runs at ~8 MiB/s, so HD one at a time used half the line | 1080p, same 6 videos: 1 worker 270 s, 3 workers 137 s (signed-out test, ~2×) |
| A single video, or a playlist with one left, uses one worker without a notice | The 1.5.0 default printed "-Parallel needs a playlist" and divided a single video's estimate by 3 (also at ≤480p) | Single-video test: estimate 29 s, actual ~34 s |
| **Format check** (yt-dlp extractor plugin `ytdl_formats.py`) | ~1 in 12 replies to the `web_embedded` client offer only format 18 (360p combined; yt-dlp warns about YouTube's "SABR-only" experiment), and yt-dlp then **silently downloads 360p** | See tests below |
| Format check also in the resolution check and the HD size probe | A reduced reply looked like 360p content (the 1.7.0 resolution check once reported 360p for HD videos this way) | — |
| **Resolution-check result remembered** per URL + `-Quality` for 7 days (`content.json`) | Re-running a playlist (after a stop or `-Estimate`) repeated the ~6–7 s lookups | `-Estimate` of 11 videos: 8.0 s → 2.9 s on a repeat |

**Format check findings:** a reduced reply lists only storyboards and format 18 (no separate video/audio formats at all), which no normal upload does. Asking the same client again in the same yt-dlp process got the same reduced answer 4 of 4 times (YouTube ties it to the session); asking with yt-dlp's default clients got the full list 5 of 5 times, at ~2 s extra for that video only. The plugin subclasses yt-dlp's YouTube extractor (`plugin_name='ytdl'`) and keeps its name, so log lines still read `[youtube] <id>: ...` and archive lines `youtube <id>`. If yt-dlp can't load the helpers, ytdl restarts without them (same fallback as the 1.7.0 thumbnail helper, now covering both).

Your signed-in runs (2001–2003) show **no** "SABR" warnings, so their format-18 downloads (18, 19 and 1 videos) were most likely videos that genuinely have no 480p; the problem showed up signed out (tests, and ytdl's own lookups).

**Verified:**
- Parse clean in PowerShell 7 and Windows PowerShell 5.1; file is pure ASCII.
- 9 Blender videos at `-Quality 1080`, no `-Parallel`: 3 workers, 9/9 at 1080p (399+251), exit 0. YouTube sent 3 reduced replies, and all 3 were fixed by the re-ask (they would have been 360p). Archive lines normal. In the 1.8.0 test before the fix, the same kind of run saved 2 of 6 videos at 360p.
- 60 test lookups across 5 videos with the plugin: 5 reduced replies, all re-asked, 60/60 at 480p.
- `-Estimate` with a remembered resolution: 2.9 s (pwsh 7); written and read back under 5.1 (4.1 s vs 8.0 s).
- Single video at 480p: one worker, no notice, exit 0.

**Considered, not changed:**
- *Trimming per-video overhead* (skipping the watch page, merging tags into the merge step, jpg covers to skip the 0.06 s convert): at 3 workers the line is the limit, so the gain would be small. Skipping the watch page also risks signed-in requests.
- *Faster worker hand-out at the end (`-Dynamic`)*: workers already finish within 13–24 s of each other at 3 workers.
- *yt-dlp's directory build* (`yt-dlp_win.zip`) starts in a fraction of the one-file exe's ~1.0 s, saving ~1 s at each scan, resolution check, worker start and cookie restart. That means installing a separate copy outside winget, so it's left for the user to decide.
- *Single-download speed history* now only grows from `-Parallel 1` runs (1.8.0 rule), which are rarer with 3 workers everywhere; the learned cap keeps updating from every full run.

### 1.8.0 — Estimates that know the connection's limit; faster resolution check (2026-11-12)
**Source:** the three real parallel runs (2001: 3 workers, 2002: 3, 2003: 4 workers), ETA lines replayed against actual finish times.

| Finding | Detail |
|---|---|
| Misleading first estimate with "best" | Printed before the resolution check, as one-at-a-time at "best" priors: **56 min and 1 h 00 m** for runs that took 28.7 and 30.1 min, corrected ~10 s later |
| Connection saturates | Total 13.7 / 14.5 MiB/s (3 workers), 14.9 (4); per download 6.7 (3) and **5.1 (4)**. The 1.6.1 rule `speedup = 1+0.7(n−1)` predicted 5.7–6.0 for 4, so 4-worker estimates started 6–19% low |
| History pollution | Parallel speeds were divided by that share before saving as "single-download" speeds: a 4-worker 5.1 MiB/s became 6.6, vs ~8 measured one at a time |
| Double counting | With `-Parallel` given up front, the coordinator's estimate used the shared per-download speed **and** divided by speedup(n), ~29% high at 4 workers (masked by other errors in the 2003 run) |
| Resolution check | 8.9–10.7 s, its 3 lookups one after another |
| Later in runs | Overall estimates mean 5–9% off after the first 10% of a run; within bandwidth noise, left alone |

**Changed:**
- **Connection-cap model:** each worker downloads for a fraction *d* of its time (transfer ÷ (transfer + fixed cost), from the run's typical video size, ~0.73 here), so ~n·d downloads overlap and each gets **min(single, cap ÷ (n·d))**. The cap is the median of `Caps` in `bandwidth.json`; the coordinator appends total MiB ÷ wall time after each full 3+-worker run (not stopped, ≥1 GB, ≥5 min; a 37 s test read 5.8 MiB/s, start-up dominated). Without a cap, the old rule is used. Replayed on the 2002 / 2003 first estimates after the resolution check: **−6% → −4%** and **+9% → 0%**; it predicts 5.0 MiB/s per download at 4 workers (5.1 measured) and 6.3 at 3 (6.7).
- Parallel runs no longer add converted speeds to the single-download history once a cap is known (one-at-a-time runs still do).
- Coordinator estimate = sum of per-video times at the shared speed ÷ n (no double counting). When the resolution check switches a run to 3 workers, that worker count's overhead/speed history is loaded (`Set-RunWorkers`).
- **No estimate before the resolution check** when it will run: `N left (runtime) | checking the resolution for the estimate...`, then the estimate. Runs where the check finds >480p now print their estimate after it too.
- **Resolution check runs its 3 lookups at once** (one yt-dlp each, 60 s limit). `-Estimate` on 10 Blender videos: **6.8–7.5 s vs 10.1–11.8 s** (pwsh and 5.1); identical heights/sizes to the sequential lookup in two side-by-side checks.
- `.ytdl-rate.json`: pre-1.0 keys (`qbest`, `qbest-p3`: runtime-ratio/regression models) are dropped on save.

**Verified:** parse-clean in 5.1 and 7; live 3-worker run (9 long Blender videos, 480p): 9/9, 0 errors, single-speed history unchanged; cap-learning path exercised under Windows PowerShell 5.1 with lowered thresholds (appended correctly, `Draws` preserved), then `bandwidth.json` restored and seeded with the three real-run caps. Seen while testing (not caused by 1.8.0): a signed-out lookup once returned only a degraded 360p format for HD videos, which made 1.7.0's check report 360p; signed-in runs haven't shown this.

### 1.7.0 — Faster at 480p and below: no worker rescans, no thumbnail misses (2026-11-12)
**Source:** full code review, then the real 2001 run log (251 videos, 3 workers) measured offline.

| Measured waste (2001 run) | Cost |
|---|---|
| Each worker re-listed the playlist the coordinator had just scanned | **8–9 s** per worker before its first download (first downloads at +20/22/23 s after launch) |
| Thumbnail misses: yt-dlp tries maxresdefault/hq720 (webp + jpg) one at a time; old uploads lack them | **1.65 s per video** (~4 misses), ~8% of each worker's time |
| Cookie restart: fixed 5 s wait, then yt-dlp re-reads the playlist | 12–22 s per rotation (3 rotations per 28 min) |
| Archive lookups: one file search per video at start-up and per finished video | ~0.4 s at start on a 1,463-video playlist; grows with archive × playlist |

**Changed:**
- **Workers use the coordinator's scan** (hidden `-QueueFile`: id, duration, position, known size per video) instead of scanning again. The worker falls back to its own scan if the file is missing or unreadable.
- **Thumbnail check** (at ≤480p and `-AudioOnly`, while thumbnails are embedded): a small yt-dlp `pre_process` plugin, embedded in `ytdl.ps1` and written to `%LOCALAPPDATA%\ytdl\plugins`, sends HEAD requests for all the guessed thumbnail URLs that rank above the best size-listed one at once. It drops the ones that return 404, so yt-dlp embeds **the same thumbnail** without trying the missing ones in turn. Any other result (timeout, other error, unexpected data) leaves yt-dlp's list unchanged. If yt-dlp can't load the plugin (pre-2025 yt-dlp), ytdl prints a notice and restarts the pass without it. It's not used above 480p, where newer uploads have the big thumbnails and the check would only add ~0.3 s. The banner shows `| thumbnail check` when it's on.
  - *Rejected first design:* keeping only thumbnails YouTube lists with a size. It picked a smaller thumbnail (480×360 instead of 640×480) on 1 of 3 test videos, because YouTube's list omits some that exist.
- **Cookie-restart wait 5 → 2 s** (the browser already holds the rotated cookies).
- **Archive in memory:** loaded once, then only newly appended lines are read (partial last line deferred; reset if the file shrinks). Same results as the old search on all 1,144 lines of the real archive. Per-video lookups cost about the same (~0.25 ms, dominated by the file open), but the start-up check no longer searches the file once per video.

**Kept as is (measured, not worth changing):** worker yt-dlp still reads the playlist pages (~6 s per launch/restart) so folder names and `NNN -` numbering stay exact. Two ffmpeg passes per video (merge + metadata, ~1 s each) can't be combined in yt-dlp. Per-line console handling is cheap at yt-dlp's output rate.

**Verified** (public Blender videos, `-Quality 480 -Sleep 0`, 3 workers, alternating order):

| Run | 1.6.1 | 1.7.0 |
|---|---|---|
| Items 1580–1588 (9 videos) | 50 s, 9 thumbnail misses | **37 s**, 0 misses |
| Items 1571–1579 (9 videos) | 46 s, 9 misses | **40 s**, 0 misses |
| First download per worker | +27–35 s | **+19–27 s** |

Filenames and embedded cover images were byte-identical between versions (18/18). Windows PowerShell 5.1 coordinator + workers: 4/4 OK. Plugin-load failure (forced): notice, 1 s restart, video saved with cover. 0 errors, 0 bot checks, no leftover temp files. Single-thumbnail test on 6 old videos: same file picked as stock yt-dlp every time, 52.2 → 47.7 s total.

**Expected on old ≤480p playlists like the 2001 run:** about 8–10 s less start-up per worker, plus ~1.3 s less per video per worker (≈ 6–8% of run time).

**Real-run check** (Port Charles 2002, 249 videos, `-Browser firefox`, "best" → 480p auto-detected, 3 workers; monitored read-only, compared with the 1.6.0 2001 run):

| | 2001 (1.6.0) | 2002 (1.7.0) |
|---|---|---|
| Videos / data | 251 / 23.0 GB (94 MB each) | 249 / 25.5 GB (105 MB each, +11%) |
| Wall time | 28.7 min | 30.1 min |
| First download after worker launch | 20–23 s | **8 s** |
| Thumbnail misses / thumbnail phase | 1,036 / 1.65 s per video | **0 / 0.07 s** |
| Non-transfer time per video (worker time − transfer) | 7.5 s | **6.1 s (−19%)** |
| Transfer share of worker time | 64% | **72%**: now bandwidth-bound (14.5 MiB/s total, 6.7 per stream) |
| Cookie rotations / cost each | 3 / 12–22 s | 4 / **5 s** |
| Overall ETA | mean 6.2%, first minute −61% | first −9%, mean 9.2%, first 5 min 6.6%, worst 21% |
| Errors / bot checks / retries | 0 / 0 / 0 | 0 / 0 / 0 |

Workers finished within 24 s of each other. A quick throughput probe (1–6 simultaneous 480p downloads of long Blender videos, 25 s windows) was too noisy to act on: the same setting measured 10.0 and 4.3 MiB/s minutes apart. Whether `-Parallel 4` raises total throughput is open and is best judged by an A/B pair of real runs.

**`-Parallel 4` vs 3, real runs** (Port Charles 2003: 197 videos, 19.4 GB, `-Browser firefox -Parallel 4`; against the 2001/2002 3-worker runs above):

| | 3 workers (2001 / 2002) | 4 workers (2003) |
|---|---|---|
| Total throughput | 13.7 / 14.5 MiB/s | **14.9 MiB/s (+3%)** |
| Seconds per GB | 74.7 / 70.8 | 68.6 |
| Per-download speed | 6.8 / 6.7 MiB/s | **5.1 MiB/s** |
| Non-transfer time per video | 6.5 / 5.2 s | 6.5 s |
| Cookie rotations | 3 per 29 min / 4 per 30 min | 4 per 22 min |
| Errors / bot checks / retries | 0 | 0 |
| Overall ETA | mean 6.1% / 9.2% | first −14%, mean 5.0% |

**Decision: the ≤480p default stays at 3 workers.** The connection saturates at ~15 MiB/s with 3, so a 4th worker splits the same bandwidth (per-download speed −24%) for +3% total, within run-to-run noise, at the cost of one more process, more frequent cookie rotations and a longer finish tail (113 s spread vs 13–24 s). `-Parallel 4` is safe to use; it just doesn't pay on this line.

**Format check (all three runs):** 480p came as `135+251` (H.264 + Opus), `244+251` (VP9, picked automatically when offered: 13 videos) or format 18 (combined 360p, ~18 per season where 480p wasn't offered). Alternate audio tracks (`251-3`, `251-5`, `251-7`, ~10% of videos) were checked on 6 files: all English, the original track. Remaining speed is bound by the connection; the only lever left is smaller formats, which would mean lower quality.

### 1.6.1 — Parallel ETA tuned on a real 251-video run (2026-11-12)
**Source:** a real 1.6.0 run, Port Charles 2001 (`-Items "767-1016,1189"` of a 1,463-video playlist, "best" requested), monitored read-only.

**What it showed:**

| Area | Finding |
|---|---|
| Resolution check | **worked as designed:** scan 251 videos in 8.4 s, 3 samples all 480p in 10.7 s, so 3 workers |
| Result | 251/251 in **28.7 min (6.9 s/video)**, about 2× the 2000 season's 13.6 s/video one at a time; workers balanced to within 13 s; 0 errors, 0 bot checks, 0 slow-downs |
| Per worker | fixed cost **5.9 s** per video (same as single), transfer 14.1 s, per-download speed **6.7 MiB/s** vs 8.8 single (0.76×, shared connection), 4.1 thumbnail misses per video |
| Overall ETA | mean 6.2% (worst 62%), but the first minute ran **−61% / −29%**: the first `ALL` line appeared at 11:08:58, built before every worker had its own estimate, with workers assuming a full single-download speed and a 4.0 s fixed-cost prior; within ±10% from minute 3 |
| Stability | **3 cookie rotations in 28 min** (vs 3 in 53 min single, so about 2× as often with 3 workers on one Firefox session; two workers rotated within 5 s), each recovered in ~6 s (~1% of run time); 2× HTTP 503 from YouTube, retried by yt-dlp; 5 site-required 5 s waits |
| Learned speed | 1.6.0 stored workers' **shared-connection** speeds into `bandwidth.json`, dragging its median from ~10 to ~7.4 MiB/s |

**Changed:**
- **Overall ETA (fixed split)** is shown only once every worker has started and reported its own estimate.
- **Bandwidth prior scaled for sharing:** each of n workers starts from typical × speedup(n)/n (0.8 for 3; 0.76 measured). Speeds saved to `bandwidth.json` are divided by that share, so they're single-download equivalents.
- **Prior fixed cost** constant +4 → **+5.5 s** (`3·S + n·R + 5.5`): 5.5 s at L0 against 5.9 s measured single and per worker.

**Live check** (same 12 Blender videos, 480p, 3 workers):

| | 1.6.0 | 1.6.1 |
|---|---|---|
| First overall ETA | −45% | **+1%** |
| Mean error | 33.9% | **8.8%** |
| Worst | 58% | 92% (one line in the final seconds of a 67 s run) |
| Speeds saved | 3.7–4.5 MiB/s (shared) | 8.9–18.2 MiB/s (single-equivalent) |

0 bot checks, 0 errors. The already-polluted `bandwidth.json` median recovers by itself as new single-equivalent samples replace the old ones (it keeps the last 50).

**Open option:** at ≤480p, old uploads miss ~4 thumbnail sizes per video (~12–15% of run time even with 3 workers). `-NoThumbnail` removes that but drops cover art; left opt-in pending a decision. *(Resolved in 1.7.0: the thumbnail check removes the misses and keeps the cover art.)*

### 1.6.0 — Learned from a real 234-video run: resolution check, probe-fed bitrate (2026-11-12)
**Source:** a real 1.5.0 run, `ytdl -Browser firefox <Port Charles 2000 playlist>` (234 videos, 81 h of video, 14.2 GB), monitored read-only through its run log.

**What it showed:**

| Area | Finding |
|---|---|
| Result | 234/234 in **53 min 16 s** (13.5 s per video); 0 errors, 0 bot checks, 0 slow-downs (no-pause L0 held for 53 min) |
| Formats | "best" resolved to **135+251 (480p H.264) ×136, 243+251 (360p VP9) ×97, 18 ×1**, never above 480p, yet the run used one worker and the "best" ETA priors |
| Time split | transfer 56%, fixed cost 43% (5.9 s), site waits 0% |
| Thumbnails | **every** video missed 4–6 HD thumbnail sizes first: **2.0 s per video, 469 s total (14.7%)**. yt-dlp has no option to pick which sizes it tries. |
| ETA | whole run 9.0% mean (worst 35%), but **first 10 min 20.0%** (+15–29%): the "best" bitrate prior (0.15) vs reality (0.049) lingered, because background-probe sizes weren't used for unprobed videos |
| Size probe | one yt-dlp call per video (each re-reading Firefox cookies); it ran the whole 53 min (233 found, 1 failed) as a second cookie user |
| Cookies | **3 real rotations** (10:00:40, 10:10:50, 10:30:53), each recovered in 6 s. First real-world confirmation of the 0.8.0 restart. |
| Startup | 25 s before the first download. The archive check was only 0.1 s (893 lines); yt-dlp's own playlist read was ~2 s; the rest is ytdl's flat scan, now timed in the log |
| Log | lines after a line break in a message had **no timestamp**, which first made it look like the cookie restart hadn't fired |

**Changed:**
1. **Resolution check.** When the request is "best"/720p+ and 8+ videos are pending, ytdl looks up 3 samples (first, middle, last) in one yt-dlp call (~11 s). If all are ≤480p, it uses the 480p-and-below settings: `-Parallel 3` (unless `-Parallel` was given), no background probe, the early ETA, and the **detected resolution's bitrate prior and history** (`q480`/`q360`), seeded with the samples' exact sizes. Workers get `-LowResContent -ContentHeight <h>`.
2. **Bitrate uses every known size.** `Get-Bitrate` counts the sizes already known for not-yet-downloaded videos (probe, `-Precise`, the resolution check), cached for 2 s. `-Precise` no longer adds its sizes separately, which would double-count.
3. **Probe batching:** 10 videos per yt-dlp call.
4. **Run log:** every line gets its own timestamp. Startup steps are logged as `[ytdl-event] playlist scan: N video(s) in X s` and `resolution check: … heights …, X s`.
5. **`-NoThumbnail`** (opt-in) drops `--embed-thumbnail`.
6. **Parallel ETA divisor** is the measured speedup `1 + 0.7·(n−1)` (2.4× for 3 workers, from the 30-video benchmark), not n.

**Replay of the real run** (first 10 minutes, single-download timeline; mean error):

| Bitrate source | Error |
|---|---|
| 1.5.0 as it ran ("best" prior 0.15) | 20.0% |
| 3 sample sizes + "best" prior | 14.3% |
| **3 sample sizes + detected 480p prior (chosen)** | **7.4%** |
| detected 480p prior, no samples | 8.8% |

(The simplified replay doesn't model the probe's later sizes, so only the first 10 minutes are compared.)

**Validation:**
- **Offline** (stand-in yt-dlp): "best" on 480p content detects, starts 3 workers with no probes; "best" on 1080p content leaves the run alone and batches its remaining probes into one call; `-NoThumbnail` drops the flag; run log 0 untimestamped lines.
- **Live:** `-Estimate` on the real Port Charles 2000 playlist detects 480p and estimates **~13.2 GB** (actual download 14.2 GB; 1.5.0 said ~21.3 GB) and ~15–16 min with 3 workers. Blender at best: samples 1280/1920/1080, no change. A real `-Quality 480` run (3 workers) and a best run both exit 0, with all files, 0 bot checks, and nothing left running.
- **Not yet measured:** a full real ≤480p "best" playlist run with 1.6.0 (expected ~20 min for the 2000 playlist instead of 53).

### 1.5.0 — Faster at 480p and below: no-pause level, automatic -Parallel 3 (2026-11-12)
**Where the time went (1.4.2, 360p / 480p, per video):** page reading 4.2 / 4.3 s, site-required wait 0 / 0.6 s, pre-download 0.6 / 0.8 s, **transfer 6.4 / 10.8 s** (two streams in sequence), finishing 1.7 / 2.1 s (merge ~0.95 s, metadata remux ~0.96 s, thumbnail ~0.15 s). Total 13.0 / 18.5 s. A single download seems capped at ~10 MiB/s, so overlapping videos is the biggest lever.

**Benchmark** (360p, 6 videos, alternating, 0 bot checks in any run):

| Mode | Average | Per video | vs 1.4.2 |
|---|---|---|---|
| 1.4.2 (L0 = 0.5 s per request) | 94 s | 15.7 s | — |
| no request pauses (`-Sleep 0`) | 68 s | 11.3 s | 28% faster |
| `-Parallel 2` / `3` / `4` | 60 / 63 / 50 s | 10.0 / 10.5 / 8.3 s | 36 / 33 / 47% faster |

(The 0.5 s request pause cost ~4 s per video, more than its nominal ~2 s, because later steps wait on it.)

**Changed:**
- **New L0 = no pauses** (`S 0, R 0`). The 1.4.x L0 (0.5 s per request) is now L1, followed by 3/5/10/20 s. Signed-in runs start at L0, unsigned at L3 (5 s, as before). Pace files now carry `Scheme = 2`; files without it (1.3/1.4) are read one level higher, so a saved slowdown isn't lost. Overhead history is keyed by both pauses (`ov-s<S>r<R>-p<n>`).
- **`-Parallel` defaults to 3 at 480p and below** (and `-AudioOnly`) unless `-Parallel` is given; the banner says so. Single-video URLs still fall back to one worker.
- **`-NoMetadata`** (opt-in) drops `--embed-metadata`, the ~1 s second ffmpeg pass.
- **`-Fast360`** (opt-in, `-Quality 360` only) selects `18/<normal 360p>`. Measured on a 280 s clip: format 18 is H.264 400 kbps + AAC, **17.4 MB in 18.0 s**; the default is AV1 153 kbps + Opus, **9.8 MB in 21.3 s**. Stills look nearly identical. So format 18 is only ~15% faster and ~78% bigger, and its real use is compatibility with players that lack AV1.

**Validation:**
- **Offline** (stand-in yt-dlp logging args): auto `-Parallel 3` at 360p, every worker with no pause args and metadata on; `-Parallel 1` single; no auto-parallel at 1080p; `-NoMetadata` drops the flag; `-Fast360` gives `18/…` at 360p and a warning at 480p; an old pace file at L1 starts at the new L2 (3 s), a Scheme-2 file at L1 at L1.
- **Live, 30 videos at 360p, same items:** 1.4.2 **455 s (15.2 s/video)** vs **1.5.0 140 s (4.7 s/video): 3.2× faster**. 30/30 files, 0 bot checks, 0 slow-downs, 0 errors in both. 3 site-required 5 s waits in each.

### 1.4.2 — ETA that copes with bandwidth swings within a run (2026-11-12)
**Data:** six transfer-heavy recordings with 1.4.1 (720p, 1080p and best, two cold runs each, ~13.6 GB, 477 timestamped progress lines). A new replay scores every variant **every 30 s** through each run, not only between videos, so the in-progress video can be evaluated. All variants are scored on the same 55 checkpoints.

**What the swings look like:** per-stream speeds ranged 2.4–19.8 MiB/s *within single runs*, with medians of ~7–10 MiB/s. In the worst run (W6), the first video (406 MiB) downloaded at 3.0 MiB/s and all later ones at 10–13 MiB/s. Because 1.4.1's bandwidth is a byte-weighted cumulative average, that one slow file set the speed for every later estimate (+50% to +170%). The first video is **not** systematically slow: its speed relative to the rest ranged 0.25×–1.89× across the six runs, so excluding it would have been overfitting one run.

**Replay (in sample, 6 runs, every 30 s):**

| Variant | Mean | Worst |
|---|---|---|
| B0 1.4.1 | 36.1% | 190% |
| B1 + in-progress video from progress lines | 30.2% | 196% |
| B2/B3 median per-video speed (alone / with B1) | 32.9% / 27.0% | 190% / 196% |
| B4 B1 + 50/50 window of the last 3 videos | 30.2% | 196% |
| B6 B1 + per-stream draws counted equally (no prior) | 33.0% | 177% |
| **B8 B1 + equal draws shrunk to 7.7 MiB/s (4 streams)** | **24.0%** | **130%** |
| shrink to 5.0 / 6.0 / 10.0 MiB/s | 39.6% / 31.2% / 21.6% | 158% / 145% / 117% |
| shrink weight 6 / 8 streams (7.7 MiB/s) | 22.8% / 22.0% | 123% / 118% |

The gain depends strongly on the prior speed being close to the user's real typical speed. A fixed 5 MiB/s would be *worse* than 1.4.1. Hence a **learned** prior.

**Changed:**
- **In-progress video:** remaining = (its size − bytes already done, from finished streams plus the latest progress line) × (50/50 of the current stream's measured speed, once it has ≥10 s of data, and the model speed) + max(1.5 s, fixed cost not yet spent). This replaces "estimate − elapsed", which stayed wrong for the whole of a slow long download.
- **Bandwidth:** every completed stream of ≥10 MiB is one draw (s/MiB), counted equally. The estimate is the mean of this run's draws plus the folder's last 10 saved draws, shrunk toward a **learned typical speed** worth 4 streams. The typical speed is the median of the last 50 stream speeds across all runs, kept in `%LOCALAPPDATA%\ytdl\bandwidth.json`, and 7.7 MiB/s until 5 exist. Runs with only small streams so far use their bytes blended toward that prior. Low resolutions with no measurement start from the prior instead of the old fixed 5 MiB/s. The 1.4.1 fixed 5 MiB/s cold blend is removed.
- The shrink weight stays at 4 (not the slightly better 6–8 in the replay), so a real change in the connection is followed sooner.

**Out of sample** (3 new runs, 720p/1080p/best, same replay):

| Model | Mean | Worst |
|---|---|---|
| 1.4.1 | 27.4% | 71% |
| 1.4.2 method with the *default* 7.7 MiB/s | 28.6% | 78% |
| **1.4.2 method with ~10 MiB/s** (what it learned during this batch: 9.7–10.5) | **22.8%** | **68%** |

So the very first run on a new install behaves about like 1.4.1; from the second run, once the typical speed is learned, it's better.

**Live (1.4.2, new videos):** 720p 15.1% / 42%, 1080p 26.9% / 47%, best 16.5% / 24%, **360p 12.2% / 21%**, **480p 18.9% / 32%** (1.4.1 live on other videos: 360p 19.2%, 480p 24.2%). `-Parallel 2` regression passed. 0 bot checks.

### 1.4.1 — ETA tuning for 1.4.0's faster pipeline (2026-11-12)
**Method:** recorded timestamped 1.4.0 runs in fresh folders (360p, 480p, 720p, 1080p, best/4K-first) and replayed them through a copy of the ETA model and 9 variants, both cold (no history) and chained (each run inheriting the capped history of the previous ones). The winner was then checked live, and by replay, on 30 new videos (out of sample).

**Findings:**
- 1.4.0's per-video fixed cost is **~6–7 s** (6.3 s in the recordings, 7.2 s out of sample), but the prior was still **11 s** (`1.5·S + 8·R + 7`). That's why 1.4.0's first estimates at 360p/480p came out +40% / +28%.
- The old formula was also wrong in shape. yt-dlp pauses before **each** stream, so twice per merged video, and the fast client makes ~4 requests, not ~8. A formula fitting both the 1.0-era data (`-Sleep 5`: 24–25 s) and 1.4.0 (6.3 s) is **`3·S + n·R + 4`**, with n = 4 (fast client) or 6 (default clients).
- Recency-weighted bandwidth (EWMA, half-life 50/100 MiB) made estimates **worse** (cold 18–21% vs 15%): it over-reacts to single slow or fast streams.

**Replay** (recordings; mean error, cold / chained):

| Variant | Cold | Chained |
|---|---|---|
| 1.4.0 | 15.2% | 19.0% |
| prior = measured 6.3 s | 14.0% | 17.6% |
| recency-weighted bandwidth (100 / 50 MiB) | 18.4% / 20.8% | 19.6% / 22.1% |
| cold bandwidth blended with 5 MiB/s (30 MiB weight) | 16.8% | 19.3% |
| formula `3·S + n·R + 4` | 14.2% | 17.6% |
| **formula + cold blend (chosen)** | **12.9%** | **17.3%** |

**Out-of-sample replay** (30 new videos, same two models):

| Model | Cold mean | Chained mean | Worst: 360p / 480p / 720p |
|---|---|---|---|
| 1.4.0 | 32.7% | 24.0% | 74% / 63% / 128% |
| **1.4.1** | **29.4%** | **23.3%** | **32% / 48% / 116%** |

**Changed:**
- `Get-PriorOverhead` = `3·S + n·R + 4` s (n = 4 under the fast client, 6 otherwise). That's 6.0 s at L0 and 25 s at the old `-Sleep 5`.
- With no saved bandwidth history, `Get-SecPerMiB` blends this run's completed transfers with a 5 MiB/s prior worth 30 MiB. Once history exists, there's no blend.

**Live (1.4.1, new videos):** 360p cold 19.2% / 32% (first +24% at 3 s; 1.4.0 recording: 23.2% / 98%, first +40%). 480p cold 24.2% / 57% (first **−3%**; 1.4.0: first +28%). 480p with history 16.9% / 35% (first −7%). `-Parallel 2` exit 0, files correct, lock released. 0 bot checks, slow-downs or fallbacks.

**Remaining limitation (measured):** the 720p live run had videos of 300–660 MiB and single-stream speeds of **2.0–16.1 MiB/s** within one run. Its first video downloaded at ~2.8 MiB/s, so every estimate after it read +81% to +116% until faster streams pulled the average back. Both models score ~50% on that run. Within-run bandwidth swings are now the main error source, and neither the cumulative nor the recency-weighted average handles them well.

### 1.4.0 — Fast extraction, one pause per video (2026-11-12)
**Where the time went at 1.3.0 L0** (timestamped logs, 360p): ~15 s per video, of which **~5 s was extraction**: 5–6 requests, each preceded by a 0.5 s pause, plus ~0.7 s of JS challenge solving. Another **~1.5–3 s was the pre-download pause, paid twice** (yt-dlp pauses before the video stream and again before the audio stream). Transfer was ~4–8 s and post-processing ~1.5 s.

**Client survey** (5 videos incl. 4K and long 1080p × best/1080/480/360 = 20 lookups per configuration, no downloads):

| Configuration | Same formats as default | Requests | Lookup time | Notes |
|---|---|---|---|---|
| default | 20/20 | 6.0 | 7.2 s | |
| default, `skip=hls` | 20/20 | 5.0 | 6.4 s | |
| `web_embedded` | 20/20 | 5.0 | 6.3 s | |
| **`web_embedded` + `skip=hls`** | **20/20** | **4.0** | **5.8 s** | chosen |
| `tv` | 0/20 | 4.0 | 4.8 s | all failed ("page needs to be reloaded") |
| `web_safari` | 0/20 | 5.0 | 7.7 s | HLS (m3u8) formats instead of https |
| `mweb` | 0/20 | 4.0 | 6.9 s | needs a GVS PO token; falls back to 360p format 18 |
| `web` | 0/20 | 2.0 | 4.7 s | only format 18; fails at 360/480 |

**Changed:**
- **Fast extraction** (default; `-NoFastClient` turns it off): `--extractor-args "youtube:player_client=web_embedded;skip=hls"` on every pass and on the background probe. Because `tv_samsung` isn't queried, its "DRM protected" notice no longer appears at all.
- **Automatic fallback:** under the fast client, an `ERROR` matching `Playback on other websites has been disabled | embedding disabled | Requested format is not available | Video unavailable | This video is not available | Sign in to confirm your age | age-restricted | inappropriate for some users` kills yt-dlp and restarts with yt-dlp's default clients (not counted as a pass). The folder is remembered in `<Out>\.ytdl-client.json` for 7 days.
- **Bot-check pattern tightened** to `confirm you're not a bot | not a bot | HTTP Error 429 | Too Many Requests | rate limit`, so "Sign in to confirm your **age**" triggers the client fallback instead of a pacing slow-down.
- **L0 = one pause per video:** `S = 0, R = 0.5`. There's no `--sleep-interval` (which yt-dlp applies before each stream, so twice per merged video), only `--sleep-requests 0.5`. Levels 1–4 are unchanged, and the adaptive back-off still applies. The prior overhead at L0 is now `8·0.5 + 7 = 11` s.

**Benchmark** (live, `-Browser firefox`, auto pacing, alternating, same items):

| Test | 1.3.0 | 1.4.0 |
|---|---|---|
| 360p, items 167–172, pair 1 | 186 s | **83 s** |
| 360p, items 167–172, pair 2 | 102 s | **77 s** |
| `-Parallel 3`, 360p, items 173–181 | 93 s | **55 s** |

The first 1.3.0 run was an outlier. Like-for-like gains were **25% (single) and 41% (parallel)**. Bot checks, slow-downs and fallbacks: 0 in every run. Picked formats were **identical in all 4 single runs**. At best quality, 1.4.0 picked `401+251` (4K) for both 4K test clips, matching the default clients. The user's playlist was also checked: the fast client picked the same formats as the default for its first 2 items (lookup only).

**Verified offline** (stand-in yt-dlp recording args): L0 sends only `--sleep-requests 0.5` plus the fast client args. An embedding-disabled error restarts without them after 5 s, saves `.ytdl-client.json`, and the next run in that folder starts on the default clients. The age message falls back without writing a pace file. `-NoFastClient` sends no extractor args.

### 1.3.0 — Adaptive pacing, background size probe, yt-dlp age check (2026-11-12)
**S1, adaptive pacing (`-Sleep` now defaults to auto).** Under the old fixed `-Sleep 5`, ~14 of the ~25 s fixed cost per video was ytdl's own pauses. Auto pacing uses levels of (pause between videos, pause before each page request): L0 1–2 s / 0.5 s, L1 3–6 s / 1 s, L2 5–10 s / 1 s (the old default), L3 10–20 s / 2 s, L4 20–40 s / 3 s. Signed-in runs (`-Browser`/`-Cookies`) start at **L0**; others at L2. A line matching `Sign in to confirm | not a bot | HTTP Error 429 | Too Many Requests | rate limit` kills yt-dlp, steps up one level, saves it to `<Out>\.ytdl-pace.json`, and restarts after 10 s (30 s × level for rate limits). These restarts don't count as passes. A new run within 24 h of the last bot check starts at the saved level. An explicit `-Sleep N` keeps fixed pacing. The ETA's prior overhead now follows the pacing (`1.5·S + 8·R + 7` s, which is 22.5 s at 5/1), and overhead history is kept per level.

**R7, coordinated back-off.** Every run's watchdog reads the pace file every 10 s and, if another worker (or run) on the folder has slowed down, restarts at that level.

**S3, background size probe.** Above 480p (not with `-Precise`, `-NoProbe`, or under the coordinator), a background runspace looks up each pending video's exact size at the download format, in download order, paced only by `--sleep-requests`. The ETA uses each size as soon as it's known. The first version added a pause between probes equal to the pacing interval, so 6 probes took 3.5 min and arrived after their videos had downloaded; one live comparison then came out *worse* (30% vs 20.9% mean). With the gap removed:

| Best quality, cold, 4K shorts first (2 alternating runs each) | Mean | Worst | \|first\| |
|---|---|---|---|
| 1.2.1 (no probe) | 18.0% | 50% | 9% |
| **1.3.0 (probe)** | **9.8%** | **24%** | **2%** |

**R3, yt-dlp age check.** At most daily (stamp in `%LOCALAPPDATA%\ytdl\update-check.json`), ytdl reads yt-dlp's date-based version. It warns at 30+ days, and **`-AutoUpdate`** updates it at 7+ days with the manager it came from (1.26.1; before, always `winget upgrade yt-dlp.yt-dlp`).

**S4, metadata rewrite, measured and not changed.** yt-dlp's metadata step remuxes the finished file: **2.5–4 s per GB** (1.9 s for a 490 MB file, 0.5 s for 190 MB), i.e. 1–2 s on a ~500 MB best-quality video, under 2% of its time.

**S2, `-Dynamic` (experimental).** The coordinator now runs a slot loop over a queue of batches: the fixed split is one balanced batch per slot (the default, as before), and `-Dynamic` uses batches of `-Chunk` videos, biggest first, handed to whichever slot is free. Batches are full ytdl runs (playlist URL + `-Items`), so naming, retries, restarts and stop all still apply. `-Parallel 3`, best quality, items 2,4,6,8,23,26,27,29, `-Sleep 5`, alternating:

| Method | Runs | Average |
|---|---|---|
| Fixed split | 160 s, 143 s | 152 s |
| `-Dynamic -Chunk 2` | 144 s, 146 s | 145 s |
| `-Dynamic -Chunk 1` | 145 s | 145 s |

The ~5% difference rests on one slow fixed run, so it's within noise and **not made the default**. Unlike the 0.10.0 per-video queue (153 s), it isn't slower either, so it's kept as an opt-in.

**S1 benchmark** (360p, items 161–166, alternating):

| Pacing | Runs | Average | Bot checks |
|---|---|---|---|
| fixed `-Sleep 5` | 254 s, 184 s | 219 s | 0 |
| **auto (L0, signed in)** | **99 s, 98 s** | **98 s (55% faster)** | 0 |

**Verified offline** (stand-in yt-dlp): starting levels (L0 with `-Browser`, L2 without, fixed with `-Sleep 7`); a bot check restarts at L1 after 10 s and saves the pace file; the next run starts at L1; an external pace-file change to L3 is followed in 9 s; the probe finds all sizes and leaves nothing running; the age check warns at 315 days and is skipped on the second run; `-Dynamic -Chunk 1` hands the third batch to the first free worker; `-Stop -Out` during `-Dynamic` starts no further batches (exit 2). **Live:** all benchmark runs above, plus `-Parallel 2` (exit 0, 42 s vs 100 s for 1.2.1 with fixed pacing) and `-Estimate`.

### 1.2.1 — Stability fixes; 720p/1080p ETA priors (2026-11-12)
- **DRM warning hidden.** `Some … client https formats have been skipped as they are DRM protected` is printed by yt-dlp when one of the clients it queries lists DRM-protected formats. yt-dlp skips them and uses the regular formats. It was never counted as an error (ytdl only counts `ERROR` lines), so it now goes to the run log only.
- **R1, folder lock.** `<Out>\.ytdl.lock` is held open exclusively, so Windows releases it if ytdl crashes and it can never go stale. A second run on the same folder exits **3** and names the holder (pid, start time, URL). Workers and `-Estimate` don't lock.
- **R2, disk space.** Before downloading, free space must cover the estimated download ×1.1, plus the largest file (merge room), plus `-MinFreeGB` (default 2); otherwise ytdl exits 2 unless `-NoSpaceCheck`. During the run, the watchdog checks every 20 s and stops cleanly (exit 2) below `-MinFreeGB`.
- **R4, run log.** A `Write-Host` wrapper copies everything ytdl prints to `<Out>\.ytdl-logs\<date>-<pid>.log` (UTF-8, auto-flushed); hidden lines and `[ytdl-event]` markers go there too. The newest 50 are kept.
- **R5, launcher.** `ytdl.cmd` uses `pwsh` if found, otherwise Windows PowerShell 5.1.
- **R6, UTF-8.** Console output encoding and `PYTHONIOENCODING` are set to UTF-8 for every role (previously only workers), so emoji and accented titles display and log correctly in 5.1. The original encoding is restored on exit.
- **S5, tool cache.** Tool folders found under WinGet\Packages are cached in `%LOCALAPPDATA%\ytdl\tools.json`.
- **Per-folder stop.** `ytdl -Stop -Out <dir>` creates `<dir>\.ytdl.stop`, which only runs on that folder honour; plain `ytdl -Stop` stays global. This was prompted by a test mistake: an offline test's global `ytdl -Stop` stopped a live 1080p accuracy run, which had to be redone.
- **Stale worker logs.** A coordinator deletes `%TEMP%\ytdl-<pid>-w*` logs whose coordinator process no longer exists (left when a window is closed mid-run).
- **720p/1080p bitrate priors**, measured: `q720` 0.09 → **0.055**, `q1080` 0.14 → **0.08** MiB per video-second (observed 0.0545 and 0.0799; the old priors made first estimates +28–35%).
- **Bug found before release:** replacing every `(Test-Path $stopFile)` with `(Test-StopRequested)` also rewrote the line *inside* `Test-StopRequested`, which then called itself. That caused a call-depth overflow wherever the stop check ran inside a wait (the `-Parallel` worker stagger, retry/restart waits). Single runs without retries passed, which hid it. It was caught by the real `-Parallel` regression, fixed, and covered by new offline tests for `-Parallel`, the retry wait and `-Stop -Out` during `-Parallel`.

**720p/1080p accuracy** (live; mean / worst / first estimate):

| Run | Version | Result | Notes |
|---|---|---|---|
| 720p cold | 1.2.0 | 11.9% / 35% / +35% | |
| 720p cold | 1.2.1 | 14.9% / 43% / −37% | speed measured 14.1 MiB/s on the small first stream, then dropped |
| 720p warm | 1.2.0 | 50% / 95% / −47% | bandwidth swung 8 → 2.4 MiB/s and back mid-run |
| 1080p cold | 1.2.1 | 35.4% / 53% / +51% | bandwidth 3.4–7.8 MiB/s |
| 1080p warm | 1.2.0 | 10.4% / 28% / +28% | |
| 1080p warm | 1.2.1 | **9.0% / 13% / +7%** | new priors |

Cold runs at 720p/1080p are dominated by bandwidth swings within the run, which no prior can foresee. The 1.3.0 background probe addresses the size side of the error.

**Verified:** offline (stand-in yt-dlp): DRM hidden but logged, emoji title intact in the log, the lock refuses a second run with exit 3 and releases cleanly, the disk pre-check refuses (exit 2) and the in-run stop triggers in 5 s, console code page 437 restored, the launcher picks 5.1 without pwsh and 7 with it, `-Stop -Out` stops only its folder, the stale-log cleanup works. Live: 720p/1080p single runs, `-Parallel 2` (after the bug fix), `-Estimate`.

### 1.2.0 — Recover from fragment 404 loops (2026-11-12)
**Problem (reported):** `Got error: HTTP Error 404: Not Found. Retrying fragment 132`, repeating until the video never finishes.

**Cause:** the video was being downloaded as a **fragmented** stream (HLS/DASH), and YouTube stopped serving its fragments: the signed stream URLs expired, or the fragmented format was withdrawn. yt-dlp's `--fragment-retries` keep asking the same dead URL, so retrying can't succeed. A fresh yt-dlp run re-extracts the video and gets new URLs. On the public test video, ytdl's selectors pick plain `https` formats at best/480/360 with yt-dlp 2026.10.26 (still the latest), so the fragmented downloads come from the particular videos being downloaded (fewer https formats offered, or a fallback).

**Changed:**
- **Fragment-404 restart:** a 404 line mentioning a fragment counts toward a per-video counter, which resets on each `Downloading webpage` line. On the 3rd one, ytdl kills the yt-dlp tree (like the 0.8.0 cookie restart), waits 5 s, and runs the identical command again. The new run gets fresh URLs, and `--continue` resumes the partial download. **`-FragmentRestarts <n>`** (default **5**, `0` = off) caps this. Restarts don't use `-Retries` passes. Once the cap is reached, detection stops killing, yt-dlp's own retries finish, and a video that still fails is retried in later passes like any other failure. The restart banner now names its reason (fresh stream URLs or fresh cookies).
- **`-S res,proto`:** at the same resolution, prefer plain https over fragmented streams. Resolution stays the first sort key, so quality isn't lowered. Verified: same picks as before on the test video (401+251 at best, 397+251 at 480p, 396+251 at 360p, all https).
- **`--abort-on-unavailable-fragments`:** a video with fragments that are permanently gone now fails with an error (and gets retried) instead of being saved silently with gaps.

**Verified:**
- Stand-in `yt-dlp.exe` printing the exact "HTTP Error 404 … Retrying fragment 132 (n/10)" lines, then hanging, with `-FragmentRestarts 2`: killed after the 3rd 404 and restarted twice ~5.8 s apart. The 3rd run was left alone and ran to completion. Exit 0, no leftovers.
- Real-download regression of the 1.2.0 build: single (360p), `-Parallel 2` (480p) and `-Estimate` (best and 480p) all exit 0, with correct numbering and archive and no leftovers.
- **Not verified:** a real YouTube fragment-404 event, which can't be triggered on demand.

### 1.1.0 — Low-resolution ETA tuning; ETA from the start at ≤480p (2026-11-12)
**Method:** recorded three timestamped runs with 1.0.0 (480p cold, 10 videos; 480p warm, 8; 360p cold, 10). Each video's wall time, transfer time, size and runtime were extracted, and the logs were replayed through the 1.0.0 formula and 12 variants.

**Findings:**
- Overhead averaged **24–25 s** (prior was 22.5 s). Raising the prior made results *worse*, because the real bias was elsewhere.
- **Bitrate priors were too high:** 480p measured **0.0287** MiB per video-second (prior 0.05) and 360p **0.0235** (prior 0.03). With a 1200 s prior weight (≈ one video), the prior still carried ~half the weight after the first video, so 1.0.0 **overestimated** by +8% to +27%.
- **Each run's first video costs a few seconds more** (player JS download, challenge solving, cookie read, all cached afterwards): e.g. 30.4 s against ~22–27 s for the rest. Averaging it in inflated every later prediction.
- At ≤480p, transfer is only ~10–25% of each video's time, so a guessed bandwidth costs little accuracy.

**Backtest** (mean / worst / first-estimate error):

| Variant | 480p cold | 480p warm | 360p cold | Overall |
|---|---|---|---|---|
| 1.0.0 | 16.4% / 27% / none | 6.1% / 9% / +5% | 10.0% / 14% / none | 11.0% |
| + 5 MiB/s bandwidth prior | 16.3% / 27% / +16% | 6.1% / 9% / +5% | 9.7% / 14% / +7% | 11.0% |
| + overhead prior 25 s | 18.5% / 28% / +23% | 7.0% / 10% / +6% | 12.1% / 15% / +15% | 12.9% (worse) |
| + measured bitrate priors | 11.6% / 25% / −4% | 4.3% / 7% / +1% | 8.5% / 14% / +1% | 8.4% |
| **+ skip first-video overhead (chosen)** | **10.6% / 24% / −4%** | **3.1% / 6% / +1%** | **8.1% / 13% / +1%** | **7.6%** |
| + 4 s first-video extra | 10.5% / 24% / −3% | 3.3% / 6% / +3% | 8.2% / 13% / +3% | 7.6% (no gain) |

Also tried and not adopted: overhead prior weight 0.5/2, median overhead, bitrate prior weight 300/600.

**Changed:**
- Bitrate priors: `q360` 0.03 → **0.025**, `q480` 0.05 → **0.03** MiB per video-second (others unchanged).
- **First-video overhead** is kept apart. It's used only until a second video finishes, and never saved to history unless the run had just one video.
- **ETA from the start at ≤480p and `-AudioOnly`:** with no bandwidth measured yet, assume 5 MiB/s (0.2 s/MiB). The line is tagged `[rough: speed not measured yet]` until the first transfer completes ("speed measured"). Above 480p transfer dominates, so those still wait for a measurement.

**Live validation** on unseen videos (mean / worst / first estimate):

| Run | 1.0.0 (backtest) | **1.1.0 live** |
|---|---|---|
| 480p cold (items 79–86) | 16.4% / 27% / none | **4.2% / 11% / +3% at 2 s** |
| 480p warm (items 95–100) | 6.1% / 9% / +5% | **4.1% / 12% / −1% at 2 s** |
| 360p cold (items 87–94) | 10.0% / 14% / none | **6.4% / 25% / +3% at 2 s** (the 25% is the last estimate: 31 s predicted vs 41 s actual) |

1.1.0 was not installed by itself; it shipped inside 1.2.0.

### 1.0.0 — First stable release (2026-11-12)
Version bump and documentation consolidation, covering all work since the first version (0.1.0). Code changes in this release: the `$YtdlVersion` constant, the `-Version` switch, and the version shown in the start banner and help header.

**Summary of 0.1.0 → 1.0.0:**

| Area | What it does now | Introduced in |
|---|---|---|
| **Naming** | Playlist → `<Out>\<Playlist Title>\NNN - <Title> [id].mp4` (original playlist position); single video → `<Out>\YouTube\<Title> [id].mp4` | 0.2.0 |
| **Resume / re-run** | Download archive skips finished videos; `--continue` resumes `.part` files; re-running the same command picks up where it left off | 0.1.0, verified 0.6.0 |
| **Sign-in / bot check** | `-Browser` / `-Cookies`; randomized `-Sleep` pacing | 0.3.0 |
| **Retries** | Up to `-Retries` passes that re-attempt only failed items, with a no-progress stop for permanently dead videos | 0.4.0 |
| **Cookie rotation** | Detected in output. With `-Browser`, yt-dlp is killed at once and restarted with fresh cookies (`-CookieRestarts`); with `-Cookies`, the stale file is dropped. | 0.5.0, 0.8.0 |
| **Stopping / hangs** | `ytdl -Stop` from any terminal; Ctrl+C cleanup; hang watchdog (`-StallMinutes`); error-loop breaker (`-MaxErrors`); `--socket-timeout 30` | 0.6.0 |
| **Shells** | Windows PowerShell 5.1 and PowerShell 7 (watchdog uses a runspace, not `Start-ThreadJob`) | 0.6.1 |
| **ETA** | Up-front scan; per-video model `overhead + size × secPerMiB` with each part measured; first ETA within the first video; `-Estimate`; `-Precise` exact sizes | 0.7.0 → 0.10.0 |
| **Speed** | `-Parallel` workers with a longest-first fixed split: **1.71×/2.17×** (2/3 workers, 360p) and **1.63×/2.21×** (best quality) | 0.9.0 |
| **Evaluated and rejected** | aria2c (35% slower), live partial-progress bandwidth (up to +172% ETA error), shared-queue `-Parallel` (14% slower) | 0.9.0, 0.10.0 |

**Known limitations at 1.0.0:**
- ETA at `-Quality best` with **mixed resolutions and no history** is rough (mean 59%, worst 106% when 4K shorts come first). Use `-Precise` for that case.
- `-StallMinutes` and real-world cookie rotation have not been triggered live. Both use code paths verified in other ways: the kill path is shared with `-Stop`, and the rotation restart was tested with a stand-in yt-dlp.
- `-Parallel` raises the bot-check risk. Use it with `-Browser` and keep it at 2–3 workers.
- `ytdl.cmd` needs pwsh 7. `ytdl.ps1` works in both shells.

**1.0.0 verification:** parses cleanly in PS 5.1 and 7; `-Version` prints `ytdl 1.0.0` via both `ytdl.ps1` (5.1) and `ytdl.cmd` (7); `-Estimate` smoke test exits 0. The download paths are unchanged from the 0.10.0 release regression (single run, `-Parallel 2`, `-Estimate`: all pass).

---

*Detailed history, newest first. Releases 0.1.0–0.10.0 were made on 2026-11-11.*

### 0.10.0 — Component ETA model; shared-queue `-Parallel` evaluated and rejected
**ETA model rewritten.** It is no longer one regression `wall = a·x + b` (0.7.1). Each video is now modeled as
```
wall = overhead + size_MiB × secPerMiB
```
with each part measured directly:
- **overhead:** per finished video, wall time minus its exact transfer time. Shrunk toward the prior `1.5×Sleep + 15 s` (weight = 1 video). Saved under `ov-s<Sleep>-p<workers>`, history capped at 5 videos.
- **secPerMiB (bandwidth):** from **completed** streams only. The "100% of X in hh:mm:ss at Y/s" line is used, preferring `X / Y` because whole seconds round down: e.g. a 2.61 MiB file logged "in 00:00:00" actually took 0.43 s. This run's transfers are blended with history capped at 150 MiB. Saved under `bw-s<Sleep>-p<workers>`.
- **size_MiB:** exact with `-Precise`; otherwise runtime × bitrate. Bitrate (MiB per video-second) is learned per quality under `br-q<Quality>`/`br-audio`, shrunk toward a per-quality prior (360p 0.03 … 2160p 0.6, best 0.15) with a weight of 1200 video-seconds, history capped at 2 h. Bitrate belongs to the videos, not the network, so it carries over between runs much better than bandwidth.
- The video in progress counts as `max(0, estimate − elapsed)`. The ETA line now also shows the remaining size (MB/GB), prints as soon as the first stream completes ("speed measured: X MiB/s"), and refreshes every 2 min during long downloads.
- Old saved keys (`q360`, `size`, … with `N/Sx/Sxx`) are ignored.

**Rejected variant:** bandwidth measured *live* from partial progress lines, to get an estimate within seconds. Those lines read ~2× too slow (3.2–4.6 MiB/s against 6.7 MiB/s from completed transfers in the same runs), because each download ramps up at the start. That pushed estimates up to **+172%**, so only completed transfers are used.

**Results** (Windows PowerShell 5.1, live downloads; mean / worst error):

| Scenario | 0.7.1 (old) | partial-live variant (rejected) | **0.10.0** |
|---|---|---|---|
| E: best, cold, 4K shorts first | 131% / 262%, no ETA until video 1 done | 23% / 86% | **59% / 106%**, first ETA at 48 s (+27%) |
| F: best, warm | 19% / 34%, first ETA +34% | 63% / 172% | **23% / 34%**, first ETA +20% |
| G: 360p, cold | 6% / 14% | 16% / 26% | **4% / 8%**, all estimates within 8% |

The remaining weak spot is best quality with mixed resolutions and little history (E). Short 4K clips raise the learned bitrate, which then overestimates long 1080p videos. `-Precise` (exact sizes) is the fix for that case.

**Shared-queue `-Parallel` built, benchmarked, rejected.** Instead of a fixed split, the coordinator handed out one video at a time to whichever of N slots was free. Each video was a short-lived worker (`-Items <one> -NoScan -Retries 0`), failures were re-queued, and the coordinator computed one overall ETA. Alternating runs, `-Parallel 3`, best quality, items 2,4,6,8,23,26,27,29 (4K shorts + long 1080p):

| Method | Runs | Average |
|---|---|---|
| Fixed split (0.9.0) | 139 s, 129 s | **134 s** |
| Shared queue | 150 s, 156 s | 153 s (**~14% slower**) |

Starting a new process per video (PowerShell, cookie extraction, playlist page) cost more than the better tail balancing saved. Its overall ETA also underestimated toward the end (down to −65%). **The fixed split stays.** If revisited, long-lived workers that pull several videos per claim would avoid most of the per-video start-up cost. (The `-NoScan` switch from this experiment remains as an internal option.)

**Install:** release candidate = 0.10.0 ETA + 0.9.0 coordinator, with the `-Precise` rule restored (each worker probes its own share). Small totals now show as MB instead of `0.00 GB`. Regression: single run, `-Parallel 2` and `-Estimate` all exit 0, with correct numbering and archive and no leftovers. Previous version kept as `ytdl.ps1.bak-0.9.0`.

### 0.9.0 — `-Parallel`; aria2c evaluated and rejected
**Where the time goes** (from the ETA tests): each video has a fixed cost of ~25 s (randomized sleep, `--sleep-requests` page loads, merge, embed), while transfer was ~0.3 s per minute of video at 360p and ~9 s per 100 MiB at best quality. For short or low-resolution videos, the waiting is ~90% of the time, so overlapping videos is the biggest lever.

**Added `-Parallel <1-8>`** (default 1 = old behaviour):
- **Coordinator:** after the flat scan (which now also prints `%(playlist_index)s`), it assigns pending playlist positions to *n* workers, longest-first onto the least-loaded worker. Each worker's positions are compressed into an `-Items` string such as `41-43,47`.
- **Workers:** each is a separate `powershell`/`pwsh` process running `ytdl.ps1 <url> <same options> -Items <share> -Worker k -WorkerCount n`. A worker is a complete ytdl run, so it keeps retries, cookie restarts, the hang watchdog and the error-loop breaker. Because workers download from the playlist URL (not bare video URLs), the playlist folder and `NNN -` numbering stay correct.
- Worker starts are **staggered 3 s** apart to avoid a burst of requests.
- **Output:** workers write to `%TEMP%\ytdl-<pid>-wK.log` (+ `.err`). The coordinator tails these every 300 ms (keeping partial lines buffered), prints each line prefixed `[wK]` with colouring, and prints an **overall line** `[ytdl] ALL: D of T done | ETA ~…`, where the finish time is the latest of the workers' own ETAs. Workers force UTF-8 (`[Console]::OutputEncoding`, `PYTHONIOENCODING=utf-8`) so titles survive the log files.
- **Stopping:** `ytdl -Stop` reaches every worker through the shared stop file. Workers don't delete the stop file (the first one to exit could otherwise hide the signal from the others); the coordinator clears it at start and end. On exit, Ctrl+C or error, the coordinator's `finally` kills any surviving worker trees (`taskkill /T /F`) and deletes the worker logs.
- **Exit code:** 2 if any worker was stopped, otherwise 1 if any worker had errors, otherwise 0.
- **Bot-check risk** grows with *n*. Use with `-Browser`, and keep *n* modest (2–3).

**aria2c tested and rejected.** The same 482 MiB best-quality video (539.6 MiB merged) was downloaded twice each way, alternating, calling yt-dlp directly with sleeps off:

| Downloader | Round 1 | Round 2 | Average |
|---|---|---|---|
| yt-dlp native | 106.7 s (5.06 MiB/s) | 88.0 s (6.13 MiB/s) | **97.3 s (5.59 MiB/s)** |
| aria2c `-x 16 -s 16 -k 1M` | 163.7 s (3.30 MiB/s) | 136.0 s (3.97 MiB/s) | 149.8 s (3.63 MiB/s) |

aria2c was **~35% slower** in both rounds, with no errors either way. YouTube appears to throttle many connections *within one file*. aria2 was uninstalled.

**Benchmarks** (Windows PowerShell 5.1, `-Browser firefox`, default `-Sleep 5`, fresh folder per run):

| Set | `-Parallel 1` | `-Parallel 2` | `-Parallel 3` |
|---|---|---|---|
| 9 videos, 6.2 h, 360p (items 41–49) | 334 s | 195 s (**1.71×**) | 154 s (**2.17×**) |
| 6 videos, 1078 MiB, best (items 37,40,42,48,49,50; P1 run first and last, −9% drift, averaged) | 300 s | 184 s (**1.63×**) | 136 s (**2.21×**) |

- At best quality, a single download stays at ~3.4–3.8 MiB/s, while three together reach 7.9 MiB/s. YouTube seems to cap throughput **per download**, so separate downloads add up (unlike aria2c's connections within one file).
- Every run: all files present, `NNN` numbering correct, archive lines = unique IDs, 0 errors, no leftover processes.
- **`ytdl -Stop` with 3 workers** (6 yt-dlp processes running): all stopped in 4 s, nothing left behind.

**Bug found and fixed:** The coordinator reported `exit codes: , , `, so successful runs returned 1 and a stopped run 1 instead of 2. Cause: in Windows PowerShell, a `Start-Process -PassThru` object loses `ExitCode` unless `.Handle` is read while the process is alive. Fix: read `$p.Handle` right after each start. Re-verified: 0 on success, 2 on stop.

### 0.8.0 — Instant restart on rotated cookies
**Problem:** `WARNING: [youtube] The provided YouTube account cookies are no longer valid…` is only a warning, so yt-dlp kept going signed-out and skipped videos until the pass ended.

**Changed (with `-Browser`):** when that warning appears, ytdl immediately kills the yt-dlp process tree (the same effect as Ctrl+C; `.part` files are kept), waits **5 s**, and restarts the identical command. The new process re-reads the browser's cookies, and `--continue` resumes partial downloads. **`-CookieRestarts <n>`** (default 10, `0` = off) caps this. Restarts don't use up `-Retries` and skip the no-progress stop; at the cap, ytdl exits 2 and suggests closing YouTube tabs in that browser. `-Stop` during the wait is honoured. With `-Cookies <file>`, 0.5.0's behaviour applies, since a file can't be refreshed.

**Verified** with a stand-in `yt-dlp.exe` that prints the exact warning and hangs 60 s, with `-CookieRestarts 2`: 3 invocations ~5.1 s apart (each kill under 0.2 s), then "Cookie restart limit (2) reached", exit 2, no leftovers. Not verified against a real YouTube rotation, which can't be triggered on demand.

### 0.7.2 — `-Precise` size probe (best-quality ETA testing)
**Test at `-Quality best` (0.7.1 model):** cold start with 4K shorts first: mean **131%**, worst **262%**; warm: 19% / 34%.

**Cause:** At best quality, size per minute depends on resolution: the 4K shorts (format 401) ran **29–44 MiB/min**, the 1080p streams (format 399) **6–10 MiB/min**. No runtime-only model can predict that. A backtest of OLS, runtime-weighted WLS and pooled-with-prior all gave the same 102% mean.

**Added `-Precise`:** before downloading, each pending video is probed at the download's format (`-f <fmt> --print "%(id)s %(filesize,filesize_approx)s"`, batch file, `--sleep-requests 1`). Probed sizes were **exact** (0.0% difference on 14 videos) but cost **~9 s per video** and double the page requests, so it's opt-in. Result: cold best-quality ETA **23% / 31%**; warm unchanged at 19% / 34%. The remaining error was bandwidth drift between runs (6.7 vs 4.2 MiB/s), which 0.10.0 addressed.

### 0.7.1 — Two-part ETA after accuracy testing
**Finding:** timestamped logs of 8 mixed-length videos (30 s – 2 h 05 m) at 360p showed every video costs a roughly **fixed ~25 s** regardless of length (sleeps, requests, merge, embed), with transfer only ~0.005 s per second of video. The 0.7.0 ratio model therefore swung from **−92% to +141%** (mean 56%).

**Fix:** least-squares `time = a × runtime + b` over finished videos (clamps `a,b ≥ 0`; prior `b = 1.5×Sleep + 15`). Sums were saved per quality, with history capped at 5 videos. Backtest: mean 56% → **9%**, worst 141% → **21%**. Live: cold **6% / 14%**, warm **11% / 17%** (first warm estimate within 3%). Superseded by 0.10.0.

### 0.7.0 — Remaining-time estimate
- **Up-front scan:** one `--flat-playlist` call lists each item's ID and runtime without loading every page. It respects `-Items` and the cookie options, and archived items are excluded.
- **ETA line** at start and after each completed video: `[ytdl] 12 of 150 done | 138 left (41h 20m of video) | ETA ~3h 05m (finish ~Wed 9:42 PM)`.
- **Model (superseded):** wall seconds per video-second × runtime left, saved per quality in `.ytdl-rate.json`. A video counts as done only once its ID is in the archive.
- **`-Estimate`** prints the line and exits. If the scan fails, ytdl says so and downloads without an ETA.

### 0.6.1 — Windows PowerShell 5.1 compatibility
**Bug:** `The term 'Start-ThreadJob' is not recognized…`. In a 5.1 window, `ytdl` resolves to `ytdl.ps1` directly (PowerShell prefers `.ps1` over the `.cmd` shim), and `Start-ThreadJob` exists only in pwsh 7. Earlier tests all went through `ytdl.cmd`, so they missed it. **Fix:** the watchdog runs in a background runspace (`[powershell]::Create()` + `BeginInvoke()`). **Verified in 5.1:** normal download, error loop, and `-Stop` mid-download (24.7%, 2.4 s, exit 2, no leftovers).

### 0.6.0 — Stop controls, hang watchdog, error-loop breaker
- **`ytdl -Stop`** creates `%TEMP%\ytdl.stop`. Every running ytdl sees it within ~2 s, kills its yt-dlp tree, skips retries, and exits 2. `-Url` became optional so `-Stop` works on its own.
- **`-StallMinutes`** (10): no output for that long kills the pass as hung (a transient failure).
- **`-MaxErrors`** (10): that many `ERROR` lines in a row without a success marker kills the pass. Auth errors fall through to the cookie retry; anything else stops the run (exit 2).
- `--socket-timeout 30`; retry waits check for the stop signal every second; `try/finally` cleanup also runs on Ctrl+C.
- **Verified:** error-loop stop; `-Stop` during a retry wait; `-Stop` mid-download (482 MiB stopped at 24.2% in 0.7 s, `.part` kept); **resume** (`Resuming download at byte 124519656`). `-StallMinutes` was not triggered live (same kill path as `-Stop`).

### 0.5.0 — Recover from rotated/expired cookies
- yt-dlp output is piped through the script (`2>&1 | ForEach-Object`) so every line can be scanned while still echoed live (errors red, warnings yellow). `--progress-delta 5` keeps piped progress readable.
- **Auth detection:** `cookies are no longer valid | Sign in to confirm | not a bot | cookies…invalid/expired`. Next pass: `-Browser` re-reads cookies; `-Cookies` drops the stale file once; neither suggests `-Browser firefox`. The wait is capped at 15 s, and the no-progress stop is skipped for auth failures.

### 0.4.0 — Auto-retry passes
`-Retries` (3) and `-RetryDelay` (60 s): a pass with a non-zero exit runs again, and the archive limits it to failed items. **No-progress stop:** a *retry* pass that adds nothing to the archive ends retries (permanently dead videos). **Verified** on an invalid ID: 1 retry, then stop, exit 1.

### 0.3.0 — Bot-check workaround
`-Browser` → `--cookies-from-browser`; `-Cookies` → `--cookies` (checked up front); `-Sleep` (5) → `--sleep-interval N --max-sleep-interval 2N --sleep-requests 1`. Later verified: `-Browser firefox` gets past an IP-level bot flag.

### 0.2.0 — Playlist folder/numbering fix
**Bug:** playlist videos were saved as `YouTube\<title> [id].mp4`. **Cause:** yt-dlp's `-o "playlist:…"` prefix names playlist *metadata* files, not the videos. **Fix:** a single conditional template, `<dir>/%(playlist_index&{:03d} - |)s%(title)s [%(id)s].%(ext)s` with `dir = %(playlist_title|YouTube)s` (or `-Folder`). **Verified** for a 1-item playlist, a single video, and 3 items with a re-run skip.

### 0.1.1 — Bootstrap fixes
`$args` (a PowerShell automatic variable) renamed to `$ytArgs`, including the `@args` splat. Dependency lookup moved from winget's (missing) `Links` folder to a recursive search of `WinGet\Packages` for yt-dlp, ffmpeg and deno, prepending their folders to the process PATH.

### 0.1.0 — Initial version
Python wasn't installed, so ytdl was written in PowerShell. yt-dlp, FFmpeg and Deno were installed via winget. `ytdl.ps1` + `ytdl.cmd` with `-Url`, `-Out`, `-Folder`, `-Quality`, `-AudioOnly`, `-Subs`, `-Items`.

---

## Logic Notes (as of 1.0.0)

### Flow
1. **Parse parameters.** `-Version` prints and exits. `-Stop` creates `%TEMP%\ytdl.stop` and exits. Otherwise `<Url>` is required.
2. **Role.** `-Parallel > 1` without `-Worker` makes this process the **coordinator**. `-Worker k` marks a worker, which switches its console and yt-dlp output to UTF-8 because the coordinator reads it from a file.
3. **Dependencies.** For yt-dlp, ffmpeg and deno: if `Get-Command` can't find one, search `%LOCALAPPDATA%\Microsoft\WinGet\Packages` and prepend its folder to this process's PATH (this covers "installed, shell not restarted"). Fail fast if yt-dlp is still missing.
4. **Build the yt-dlp arguments:** naming template, base flags, format, subtitles, `-Items`, cookies (`$authArgs`), sleep pacing, then the URL.
5. **Scan** (skipped with `-NoScan`): one `--flat-playlist --print "%(id)s %(duration)s %(playlist_index)s"` request → queue of id → runtime, plus id → playlist position. Archived IDs are removed to give the pending set. With `-Precise` (not on the coordinator), the pending videos are probed for exact sizes. The first ETA line is printed.
6. **`-Estimate`** exits here.
7. **Coordinator** (when `-Parallel > 1` and ≥ 2 pending playlist videos): split, launch workers, tail their logs, exit. See *Parallel*.
8. **Single run:** start the watchdog runspace, clear any stale stop file (non-workers only), then run **passes**:
   - Each pass runs `yt-dlp | ForEach-Object` and handles every line: echo it with colour, update the watchdog timestamp, do ETA bookkeeping, detect auth problems, kill on cookie rotation, and count consecutive errors.
   - After a pass: success ends the loop. A cookie-rotation kill means a 5 s wait, then a restart that doesn't count as a pass. Stop / stall / error loop follow their rules. Auth failures retry after ≤ 15 s. Other failures retry after `-RetryDelay` unless a retry pass made no progress.
9. **Cleanup** (`finally`, also on Ctrl+C): save ETA measurements, kill any leftover yt-dlp, stop the watchdog, remove the stop file (non-workers only). The exit code is reported.

### Output naming
```
<Out>\<dir>\<NNN - ><title> [<id>].<ext>
dir  = %(playlist_title|YouTube)s      (or -Folder)
NNN  = %(playlist_index&{:03d} - |)s   (only when there's a playlist)
```
- `NNN` is the **original** playlist position, so `-Items "5-7"` gives `005`–`007` and numbering is stable across partial runs and parallel workers.
- `[id]` keeps names unique and traceable. `--windows-filenames` swaps forbidden characters for full-width lookalikes (`:` → `：`); emoji are kept.

### yt-dlp flags and why
| Flag | Reason |
|---|---|
| `--paths <Out>`, `-o <template>` | Naming above |
| `--yes-playlist` | A `watch?v=…&list=…` URL downloads the playlist |
| `--ignore-errors` | Skip dead items instead of aborting the playlist |
| `--download-archive <Out>\.ytdl-archive.txt` | Skip finished videos on re-runs. **One archive per `-Out`**, shared by every playlist there. |
| `--no-overwrites`, `--continue` | Never clobber; resume `.part` files |
| `--embed-metadata`, `--embed-thumbnail` | Title, uploader, date and cover art inside the file |
| `--progress --progress-delta 5` | Readable progress through the pipe (one line per 5 s) |
| `--socket-timeout 30` | A dead connection errors out instead of hanging |
| `--retries 10`, `--fragment-retries 10` | Flaky-network resilience inside yt-dlp |
| `--abort-on-unavailable-fragments` | A video with permanently missing fragments fails (and is retried) instead of being saved with gaps (1.2.0) |
| `-S res,proto` | At the same resolution, prefer plain https over fragmented HLS/DASH, which is where fragment 404s happen (1.2.0) |
| `--sleep-interval S --max-sleep-interval 2S --sleep-requests 1` | Pacing to avoid the bot check (`-Sleep 0` turns it off) |
| `--cookies-from-browser` / `--cookies` | Signed-in session |

**Format:** video `bv*+ba/b` (or capped by `[height<=N]`), merged to **mp4**. `-AudioOnly`: `bestaudio/best` → mp3 at VBR 0. `-Subs`: `en.*` manual + auto, embedded.

### Retries, auth and cookie rotation
- **Pass loop:** up to `1 + -Retries` passes; the archive limits every retry to failed items.
- **No-progress stop:** a *retry* pass that adds nothing to the archive ends retries (dead videos). It doesn't apply to auth failures or hangs.
- **Auth failure** (any auth pattern in a pass): with `-Browser`, the next pass re-reads cookies; with `-Cookies`, the stale file is dropped once; otherwise a hint is printed. The wait is `min(RetryDelay, 15)` s.
- **Cookie rotation, live** (with `-Browser`): the "cookies are no longer valid" line triggers an immediate kill, a 5 s wait and a restart, up to `-CookieRestarts` times. These restarts don't count as passes.
- **Fragment 404 loop** (1.2.0): the 3rd "HTTP Error 404 … fragment" line *for the same video* triggers a kill, a 5 s wait and a restart (fresh stream URLs; `.part` resumed), up to `-FragmentRestarts` times. These restarts don't count as passes either. Past the cap, yt-dlp's own retries and `--abort-on-unavailable-fragments` decide, and a failed video falls into the normal retry passes.

### Stop, watchdog, error loop
- The main thread is blocked reading yt-dlp's output, so a **watchdog runspace** (same process, shared synchronized hashtable `Last/Running/Done/Abort`) checks every 2 s for the stop file (`Abort = 'stop'`) and for silence longer than `-StallMinutes` (`'stall'`).
- **Kill path:** find child processes of this PowerShell process named `yt-dlp*` and run `taskkill /T /F` on them (the yt-dlp exe has its own child). The pipeline then ends and the loop reads `Abort`.
- **Error loop:** `-MaxErrors` consecutive `ERROR` lines, with no `[Merger]/[ExtractAudio]/[EmbedThumbnail]/[Metadata]` or "already recorded" in between, set `'errorloop'`. With auth errors this falls through to the auth retry; otherwise the run stops (exit 2).
- Retry and restart waits sleep in 1 s steps and check the stop file.

### ETA model
```
per video:  wall = overhead + size_MiB × secPerMiB
ETA = Σ over pending videos (in-progress video: minus elapsed) / workers-on-this-estimate
```

| Part | Measured from | Prior / fallback | Saved key (history cap) |
|---|---|---|---|
| overhead | wall time − exact transfer time, per finished video; **each run's first video is excluded once a second one finishes** (start-up cost) | `3·S + n·R + 4` s for the current pacing (S = pause before each stream, paid twice per merged video; R = pause per request; n = 4 requests with the fast client, 6 without): 6.0 s at L0, 25 s at `-Sleep 5`; weight 1 video (1.4.1) | `ov-s<S>-p<workers>` (5 videos); reset to the new level's history when auto pacing changes level |
| secPerMiB | 1.4.2: each completed stream ≥10 MiB is one draw, counted equally (this run plus the folder's last 10), shrunk toward the learned typical speed (median of the last 50 stream speeds across all runs, default 7.7 MiB/s) worth 4 streams; the in-progress video uses its own bytes left and current speed | **≤480p / audio:** 5 MiB/s guess, tagged `rough` · **above 480p:** none, the ETA waits for the first completed stream | `bw-s<Sleep>-p<workers>` (150 MiB) |
| size_MiB | `-Precise` probe (exact), else runtime × bitrate | bitrate prior per quality (360p 0.025, 480p 0.03, 720p 0.055, 1080p 0.08, 1440p 0.3, 2160p 0.6, best 0.15, audio 0.016 MiB/s), weight 1200 video-s; above 480p, exact sizes from the background probe replace this as they arrive | `br-q<Quality>` / `br-audio` (2 h) |

- **When it prints:** at start (≤480p/audio always, tagged `rough` without saved bandwidth; higher qualities only if saved bandwidth exists), when the first stream completes ("speed measured"), after each finished video, and every 2 min during long downloads.
- **Done detection:** a new video's `Downloading webpage` line closes the previous video, which counts only if its ID is now in the archive.
- **Why this shape:** bandwidth drifts between runs (up to ~1.6×) and must come from *this* run's **completed** transfers; partial progress reads ~2× slow during ramp-up. Bitrate is a property of the videos and transfers between runs. Overhead is roughly constant (~25 s at `-Sleep 5`).
- **Accuracy:** 1.1.0 live at 480p cold 4.2% / 11%, 480p warm 4.1% / 12%, 360p cold 6.4% / 25%, with first estimates within ±3% at 2 s. 0.10.0 at best quality: warm 23% / 34%; cold with 4K shorts first 59% / 106% (use `-Precise`, 23% / 31%).

### Parallel (`-Parallel n`)
- **Split:** pending playlist positions are assigned longest-first to the least-loaded of *n* workers. Load = `secPerMiB × size + overhead` from the model, with a fallback of `0.2 s/MiB` when no speed is known yet. Positions are compressed to an `-Items` range string.
- **Workers:** `powershell`/`pwsh` (whichever host is running) + `ytdl.ps1 <url> <same options> -Items <share> -Worker k -WorkerCount n`, started 3 s apart with stdout/stderr redirected to `%TEMP%` logs. Each worker is a full ytdl run with its own scan, ETA, retries, cookie restarts, watchdog and error loop. Under `-Precise`, each worker probes only its own share.
- **Coordinator:** tails the logs every 300 ms, prefixes lines `[wK]`, and prints `[ytdl] ALL: D of T done | ETA` using the latest worker finish time. It reads `$p.Handle` at start so `ExitCode` survives. Exit code is 2 if any worker returned 2, else 1 if any was non-zero, else 0. Its `finally` kills worker trees, deletes logs and clears the stop file.
- **ETA keys** include the worker count (`-p<n>`), because per-download speed under contention differs from a single run. The coordinator's own first estimate divides by *n*.
- **Measured:** 1.71×/2.17× at 360p and 1.63×/2.21× at best quality for 2/3 workers. YouTube appears to cap speed per download, so separate downloads add up. A shared-queue design was 14% slower (per-video process start-up) and was not adopted.

### Pacing, background probe, lock, log, disk (1.2.1–1.3.0)
- **Startup order:** parameters → `-Version`/`-Stop` → UTF-8 → tools (cache, then WinGet search) → yt-dlp age check (daily) → output folder → **folder lock + run log** (not for workers or `-Estimate`; exit 3 if locked) → yt-dlp args → **pacing level** (auto: L0 signed-in / L2 otherwise, raised to the saved level if a bot check was <24 h ago) → scan + ETA → **disk pre-check** → `-Estimate` exit → coordinator or single run → watchdog + **background probe** → passes.
- **Pacing args are added per pass** (`$passArgs + Get-PaceArgs`), so a restart after a level change picks up the new pauses. Bot-check detection is only active in auto mode and below the top level; at L4, the existing auth handling (retry passes) applies.
- **Watchdog duties** every 2 s: global and per-folder stop files, stall timer; every 20 s free disk space; every 10 s (auto pacing) the shared pace file.
- **Background probe:** one yt-dlp at a time in a runspace, writing exact MiB into a synchronized `$eta.Size` table that `Get-X` reads. Its yt-dlp processes are children of the ytdl process, so every kill path (stop, stall, cookie/fragment/pace restarts) also ends a probe in progress. It's stopped and disposed in the `finally`, and the run log records found/failed counts.
- **Lock** is an `[IO.File]::Open(…, 'None')` handle released by `Release-Lock` on every exit path. A crash releases it at the OS level; the lock file left behind is harmless, since the next run reopens it.
- **Run log** is written by the `Write-Host` wrapper, so every message is captured without per-message code. Lines hidden from the console (the DRM notice) are written with `Write-LogOnly`.

### Known limitations / gotchas
- **Bot check:** YouTube may require sign-in after heavy use. Use `-Browser firefox` (readable while Firefox runs). Chromium-based browsers on Windows encrypt cookies per app and usually must be **fully closed** for `--cookies-from-browser`, and may still fail.
- **Cookie rotation:** browsing YouTube in the same browser during a run rotates the session. ytdl recovers (0.8.0), but closing YouTube tabs is smoother. For a cookies file that won't rotate: open a **private window**, sign in, open `https://www.youtube.com/robots.txt`, export youtube.com cookies, then **close the window without signing out**.
- **Shared archive:** a video already downloaded under the same `-Out` is skipped even when it appears in another playlist.
- **ETA at best quality** with mixed resolutions and no history is rough; use `-Precise`.
- **`-Parallel`** increases request rate (bot-check risk); keep it at 2–3 with `-Browser`.
- **Shells:** `ytdl.ps1` must stay 5.1-compatible (no `Start-ThreadJob`, `??`, `?.`, ternaries) and **ASCII-only** (5.1 reads BOM-less scripts as ANSI). `ytdl.cmd` needs pwsh 7. Under 5.1, titles with emoji may display garbled in the console; filenames are fine.
- **Maintenance:** YouTube changes often. When downloads start failing, first run `winget upgrade yt-dlp.yt-dlp`.
- **`ytdl -Stop` with nothing running** leaves `%TEMP%\ytdl.stop`; the next run clears it.

### Test history
| Date | Test | Result |
|---|---|---|
| 11-11 | Single video, 360p | Pass |
| 11-11 | 1-item playlist | **Fail** (no folder/index) → fixed 0.2.0 → Pass |
| 11-11 | Re-run same playlist; 3-item playlist + re-run | Pass (archive skip) |
| 11-11 | Auto-retry on invalid video | Pass (1 retry, no-progress stop, exit 1) |
| 11-11 | Normal download via piped output (0.5.0) | Pass |
| 11-11 | `-MaxErrors 1` error loop | Pass (exit 2) |
| 11-11 | `-Stop` during retry wait / mid-download / resume after stop | Pass / Pass (24%, 0.7 s) / Pass (byte 124519656) |
| 11-11 | `-Browser firefox` past an IP bot-flag | Pass |
| 11-11 | `-StallMinutes`; real cookie rotation | Not triggered live (shared/stand-in paths verified) |
| 11-11 | Windows PowerShell 5.1: download / error loop / `-Stop` (0.6.1) | Pass ×3 |
| 11-11 | ETA 0.7.0 ratio model (8 mixed videos) | **Fail**: 56% / 141% → 0.7.1 |
| 11-11 | ETA 0.7.1, 360p cold / warm | Pass: 6% / 14%, 11% / 17% |
| 11-11 | ETA 0.7.1 at best, cold (4K first) / warm | **Fail** 131% / 262%; 19% / 34% |
| 11-11 | `-Precise` probe accuracy; best cold / warm | Exact sizes (~9 s/video); 23% / 31%; 19% / 34% |
| 11-11 | Cookie-rotation kill + restart (stand-in yt-dlp) | Pass: 2 restarts, limit, exit 2 |
| 11-11 | aria2c vs native (482 MiB ×2 each) | **Rejected**: 3.63 vs 5.59 MiB/s |
| 11-11 | `-Parallel` 1/2/3, 360p (9 videos) | Pass: 334 / 195 / 154 s |
| 11-11 | `-Parallel` 1/2/3/1, best (6 videos) | Pass: 300 / 184 / 136 s |
| 11-11 | `-Stop` with 3 workers | Pass: 4 s, no leftovers |
| 11-11 | `-Parallel` exit codes | **Fail** (blank) → `.Handle` fix → Pass |
| 11-11 | ETA with partial-progress bandwidth | **Rejected**: up to 172% |
| 11-11 | ETA 0.10.0: best cold / best warm / 360p cold | 59% / 106% · 23% / 34% · **4% / 8%** |
| 11-11 | Shared-queue `-Parallel 3` vs fixed split ×2 | **Rejected**: 153 vs 134 s |
| 11-11 | 0.10.0 regression: single, `-Parallel 2`, `-Estimate` | Pass |
| 11-12 | 1.0.0: parse (5.1 + 7), `-Version` (both shells), `-Estimate` | Pass |
| 11-12 | Low-res ETA backtest: 1.0.0 + 12 variants on 480p cold/warm and 360p cold logs | 1.0.0 11.0% overall → chosen variant **7.6%** |
| 11-12 | 1.1.0 live: 480p cold / 480p warm / 360p cold | **4.2% / 11% · 4.1% / 12% · 6.4% / 25%**; first ETA ±3% at 2 s |
| 11-12 | yt-dlp update check; format protocols picked on the test video | 2026.10.26 still latest; https at best/480/360 (with and without `-S res,proto`) |
| 11-12 | Fragment-404 restart (stand-in yt-dlp, `-FragmentRestarts 2`) | Pass: 2 restarts, then left to finish, exit 0, no leftovers |
| 11-12 | 1.2.0 regression: single 360p, `-Parallel 2` 480p, `-Estimate` best/480p | Pass |
| 11-12 | Real fragment-404 event | Not triggered live (can't be produced on demand) |
| 11-12 | 720p/1080p ETA (1.2.0): 720 cold / 720 warm / 1080 warm | 11.9% / 35% · 50% / 95% (bandwidth swing) · 10.4% / 28% |
| 11-12 | 1080p cold (1.2.0) | **Invalid**: stopped mid-run by an offline test's global `-Stop` → per-folder stop added |
| 11-12 | 1.2.1 offline: DRM hide, lock, disk pre/in-run, UTF-8 restore, tool cache, launcher fallback, `-Stop -Out` | Pass |
| 11-12 | 1.2.1 live: 720 cold / 1080 cold / 1080 warm | 14.9% / 43% · 35.4% / 53% · **9.0% / 13%** |
| 11-12 | 1.2.1 live `-Parallel 2` | **Fail** (call-depth overflow: self-calling `Test-StopRequested`) → fixed → Pass |
| 11-12 | Metadata remux cost (S4) | 2.5–4 s/GB → not changed |
| 11-12 | 1.3.0 offline: pacing levels, back-off, pace memory, pace sync, probe, age check, `-Dynamic`, stop during `-Dynamic` | Pass |
| 11-12 | Adaptive vs fixed pacing, 360p ×2 each | **Auto 98 s vs 219 s (55% faster)**, 0 bot checks |
| 11-12 | Background probe ETA, best cold ×2 each (after removing the probe gap) | **9.8% / 24% vs 18.0% / 50%** |
| 11-12 | `-Dynamic` vs fixed split, `-Parallel 3` best | 145 s vs 152 s (within noise) → opt-in only |
| 11-12 | 1.3.0 install: version (both shells), live `-Estimate` | Pass |
| 11-12 | Client survey: 7 configurations × 5 videos × 4 qualities (lookups only) | Only `skip=hls` and `web_embedded` keep identical formats; `web_embedded` + `skip=hls`: 20/20, 4 requests, 5.8 s |
| 11-12 | 1.4.0 offline: L0 args, fast-client fallback and memory, age message, `-NoFastClient` | Pass |
| 11-12 | 1.4.0 vs 1.3.0 live, 360p ×2 and `-Parallel 3` | **77–83 s vs 102–186 s; 55 s vs 93 s**; formats identical; 0 bot checks |
| 11-12 | 1.4.0 best quality on 4K clips | Pass: 401+251, same as default |
| 11-12 | 1.4.0 ETA recordings: 360 / 480 / 720 / 1080 / best, cold (live scores) | 23.2% · 24.7% · 6.9% · 15.5% · 22.6% mean |
| 11-12 | ETA replay, 9 variants, cold + chained | 1.4.0 15.2% / 19.0% → chosen 12.9% / 17.3%; recency-weighted bandwidth rejected |
| 11-12 | 1.4.1 live: 360 / 480 cold, 480 with history, 720 cold | 19.2% · 24.2% (first −3%) · 16.9% · 61.1% (bandwidth 2–16 MiB/s within the run) |
| 11-12 | 1.4.1 vs 1.4.0 replay on the 30 new videos | 29.4% / 23.3% vs 32.7% / 24.0%; worst cases 32/48/116% vs 74/63/128% |
| 11-12 | 1.4.1 `-Parallel 2` regression | Pass |
| 11-12 | Bandwidth-swing recordings: 6 runs at 720/1080/best, every-30-s replay, 10+ variants | 1.4.1 36.1% / 190% → chosen 24.0% / 130%; first-video exclusion rejected (no pattern) |
| 11-12 | 1.4.2 out-of-sample replay (3 runs) | 27.4% (1.4.1) vs 28.6% (default prior) / **22.8% (learned prior)** |
| 11-12 | 1.4.2 live: 720 / 1080 / best / 360 / 480 cold | 15.1% · 26.9% · 16.5% · **12.2%** · 18.9% |
| 11-12 | 1.4.2 `-Parallel 2` regression | Pass |
| 11-12 | 360p speed: base / no pauses / `-Parallel 2·3·4`, alternating | 94 s → 68 s / 60·63·50 s; 0 bot checks |
| 11-12 | 1.5.0 offline: auto-parallel, no-pause L0, `-NoMetadata`, `-Fast360`, pace-file mapping | Pass |
| 11-12 | `-Fast360` vs normal 360p (280 s clip) | 18.0 s / 17.4 MB (H.264) vs 21.3 s / 9.8 MB (AV1); similar picture → compatibility option only |
| 11-12 | 1.5.0 vs 1.4.2, 30 videos at 360p | **140 s vs 455 s (3.2×)**, 0 bot checks, 0 errors |
| 11-12 | Real-world 1.5.0 run, 234 videos "best" (= 480p/360p) | 53 min, 0 errors/bot checks, 3 cookie rotations recovered; ETA 9.0% overall, 20.0% first 10 min |
| 11-12 | 1.6.0 offline: resolution check, worker probe suppression, probe batching, `-NoThumbnail`, log timestamps | Pass |
| 11-12 | 1.6.0 first-10-min ETA replay on the real run | 20.0% → **7.4%** |
| 11-12 | 1.6.0 live: detection on the real playlist (`-Estimate`), Blender negative case, 480p parallel and best downloads | Pass |
| 11-12 | Real-world 1.6.0 run, 251 videos "best" (= 480p), auto-detected 3 workers | 28.7 min (6.9 s/video), 0 errors; ETA 6.2% overall, first minute −61% |
| 11-12 | 1.6.1 vs 1.6.0, same 12 videos at 480p, 3 workers | first overall ETA **+1% vs −45%**, mean 8.8% vs 33.9% |
| 11-13 | yt-dlp download methods, one 141.9 MiB 1080p video stream (signed out, directory build) | Default 10 MiB pieces one at a time: 10.1 MiB/s average (8.3–12.2, 5 runs, 17.1 s each). **50 MiB pieces: YouTube throttles the request to ~100 KiB/s** (stalled 17 min; 150 MiB would be the same). 5 MiB pieces: 8.9 MiB/s (2 runs). **Parallel fragments** (`formats=dashy` + `-N 3`): 15.8 MiB/s (11.9–19.5, 12.2 s), 4 of 5 completed, one failed on HTTP 403 for every fragment. `-N 6`: 14.6 MiB/s (10.4–20.8), 5 of 5. See the 2026-11-13 comparison below |

**yt-dlp vs ytdl download method (2026-11-13, from yt-dlp's source and the tests above).** yt-dlp downloads a playlist one video at a time (a plain loop over entries; no parallel-playlist option), each video's streams one after another (video, then audio, then an ffmpeg merge), and each YouTube direct-download (https) stream as 10 MiB range requests one at a time (`CHUNK_SIZE = 10 << 20`, `downloader_options.http_chunk_size`; `--http-chunk-size` overrides it). ytdl keeps that per-file method and adds parallelism and lower overhead around it: 3 yt-dlp processes at once (the biggest difference), a faster extraction client, the thumbnail and format checks, the fast-starting build, and restarts instead of failures. Splitting one file into parallel 10 MiB fragments (`youtube:formats=dashy` + `-N`) is the only faster per-file method found: ~29% less time per stream alone. It would help single videos and one-worker runs; in a 3-worker run the connection is already the limit. The extractor only offers the dashy variant when a format's size is known, and the one 403 failure needs a signed-in check before it becomes a default. Not adopted yet.

Test downloads were made in the session scratchpad and deleted afterwards. Test content: public Blender channel uploads and YouTube's first video.
