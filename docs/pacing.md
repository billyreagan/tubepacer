# How tubepacer paces itself

This page describes the pacing design in tubepacer 1.33.0 in enough detail to reimplement it. The code is in `ytdl.ps1`: look for `limit guard`, `Step-Budget` and `$paceLevels`. Where this page and the code disagree, the code is right; please [open an issue](https://github.com/billyreagan/tubepacer/issues).

The design has one rule: **ask YouTube less often**. It doesn't hide. tubepacer doesn't rotate proxies or IP addresses, fake browser fingerprints, or cycle cookies across accounts.

## What YouTube is known to do

Sources: **[S]** = yt-dlp's documentation or maintainers; **[A]** = anecdotal (user reports, not measured).

- **Budgets [S].** yt-dlp's [Extractors wiki](https://github.com/yt-dlp/yt-dlp/wiki/Extractors) gives about 300 videos an hour signed out (about 1,000 page and player requests) and about 2,000 videos an hour signed in (about 4,000 requests). It suggests 5–10 s between downloads.
- **Over the budget [S].** HTTP 429 and "This content isn't available, try again later" mean the session went over its request budget ([#3766](https://github.com/yt-dlp/yt-dlp/issues/3766), [#11426](https://github.com/yt-dlp/yt-dlp/issues/11426)).
- **IP reputation [S].** "Sign in to confirm you're not a bot" while signed out means the IP address is blocked ([#3766](https://github.com/yt-dlp/yt-dlp/issues/3766)). Pacing alone may not fix it; signing in usually does.
- **Account limits [S].** These are separate from IP limits. "Video unavailable" while using cookies can mean the account is flagged ([#10085](https://github.com/yt-dlp/yt-dlp/issues/10085)).
- **Captions [S].** Auto-translated captions have a stricter 429 limit of their own ([#13831](https://github.com/yt-dlp/yt-dlp/issues/13831)). Manual and `-orig` captions are not affected.
- **PO tokens [S].** See the [PO Token Guide](https://github.com/yt-dlp/yt-dlp/wiki/PO-Token-Guide). Requests without a required token risk a block.
- **Ban lengths [A].** These are not documented. Reports range from about 25 minutes, to "up to an hour", to most of a day. Nobody has measured whether requests during a block extend it. tubepacer assumes they do, but that is an inference.

## The levels

| Level | Pause between videos (`--sleep-interval` to `--max-sleep-interval`) | Pause before each request (`--sleep-requests`) |
|---|---|---|
| L0 | none | none |
| L1 | none | 0.5 s |
| L2 | 3–6 s | 1 s |
| L3 | 5–10 s | 1 s |
| L4 | 10–20 s | 2 s |
| L5 | 20–40 s | 3 s |

The request pause gets ±50% jitter, drawn fresh each time yt-dlp is launched, because a fixed value is a pattern. Once captions have hit a 429, each caption waits 10 s (`--sleep-subtitles`); otherwise they wait 2 s whenever the level has any pause.

**Starting level (the floor).** L1 signed in, or L0 when 20 or fewer videos are left to download. L3 signed out. A run never speeds up below its floor.

**Shared level.** Parallel workers in a folder share `<Out>\<Folder>\.ytdl-pace.json` and follow the slowest of them.

## Steps up and down (AIMD)

- **Bot check:** up one level.
- **429:** up two levels.
- **A clean streak, and no limit hit on the PC for 30 minutes:** down one level, to no lower than the floor. The streak needed starts at 25 videos and doubles on every trip in a run, so the first step down needs 50 clean videos, then 100, then 200 (the cap).
- Level changes take effect from the next video.
- **Between runs:** the saved level loses one level for every two hours without a bot check. This applies to the folder's `.ytdl-pace.json` and to the level the last trip reached on this PC, which is kept in `pace.json`.

After a bot check, yt-dlp is stopped (the partial file is kept) and restarted at the new level after 10 s. After a 429 it restarts after 30 s × the level (5 min at L5). A 429 never stops the run or opens the breaker (since 1.31). Both waits apply only if the breaker stays closed.

## The hourly budget

Every run and worker on the PC records the YouTube requests it makes (page, player and caption requests, scans, size checks, retries and restarts) in `%LOCALAPPDATA%\ytdl\pace-<network>.json`, with one log for signed in and one for signed out. These logs are kept separately because YouTube limits the IP address and the account separately, not per folder. The network key is a hash of the local gateways (`YTDL_NETKEY` overrides it), so another network starts fresh. Writes go through a named mutex; an update that waits more than 30 s is dropped rather than written without it.

- **Limit:** 700 requests an hour signed out and 4,700 signed in. At about 4.7 requests a video that is 150 and 1,000 videos, about half of the wiki's figures. (Before 1.31 the budget counted videos started.)
- **At 80% of the limit:** up one level, once per run.
- **Over the limit:** stop, wait until enough of the oldest requests drop out of the hour to get back to 90%, then continue.

## The circuit breaker

The breaker opens on any of these:

- a bot check while already at L5
- a second bot check within 10 minutes anywhere on the PC (hits within 60 s of each other count as one, since all workers see the same block at once)

When it opens:

- `CooldownUntil` is written to the pace file: 1 hour from now, flat (before 1.31 a 429 could open it too, and each opening doubled the pause).
- Every run on the PC stops (partial files are kept) and exits with code **75**. The message gives the reason, the time the breaker closes, and the minutes left.
- New runs, `-Estimate` included, print the same message and exit 75 before sending any request. A queue or `-Sync` stops at that point and keeps the rest of its work for later.
- After the cooldown, the first run checks one video (`--simulate`, the first playlist item). If the check fails, the breaker opens again for another hour. If it passes, the run starts at the level it held.

`-IgnoreCooldown` skips all of this. It isn't advised.

Before 1.25, pacing had no ceiling action. At L5 nothing more happened: one benchmark run drew 125 bot checks in 652 s and saved 0 files, which most likely extended the block (suite 11, "ytdl PoToken" run 1).

## Signals tubepacer tells apart

| Signal | Class | Action |
|---|---|---|
| HTTP 429, "Too Many Requests", "isn't available, try again later" | Over budget | Up 2 levels; the run carries on |
| "Your account has been rate-limited by YouTube for up to an hour" (since 1.33) | Account limit | Up 2 levels. Every run on the PC waits together; one video is tried every 5 min. A clean video ends the wait. Still limited after 60 min: the breaker opens (exit 75). Signed in: suggest trying without `-Browser`/`-Cookies` |
| "Confirm you're not a bot", signed out | IP reputation | Up 1 level. The first time, suggest `-Browser` or `-SignInOnBlock`. With `-SignInOnBlock`, switch to signed in once instead |
| "Confirm you're not a bot", signed in | Pacing | Up 1 level. The breaker opens on a second one within 10 min, or one at L5 |
| "Video unavailable" 3 times, signed in | The account may be flagged | Suggest trying without `-Browser`/`-Cookies` |
| 429 on a caption download | Caption limit | Captions wait 10 s each. Videos aren't slowed |

Lines that only echo a title or a file name (`[download] Destination`, `[Merger]` and so on) are ignored, so a video titled "not a bot" doesn't trigger anything.

## Retries

yt-dlp's own retries used to fire back to back, which added requests during a block. tubepacer now passes:

```
--retry-sleep extractor:exp=5:300 --retry-sleep http:exp=1:30 --retry-sleep fragment:exp=1:20
```

These apply unless you pass your own `--retry-sleep`.

## What is measured, and what isn't

Measured on one Windows PC and home connection. Every run, script and raw result is in the [benchmark report](https://claude.ai/artifact/HBzdTEVdfXRFG6b9RpPMiT).

- **Signed in, adaptive pacing (1.24):** 0 bot checks in 208 videos (E5–E6). On the same 6 videos it was 3.3× faster than yt-dlp's fixed sleeps (E5).
- **Signed out:** no replicated result. The planned rerun was bot-blocked four times on 2026-11-16 and was dropped, so the report makes no signed-out bot-check claim.
- **1.32.0 against 1.24.2 (T3-lite, 2026-11-17, signed in; rough: 3 videos, 2 rounds):** 0 bot checks or 429s for either in 9 videos. On 3 videos at 1080p (E5) 1.32.0 was slower: 58.8 s against 45.4 s (0.78×, 95% interval 0.31–1.97, 0 of 2 rounds won). Two of its runs started at a raised pace level left over from earlier runs, since the guard steps down only after a clean streak and 30 quiet minutes. Against plain yt-dlp's fixed sleeps (102.2 s, baseline from 2026-11-13) that is 1.74× for 1.32.0 and 2.25× for 1.24.2. After one simulated bot check (E5R, 1 round) both sent about the same number of requests before the next saved file (12 against 13), but 1.32.0 waited longer (105 s against 39 s) and took 155.6 s against 56.7 s. E6 (first byte) was not rerun.

Not measured:

- how long YouTube's blocks last
- whether requests during a block extend it
- where exactly YouTube's thresholds sit for a given IP address or account

The budget and the breaker are set conservatively for those reasons. Runs on other connections and accounts help fill these gaps: post yours in [Pacing reports](https://github.com/billyreagan/tubepacer/discussions/categories/pacing-reports). The form asks for the version, sign-in, bot checks, the highest level reached and the pacing part of `ytdl -Doctor`.

## Prior art

Tube Archivist sleeps about 3 s with ±50% jitter. yt-dlp offers fixed and random sleeps (`-t sleep`). None of the 78 downloaders we surveyed documents adaptive pacing (stepping up and back down), a shared hourly budget or a circuit breaker. That doesn't mean nobody has built one, only that we found none documented.
