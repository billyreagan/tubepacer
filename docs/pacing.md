# How tubepacer paces itself

This page describes pacing in tubepacer 1.33 in enough detail to reimplement it. The code is in `ytdl.ps1` (search `limit guard`, `Step-Budget`, `$paceLevels`); where they disagree, the code is right, so please [open an issue](https://github.com/billyreagan/tubepacer/issues).

The rule is **ask YouTube less often**, never hide: no rotating proxies or IP addresses, fake browser fingerprints, or cookies cycled across accounts.

## What YouTube is known to do

**[S]** = yt-dlp's documentation or maintainers; **[A]** = anecdotal (user reports, not measured).

- **Budgets [S].** yt-dlp's [Extractors wiki](https://github.com/yt-dlp/yt-dlp/wiki/Extractors) gives about 300 videos an hour signed out (~1,000 page and player requests) and 2,000 signed in (~4,000 requests), and suggests 5–10 s between downloads.
- **Over budget [S].** HTTP 429 and "This content isn't available, try again later" ([#3766](https://github.com/yt-dlp/yt-dlp/issues/3766), [#11426](https://github.com/yt-dlp/yt-dlp/issues/11426)).
- **IP reputation [S].** "Sign in to confirm you're not a bot" while signed out means the IP address is blocked ([#3766](https://github.com/yt-dlp/yt-dlp/issues/3766)). Pacing alone may not fix it; signing in usually does.
- **Account limits [S]** are separate from IP limits: "Video unavailable" with cookies can mean the account is flagged ([#10085](https://github.com/yt-dlp/yt-dlp/issues/10085)).
- **Captions [S].** Auto-translated captions have their own, stricter 429 limit ([#13831](https://github.com/yt-dlp/yt-dlp/issues/13831)); manual and `-orig` captions don't.
- **PO tokens [S].** Requests missing a required token risk a block ([PO Token Guide](https://github.com/yt-dlp/yt-dlp/wiki/PO-Token-Guide)).
- **Ban lengths [A]** are undocumented; reports range from about 25 minutes to most of a day. tubepacer assumes requests during a block extend it (unmeasured).

## The levels

| Level | Between videos (`--sleep-interval`–`--max-sleep-interval`) | Before each request (`--sleep-requests`) |
|---|---|---|
| L0 | none | none |
| L1 | none | 0.5 s |
| L2 | 3–6 s | 1 s |
| L3 | 5–10 s | 1 s |
| L4 | 10–20 s | 2 s |
| L5 | 20–40 s | 3 s |

The request pause gets ±50% jitter, drawn fresh at each yt-dlp launch, so it forms no fixed pattern. Captions wait 2 s at any level with a pause, or 10 s each (`--sleep-subtitles`) after a caption 429.

**Floor.** Signed in: L1, or L0 when 20 or fewer videos are left. Signed out: L3. A run never goes below its floor.

**Shared level.** Parallel workers in a folder share `<Out>\<Folder>\.ytdl-pace.json` and follow the slowest.

## Steps up and down (AIMD)

- **Bot check:** up one level. **429:** up two. Changes apply from the next video.
- **Down one level** (never below the floor) after a clean streak with no limit hit on the PC for 30 minutes. The streak starts at 25 videos and doubles on each trip up: 50, then 100, then 200 (the cap).
- **Between runs**, a saved level (the folder's `.ytdl-pace.json` and the PC's last trip level) drops one per two hours without a bot check.

After a bot check, yt-dlp is stopped (keeping the partial file) and restarted at the new level after 10 s; after a 429, after 30 s × the level (5 min at L5), unless the breaker has opened. Since 1.31 a 429 never stops the run or opens the breaker.

## The hourly budget

Every run and worker on the PC logs each YouTube request (pages, players, captions, scans, size checks, retries) in `%LOCALAPPDATA%\ytdl\pace-<network>.json`, separately signed in and out, because YouTube limits the IP address and account, not the folder. The network key hashes the local gateways (`YTDL_NETKEY` overrides it), so a new network starts fresh. Writes use a named mutex; one waiting over 30 s is dropped, not written unguarded.

- **Limit:** 700 requests an hour signed out, 4,700 signed in. At ~4.7 requests a video that is 150 and 1,000 videos, about half the wiki's figures. (Before 1.31 it counted videos started.)
- **At 80%:** up one level, once per run.
- **At 100%:** wait until old requests age out to 90%, then continue.

## The circuit breaker

It opens on a bot check at L5, or on a second bot check within 10 minutes anywhere on the PC (hits within 60 s count as one, since all workers see the same block).

When it opens:

- `CooldownUntil` in the pace file is set to one hour from now, flat. (Before 1.31 a 429 could open it, and each opening doubled the pause.)
- Every run on the PC stops (keeping partial files) and exits with code **75**, giving the reason and when the breaker closes.
- New runs, `-Estimate` included, do the same before any request. A queue or `-Sync` keeps the rest of its work for later.
- After the cooldown, the first run checks one video (`--simulate`, first playlist item): a failure reopens the breaker for another hour; a pass resumes at the held level.

`-IgnoreCooldown` skips all of this; it isn't advised.

Why: before 1.25 nothing happened at L5, and one benchmark run drew 125 bot checks in 652 s, saving no files (suite 11, "ytdl PoToken" run 1).

## Signals tubepacer tells apart

| Signal | Class | Action |
|---|---|---|
| HTTP 429, "Too Many Requests", "isn't available, try again later" | Over budget | Up 2 levels; the run carries on |
| "Your account has been rate-limited by YouTube for up to an hour" (since 1.33) | Account limit | Up 2 levels. All runs on the PC wait, trying one video every 5 min until one succeeds; after 60 min the breaker opens (exit 75). Suggests trying without `-Browser`/`-Cookies` |
| "Confirm you're not a bot", signed out | IP reputation | Up 1 level. First time: suggests `-Browser` or `-SignInOnBlock` (which signs in once instead) |
| "Confirm you're not a bot", signed in | Pacing | Up 1 level; a second within 10 min, or one at L5, opens the breaker |
| "Video unavailable" 3 times, signed in | Account may be flagged | Suggests trying without `-Browser`/`-Cookies` |
| 429 on a caption download | Caption limit | Captions wait 10 s each; videos aren't slowed |

Lines that only echo a title or file name (`[download] Destination`, `[Merger]`…) are ignored, so a video titled "not a bot" triggers nothing.

## Retries

yt-dlp's own retries used to fire back to back, adding requests during a block. Unless you pass your own `--retry-sleep`, tubepacer passes:

```
--retry-sleep extractor:exp=5:300 --retry-sleep http:exp=1:30 --retry-sleep fragment:exp=1:20
```

## What is measured, and what isn't

One Windows PC and home connection, signed in unless noted. Runs, scripts and raw data are in the [benchmark report](https://claude.ai/artifact/RLR1bpGc2kVgoo3Ca6LgTM). Brackets give 95% intervals; one that spans 1 means no clear difference.

- **Adaptive pacing (1.24):** 0 bot checks in 208 videos (E5–E6), and 3.4× faster than yt-dlp's fixed sleeps on the same 6 videos (E5).
- **Signed out:** no replicated result. The rerun was bot-blocked four times on 2026-11-16 and dropped, so there is no signed-out bot-check claim.
- **Cost of the limit guard (1.32–1.33, suites 14–17, 16–17 Nov 2026):** no run drew a real bot check or 429, and every guarded version still beat plain yt-dlp. Ratios below are 1.24.2's time over the newer version's, so under 1 means the newer one was slower.
  - 2 videos at 720p, 4 alternating pairs, fresh state each run: 1.33.1 tied on wall time (0.98× [0.79–1.23]; median 18.4 s each) but had about 2 s more overhead (13.4 s against 11.2 s; 0.83× [0.78–0.88]), mostly request pauses. 1.32.1: 0.76× [0.51–1.14].
  - An earlier rough test (T3-lite: 3 videos at 1080p, 2 rounds) had 1.32.0 at 0.78× [0.31–1.97], partly because two runs started at a raised level. After one simulated bot check it sent about as many requests as 1.24.2 (12 against 13) but waited longer (105 s against 39 s).
- **Account limit, simulated (1.33.1, 1 run, wait cut to 20 s):** both workers shared one 20.3 s wait and saved both files (exit 0, 47.6 s; 18.4 s normally). Two flaws, fixed in 1.33.2: a worker stopped yt-dlp mid-video (re-downloading 9.6 MiB), and the notice said "every 0 min". A 1.33.2 rerun had neither (52.2 s). No real account limit was involved.

Not measured: how long blocks last, whether requests during one extend it, and where YouTube's thresholds sit for a given IP or account; hence the conservative budget and breaker. Post runs from other connections and accounts in [Pacing reports](https://github.com/billyreagan/tubepacer/discussions/categories/pacing-reports).

## Prior art

Tube Archivist sleeps about 3 s with ±50% jitter; yt-dlp offers fixed and random sleeps (`-t sleep`). None of the 78 downloaders we surveyed documents adaptive pacing (stepping up and back down), a shared hourly budget or a circuit breaker. Some may have one without documenting it.
