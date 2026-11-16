<#
.SYNOPSIS
  ytdl 1.29.0 - Download a YouTube video, playlist or channel from a single URL (wrapper around yt-dlp).
  Changelog and design notes: ytdl-NOTES.md (same folder).

.EXAMPLE
  ytdl "https://www.youtube.com/playlist?list=PLxxxx"
  ytdl "https://youtu.be/abc123" -Out "D:\Videos"
  ytdl "<playlist url>" -Quality 720 -Folder "My Playlist"
  ytdl "<playlist url>" -AudioOnly
  ytdl "<playlist url>" -Browser firefox -Parallel 3
  ytdl "<playlist url>" -Estimate        # count, runtime and ETA only; no download
  ytdl -Stop            # from another terminal: stop all running ytdl downloads
  ytdl "https://www.youtube.com/@SomeChannel" -Subscribe -Browser firefox -Quality 1080
  ytdl -Sync            # download what's new on every subscription (-Sync -Estimate: just show it)
  ytdl -Schedule daily -At 03:00   # run -Sync every day; -Schedule off removes it
  ytdl -Subscriptions   # list them;  ytdl 2 -Unsubscribe  removes number 2
  ytdl "<channel url>" -Subscribe -MinMinutes 5 -Exclude "trailer|teaser" -Keep 20   # filters, keep newest 20
  ytdl -BrowserButton on -Quality 1080 -Browser firefox   # bookmark buttons: download/subscribe the open page
  ytdl "<url>" -YtdlpArgs '--proxy socks5://127.0.0.1:9050 --limit-rate 5M'   # any other yt-dlp option
  ytdl -Doctor -Browser firefox   # check tools, sign-in, disk, pacing and the schedule
  ytdl -Doctor -Report            # the same, saved as a text file for a bug report (names and links hidden)
  ytdl -Doctor -Fix               # make the fixes it can, asking first (-Fix -Yes: only the safe ones, no questions)
  ytdl -Version
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Url,

    # Base directory for downloads (default: your Videos folder)
    [string]$Out = [Environment]::GetFolderPath('MyVideos'),

    # Override the folder name (default: playlist title, or "YouTube" for single videos)
    [string]$Folder,

    # Max video height: best, 4320, 2160, 1440, 1080, 720, 480, 360, 240, 144 (1.22.0: 4320, 240, 144)
    [ValidateSet('best', '4320', '2160', '1440', '1080', '720', '480', '360', '240', '144')]
    [string]$Quality = 'best',

    # Extract audio only (mp3 unless -AudioFormat says otherwise)
    [switch]$AudioOnly,

    # 1.21.0: audio format (implies -AudioOnly): mp3 (re-encoded, plays everywhere; the default), m4a (YouTube's AAC
    # as it is: no re-encode, no quality loss, smaller), opus (YouTube's Opus as it is: the best sound per MB),
    # best (whichever of the two YouTube rates higher, as it is)
    [ValidateSet('mp3', 'm4a', 'opus', 'best')] [string]$AudioFormat,

    # 1.21.0: SponsorBlock (community-submitted segments): mark = chapters at sponsor, intro, self-promotion etc.;
    # remove = cut out sponsor, self-promotion and 'subscribe' reminder segments
    [ValidateSet('mark', 'remove')] [string]$SponsorBlock,

    # 1.22.0: use a PO-token provider (bgutil, run locally on deno) so YouTube's "confirm you're not a bot"
    # checks have a proof-of-origin token to accept. Installed into %LOCALAPPDATA%\ytdl\pot on first use.
    [switch]$PoToken,

    # 1.21.0: cap the whole run's download speed, e.g. 5M or 800K (per second). Split evenly across the downloads
    # running at once, with pieces off, so the total stays under it
    [string]$LimitRate,

    # Download subtitles (English + auto-generated) and embed them
    [switch]$Subs,

    # 1.23.0: subtitle languages (implies -Subs): yt-dlp language codes or patterns, comma-separated
    # (en,de or 'en.*,pt-BR'), or all
    [string]$SubLangs,

    # 1.23.0: also save a past live stream's chat replay (.live_chat.json next to the video)
    [switch]$LiveChat,

    # 1.23.0: file name template from yt-dlp fields, inside the folder ytdl picks; .%(ext)s is added when missing.
    # E.g. '%(upload_date>%Y-%m-%d)s %(title)s [%(id)s]'. Not with -Library (that layout names the files).
    [string]$Template,

    # 1.23.0: container. mp4 (the default; plays everywhere), mkv (takes any codec), webm (VP9/AV1 with Opus;
    # mkv when a video has no webm streams). With webm the thumbnail is saved next to the file, not inside.
    [ValidateSet('mp4', 'mkv', 'webm')] [string]$Container,

    # 1.23.0: preferred video codec at the chosen height. auto = yt-dlp's order; h264 plays on everything
    # (YouTube offers it up to 1080p, so higher -Quality still gets VP9/AV1); vp9; av1 (smallest files)
    [ValidateSet('auto', 'h264', 'vp9', 'av1')] [string]$Codec,

    # 1.23.0: download only these parts of one video: '1:00-2:30', or several: '0:10-0:40,5:00-6:00'
    # (inf = to the end). A video link only; clips have their own archive, so the whole video can still come later.
    [string]$Section,

    # 1.23.0: also split the video into one file per chapter, in a folder named after the video
    [switch]$SplitChapters,

    # 1.23.0: record a live stream from its start (not from the moment you join). A video link or a channel's
    # /live link; an upcoming stream is waited for (checked every minute). One download at a time, no ETA.
    [switch]$Live,

    # Only download playlist items in this range, e.g. "1-10" or "3,5,7"
    # (1.12.1: a list too: -Items 109,172 unquoted is an array in PowerShell; it used to fail to bind)
    [string[]]$Items,

    # Use your signed-in YouTube session from this browser (fixes "Sign in to confirm you're not a bot")
    [ValidateSet('firefox', 'chrome', 'edge', 'brave', 'opera', 'vivaldi', 'chromium')]
    [string]$Browser,

    # Or: path to an exported cookies.txt (Netscape format)
    [string]$Cookies,

    # Seconds to pause between videos (randomized up to 2x). Default -1 = auto: adaptive pacing
    # that starts fast when signed in and slows down on any bot check. 0 = no pauses.
    [int]$Sleep = -1,

    # Extra full passes to run if a pass ends with errors (only failed/missing items are retried). 0 = off
    [int]$Retries = 3,

    # Seconds to wait before each retry pass (1.18.0: unless given, the first retry waits only 15 s:
    # most failures are passing network errors; later retries wait the full 60)
    [int]$RetryDelay = 60,

    # Kill a pass if yt-dlp prints nothing for this many minutes (hang). 0 = off
    [int]$StallMinutes = 10,

    # Abort after this many ERROR lines in a row with no successful download in between. 0 = off
    [int]$MaxErrors = 10,

    # With -Browser: on "cookies are no longer valid", kill yt-dlp immediately and restart the same
    # command with fresh browser cookies, up to this many times (separate from -Retries). 0 = off
    [int]$CookieRestarts = 10,

    # On a fragment 404 loop ("HTTP Error 404 ... Retrying fragment"), kill yt-dlp and restart the
    # same command so it fetches fresh stream URLs and resumes, up to this many times. 0 = off
    [int]$FragmentRestarts = 5,

    # Stop cleanly if free space on the download drive drops below this many GB during a run
    [double]$MinFreeGB = 2,

    # Skip the up-front check that the estimated download fits on the drive
    [switch]$NoSpaceCheck,

    # Above 480p, exact sizes are looked up in the background for a better ETA; this turns that off
    [switch]$NoProbe,

    # 1.25.0: start even though YouTube blocked this PC recently (the limit guard's cooldown). Not advised:
    # requests during a block are thought to extend it.
    [switch]$IgnoreCooldown,

    # If yt-dlp is 7+ days old (checked at most daily), update it before downloading, with the manager it came from (Scoop, winget, pip, pipx; Chocolatey: prints the admin command)
    [switch]$AutoUpdate,

    # Use yt-dlp's default YouTube clients instead of the faster web_embedded-only extraction
    [switch]$NoFastClient,

    # Don't embed title/date/uploader tags (saves ~1 s per video: one fewer ffmpeg rewrite)
    [switch]$NoMetadata,

    # With -Quality 360: use YouTube's single combined H.264/AAC 360p stream (format 18) for older
    # players/TVs without AV1 support. Only ~15% faster per video and ~75% bigger files than the
    # default AV1 360p at similar quality, so use it for compatibility, not speed. Falls back if missing.
    [switch]$Fast360,

    # Don't embed the thumbnail as cover art. Old uploads lack the HD thumbnails yt-dlp tries first,
    # which cost ~2 s per video in misses (15% of a real 234-video run).
    [switch]$NoThumbnail,

    # 1.15.0 subscriptions. -Subscribe saves this URL (a channel or playlist) with the options given
    # alongside it; -Sync downloads whatever is new on every subscription (the archive skips the rest).
    [switch]$Subscribe,
    # Remove a subscription (by URL, or by its number in -Subscriptions). Files are kept.
    [switch]$Unsubscribe,
    # List subscriptions, their last sync, and the schedule
    [switch]$Subscriptions,
    # Download new videos from every subscription. With -Estimate: only show what's new.
    [switch]$Sync,
    # Run -Sync automatically as a Windows scheduled task: daily (at -At), hourly (from -At), or off
    [ValidateSet('daily', 'hourly', 'off')]
    [string]$Schedule,
    # Time of day for -Schedule, 24-hour HH:mm
    [string]$At = '03:00',
    # 1.23.0: with -Subscribe, write a podcast feed (feed.xml in the subscription's folder) after each -Sync.
    # Enclosures point at the local files, or at -FeedBase + the file's path inside the folder (for a web server).
    [switch]$Feed,
    [string]$FeedBase,
    # 1.23.0: list the last downloads (20, or ytdl -History 50): date, height, size, title, folder. -Match filters titles.
    [switch]$History,

    # 1.16.0 filters (any run; saved with -Subscribe): skip videos shorter or longer than this many
    # minutes, keep only titles matching -Match / not matching -Exclude (regex, case-insensitive),
    # and only videos uploaded on or after -After (2026-10-01, or relative: "30 days", "2 weeks").
    [double]$MinMinutes = 0,
    [double]$MaxMinutes = 0,
    [string]$Match,
    [string]$Exclude,
    [string]$After,
    # 1.16.0 retention, for subscriptions: after each -Sync, delete this subscription's oldest videos
    # beyond the newest -Keep, or older than -KeepDays (by upload date). Only files ytdl downloaded for
    # that subscription since 1.16.0 are touched; the archive keeps them from downloading again.
    [int]$Keep = 0,
    [int]$KeepDays = 0,
    # 1.16.0: 'on' registers the ytdl:// link handler and makes the browser bookmark buttons (the
    # options given alongside are what the buttons use); 'off' removes them.
    [ValidateSet('on', 'off')]
    [string]$BrowserButton,
    # Internal: the ytdl:// link a browser button opened. Not for direct use.
    [string]$FromLink,
    # Internal (-Sync): file recording this subscription's downloaded files, for -Keep/-KeepDays
    [string]$FileList,

    # Signal every running ytdl to stop, then exit
    [switch]$Stop,

    # 1.16.0: pause every running ytdl (with -Out <dir>: only runs downloading there), or resume them.
    # In a download window, P pauses and resumes too (R also resumes); Ctrl+C still stops.
    [switch]$Pause,
    [switch]$Resume,

    # 1.17.0: no green progress bar at the bottom of the window (it's off anyway when output isn't a console)
    [switch]$NoProgressBar,

    # 1.18.0: more yt-dlp options, as one quoted string, e.g. '--proxy socks5://127.0.0.1:9050 --limit-rate 5M
    # --sponsorblock-remove sponsor'. Connection options (proxy, IPv4/6, extractor args, headers) reach every
    # yt-dlp call; the rest only the download. Options ytdl manages itself are refused, naming ytdl's own.
    [string]$YtdlpArgs,

    # 1.18.0: Windows notification when a run or sync ends. auto = runs over 2 minutes, any failure or stop,
    # and syncs that found new videos or failed; on = always; off = never
    [ValidateSet('auto', 'on', 'off')] [string]$Notify = 'auto',

    # 1.19.0: lay files out for a media server: <Out>\<Channel>\Season <year>\<Channel> - s<year>e<MMDDHH> - <Title> [id].mp4
    # with episode images and the channel/playlist image as poster.jpg; jellyfin also writes an .nfo per episode
    # (title, air date, description). -Folder names the show instead of the channel. Saved with -Subscribe.
    [ValidateSet('jellyfin', 'plex')] [string]$Library,

    # 1.20.0: if a ytdl download is running, put this link (with the options given) in the queue it works
    # through when it finishes, in its own window; if none is running, just download it now
    [switch]$Add,
    # 1.20.0: list the queued links and the downloads running now; -ClearQueue empties the queue
    # (named ListQueue inside: ytdl already uses $queue for the scanned videos, and PowerShell names ignore case)
    [Alias('Queue')] [switch]$ListQueue,
    [switch]$ClearQueue,

    # 1.18.0: check yt-dlp, ffmpeg, deno, sign-in (with -Browser/-Cookies), free space, pacing, subscriptions
    # and the schedule, print what's wrong and how to fix it, then exit. 1.28.0: ytdl -Doctor <video url> also
    # checks that video (one metadata request): available or why not, the formats vs -Quality, the archive
    [switch]$Doctor,

    # 1.26.0: with -Doctor (implies it): also save the results as a text file for a bug report, with the
    # user, PC, folder names and links hidden, and copy it to the clipboard
    [switch]$Report,

    # 1.29.0: with -Doctor (implies it): offer the fixes ytdl can make itself (update or install yt-dlp, ffmpeg,
    # deno; remove an extra copy; delete leftover files; set up the scheduled sync again), asking for each one,
    # then check again. -Fix -Yes runs the safe ones without asking (removing and deleting always ask)
    [switch]$Fix,
    [switch]$Yes,

    # Print the ytdl version and exit
    [switch]$Version,

    # Only scan the URL and print video count, total runtime and estimated download time; no download
    [switch]$Estimate,

    # Look up each remaining video's exact file size first (~9 s per video) for an accurate ETA
    # even when resolutions vary (e.g. 4K clips mixed with 1080p streams at -Quality best)
    [switch]$Precise,

    # Download this many playlist videos at once (separate worker processes). Default 3; 1 = one at a time
    [ValidateRange(1, 8)]
    [int]$Parallel = 1,

    # Fetch each file as 10 MiB pieces, this many at once (yt-dlp fetches them one at a time). Default:
    # 3 when the run uses 1 or 2 workers (a single video, a 2-video run, -Parallel 1 or 2), off with
    # 3+ workers (they already fill the connection). 0 or 1 = off.
    [ValidateRange(0, 8)]
    [int]$Fragments = -1,

    # -Parallel: hand out work from a shared queue in batches of -Chunk videos instead of a fixed
    # split, so a worker that finishes early takes more (no idle tail). Experimental until benchmarked.
    [switch]$Dynamic,
    [ValidateRange(1, 50)]
    [int]$Chunk = 3,

    # Internal: set by -Parallel on its worker processes. Not for direct use.
    [int]$Worker = 0,
    [int]$WorkerCount = 1,
    [switch]$NoScan,     # worker launched by the coordinator: skip the playlist scan and ETA
    [switch]$LowResContent,  # set by the coordinator when the resolution check found <= 480p videos
    [int]$ContentHeight = 0, # ...and the height it found, so workers use that resolution's ETA priors
    [int]$StartFloor = -1,   # 1.25.0: the coordinator's lowest pacing level (0 for a small signed-in batch)
    [string]$QueueFile       # 1.7.0: the coordinator's scan of this worker's share (worker skips its own scan)
)

$YtdlVersion = '1.29.0'
if ($Report -or $Fix) { $Doctor = [switch]$true }   # 1.26.0: -Report alone means -Doctor -Report; 1.29.0: -Fix too
$ItemsStr = (@($Items) | Where-Object { $_ } | ForEach-Object { "$_".Trim() }) -join ','
if ($AudioFormat) { $AudioOnly = [switch]$true }   # 1.21.0
$limitBytes = 0                                    # 1.21.0: -LimitRate in bytes per second
if ($LimitRate) {
    if ($LimitRate -notmatch '^\s*(\d+(?:\.\d+)?)\s*([KMG]?)(?:i?B)?\s*$') { Microsoft.PowerShell.Utility\Write-Host "[ytdl] -LimitRate: use a speed like 5M, 800K or 1.5M (per second); got '$LimitRate'." -ForegroundColor Red; exit 1 }
    $limitBytes = [double]$Matches[1] * @{ '' = 1; 'K' = 1KB; 'M' = 1MB; 'G' = 1GB }[$Matches[2].ToUpper()]
    if ($limitBytes -lt 10KB) { Microsoft.PowerShell.Utility\Write-Host "[ytdl] -LimitRate $LimitRate is under 10K per second; too slow for video." -ForegroundColor Red; exit 1 }
}
$ErrorActionPreference = 'Stop'
$stopFile = Join-Path $env:TEMP 'ytdl.stop'

# 1.16.0: a ytdl:// link from a browser button may carry only the link itself. Checked before anything
# else runs: a link crafted with a quote could otherwise smuggle in options (-Out, -Cookies, -Stop...).
if ($PSBoundParameters.ContainsKey('FromLink') -and @($PSBoundParameters.Keys | Where-Object { $_ -ne 'FromLink' }).Count) {
    Microsoft.PowerShell.Utility\Write-Host "[ytdl] Refused a ytdl:// link that carried extra options ($(@($PSBoundParameters.Keys | Where-Object { $_ -ne 'FromLink' }) -join ', ')). A link may only name a YouTube page." -ForegroundColor Red
    try { [void][Console]::ReadKey($true) } catch { }
    exit 1
}

# Everything ytdl prints goes through this wrapper, so the run log (R4, opened later) captures
# all of it without touching each message. Before the log is open it just prints.
$script:runLog = $null
function Write-Host {
    param([Parameter(Position = 0, ValueFromRemainingArguments = $true)] $Object, $ForegroundColor, [switch] $NoNewline)
    $text = ($Object | ForEach-Object { "$_" }) -join ' '
    if ($script:runLog) { try { $ts = (Get-Date).ToString('HH:mm:ss'); foreach ($ln in ($text -split "`r?`n")) { if ($ln.Trim()) { $script:runLog.WriteLine("$ts $ln") } } } catch { } }
    $hp = @{}; if ($ForegroundColor) { $hp.ForegroundColor = $ForegroundColor }; if ($NoNewline) { $hp.NoNewline = $true }
    $lift = $script:barShown -and -not $NoNewline     # 1.17.0: keep the progress bar under the newest line
    if ($lift) { Clear-BarLine }
    Microsoft.PowerShell.Utility\Write-Host $text @hp
    if ($lift) { Show-Bar }
}
function Write-LogOnly([string]$text) { if ($script:runLog) { try { $ts = (Get-Date).ToString('HH:mm:ss'); foreach ($ln in ($text -split "`r?`n")) { if ($ln.Trim()) { $script:runLog.WriteLine("$ts $ln") } } } catch { } } }

# ---- 1.17.0: progress bar ----------------------------------------------------------------------------
# One green bar on the bottom line of the window for the whole run: data downloaded so far against
# the estimated total (finished videos + the part of the current file done, against ytdl's size
# estimate for everything still to come), then videos done and the current speed. Every printed line
# goes through Write-Host above, which lifts the bar, prints, and redraws it, so it stays at the bottom.
# Plain console colors (no escape codes), so it works in Windows PowerShell 5.1 too. Only the
# top-level run in a real console draws it; parallel workers feed the coordinator's bar instead.
$script:barOn = $false; $script:barShown = $false; $script:barLast = [datetime]::MinValue
$script:barPctMax = 0.0; $script:barFinal = $false
$script:barState = $null      # scriptblock returning @{ Done; Total; FilesDone; FilesTotal; Speed; Paused }
function Get-ConsoleWidth { try { [math]::Max(40, [Console]::WindowWidth) } catch { 100 } }
function Clear-BarLine {
    try { [Console]::Write("`r" + (' ' * ((Get-ConsoleWidth) - 1)) + "`r") } catch { }
}
function Format-BarSize([double]$mib) { if ($mib -ge 1024) { '{0:N2} GB' -f ($mib / 1024) } else { '{0:N0} MB' -f $mib } }
function Show-Bar {
    if (-not $script:barOn -or -not $script:barState) { return }
    $s = $null; try { $s = & $script:barState } catch { }
    if (-not $s) { return }
    $total = [math]::Max([double]$s.Total, [double]$s.Done)
    if ($script:barFinal) { $total = [double]$s.Done }   # run finished: the real total is what came down
    $pct = if ($total -gt 0) { [double]$s.Done / $total } else { 0.0 }
    # Fill only forward: when an estimate turns out low, the total grows and the share would shrink.
    # The bar then holds until the download catches up; the MB figures always show the true numbers.
    $pct = [math]::Max($pct, [double]$script:barPctMax); $script:barPctMax = $pct
    $txt = ' {0,3}%  {1} / {2}' -f [int][math]::Floor($pct * 100), (Format-BarSize $s.Done), (Format-BarSize $total)
    if ($s.FilesTotal -gt 0) { $txt += "  $($s.FilesDone) of $($s.FilesTotal) video$(if ($s.FilesTotal -ne 1) { 's' })" }
    if ($s.Paused) { $txt += '  paused' } elseif ($s.Speed -gt 0) { $txt += '  {0:N1} MiB/s' -f $s.Speed }
    $W = Get-ConsoleWidth
    $bw = [math]::Max(10, [math]::Min(40, $W - $txt.Length - 4))
    if ($bw + $txt.Length + 3 -ge $W) { $txt = $txt.Substring(0, [math]::Max(0, $W - $bw - 4)) }   # never wrap: \r couldn't clear it
    $fill = [int][math]::Round($pct * $bw)
    try {
        [Console]::Write("`r")
        Microsoft.PowerShell.Utility\Write-Host '[' -NoNewline -ForegroundColor DarkGray
        Microsoft.PowerShell.Utility\Write-Host (([string][char]0x2588) * $fill) -NoNewline -ForegroundColor Green
        Microsoft.PowerShell.Utility\Write-Host (([string][char]0x2591) * ($bw - $fill)) -NoNewline -ForegroundColor DarkGray
        Microsoft.PowerShell.Utility\Write-Host ']' -NoNewline -ForegroundColor DarkGray
        Microsoft.PowerShell.Utility\Write-Host $txt -NoNewline -ForegroundColor $(if ($s.Paused) { 'Yellow' } else { 'Green' })
        $script:barShown = $true; $script:barLast = Get-Date
    } catch { $script:barOn = $false }
}
# Redraw at most twice a second (or now, with -Force)
function Update-Bar([switch]$Force) {
    if (-not $script:barOn) { return }
    if (-not $Force -and ((Get-Date) - $script:barLast).TotalMilliseconds -lt 500) { return }
    if ($script:barShown) { Clear-BarLine }
    Show-Bar
}
# Leave the final bar in place and move below it (end of run, Ctrl+C)
function Close-Bar {
    if (-not $script:barShown) { return }
    if ($script:barOn) { Clear-BarLine; Show-Bar }
    $script:barShown = $false
    try { [Console]::WriteLine() } catch { }
}

if ($Version) { Write-Host "ytdl $YtdlVersion"; exit 0 }
$runT0 = Get-Date

# ---- 1.18.0: -YtdlpArgs --------------------------------------------------------------------------------
# Split like a command line ("double" or 'single' quotes group words), then group each option with the
# values after it. Options that would fight ytdl's own handling are refused with ytdl's equivalent.
# Connection options also go to the scan, the resolution check and the size lookups (a proxy must cover
# everything); the rest (speed cap, SponsorBlock, sections...) only to the download itself.
$userNetArgs = @(); $userDlArgs = @()
if ($YtdlpArgs) {
    $toks = @(foreach ($m in [regex]::Matches($YtdlpArgs, '"((?:[^"\\]|\\.)*)"|''([^'']*)''|(\S+)')) {
        if ($m.Groups[1].Success) { $m.Groups[1].Value -replace '\\"', '"' } elseif ($m.Groups[2].Success) { $m.Groups[2].Value } else { $m.Groups[3].Value } })
    # Case matters: -s and -S, -j and -J, -o and -O are different yt-dlp options (a hashtable would merge them)
    $managed = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
    foreach ($p in @(
        @('-o', '-Template (file name) or -Folder'),
        @('--output', '-Template (file name) or -Folder'),
        @('--sub-langs', '-SubLangs'),
        @('--download-sections', '-Section'),
        @('--split-chapters', '-SplitChapters'),
        @('-P', '-Out'),
        @('--paths', '-Out'),
        @('--download-archive', 'nothing (ytdl keeps .ytdl-archive.txt in the folder)'),
        @('--no-download-archive', 'nothing (ytdl keeps .ytdl-archive.txt in the folder)'),
        @('-a', 'one link per run, or -Subscribe'),
        @('--batch-file', 'one link per run, or -Subscribe'),
        @('-f', '-Quality or -AudioOnly'),
        @('--format', '-Quality or -AudioOnly'),
        @('-S', '-Quality and -Codec'),
        @('--format-sort', '-Quality and -Codec'),
        @('--merge-output-format', '-Container'),
        @('--remux-video', '-Container'),
        @('-x', '-AudioOnly'),
        @('--extract-audio', '-AudioOnly'),
        @('--audio-format', '-AudioOnly'),
        @('-I', '-Items'),
        @('--playlist-items', '-Items'),
        @('--yes-playlist', 'nothing'),
        @('--no-playlist', 'a plain video link'),
        @('--cookies', '-Cookies'),
        @('--cookies-from-browser', '-Browser'),
        @('--no-cookies', 'leaving out -Browser/-Cookies'),
        @('--no-cookies-from-browser', 'leaving out -Browser'),
        @('--sleep-interval', '-Sleep (ytdl paces itself)'),
        @('--min-sleep-interval', '-Sleep (ytdl paces itself)'),
        @('--max-sleep-interval', '-Sleep (ytdl paces itself)'),
        @('--sleep-requests', '-Sleep (ytdl paces itself)'),
        @('-N', '-Fragments'),
        @('--concurrent-fragments', '-Fragments'),
        @('--match-filters', '-MinMinutes/-MaxMinutes/-Match/-Exclude'),
        @('--match-filter', '-MinMinutes/-MaxMinutes/-Match/-Exclude'),
        @('--break-match-filters', '-After'),
        @('--dateafter', '-After'),
        @('--date', '-After'),
        @('--embed-thumbnail', 'nothing (on by default; -NoThumbnail turns it off)'),
        @('--no-embed-thumbnail', '-NoThumbnail'),
        @('--embed-metadata', 'nothing (on by default)'),
        @('--no-embed-metadata', '-NoMetadata'),
        @('-i', 'nothing (ytdl skips failed videos and retries them)'),
        @('--ignore-errors', 'nothing'),
        @('--abort-on-error', '-MaxErrors'),
        @('--no-abort-on-error', 'nothing'),
        @('--print', 'nothing (ytdl reads yt-dlp''s output)'),
        @('-O', 'nothing'),
        @('--print-to-file', 'nothing'),
        @('--progress-template', 'nothing'),
        @('-q', 'nothing'),
        @('--quiet', 'nothing'),
        @('--no-progress', '-NoProgressBar'),
        @('--progress-delta', 'nothing'),
        @('--newline', 'nothing'),
        @('-j', '-Estimate'),
        @('--dump-json', '-Estimate'),
        @('-J', '-Estimate'),
        @('--dump-single-json', '-Estimate'),
        @('-s', '-Estimate'),
        @('--simulate', '-Estimate'),
        @('--no-simulate', 'nothing'),
        @('--skip-download', '-Estimate'),
        @('--flat-playlist', 'nothing'),
        @('--no-flat-playlist', 'nothing')
    )) { $managed[$p[0]] = $p[1] }
    $netOpts = @('--proxy', '--geo-verification-proxy', '--source-address', '-4', '--force-ipv4', '-6', '--force-ipv6', '--impersonate', '--xff',
                 '--extractor-args', '--user-agent', '--referer', '--add-headers', '--add-header', '--no-check-certificates', '--legacy-server-connect',
                 '--client-certificate', '--client-certificate-key', '--client-certificate-password', '--extractor-retries', '--js-runtimes', '--remote-components')
    $groups = @(); $cur = $null
    foreach ($t in $toks) {
        if ($t -match '^-' -and ($t -notmatch '^-\d' -or $t -in '-4', '-6')) { $cur = [System.Collections.ArrayList]@($t); $groups += , $cur }
        elseif ($cur) { [void]$cur.Add($t) }
        else { Write-Host "[ytdl] -YtdlpArgs: '$t' isn't an option (options start with -). Example: -YtdlpArgs '--limit-rate 5M'" -ForegroundColor Red; exit 1 }
    }
    foreach ($g in $groups) {
        $opt = ($g[0] -split '=', 2)[0]
        if ($managed.ContainsKey($opt)) { Write-Host "[ytdl] -YtdlpArgs: ytdl manages $opt itself; use $($managed[$opt]) instead." -ForegroundColor Red; exit 1 }
        if ($netOpts -contains $opt) { $userNetArgs += @($g) } else { $userDlArgs += @($g) }
        # Measured (1.18.0 test): --limit-rate 1M gave 1.0-2.2 MiB/s per stream line with 3 pieces and 2 workers
        if ($opt -in '-r', '--limit-rate' -and $Worker -eq 0) { Write-Host "[ytdl] Note: yt-dlp applies $opt to each stream it downloads, and ytdl runs several (videos at once, each in pieces), so the total can be a few times higher. For a cap on the total use -LimitRate instead." -ForegroundColor DarkGray }
    }
}

# 1.23.0 -Section: checked before anything starts. One video only (a playlist would cut every video at the same
# times). Clips keep their own archive per set of times, so the same clip isn't fetched twice and the whole
# video (the normal archive) can still be downloaded later.
$archName = '.ytdl-archive.txt'; $clipTag = ''
if ($Section) {
    $timeRx = '(\d+(:\d{1,2}){0,2}(\.\d+)?)'
    $parts = @($Section -split '\s*,\s*' | Where-Object { $_ })
    foreach ($sp in $parts) {
        if ($sp -notmatch "^$timeRx-($timeRx|inf)$") { Write-Host "[ytdl] -Section: '$sp' isn't a time range. Examples: 1:00-2:30, 0:10-0:40,5:00-6:00, 45:00-inf" -ForegroundColor Red; exit 1 }
    }
    if ($Url -match '[?&]list=' -or $Url -notmatch '(?:youtube\.com/(?:watch\?(?:[^#]*&)?v=|shorts/|live/|embed/)|youtu\.be/)[\w-]{11}') {
        Write-Host "[ytdl] -Section works on one video link (watch?v=..., youtu.be/..., shorts/...), not a playlist or channel." -ForegroundColor Red; exit 1
    }
    $clipTag = ($parts -join ' + ') -replace ':', '.'
    $archName = ".ytdl-archive-clip $clipTag.txt"
}
# 1.23.0 -Live: one stream (a video link, or a channel's /live link, which points at its current stream)
if ($Live) {
    if ($Section) { Write-Host "[ytdl] -Live and -Section don't go together: record the stream first, then cut a part with -Section once it's a normal video." -ForegroundColor Red; exit 1 }
    if ($Url -match '[?&]list=' -or ($Url -notmatch '(?:youtube\.com/(?:watch\?(?:[^#]*&)?v=|shorts/|live/|embed/)|youtu\.be/)[\w-]{11}' -and $Url -notmatch 'youtube\.com/(@[^/?#]+|channel/[^/?#]+|c/[^/?#]+|user/[^/?#]+)/live/?(?:[?#].*)?$')) {
        Write-Host "[ytdl] -Live works on one stream: a video link (watch?v=..., youtube.com/live/...) or a channel's /live link (youtube.com/@name/live)." -ForegroundColor Red; exit 1
    }
    # waiting for a scheduled stream prints nothing for a long time; don't let the stall watchdog kill it
    if (-not $PSBoundParameters.ContainsKey('StallMinutes')) { $StallMinutes = 0 }
    if ($Worker -eq 0) { $Parallel = 1; $PSBoundParameters['Parallel'] = 1 }
}
# 1.23.0 -Feed / -FeedBase: subscription options
if (($Feed -or $FeedBase) -and -not $Subscribe -and -not $Worker -and -not $FileList) {
    Write-Host "[ytdl] -Feed is a subscription option: ytdl <channel or playlist url> -Subscribe -Feed [-FeedBase https://...]. The feed is written after each ytdl -Sync." -ForegroundColor Red; exit 1
}
if ($FeedBase -and $FeedBase -notmatch '^https?://[^\s]+$') { Write-Host "[ytdl] -FeedBase must be an http(s) URL, e.g. http://192.168.1.5:8080/podcasts/mychannel" -ForegroundColor Red; exit 1 }
if ($FeedBase -and $Subscribe) { $Feed = [switch]$true; $PSBoundParameters['Feed'] = [switch]$true }
# 1.23.0 -Template: no folder parts (ytdl picks the folder; -Folder names it)
if ($Template -and $Template -match '[\\/]') { Write-Host "[ytdl] -Template names the file only; use -Folder for the folder (no / or \ in the template)." -ForegroundColor Red; exit 1 }

# ---- 1.18.0: Windows notifications ------------------------------------------------------------------------
# PowerShell 7 can't load Windows' toast API, so a hidden Windows PowerShell 5.1 shows it (fire and forget).
# Never from workers or from the runs a -Sync makes (YTDL_IN_SYNC): the sync shows one summary itself.
# 1.18.1: why Windows would drop a toast, or $null. Registry only (fast): the global switch and Windows
# PowerShell's own switch (the app id the toast is shown as).
function Get-ToastBlock {
    try {
        $g = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' -ErrorAction Stop).ToastEnabled
        if ($null -ne $g -and [int]$g -eq 0) { return 'notifications are turned off in Windows (Settings > System > Notifications)' }
    } catch { }
    try {
        $a = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe' -ErrorAction Stop).Enabled
        if ($null -ne $a -and [int]$a -eq 0) { return 'notifications from Windows PowerShell are turned off (Settings > System > Notifications > Windows PowerShell)' }
    } catch { }
    $null
}
function Show-Toast([string]$title, [string]$text) {
    if ($Notify -eq 'off' -or $Worker -gt 0 -or $env:YTDL_IN_SYNC -eq '1') { return }
    Write-LogOnly "[ytdl-event] notification: $title | $text"
    if ($env:YTDL_TOAST_TEST) { Microsoft.PowerShell.Utility\Write-Host "[ytdl-toast] $title | $text"; if ($env:YTDL_TOAST_TEST -ne 'show') { return } }
    # 1.18.1: Windows drops toasts silently when notifications are off (for everything, or for PowerShell);
    # say so instead of pretending (found on 2026-11-13: ToastEnabled 0, notifier "DisabledForUser")
    $off = Get-ToastBlock
    if ($off) { Write-Host "[ytdl] No notification shown: $off. (-Notify off hides this note.)" -ForegroundColor DarkGray; return }
    $x = "<toast><visual><binding template='ToastGeneric'><text>$([Security.SecurityElement]::Escape($title))</text><text>$([Security.SecurityElement]::Escape($text))</text></binding></visual></toast>"
    $ps = "[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]; " +
          "[void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]; " +
          "`$d = New-Object Windows.Data.Xml.Dom.XmlDocument; `$d.LoadXml('" + ($x -replace "'", "''") + "'); " +
          "[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe').Show((New-Object Windows.UI.Notifications.ToastNotification `$d))"
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ps))
    try { Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList "-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand $enc" -WindowStyle Hidden } catch { }
}
# End of a download run: auto mode skips quick clean runs (you were watching them)
function Send-RunToast([int]$code, [int]$nFailed, [string]$why) {
    if ($Estimate) { return }
    $secs = ((Get-Date) - $script:runT0).TotalSeconds
    if ($Notify -eq 'auto' -and $code -eq 0 -and -not $why -and $nFailed -eq 0 -and $secs -lt 120) { return }
    $new = 0; try { $new = [math]::Max(0, (Get-ArchiveCount) - $script:archStart0) } catch { }
    $title = if ($why) { 'ytdl stopped' } elseif ($code -eq 0 -and $nFailed -eq 0) { 'ytdl finished' } else { 'ytdl finished with errors' }
    $t = "$new video(s) downloaded in $(Format-Dur $secs)" + $(if ($nFailed) { ", $nFailed failed" } else { '' }) + " - $Out"
    if ($why) { $t = "$why $t" }
    Show-Toast $title $t
}

# ---- ytdl -Stop: drop the stop signal and exit -------------------------------------------
# A stop can target one output folder (ytdl -Stop -Out <dir>) or every run (ytdl -Stop).
$folderStop = Join-Path $Out '.ytdl.stop'
if ($Stop) {
    if ($PSBoundParameters.ContainsKey('Out')) {
        if (-not (Test-Path -LiteralPath $Out)) { Write-Host "No such folder: $Out" -ForegroundColor Yellow; exit 1 }
        New-Item -ItemType File -Force -Path $folderStop | Out-Null
        Write-Host "Stop signal sent to ytdl runs downloading to $Out. They will halt within a few seconds." -ForegroundColor Yellow
    } else {
        New-Item -ItemType File -Force -Path $stopFile | Out-Null
        Write-Host "Stop signal sent. All running ytdl downloads will halt within a few seconds." -ForegroundColor Yellow
    }
    exit 0
}
function Test-StopRequested { (Test-Path $stopFile) -or (Test-Path $folderStop) }

# ---- 1.16.0: pause / resume ------------------------------------------------------------------------
# Like -Stop, a signal file: %TEMP%\ytdl.pause pauses every run, <Out>\.ytdl.pause one folder (P in the
# download window toggles that one). Each run's watchdog suspends its yt-dlp process tree (yt-dlp,
# ffmpeg, deno) while a pause file exists and resumes it after, so the download continues where it was.
# %TEMP%\ytdl.pauses.txt lists folder pauses, so a plain -Resume can clear them all.
$pauseFile   = Join-Path $env:TEMP 'ytdl.pause'
$folderPause = Join-Path $Out '.ytdl.pause'
$pauseList   = Join-Path $env:TEMP 'ytdl.pauses.txt'
function Test-PauseRequested { (Test-Path $pauseFile) -or (Test-Path $folderPause) }
function Clear-AllPauses {
    $paths = @($pauseFile)
    if (Test-Path -LiteralPath $pauseList) { $paths += @(Get-Content -LiteralPath $pauseList -ErrorAction SilentlyContinue | Where-Object { $_ -like '*\.ytdl.pause' }) }
    foreach ($p in $paths) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $pauseList -Force -ErrorAction SilentlyContinue
}
if ($Pause -or $Resume) {
    if ($Pause -and $Resume) { Write-Host "Use -Pause or -Resume, not both." -ForegroundColor Yellow; exit 1 }
    $oneFolder = $PSBoundParameters.ContainsKey('Out')
    if ($oneFolder -and -not (Test-Path -LiteralPath $Out)) { Write-Host "No such folder: $Out" -ForegroundColor Yellow; exit 1 }
    if ($Pause) {
        if ($oneFolder) { New-Item -ItemType File -Force -Path $folderPause | Out-Null; Add-Content -LiteralPath $pauseList -Value $folderPause }
        else { New-Item -ItemType File -Force -Path $pauseFile | Out-Null }
        Write-Host "Paused $(if ($oneFolder) { "ytdl runs downloading to $Out" } else { 'all running ytdl downloads' }) (within ~2 s). Resume: ytdl -Resume$(if ($oneFolder) { ' -Out "' + $Out + '"' })" -ForegroundColor Yellow
    } else {
        if ($oneFolder) { Remove-Item -LiteralPath $folderPause -Force -ErrorAction SilentlyContinue; Remove-Item -LiteralPath $pauseFile -Force -ErrorAction SilentlyContinue }
        else { Clear-AllPauses }
        Write-Host "Resumed $(if ($oneFolder) { "ytdl runs downloading to $Out" } else { 'all paused ytdl downloads' })." -ForegroundColor Green
    }
    exit 0
}
function Clear-StopFiles { Remove-Item $stopFile, $folderStop, $folderPause -Force -ErrorAction SilentlyContinue }   # 1.16.0: + a stale folder pause

# ---- 1.15.0: channel URLs ------------------------------------------------------------------------
# A bare channel URL (youtube.com/@name, /channel/ID, /c/name, /user/name) makes yt-dlp list the
# Videos, Shorts and Live tabs as separate playlists, each numbered from 1 under its own title, so
# folders split and numbers collide. ytdl uses the channel's Videos tab instead (/shorts or /streams
# can still be given explicitly). Channel tabs list newest first, so a video's position changes with
# every upload; files from a channel tab are named by upload date instead of position.
function ConvertTo-ChannelUrl([string]$u) {
    if ($u -match '^(?:https?://)?(?:www\.|m\.)?youtube\.com/(@[^/?#]+|channel/[^/?#]+|c/[^/?#]+|user/[^/?#]+)/?(?:featured/?)?(?:[?#].*)?$') {
        return "https://www.youtube.com/$($Matches[1])/videos"
    }
    $u
}
if ($Url -and $Url -notmatch '^\d+$') {
    $chUrl = ConvertTo-ChannelUrl $Url
    if ($chUrl -ne $Url) { Write-Host "[ytdl] Channel URL: using its Videos tab ($chUrl). For Shorts or Live, add /shorts or /streams." -ForegroundColor DarkGray; $Url = $chUrl }
}
$isChannelTab = $Url -match 'youtube\.com/(@|channel/|c/|user/)[^/?#]+/(videos|shorts|streams)\b'

# ---- 1.15.0: subscriptions --------------------------------------------------------------------
# %LOCALAPPDATA%\ytdl\subscriptions.json holds each subscribed URL with the options given when it was
# added. -Sync runs ytdl once per subscription with those options, one after another; each run is a
# normal ytdl run (lock, log, archive, retries, parallel workers), so only new videos download.
$subsFile = if ($env:YTDL_SUBSCRIPTIONS) { $env:YTDL_SUBSCRIPTIONS } else { Join-Path $env:LOCALAPPDATA 'ytdl\subscriptions.json' }
$subTask = if ($env:YTDL_TASKNAME) { $env:YTDL_TASKNAME } else { 'ytdl sync' }
$subOptNames = @('Folder', 'Quality', 'AudioOnly', 'Subs', 'Items', 'Browser', 'Cookies', 'Parallel', 'Fragments',
                 'NoThumbnail', 'NoMetadata', 'Fast360', 'NoFastClient', 'Retries', 'MinFreeGB', 'Sleep',
                 'MinMinutes', 'MaxMinutes', 'Match', 'Exclude', 'After', 'Keep', 'KeepDays',   # 1.16.0: filters, retention
                 'YtdlpArgs', 'Library', 'AudioFormat', 'SponsorBlock', 'LimitRate', 'PoToken',   # 1.18.0, 1.19.0, 1.21.0, 1.22.0
                 'SubLangs', 'LiveChat', 'Template', 'Container', 'Codec', 'SplitChapters', 'Feed', 'FeedBase')   # 1.23.0 (not -Section, -Live: one video)
# 1.16.0: options that -Sync applies itself after the run, so they aren't passed to the run
$subSyncOnly = @('Keep', 'KeepDays', 'Feed', 'FeedBase')   # 1.23.0: the feed too
# The file where a subscription's runs record what they downloaded (for -Keep / -KeepDays)
function Get-SubFileList($s) {
    $h = [BitConverter]::ToString([Security.Cryptography.SHA1]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes([string]$s.Url))).Replace('-', '').Substring(0, 10)
    Join-Path $s.Out ".ytdl-sub-$h.txt"
}
function Read-Subs {
    if (-not (Test-Path -LiteralPath $subsFile)) { return }
    try { (Get-Content -LiteralPath $subsFile -Raw -Encoding UTF8 | ConvertFrom-Json).Subs | Where-Object { $_ } }
    catch { Write-Host "[ytdl] Can't read $subsFile ($($_.Exception.Message)). Fix or delete it." -ForegroundColor Red; exit 1 }
}
function Save-Subs($list) {
    New-Item -ItemType Directory -Force (Split-Path $subsFile) | Out-Null
    $tmp = "$subsFile.tmp"
    ConvertTo-Json -InputObject ([ordered]@{ Version = 1; Subs = @($list) }) -Depth 5 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $subsFile -Force
}
# A subscription's options as ytdl arguments (switches as -Name, values as -Name value)
function Get-SubArgs($s, [switch]$ForRun) {
    $a = @($s.Url, '-Out', $s.Out)
    if ($s.Options) {
        foreach ($p in $s.Options.PSObject.Properties) {
            if ($ForRun -and $p.Name -in $subSyncOnly) { continue }
            if ($p.Value -is [bool]) { if ($p.Value) { $a += "-$($p.Name)" } }
            # 1.18.0: a value starting with - (-YtdlpArgs, a -Match pattern) goes as -Name:value, or pwsh -File
            # reads it as a parameter name (any "-x:y" or a bare "-s" is taken as one)
            elseif ("$($p.Value)" -like '-*') { $a += "-$($p.Name):$($p.Value)" }
            else { $a += @("-$($p.Name)", [string]$p.Value) }
        }
    }
    if ($ForRun) { $a += @('-FileList', (Get-SubFileList $s)) }
    $a
}
# PowerShell 7 reads ISO dates from JSON as [datetime]; 5.1 keeps them as text
function Format-When($v) { if ($v -is [datetime]) { $v.ToString('yyyy-MM-dd HH:mm') } else { ("$v" -replace 'T', ' ') -replace ':\d\d$', '' } }
function Format-SubOpts($s) { ((Get-SubArgs $s) | Select-Object -Skip 3) -join ' ' }
function Resolve-SubRef([string]$ref) {
    $all = @(Read-Subs)
    if ($ref -match '^\d+$') { $n = [int]$ref; if ($n -ge 1 -and $n -le $all.Count) { return $all[$n - 1].Url }; return $null }
    $ref
}
function Get-ArchiveLines([string]$dir) {
    $f = Join-Path $dir '.ytdl-archive.txt'
    if (Test-Path -LiteralPath $f) { try { return [IO.File]::ReadAllLines($f).Count } catch { } }
    0
}
# The options given on this command line that a subscription or the browser button remembers
function Get-GivenOptions($bound) {
    $opts = [ordered]@{}
    foreach ($n in $subOptNames) {
        if (-not $bound.ContainsKey($n)) { continue }
        $v = $bound[$n]
        if ($v -is [System.Management.Automation.SwitchParameter]) { $v = [bool]$v }
        if ($n -eq 'Items') { $v = $ItemsStr }
        if ($n -eq 'Cookies') {
            if (-not (Test-Path -LiteralPath $v)) { Write-Host "Cookies file not found: $v" -ForegroundColor Red; exit 1 }
            $v = (Resolve-Path -LiteralPath $v).Path
        }
        $opts[$n] = $v
    }
    $opts
}

# ---- 1.16.0: filters -----------------------------------------------------------------------------
# Checked here, before -Subscribe saves them. Applied twice in a run: to the up-front scan (so the
# estimate and the worker split leave filtered videos out) and as yt-dlp --match-filters/--dateafter
# (so a video the scan couldn't judge is still filtered when yt-dlp sees its details).
function ConvertTo-AfterDate([string]$s) {
    $s = "$s".Trim()
    if ($s -match '^(\d{4})-?(\d{2})-?(\d{2})$') { try { return [datetime]::new([int]$Matches[1], [int]$Matches[2], [int]$Matches[3]) } catch { return $null } }
    if ($s -match '^(\d+)\s*(day|week|month|year)s?$') {
        $n = [int]$Matches[1]; $d = (Get-Date).Date
        switch ($Matches[2]) { 'day' { return $d.AddDays(-$n) } 'week' { return $d.AddDays(-7 * $n) } 'month' { return $d.AddMonths(-$n) } 'year' { return $d.AddYears(-$n) } }
    }
    $null
}
$afterDate = $null
if ($After) {
    $afterDate = ConvertTo-AfterDate $After
    if (-not $afterDate) { Write-Host "-After needs a date such as 2026-10-01, or a span such as `"30 days`", `"2 weeks`" or `"6 months`"." -ForegroundColor Red; exit 1 }
}
foreach ($rx in @(@('Match', $Match), @('Exclude', $Exclude))) {
    if ($rx[1]) { try { [void][regex]::new($rx[1]) } catch { Write-Host "-$($rx[0]) isn't a valid pattern: $($rx[1])" -ForegroundColor Red; exit 1 } }
}
if ($MinMinutes -lt 0 -or $MaxMinutes -lt 0 -or ($MaxMinutes -gt 0 -and $MaxMinutes -lt $MinMinutes)) {
    Write-Host "-MinMinutes and -MaxMinutes must be 0 or more, with -MaxMinutes at least -MinMinutes." -ForegroundColor Red; exit 1
}
if (($Keep -gt 0 -or $KeepDays -gt 0) -and -not $Subscribe -and -not $BrowserButton -and $Worker -eq 0 -and -not $FileList) {
    Write-Host "[ytdl] -Keep and -KeepDays apply to subscriptions (they run after each -Sync); ignored for this run." -ForegroundColor DarkYellow
}
$hasFilters = ($MinMinutes -gt 0 -or $MaxMinutes -gt 0 -or $Match -or $Exclude -or $afterDate)

# ---- 1.16.0: browser button (ytdl:// links) --------------------------------------------------------
# -BrowserButton on registers ytdl:// for this Windows user (HKCU\Software\Classes\ytdl) and writes a
# page with two bookmarklets: "ytdl" (download the open YouTube page) and "ytdl +sub" (subscribe to it),
# using the options given with -BrowserButton. The browser asks before opening ytdl the first time.
# A link only ever names a YouTube page: the check at the top of the script refuses extra options,
# and -FromLink below accepts only https YouTube URLs without spaces or quotes.
$linkScheme = if ($env:YTDL_LINKSCHEME) { $env:YTDL_LINKSCHEME } else { 'ytdl' }
$linkFile = Join-Path (Split-Path $subsFile) 'browser-button.json'
$linkPage = Join-Path (Split-Path $subsFile) 'browser-button.html'
$linkKey  = "HKCU:\Software\Classes\$linkScheme"
if ($BrowserButton) {
    if ($BrowserButton -eq 'off') {
        Remove-Item -LiteralPath $linkKey -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $linkFile, $linkPage -Force -ErrorAction SilentlyContinue
        Write-Host "Browser button removed: $($linkScheme):// links no longer open ytdl. Delete the two bookmarks from your browser yourself." -ForegroundColor Green
        exit 0
    }
    $opts = Get-GivenOptions $PSBoundParameters
    New-Item -ItemType Directory -Force (Split-Path $linkFile) | Out-Null
    ConvertTo-Json -InputObject ([ordered]@{ Version = 1; Out = [IO.Path]::GetFullPath($Out); Options = $opts }) -Depth 4 | Set-Content -LiteralPath $linkFile -Encoding UTF8
    $exe = (Get-Process -Id $PID).Path
    New-Item -Path $linkKey -Force -Value "URL:$linkScheme link (ytdl)" | Out-Null
    New-ItemProperty -Path $linkKey -Name 'URL Protocol' -Value '' -Force | Out-Null
    New-Item -Path "$linkKey\shell\open\command" -Force -Value "`"$exe`" -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -FromLink `"%1`"" | Out-Null
    $jsDl  = "javascript:location.href='$($linkScheme):download?'+encodeURIComponent(location.href)"
    $jsSub = "javascript:location.href='$($linkScheme):subscribe?'+encodeURIComponent(location.href)"
    $o = (@($opts.Keys) | ForEach-Object { if ($opts[$_] -is [bool]) { "-$_" } else { "-$_ $($opts[$_])" } }) -join ' '
    $enc = { param($t) [Net.WebUtility]::HtmlEncode($t) }
    @"
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>ytdl browser buttons</title>
<style>:root{color-scheme:light dark;--bg:#f6f7f9;--fg:#18202c;--mut:#5a6577;--acc:#2350d8;--card:#fff;--rule:#d9dee7}
@media (prefers-color-scheme:dark){:root{--bg:#10151f;--fg:#e5eaf3;--mut:#9aa6ba;--acc:#7b9cff;--card:#18202f;--rule:#2b3548}}
body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.55 system-ui,-apple-system,"Segoe UI",sans-serif;padding:32px 16px}
main{max-width:640px;margin:0 auto;display:grid;gap:20px}h1{margin:0;font-size:1.6rem}p,li{color:var(--mut)}
.btns{display:flex;gap:12px;flex-wrap:wrap}.btns a{display:inline-block;padding:10px 18px;border-radius:8px;background:var(--acc);color:#fff;font-weight:600;text-decoration:none}
.card{background:var(--card);border:1px solid var(--rule);border-radius:10px;padding:16px 20px}code{font-family:ui-monospace,Consolas,monospace;font-size:.9em}</style></head>
<body><main>
<h1>ytdl browser buttons</h1>
<p>Drag each button to your browser's bookmarks bar (show the bar with Ctrl+Shift+B). Then, on a YouTube video, playlist or channel page, click one.</p>
<div class="btns"><a href="$(& $enc $jsDl)">ytdl</a><a href="$(& $enc $jsSub)">ytdl +sub</a></div>
<div class="card"><ul>
<li><b>ytdl</b> downloads the page you're on. <b>ytdl +sub</b> subscribes to it, so <code>ytdl -Sync</code> (or the schedule) fetches its new videos.</li>
<li>The first time, the browser asks whether to open ytdl; you can let it remember the answer.</li>
<li>A window opens with the download's progress. If another download is already using the folder, this one waits for it.</li>
<li>Saves to: <code>$(& $enc ([IO.Path]::GetFullPath($Out)))</code>$(if ($o) { "<br>Options: <code>$(& $enc $o)</code>" })</li>
<li>To change these, run <code>ytdl -BrowserButton on</code> again with other options. To remove: <code>ytdl -BrowserButton off</code>.</li>
</ul></div></main></body></html>
"@ | Set-Content -LiteralPath $linkPage -Encoding UTF8
    Write-Host "[ytdl] Browser button ready: $($linkScheme):// links now open ytdl." -ForegroundColor Green
    Write-Host "  Downloads go to $([IO.Path]::GetFullPath($Out))$(if ($o) { " with $o" })."
    Write-Host "  Opening $linkPage : drag its two buttons to your bookmarks bar." -ForegroundColor DarkGray
    if (-not $env:YTDL_NOOPEN) { try { Start-Process $linkPage } catch { } }
    exit 0
}

# ---- 1.20.0: a queue of links for the running ytdl --------------------------------------------------
# %LOCALAPPDATA%\ytdl\queue.json holds links added with -Add (or by the browser button) while a download
# runs; that run works through them when it's done, one at a time in its window, each a normal ytdl run
# with the options it was added with. runs\<pid>.json records each top-level run (the PowerShell
# launcher runs ytdl inside your own shell, so the process list can't tell). A record counts only while
# that process, with the same start time, is alive and still holds its folder lock (a sync, between its
# runs, holds none). YTDL_STATE moves both (tests).
$stateDir  = if ($env:YTDL_STATE) { $env:YTDL_STATE } else { Join-Path $env:LOCALAPPDATA 'ytdl' }
$linkQueueFile = Join-Path $stateDir 'queue.json'
$runsDir   = Join-Path $stateDir 'runs'

# ---- 1.25.0 limit guard: one breaker and one hourly budget for the whole PC ------------------
# YouTube limits per IP and per account, not per folder, so every ytdl run and worker (and the
# benchmarks, bench\lib-limit.ps1) share <state>\pace.json. Times are Unix seconds. Writes go
# through a named mutex, so workers can't lose each other's entries.
#   CooldownUntil  no YouTube requests before this (the breaker is open)
#   Opens          breaker openings in the last 24 h: each doubles the next cooldown (1 h .. 24 h)
#   Events         bot checks / rate limits in the last 24 h (two within 10 min open the breaker)
#   ProbeNeeded    after a cooldown, check one video before a full run
#   Level/LevelAt  the pacing level the last trip reached (decays 1 level per 2 clean hours)
#   LogIn/LogOut   video starts in the last hour, signed in / signed out
$globalPaceFile = Join-Path $stateDir 'pace.json'
$breakerBaseSec = 3600; $breakerMaxSec = 86400
$limitPattern   = 'confirm you.?re not a bot|not a bot|HTTP Error 429|Too Many Requests|rate.?limit|isn.t available, try again later'
$limit429Pattern = '429|Too Many Requests|rate.?limit|try again later'
# Lines that echo a title or a file name, where those words may appear without meaning anything
$limitSkipPattern = '^\[(download\] Destination|Merger|ExtractAudio|Metadata|EmbedThumbnail|MoveFiles|Fixup\w*|info\] Writing)'
function Get-Epoch { [double][DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
function Read-GlobalPace {
    $g = @{ Scheme = 3; CooldownUntil = 0.0; Kind = ''; ProbeNeeded = $false; Level = 0; LevelAt = 0.0; Events = @(); Opens = @(); LogIn = @(); LogOut = @() }
    try {
        $j = [IO.File]::ReadAllText($globalPaceFile) | ConvertFrom-Json
        foreach ($p in $j.PSObject.Properties) { $g[$p.Name] = $p.Value }
    } catch { }
    foreach ($k in 'Events', 'Opens', 'LogIn', 'LogOut') { $g[$k] = @(@($g[$k]) | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ }) }
    foreach ($k in 'CooldownUntil', 'LevelAt') { $g[$k] = [double]$g[$k] }
    $g.Level = [int]$g.Level; $g.ProbeNeeded = [bool]$g.ProbeNeeded
    $g
}
# Read, change (scriptblock gets the hashtable and now), prune, write; returns the new state.
function Update-GlobalPace([scriptblock]$change) {
    $m = $null; $own = $false
    try { $m = New-Object Threading.Mutex($false, 'Local\ytdl-pace'); try { $own = $m.WaitOne(5000) } catch [Threading.AbandonedMutexException] { $own = $true } } catch { }
    try {
        $g = Read-GlobalPace; $now = Get-Epoch
        $null = & $change $g $now
        foreach ($k in 'Events', 'Opens') { $g[$k] = @($g[$k] | Where-Object { $_ -gt $now - 86400 }) }
        foreach ($k in 'LogIn', 'LogOut') { $g[$k] = @($g[$k] | Where-Object { $_ -gt $now - 3600 } | ForEach-Object { [math]::Round($_) }) }
        try {
            if (-not (Test-Path -LiteralPath $stateDir)) { New-Item -ItemType Directory -Force $stateDir | Out-Null }
            [IO.File]::WriteAllText($globalPaceFile, ($g | ConvertTo-Json -Depth 3 -Compress))
        } catch { }
        $g
    } finally { if ($own) { try { $m.ReleaseMutex() } catch { } }; if ($m) { $m.Dispose() } }
}
function Get-BreakerLeft($g) { [math]::Max(0.0, [double]$g.CooldownUntil - (Get-Epoch)) }
function Get-BreakerText($g) {
    $until = [DateTimeOffset]::FromUnixTimeSeconds([int64]$g.CooldownUntil).LocalDateTime
    $why = switch ($g.Kind) { '429' { 'a rate limit (HTTP 429)' } 'max' { 'bot checks at the slowest pacing' } 'budget' { 'the hourly budget' } default { 'repeated bot checks' } }
    $day = if ($until.Date -ne (Get-Date).Date) { $until.ToString('ddd ') } else { '' }
    "YouTube limit guard: no downloads until $day$($until.ToString('HH:mm')) ($([math]::Ceiling((Get-BreakerLeft $g) / 60)) min left) after $why on this PC. Starting earlier would likely extend the block (-IgnoreCooldown starts anyway). Closing this window is fine: a run started before then stops with this message, and the first one after it checks one video before the rest."
}
# Open the breaker. If it's already open (another worker got there first), it stays as it is.
function Open-Breaker([string]$kind) {
    $null = Update-GlobalPace {
        param($g, $now)
        if ($g.CooldownUntil -gt $now) { return }
        $n = @($g.Opens | Where-Object { $_ -gt $now - 86400 }).Count
        $g.CooldownUntil = $now + [math]::Min($breakerMaxSec, $breakerBaseSec * [math]::Pow(2, $n))
        $g.Opens = @($g.Opens) + $now; $g.Kind = $kind; $g.ProbeNeeded = $true
    }
}
# Record a bot check / rate limit; returns how many happened on this PC in the last 10 min.
# Hits within 60 s of the last one are one episode (all workers see the same block at once).
function Add-PaceEvent([string]$kind, [int]$level) {
    $r = Update-GlobalPace {
        param($g, $now)
        $last = ($g.Events | Measure-Object -Maximum).Maximum
        if (-not $last -or $now - $last -ge 60) { $g.Events = @($g.Events) + $now }
        $g.Kind = $kind
        $held = $g.Level - [math]::Floor(($now - $g.LevelAt) / 7200)
        if ($level -ge $held) { $g.Level = $level; $g.LevelAt = $now }
    }
    $now = Get-Epoch
    @($r.Events | Where-Object { $_ -gt $now - 600 }).Count
}
function Lock-Queue {
    New-Item -ItemType Directory -Force $stateDir | Out-Null
    for ($i = 0; $i -lt 100; $i++) { try { return [IO.File]::Open("$linkQueueFile.lock", 'OpenOrCreate', 'ReadWrite', 'None') } catch { Start-Sleep -Milliseconds 100 } }
    throw "The ytdl queue stayed locked for 10 s ($linkQueueFile.lock)."
}
function Read-QueueRaw {
    if (-not (Test-Path -LiteralPath $linkQueueFile)) { return @() }
    try { @((Get-Content -LiteralPath $linkQueueFile -Raw -Encoding UTF8 | ConvertFrom-Json).Items | Where-Object { $_ }) } catch { @() }
}
function Write-QueueRaw($items) { ConvertTo-Json -InputObject ([ordered]@{ Items = @($items) }) -Depth 6 | Set-Content -LiteralPath $linkQueueFile -Encoding UTF8 }
function Add-QueueItem([string]$u, [string]$o, $opts) {
    $l = Lock-Queue
    try { $q = @(Read-QueueRaw) + @([pscustomobject]@{ Url = $u; Out = $o; Options = $opts; Added = (Get-Date).ToString('s') }); Write-QueueRaw $q; $q.Count } finally { $l.Dispose() }
}
function Pop-QueueItem {
    $l = Lock-Queue
    try { $q = @(Read-QueueRaw); if (-not $q.Count) { return $null }; Write-QueueRaw @($q | Select-Object -Skip 1); $q[0] } finally { $l.Dispose() }
}
function Register-Run([string]$what) {
    try { New-Item -ItemType Directory -Force $runsDir | Out-Null
          @{ Pid = $PID; Start = [string](Get-Process -Id $PID).StartTime.Ticks; Out = [IO.Path]::GetFullPath($Out); What = $what } | ConvertTo-Json |
              Set-Content -LiteralPath (Join-Path $runsDir "$PID.json") -Encoding UTF8 } catch { }
}
function Unregister-Run { Remove-Item -LiteralPath (Join-Path $runsDir "$PID.json") -Force -ErrorAction SilentlyContinue }
function Get-ActiveRuns {
    @(Get-ChildItem -LiteralPath $runsDir -Filter *.json -ErrorAction SilentlyContinue | ForEach-Object {
        $r = $null; try { $r = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json } catch { }
        $p = $null; if ($r) { $p = Get-Process -Id ([int]$r.Pid) -ErrorAction SilentlyContinue }
        $live = $p -and "$($p.StartTime.Ticks)" -eq "$($r.Start)"
        if ($live -and $r.What -ne 'sync') {   # still downloading? its folder lock says (a crashed in-shell run leaves a record)
            try { $t = [IO.File]::Open((Join-Path $r.Out '.ytdl.lock'), 'Open', 'ReadWrite', 'None'); $t.Dispose(); $live = $false } catch [IO.FileNotFoundException], [IO.DirectoryNotFoundException] { $live = $false } catch { }
        }
        if ($live) { if ([int]$r.Pid -ne $PID) { $r } } else { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
    })
}
# At the end of a top-level run (after its folder lock is released): the queued links, one by one.
function Invoke-QueueDrain {
    if ($env:YTDL_IN_QUEUE -eq '1' -or $env:YTDL_IN_SYNC -eq '1' -or $Worker -gt 0 -or $Estimate) { return 0 }
    $worst = 0; $hostExe = (Get-Process -Id $PID).Path
    while (-not (Test-Path $stopFile)) {
        $it = Pop-QueueItem; if (-not $it) { break }
        $left = @(Read-QueueRaw).Count
        Microsoft.PowerShell.Utility\Write-Host "`n=== Next from the queue: $($it.Url)$(if ($left) { " ($left more after this)" }) ===" -ForegroundColor Cyan
        $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath) + @(Get-SubArgs $it)
        $env:YTDL_IN_QUEUE = '1'
        try { & $hostExe @a; $c = $LASTEXITCODE } finally { Remove-Item Env:YTDL_IN_QUEUE -ErrorAction SilentlyContinue }
        if ($c -eq 2) { $worst = 2; Microsoft.PowerShell.Utility\Write-Host "[ytdl] That download was stopped; the rest of the queue stays (ytdl -Queue)." -ForegroundColor Yellow; break }
        if ($c -eq 75) { $worst = 75; Microsoft.PowerShell.Utility\Write-Host "[ytdl] YouTube limit guard is on; the rest of the queue stays (ytdl -Queue)." -ForegroundColor Yellow; break }   # 1.25.0
        if ($c -ne 0 -and $worst -eq 0) { $worst = 1 }
    }
    $worst
}
# ---- 1.23.0: -History ------------------------------------------------------------------------------
# Every finished file adds "unix time<TAB>id<TAB>height<TAB>path<TAB>title" to %LOCALAPPDATA%\ytdl\history.tsv
# (yt-dlp --print-to-file after the move, set below). -History shows the newest; size comes from the disk.
$historyFile = Join-Path $stateDir 'history.tsv'
if ($History) {
    $want = if ($Url -match '^\d+$') { [int]$Url } else { 20 }
    if (-not (Test-Path -LiteralPath $historyFile)) { Write-Host "[ytdl] No history yet. Downloads from ytdl 1.23.0 on are listed here." -ForegroundColor DarkGray; exit 0 }
    $rows = foreach ($l in [IO.File]::ReadAllLines($historyFile)) {
        $p = $l -split "`t", 5
        if ($p.Count -lt 5 -or $p[0] -notmatch '^\d+$') { continue }
        if ($Match -and $p[4] -notmatch $Match) { continue }
        [pscustomobject]@{ T = [long]$p[0]; Id = $p[1]; H = $p[2]; Path = $p[3]; Title = $p[4] }
    }
    $rows = @($rows | Sort-Object T | Select-Object -Last $want)
    if (-not $rows.Count) { Write-Host "[ytdl] Nothing in the history$(if ($Match) { " matches '$Match'" })." -ForegroundColor DarkGray; exit 0 }
    $w = [math]::Max(40, (Get-ConsoleWidth) - 1)
    Write-Host ("{0,-16} {1,6} {2,9}  {3}" -f 'Downloaded', 'Height', 'Size', 'Title  (folder)') -ForegroundColor DarkGray
    foreach ($hr in $rows) {
        $when = [DateTimeOffset]::FromUnixTimeSeconds($hr.T).LocalDateTime.ToString('yyyy-MM-dd HH:mm')
        $h = if ($hr.H -match '^\d+$') { "$($hr.H)p" } elseif ($hr.Path -match '\.(mp3|m4a|opus|ogg|flac|wav)$') { 'audio' } else { '?' }
        $size = if (Test-Path -LiteralPath $hr.Path) { $b = (Get-Item -LiteralPath $hr.Path).Length; if ($b -ge 1GB) { '{0:N2} GB' -f ($b / 1GB) } else { '{0:N0} MB' -f ($b / 1MB) } } else { 'deleted' }
        $line = "{0,-16} {1,6} {2,9}  {3}  ({4})" -f $when, $h, $size, $hr.Title, (Split-Path $hr.Path -Parent)
        if ($line.Length -gt $w) { $line = $line.Substring(0, $w - 3) + '...' }
        Write-Host $line -ForegroundColor $(if ($size -eq 'deleted') { 'DarkGray' } else { 'Gray' })
    }
    Write-Host "[ytdl] $($rows.Count) shown. All of it: $historyFile" -ForegroundColor DarkGray
    exit 0
}

if ($ListQueue -or $ClearQueue) {
    if ($ClearQueue) {
        $l = Lock-Queue; try { $n = @(Read-QueueRaw).Count; Write-QueueRaw @() } finally { $l.Dispose() }
        Write-Host "[ytdl] Removed $n link(s) from the queue." -ForegroundColor Green; exit 0
    }
    $act = @(Get-ActiveRuns); $q = @(Read-QueueRaw)
    if ($act.Count) { foreach ($r in $act) { Write-Host "  Running: $(if ($r.What -eq 'sync') { 'ytdl -Sync' } else { $r.What })  ->  $($r.Out)" -ForegroundColor Cyan } }
    else { Write-Host '  No ytdl download is running.' -ForegroundColor DarkGray }
    if (-not $q.Count) { Write-Host '  The queue is empty. Add to it with: ytdl <url> -Add' -ForegroundColor DarkGray }
    else {
        $i = 0; foreach ($it in $q) { $i++; Write-Host ("  {0}. {1}  ->  {2}  {3}" -f $i, $it.Url, $it.Out, (((Get-SubArgs $it) | Select-Object -Skip 3) -join ' ')) }
        if (-not $act.Count) { Write-Host '  Nothing is running to work through them: run ytdl <url> -Add again, or any download; it takes the queue when it ends.' -ForegroundColor Yellow }
    }
    exit 0
}

if ($FromLink) {
    try { $Host.UI.RawUI.WindowTitle = 'ytdl' } catch { }
    function Close-LinkWindow([int]$code) {
        Write-Host ''; Write-Host 'Press any key to close this window.' -ForegroundColor DarkGray
        try { [void][Console]::ReadKey($true) } catch { }
        exit $code
    }
    if ($FromLink -notmatch "^$([regex]::Escape($linkScheme)):(?://)?(download|subscribe)/?\?(.+)$") {
        Write-Host "[ytdl] Not a ytdl link this version understands: $FromLink" -ForegroundColor Red; Close-LinkWindow 1
    }
    $action = $Matches[1]
    $target = try { [Uri]::UnescapeDataString($Matches[2]) } catch { '' }
    if ($target -notmatch '^https://(www\.|m\.|music\.)?(youtube\.com|youtu\.be)/[^\s"]{1,400}$') {
        Write-Host "[ytdl] The browser button only works on YouTube pages (got: $target)." -ForegroundColor Yellow; Close-LinkWindow 1
    }
    $cfg = $null
    try { $cfg = Get-Content -LiteralPath $linkFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    if (-not $cfg) { Write-Host "[ytdl] The browser button isn't set up (run ytdl -BrowserButton on)." -ForegroundColor Yellow; Close-LinkWindow 1 }
    try { $Host.UI.RawUI.WindowTitle = "ytdl: $target" } catch { }
    $a = @(Get-SubArgs ([pscustomobject]@{ Url = $target; Out = $cfg.Out; Options = $cfg.Options }))
    if ($action -eq 'subscribe') { $a += '-Subscribe' }
    else {
        # 1.20.0: a download is running (any folder): queue this one for it and close, instead of a second window
        if (@(Get-ActiveRuns).Count) {
            $n = Add-QueueItem $target ([IO.Path]::GetFullPath($cfg.Out)) $cfg.Options
            Write-Host "[ytdl] Queued as number $n. It downloads when the current ytdl download finishes, in that window." -ForegroundColor Green
            Start-Sleep -Seconds 4; exit 0
        }
        # Wait for a download already running in that folder (a second click) instead of failing.
        $lockFile = Join-Path $cfg.Out '.ytdl.lock'; $said = $false
        New-Item -ItemType Directory -Force $cfg.Out | Out-Null
        while ($true) {
            try { $fs = [IO.File]::Open($lockFile, 'OpenOrCreate', 'ReadWrite', 'None'); $fs.Dispose(); break }
            catch {
                if (-not $said) { Write-Host "[ytdl] Another download is using $($cfg.Out); this one starts when it finishes." -ForegroundColor Cyan; $said = $true }
                if (Test-Path $stopFile) { Write-Host "[ytdl] Stop requested; not starting." -ForegroundColor Yellow; Close-LinkWindow 2 }
                Start-Sleep -Seconds 5
            }
        }
    }
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @a
    $code = $LASTEXITCODE
    if ($action -eq 'subscribe' -and $code -eq 0) { Write-Host "  (Run ytdl -Sync, or set ytdl -Schedule daily, to download its videos.)" -ForegroundColor DarkGray }
    Close-LinkWindow $code
}

if ($Subscribe -or $Unsubscribe) {
    if (-not $Url) { Write-Host "Usage: ytdl <channel or playlist url> -Subscribe [options]   |   ytdl <url or number> -Unsubscribe" -ForegroundColor Yellow; exit 1 }
    $all = @(Read-Subs)
    if ($Unsubscribe) {
        $target = Resolve-SubRef $Url
        # 1.21.1: not $keep: that is the [int] -Keep parameter (names ignore case), so a list failed to convert
        $remaining = @($all | Where-Object { $_.Url -ne $target })
        if (-not $target -or $remaining.Count -eq $all.Count) { Write-Host "Not subscribed: $Url (see ytdl -Subscriptions)" -ForegroundColor Yellow; exit 1 }
        Save-Subs $remaining
        Write-Host "Unsubscribed: $target. Downloaded files and the archive are kept." -ForegroundColor Green
        exit 0
    }
    if ($Url -match '^\d+$') { Write-Host "-Subscribe needs a channel or playlist URL." -ForegroundColor Yellow; exit 1 }
    $opts = Get-GivenOptions $PSBoundParameters
    $prev = $all | Where-Object { $_.Url -eq $Url } | Select-Object -First 1
    $entry = [ordered]@{
        Url = $Url; Out = [IO.Path]::GetFullPath($Out); Options = $opts
        Added = $(if ($prev) { $prev.Added } else { (Get-Date).ToString('s') })
        LastSync = $(if ($prev) { $prev.LastSync } else { $null })
        LastNew = $(if ($prev) { $prev.LastNew } else { $null })
        LastExit = $(if ($prev) { $prev.LastExit } else { $null })
    }
    $list = @(foreach ($s in $all) { if ($s.Url -eq $Url) { $entry } else { $s } })
    if (-not $prev) { $list = @($list) + $entry }
    Save-Subs $list
    $verb = if ($prev) { 'Updated' } else { 'Subscribed' }
    Write-Host "[ytdl] $($verb): $Url" -ForegroundColor Green
    Write-Host "  Files go to $($entry.Out); its archive skips videos already there."
    $o = (@($opts.Keys) | ForEach-Object { if ($opts[$_] -is [bool]) { "-$_" } else { "-$_ $($opts[$_])" } }) -join ' '
    if ($o) { Write-Host "  Options: $o" }
    if ($opts.Contains('Keep') -or $opts.Contains('KeepDays')) {
        Write-Host "  Retention: after each sync, older videos are deleted. It applies only to files this subscription downloads from now on; the archive keeps deleted ones from coming back." -ForegroundColor Yellow
    }
    if ($prev) { Write-Host "  (These replace the options it had before$(if ($prev.Options) { ": " + (Format-SubOpts $prev) } else { '' }).)" -ForegroundColor DarkGray }
    if ($isChannelTab -and -not $opts.Contains('Items') -and -not $opts.Contains('After')) {
        Write-Host "  The first sync downloads the whole channel. To start from recent videos instead, subscribe again with -After `"30 days`" or -Items 1-20 (channels list newest first)." -ForegroundColor Yellow
    }
    $hasTask = $null -ne (Get-ScheduledTask -TaskName $subTask -ErrorAction SilentlyContinue)
    Write-Host ("  Download now: ytdl -Sync   (preview: ytdl -Sync -Estimate)" + $(if (-not $hasTask) { "   |   every day: ytdl -Schedule daily" } else { '' })) -ForegroundColor DarkGray
    exit 0
}

if ($Subscriptions) {
    $all = @(Read-Subs)
    if (-not $all.Count) { Write-Host "No subscriptions. Add one: ytdl <channel or playlist url> -Subscribe [options]" }
    $i = 0
    foreach ($s in $all) {
        $i++
        Write-Host "$i. $($s.Url)" -ForegroundColor Cyan
        $o = Format-SubOpts $s
        Write-Host "   -> $($s.Out)$(if ($o) { "   $o" })"
        if ($s.LastSync) { Write-Host "   last sync $(Format-When $s.LastSync): $($s.LastNew) new, exit $($s.LastExit)" -ForegroundColor DarkGray }
        else { Write-Host "   not synced yet (added $(Format-When $s.Added))" -ForegroundColor DarkGray }
    }
    $t = Get-ScheduledTask -TaskName $subTask -ErrorAction SilentlyContinue
    if ($t) {
        $ti = $t | Get-ScheduledTaskInfo
        $last = if ($ti.LastRunTime -and $ti.LastRunTime.Year -gt 2000) { "; last run $($ti.LastRunTime), result $($ti.LastTaskResult)" } else { '' }
        Write-Host "Schedule: next sync $($ti.NextRunTime)$last. Remove with ytdl -Schedule off." -ForegroundColor Green
    } else { Write-Host "Schedule: none. Sync automatically with ytdl -Schedule daily [-At 03:00]." -ForegroundColor DarkGray }
    exit 0
}

if ($Schedule) {
    $t = Get-ScheduledTask -TaskName $subTask -ErrorAction SilentlyContinue
    if ($Schedule -eq 'off') {
        if ($t) { Unregister-ScheduledTask -TaskName $subTask -Confirm:$false; Write-Host "Scheduled sync removed." -ForegroundColor Green }
        else { Write-Host "No scheduled sync was set." }
        exit 0
    }
    $time = $null
    try { $time = [datetime]::ParseExact($At, 'H:mm', [Globalization.CultureInfo]::InvariantCulture) } catch { }
    if (-not $time) { Write-Host "-At needs a 24-hour time such as 03:00 or 18:30." -ForegroundColor Red; exit 1 }
    # The running host (pwsh or powershell), hidden; the task runs only while you're signed in to
    # Windows, because -Browser reads your browser's YouTube sign-in from your profile.
    $hostExe = (Get-Process -Id $PID).Path
    $action = New-ScheduledTaskAction -Execute $hostExe -WorkingDirectory (Split-Path $PSCommandPath) `
                -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -Sync"
    if ($Schedule -eq 'hourly') { $trigger = New-ScheduledTaskTrigger -Once -At $time -RepetitionInterval (New-TimeSpan -Hours 1) }
    else { $trigger = New-ScheduledTaskTrigger -Daily -At $time }
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                -ExecutionTimeLimit (New-TimeSpan -Hours 12) -MultipleInstances IgnoreNew
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $subTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force `
        -Description 'ytdl: download new videos from your subscriptions (ytdl -Subscriptions lists them; ytdl -Schedule off removes this task)' | Out-Null
    $ti = Get-ScheduledTask -TaskName $subTask | Get-ScheduledTaskInfo
    Write-Host "[ytdl] Sync scheduled $Schedule$(if ($Schedule -eq 'hourly') { ' from' } else { ' at' }) $($time.ToString('HH:mm')). Next run: $($ti.NextRunTime)." -ForegroundColor Green
    Write-Host "  It runs while you're signed in to Windows, in a hidden window; a missed run starts when the PC is next on."
    Write-Host "  Each subscription's log: <its folder>\.ytdl-logs. Sync summary: $(Join-Path (Split-Path $subsFile) 'sync.log'). Remove: ytdl -Schedule off" -ForegroundColor DarkGray
    if (-not @(Read-Subs).Count) { Write-Host "  No subscriptions yet: add one with ytdl <channel or playlist url> -Subscribe" -ForegroundColor Yellow }
    exit 0
}

if ($Sync) {
    $all = @(Read-Subs)
    if (-not $all.Count) { Write-Host "No subscriptions. Add one: ytdl <channel or playlist url> -Subscribe [options]"; exit 0 }
    $syncLog = Join-Path (Split-Path $subsFile) 'sync.log'
    function Add-SyncLog([string]$t) { try { Add-Content -LiteralPath $syncLog -Value "$((Get-Date).ToString('s')) $t" -Encoding UTF8 } catch { } }
    # 1.16.0 retention (-Keep N / -KeepDays N). The subscription's runs append "upload_date<TAB>id<TAB>path"
    # for each finished file to its file list (yt-dlp --print-to-file, see -FileList). Only files in
    # that list, inside the subscription's -Out, whose name carries their [id], can be deleted: never
    # anything else in a shared folder such as Videos. Archive lines stay, so they don't come back.
    function Invoke-Retention($s) {
        $keepN = 0; $keepD = 0
        if ($s.Options) {
            if ($s.Options.PSObject.Properties['Keep']) { $keepN = [int]$s.Options.Keep }
            if ($s.Options.PSObject.Properties['KeepDays']) { $keepD = [int]$s.Options.KeepDays }
        }
        if ($keepN -le 0 -and $keepD -le 0) { return 0 }
        $list = Get-SubFileList $s
        if (-not (Test-Path -LiteralPath $list)) { return 0 }
        $root = [IO.Path]::GetFullPath($s.Out).TrimEnd('\') + '\'
        $byId = [ordered]@{}
        foreach ($l in [IO.File]::ReadAllLines($list)) {
            $p = $l -split "`t", 3
            if ($p.Count -lt 3 -or $p[1] -notmatch '^[\w-]{11}$') { continue }
            $byId[$p[1]] = [pscustomobject]@{ Date = $p[0].Trim(); Id = $p[1]; Path = $p[2].Trim() }
        }
        $items = @($byId.Values | Where-Object { Test-Path -LiteralPath $_.Path } | Sort-Object Date -Descending)
        $cut = if ($keepD -gt 0) { (Get-Date).AddDays(-$keepD).ToString('yyyyMMdd') } else { '' }
        $gone = 0; $n = 0
        foreach ($it in $items) {
            $n++
            $old = ($keepN -gt 0 -and $n -gt $keepN) -or ($cut -and $it.Date -match '^\d{8}$' -and $it.Date -lt $cut)
            if (-not $old) { continue }
            $full = [IO.Path]::GetFullPath($it.Path)
            if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { continue }
            if ((Split-Path $full -Leaf) -notlike "*[[]$($it.Id)[]]*") { continue }
            # 1.19.0: and the -Library side files of that episode (.nfo, -thumb.jpg / .jpg)
            $stem = [IO.Path]::Combine([IO.Path]::GetDirectoryName($full), [IO.Path]::GetFileNameWithoutExtension($full))
            foreach ($side in "$stem.nfo", "$stem-thumb.jpg", "$stem.jpg") { if (Test-Path -LiteralPath $side) { Remove-Item -LiteralPath $side -Force -ErrorAction SilentlyContinue } }
            try { Remove-Item -LiteralPath $full -Force; $gone++; Write-Host "  Removed (keeping $(if ($keepN) { "the newest $keepN" } else { "the last $keepD days" })): $(Split-Path $full -Leaf)" -ForegroundColor DarkGray } catch { }
        }
        $live = @($byId.Values | Where-Object { Test-Path -LiteralPath $_.Path } | ForEach-Object { "$($_.Date)`t$($_.Id)`t$($_.Path)" })
        try { [IO.File]::WriteAllLines($list, [string[]]$live, (New-Object Text.UTF8Encoding($false))) } catch { }
        $gone
    }
    # 1.23.0 -Feed: a podcast feed (RSS 2.0) of the files in the subscription's file list that still exist,
    # newest upload first. So -Keep / -KeepDays shape the feed too. Title = the file name without "[id]".
    function Write-SubFeed($s) {
        if (-not $s.Options -or -not ($s.Options.PSObject.Properties['Feed'] -or $s.Options.PSObject.Properties['FeedBase'])) { return $null }
        $base = if ($s.Options.PSObject.Properties['FeedBase']) { ([string]$s.Options.FeedBase).TrimEnd('/') } else { '' }
        $root = [IO.Path]::GetFullPath($s.Out).TrimEnd('\')
        $byId = [ordered]@{}
        $list = Get-SubFileList $s
        if (Test-Path -LiteralPath $list) {
            foreach ($l in [IO.File]::ReadAllLines($list)) {
                $p = $l -split "`t", 3
                if ($p.Count -lt 3 -or $p[1] -notmatch '^[\w-]{11}$') { continue }
                $path = $p[2].Trim()
                if ($path -match '\.(json|nfo|jpg|webp|png|vtt|srt)$' -or -not (Test-Path -LiteralPath $path)) { continue }
                $byId[$p[1]] = [pscustomobject]@{ Date = $p[0].Trim(); Id = $p[1]; Path = [IO.Path]::GetFullPath($path) }
            }
        }
        $types = @{ '.mp4' = 'video/mp4'; '.m4a' = 'audio/mp4'; '.mp3' = 'audio/mpeg'; '.opus' = 'audio/ogg'; '.ogg' = 'audio/ogg'; '.webm' = 'video/webm'; '.mkv' = 'video/x-matroska'; '.flac' = 'audio/flac'; '.wav' = 'audio/wav' }
        $esc = { param($t) [Security.SecurityElement]::Escape([string]$t) }
        $sb = New-Object Text.StringBuilder
        [void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
        [void]$sb.AppendLine('<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">')
        [void]$sb.AppendLine('<channel>')
        [void]$sb.AppendLine("  <title>$(& $esc (Split-Path $root -Leaf))</title>")
        [void]$sb.AppendLine("  <link>$(& $esc $s.Url)</link>")
        [void]$sb.AppendLine("  <description>$(& $esc "Downloaded by ytdl from $($s.Url)")</description>")
        [void]$sb.AppendLine("  <lastBuildDate>$((Get-Date).ToUniversalTime().ToString('r'))</lastBuildDate>")
        $n = 0
        foreach ($it in @($byId.Values | Sort-Object Date -Descending)) {
            $fi = Get-Item -LiteralPath $it.Path
            $title = ([IO.Path]::GetFileNameWithoutExtension($fi.Name) -replace "\s*\[$([regex]::Escape($it.Id))\]", '').Trim()
            $when = try { [datetime]::ParseExact($it.Date, 'yyyyMMdd', [Globalization.CultureInfo]::InvariantCulture) } catch { $fi.LastWriteTime }
            $rel = if ($fi.FullName.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { $fi.FullName.Substring($root.Length + 1) } else { $null }
            $href = if ($base -and $rel) { $base + '/' + ((($rel -split '\\') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/') } else { ([Uri]$fi.FullName).AbsoluteUri }
            $type = $types[$fi.Extension.ToLowerInvariant()]; if (-not $type) { $type = 'application/octet-stream' }
            [void]$sb.AppendLine('  <item>')
            [void]$sb.AppendLine("    <title>$(& $esc $title)</title>")
            [void]$sb.AppendLine("    <link>https://www.youtube.com/watch?v=$($it.Id)</link>")
            [void]$sb.AppendLine("    <guid isPermaLink=`"false`">yt:$($it.Id)</guid>")
            [void]$sb.AppendLine("    <pubDate>$($when.ToString('r'))</pubDate>")
            [void]$sb.AppendLine("    <enclosure url=`"$(& $esc $href)`" length=`"$($fi.Length)`" type=`"$type`"/>")
            [void]$sb.AppendLine('  </item>')
            $n++
        }
        [void]$sb.AppendLine('</channel>')
        [void]$sb.AppendLine('</rss>')
        $out = Join-Path $root 'feed.xml'
        try { [IO.File]::WriteAllText("$out.tmp", $sb.ToString(), (New-Object Text.UTF8Encoding($false))); Move-Item -LiteralPath "$out.tmp" -Destination $out -Force } catch { return $null }
        "$n episode(s) in $out"
    }
    Remove-Item $stopFile -Force -ErrorAction SilentlyContinue
    $hostExe = (Get-Process -Id $PID).Path
    $mode = if ($Estimate) { ' (estimate only)' } else { '' }
    Add-SyncLog "sync start$($mode): $($all.Count) subscription(s), pid $PID"
    $env:YTDL_IN_SYNC = '1'   # 1.18.0: the runs below don't notify; this sync sends one summary
    Register-Run 'sync'        # 1.20.0: -Add while a sync runs queues for it
    $worst = 0; $total = 0; $i = 0; $done = @{}
    foreach ($s in $all) {
        $i++
        if (Test-Path $stopFile) { Write-Host "[ytdl] Stop requested; remaining subscriptions skipped." -ForegroundColor Yellow; $worst = 2; break }
        Write-Host ''
        Write-Host "[ytdl] Sync $i of $($all.Count)$($mode): $($s.Url)" -ForegroundColor Cyan
        $before = Get-ArchiveLines $s.Out
        $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath) + (Get-SubArgs $s -ForRun)
        if ($Estimate) { $a += '-Estimate' }
        if ($AutoUpdate) { $a += '-AutoUpdate' }
        & $hostExe @a
        $code = $LASTEXITCODE
        $new = [math]::Max(0, (Get-ArchiveLines $s.Out) - $before)
        $total += $new
        $removed = 0
        if (-not $Estimate -and $code -ne 2) {
            $removed = Invoke-Retention $s
            $fd = Write-SubFeed $s; if ($fd) { Write-Host "  Feed: $fd" -ForegroundColor DarkGray }   # 1.23.0
        }
        $done[$s.Url] = @{ Code = $code; New = $new }
        Add-SyncLog "$($s.Url): exit $code, $new new$(if ($removed) { ", $removed removed by retention" })"
        if ($code -eq 2) { $worst = 2; Write-Host "[ytdl] That run was stopped; remaining subscriptions skipped." -ForegroundColor Yellow; break }
        if ($code -eq 75) { $worst = 75; Write-Host "[ytdl] YouTube limit guard is on; remaining subscriptions skipped (they'll be checked on the next sync)." -ForegroundColor Yellow; break }   # 1.25.0
        if ($code -ne 0 -and $worst -eq 0) { $worst = 1 }
    }
    if (-not $Estimate -and $done.Count) {
        # Re-read before saving, so a -Subscribe made during the sync isn't lost
        $now = (Get-Date).ToString('s')
        $fresh = @(Read-Subs)
        foreach ($s in $fresh) { if ($done.ContainsKey($s.Url)) { $s.LastSync = $now; $s.LastNew = $done[$s.Url].New; $s.LastExit = $done[$s.Url].Code } }
        Save-Subs $fresh
    }
    Write-Host ''
    $msg = if ($Estimate) { "Sync estimate done: $($done.Count) subscription(s) checked." } else { "Sync done: $total new video(s) from $($done.Count) of $($all.Count) subscription(s)." }
    Write-Host "[ytdl] $msg" -ForegroundColor $(if ($worst -eq 0) { 'Green' } else { 'Yellow' })
    Add-SyncLog "sync end: exit $worst, $total new"
    Remove-Item Env:YTDL_IN_SYNC -ErrorAction SilentlyContinue
    if (-not $Estimate -and ($Notify -eq 'on' -or $total -gt 0 -or $worst -ne 0)) {   # 1.18.0
        $bad = @($done.Keys | Where-Object { $done[$_].Code -ne 0 }).Count
        Show-Toast $(if ($worst -eq 0) { 'ytdl sync done' } else { 'ytdl sync: problems' }) ("$total new video(s) from $($done.Count) subscription(s)" + $(if ($bad) { ", $bad with errors (see ytdl -Subscriptions)" } else { '' }))
    }
    if ($worst -notin 2, 75) { $qc = Invoke-QueueDrain; if ($worst -eq 0 -and $qc) { $worst = $qc } }   # 1.20.0
    Unregister-Run
    exit $worst
}

# 1.20.0: -Add while a download runs: queue it and leave; otherwise carry on as a normal download
if ($Add) {
    if (-not $Url) { Write-Host 'Usage: ytdl <url> -Add [options]' -ForegroundColor Yellow; exit 1 }
    $act = @(Get-ActiveRuns)
    if ($act.Count) {
        $n = Add-QueueItem $Url ([IO.Path]::GetFullPath($Out)) (Get-GivenOptions $PSBoundParameters)
        $what = if ($act[0].What -eq 'sync') { 'ytdl -Sync' } else { $act[0].What }
        Write-Host "[ytdl] Queued as number $n. It starts when the download running now finishes ($what), in that window. See the queue: ytdl -Queue" -ForegroundColor Green
        exit 0
    }
    Write-Host '[ytdl] No ytdl download is running, so this one starts now.' -ForegroundColor DarkGray
}
if (-not $Url -and -not $Doctor) { Write-Error "Usage: ytdl <url> [options]   |   ytdl -Sync   |   ytdl -Subscriptions   |   ytdl -Stop   |   ytdl -Doctor [<video url>]" }

# 1.5.0: at 480p and below, transfer is only half of each video's time and a single download is
# capped at ~10 MiB/s, so overlapping videos pays off most (360p benchmark: -Parallel 2/3/4 were
# 33-47% faster on just 6 videos). Default to 3 workers there unless -Parallel was given.
# 1.9.0: at every quality. One download runs at ~8 MiB/s on a ~16 MiB/s line, so HD one at a time
# used half the connection (1080p test, same 6 videos: 1 worker 270 s, 3 workers 137 s).
# A single video (or a playlist with one left) still downloads with one worker, without a notice.
$autoParallel = $false
if ($Worker -eq 0 -and -not $PSBoundParameters.ContainsKey('Parallel')) {
    $Parallel = 3; $autoParallel = $true
}
$isCoordinator = ($Parallel -gt 1 -and $Worker -eq 0)
# 1.17.0: the progress bar needs a real console window: not a worker, a scheduled task, or captured output
$script:barOn = ($Worker -eq 0 -and -not $NoProgressBar -and -not $Estimate -and $Host.Name -eq 'ConsoleHost' -and
                 ($env:YTDL_FORCE_BAR -eq '1' -or -not $(try { [Console]::IsOutputRedirected } catch { $true })))   # FORCE_BAR: tests only
# yt-dlp's progress lines: every 5 s normally; every second while a bar shows them (they're hidden from
# the console then, and only logged). Workers inherit YTDL_PROGRESS_DELTA from a coordinator with a bar.
$progressDelta = if ($env:YTDL_PROGRESS_DELTA) { $env:YTDL_PROGRESS_DELTA } elseif ($script:barOn) { '1' } else { '5' }
# UTF-8 end to end (yt-dlp -> this process -> console/log), so titles with emoji or accents
# aren't garbled in Windows PowerShell 5.1. The original console encoding is restored on exit.
$origConsoleEnc = [Console]::OutputEncoding
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$env:PYTHONIOENCODING = 'utf-8'
function Restore-Console { if ($Worker -eq 0) { try { [Console]::OutputEncoding = $origConsoleEnc } catch { } } }

# Make sure yt-dlp, ffmpeg and deno are on PATH for this process, even if the
# shell hasn't been restarted since `winget install` updated PATH.
# Found folders are cached in %LOCALAPPDATA%\ytdl\tools.json so later runs skip the recursive search.
$wingetPkgs = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
$toolCache  = Join-Path $env:LOCALAPPDATA 'ytdl\tools.json'
$tools = @{}; $toolsChanged = $false
if (Test-Path $toolCache) { try { (Get-Content $toolCache -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $tools[$_.Name] = $_.Value } } catch { } }
foreach ($tool in 'yt-dlp', 'ffmpeg', 'deno') {
    if (Get-Command $tool -ErrorAction SilentlyContinue) { continue }
    $dir = $tools[$tool]
    if (-not ($dir -and (Test-Path (Join-Path $dir "$tool.exe")))) {
        $dir = $null
        if (Test-Path $wingetPkgs) {
            $exe = Get-ChildItem $wingetPkgs -Recurse -Filter "$tool.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($exe) { $dir = $exe.DirectoryName; $tools[$tool] = $dir; $toolsChanged = $true }
        }
    }
    if ($dir) { $env:PATH = "$dir;$env:PATH" }
}
if ($toolsChanged) {
    try { New-Item -ItemType Directory -Force (Split-Path $toolCache) | Out-Null; $tools | ConvertTo-Json | Set-Content $toolCache -Encoding ASCII } catch { }
}

$ytdlp = (Get-Command yt-dlp -ErrorAction SilentlyContinue).Source
if (-not $ytdlp) {
    Write-Error "yt-dlp not found. Install it with: winget install yt-dlp.yt-dlp"
}

# ---- update commands by install method (1.26.0 doctor hints; script scope since 1.26.1) ----
# The command that updates a tool, from the path of the copy that runs: Scoop, Chocolatey, pipx, pip or winget
# (the winget id is read from the package folder, so ffmpeg from yt-dlp.FFmpeg keeps that id).
function Get-UpdateHint([string]$tool, [string]$path) {
    if ($path -match '\\scoop\\') { return "scoop update $tool" }
    if ($path -match '\\chocolatey\\') { return "choco upgrade $tool" }
    if ($path -match '\\pipx\\') { return "pipx upgrade $tool" }
    if ($path -match '\\Python[^\\]*\\Scripts\\') { return "python -m pip install -U $tool" }
    $id = @{ 'yt-dlp' = 'yt-dlp.yt-dlp'; ffmpeg = 'Gyan.FFmpeg'; deno = 'DenoLand.Deno' }[$tool]
    if ($path -match '\\WinGet\\Packages\\([^\\_]+)_') { $id = $Matches[1] }
    "winget upgrade $id"
}
# 1.26.1: -AutoUpdate runs the updater that matches the install (before, always winget, which failed or put a
# second copy on PATH). pip uses the python.exe next to Scripts\ when there is one. Chocolatey needs admin: callers
# print the hint instead. YTDL_TEST_UPDATE=print returns the command line without running it.
function Invoke-ToolUpdate([string]$tool, [string]$path) {
    $hint = Get-UpdateHint $tool $path
    $exe, $argList = switch -Wildcard ($hint) {
        'scoop *'  { 'scoop', @('update', $tool) }
        'pipx *'   { 'pipx', @('upgrade', $tool) }
        'python *' { $py = Join-Path (Split-Path (Split-Path $path)) 'python.exe'
                     $(if (Test-Path -LiteralPath $py) { $py } else { 'python' }), @('-m', 'pip', 'install', '-U', $tool) }
        'winget *' { 'winget', @('upgrade', '--id', ($hint -replace '^winget upgrade ', ''), '-e', '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity') }
        default    { $null, $null }
    }
    if (-not $exe) { return "not run (needs admin): $hint" }
    if ($env:YTDL_TEST_UPDATE -eq 'print') { return "$exe $($argList -join ' ')" }
    & $exe @argList 2>&1 | ForEach-Object { "$_" }
}

# ---- yt-dlp age check (R3) ----------------------------------------------------------------
# An outdated yt-dlp is the most common cause of sudden failures (YouTube changes often).
# yt-dlp versions are release dates (2026.10.26), so age is easy to tell. Checked at most daily.
$updStamp = Join-Path $env:LOCALAPPDATA 'ytdl\update-check.json'
$doCheck = $true
if (Test-Path $updStamp) { try { $doCheck = ((Get-Date) - [datetime](Get-Content $updStamp -Raw | ConvertFrom-Json).Checked).TotalHours -ge 24 } catch { } }
if ($Worker -eq 0 -and $doCheck) {
    $ver = "$(& $ytdlp --version 2>$null | Select-Object -First 1)".Trim()
    if ($ver -match '^(\d{4})\.(\d{2})\.(\d{2})') {
        $age = [int]((Get-Date) - (Get-Date -Year ([int]$Matches[1]) -Month ([int]$Matches[2]) -Day ([int]$Matches[3]))).TotalDays
        if ($AutoUpdate -and $age -ge 7) {
            $hint = Get-UpdateHint 'yt-dlp' $ytdlp
            if ($hint -like 'choco *') {
                Write-Host "[ytdl] yt-dlp $ver is $age days old. It came from Chocolatey, which needs an admin shell: $hint" -ForegroundColor Yellow
            } else {
                Write-Host "[ytdl] yt-dlp $ver is $age days old; updating: $hint" -ForegroundColor Cyan
                Invoke-ToolUpdate 'yt-dlp' $ytdlp | Select-Object -Last 2 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
                $ver = "$(& $ytdlp --version 2>$null | Select-Object -First 1)".Trim()
                Write-Host "[ytdl] yt-dlp is now $ver" -ForegroundColor Cyan
            }
        } elseif ($age -ge 30) {
            Write-Host "[ytdl] yt-dlp $ver is $age days old. If downloads fail, update it: $(Get-UpdateHint 'yt-dlp' $ytdlp) (or run ytdl with -AutoUpdate)." -ForegroundColor Yellow
        }
        try { New-Item -ItemType Directory -Force (Split-Path $updStamp) | Out-Null; @{ Checked = (Get-Date).ToString('s'); Version = $ver } | ConvertTo-Json | Set-Content $updStamp -Encoding ASCII } catch { }
    }
}

# ---- fast-starting yt-dlp build (1.10.0) ------------------------------------------------------
# winget's yt-dlp.exe is a one-file build that unpacks itself on every start: ~1.0 s before it does
# anything, paid at each scan, resolution check, worker start, cookie restart and probe batch. The
# official directory build (yt-dlp_win.zip, same release) starts in ~0.33 s. When it's installed in
# %LOCALAPPDATA%\ytdl\yt-dlp-dir (opt-in; delete the folder to stop using it), ytdl uses it as long as
# it is the same version as the winget copy. winget stays the source of updates: when the winget
# yt-dlp.exe changes (upgrade), ytdl fetches the matching directory build from yt-dlp's GitHub
# release, checks it against the release's SHA2-256SUMS, and swaps it in. Until then, or if that
# fails, it uses the winget copy.
$fastDir = Join-Path $env:LOCALAPPDATA 'ytdl\yt-dlp-dir'
$fastExe = Join-Path $fastDir 'yt-dlp.exe'
$fastInfoFile = Join-Path $fastDir 'ytdl-version.txt'
function Get-WingetStamp { try { $fi = Get-Item -LiteralPath $ytdlp; "$($fi.Length)-$($fi.LastWriteTimeUtc.Ticks)" } catch { '' } }
function Read-FastInfo { try { $t = @(Get-Content -LiteralPath $fastInfoFile); @{ Version = "$($t[0])".Trim(); Stamp = "$($t[1])".Trim() } } catch { @{ Version = ''; Stamp = '' } } }
function Install-FastBuild([string]$tag) {
    $tmp = Join-Path $env:TEMP "ytdl-fastbuild-$PID"
    try {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory $tmp | Out-Null
        $base = "https://github.com/yt-dlp/yt-dlp/releases/download/$tag"
        & curl.exe -sSfL --max-time 300 -o "$tmp\SHA2-256SUMS" "$base/SHA2-256SUMS" 2>$null; if ($LASTEXITCODE -ne 0) { return $false }
        $want = "$((Get-Content "$tmp\SHA2-256SUMS" | Where-Object { $_ -match '\syt-dlp_win\.zip$' } | Select-Object -First 1) -split '\s+' | Select-Object -First 1)"
        if ($want -notmatch '^[0-9a-fA-F]{64}$') { return $false }
        & curl.exe -sSfL --max-time 300 -o "$tmp\yt-dlp_win.zip" "$base/yt-dlp_win.zip" 2>$null; if ($LASTEXITCODE -ne 0) { return $false }
        if ((Get-FileHash "$tmp\yt-dlp_win.zip" -Algorithm SHA256).Hash -ne $want.ToUpperInvariant()) { return $false }
        Expand-Archive "$tmp\yt-dlp_win.zip" -DestinationPath "$tmp\x" -Force
        if ("$(& "$tmp\x\yt-dlp.exe" --version 2>$null | Select-Object -First 1)".Trim() -ne $tag) { return $false }
        @($tag, (Get-WingetStamp)) | Set-Content "$tmp\x\ytdl-version.txt" -Encoding ASCII
        # Move the old build aside first: that fails cleanly if another run is using it.
        $old = "$fastDir.old-$PID"
        if (Test-Path -LiteralPath $fastDir) { Move-Item -LiteralPath $fastDir -Destination $old }
        Move-Item -LiteralPath "$tmp\x" -Destination $fastDir
        Remove-Item -LiteralPath $old -Recurse -Force -ErrorAction SilentlyContinue
        return $true
    } catch { return $false } finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
if (Test-Path -LiteralPath $fastExe) {
    $fi = Read-FastInfo; $stampNow = Get-WingetStamp
    if ($Worker -eq 0 -and $fi.Stamp -ne $stampNow) {
        # The winget copy changed (or the build was set up by hand): find its version and match it.
        $wv = "$(& $ytdlp --version 2>$null | Select-Object -First 1)".Trim()
        if ($wv -eq $fi.Version) { try { @($wv, $stampNow) | Set-Content $fastInfoFile -Encoding ASCII; $fi.Stamp = $stampNow } catch { } }
        elseif ($wv -match '^\d{4}\.\d{2}\.\d{2}(\.\d+)?$') {
            Write-Host "[ytdl] Updating the fast-starting yt-dlp build to $wv..." -ForegroundColor DarkGray
            if (Install-FastBuild $wv) { $fi = Read-FastInfo }
            else { Write-Host "[ytdl] Couldn't update it; using winget's yt-dlp this run (starts ~0.7 s slower)." -ForegroundColor DarkYellow }
        }
    }
    if ($fi.Stamp -eq $stampNow -and (Test-Path -LiteralPath $fastExe)) { $ytdlp = $fastExe }
}

# ---- 1.18.0: ytdl -Doctor ----------------------------------------------------------------------------
# Everything a run depends on, checked the way a run uses it, with the fix for each problem. Online: the
# sign-in check (one video, metadata only, ~3 s) and, at most daily, GitHub's latest tubepacer release
# (1.26.0), and one HEAD request to youtube.com for reachability and the clock (1.27.0); with a video link, one yt-dlp -J for it (1.28.0). Exit 0 = no problems, 1 = something failed. 1.26.0 -Report: the same results in a text file
# (and the clipboard) with names, folders and links hidden, ready for a GitHub issue.
if ($Doctor) {
    $script:docBad = 0; $script:docWarn = 0; $script:docLines = New-Object 'Collections.Generic.List[string]'; $script:docHide = @()
    function Out-Check([string]$state, [string]$what, [string]$detail, [string]$fix) {
        $col = @{ OK = 'Green'; WARN = 'Yellow'; FAIL = 'Red'; INFO = 'DarkGray' }[$state]
        if ($state -eq 'FAIL') { $script:docBad++ } elseif ($state -eq 'WARN') { $script:docWarn++ }
        Microsoft.PowerShell.Utility\Write-Host ('  {0,-5}' -f $state) -ForegroundColor $col -NoNewline
        Microsoft.PowerShell.Utility\Write-Host (' {0,-15} {1}' -f $what, $detail)
        $script:docLines.Add(('  {0,-5} {1,-15} {2}' -f $state, $what, $detail))
        if ($fix -and $state -ne 'OK') { Microsoft.PowerShell.Utility\Write-Host ('                       -> ' + $fix) -ForegroundColor DarkGray
                                         $script:docLines.Add('                       -> ' + $fix) }
    }
    function Get-Short([string]$s, [int]$n) { $s = $s.Trim(); if ($s.Length -gt $n) { $s.Substring(0, $n - 3) + '...' } else { $s } }
    # 1.26.0: install/update/remove commands that match how a tool was installed (Scoop, winget, pip, pipx,
    # Chocolatey). ytdl itself installed with Scoop means Scoop is there, so missing tools come from it too.
    $docScoop = "$PSCommandPath" -match '\\scoop\\'
    function Get-InstallHint([string]$tool, [bool]$scoop) {
        if ($scoop) { "scoop install $tool" } else { 'winget install ' + @{ 'yt-dlp' = 'yt-dlp.yt-dlp'; ffmpeg = 'Gyan.FFmpeg'; deno = 'DenoLand.Deno' }[$tool] }
    }
    # Get-UpdateHint lives at script scope since 1.26.1 (-AutoUpdate uses it too)
    function Get-RemoveHint([string]$tool, [string]$path) {
        (Get-UpdateHint $tool $path) -replace '^scoop update', 'scoop uninstall' -replace '^winget upgrade', 'winget uninstall' -replace '^choco upgrade', 'choco uninstall' -replace '^pipx upgrade', 'pipx uninstall' -replace '^python -m pip install -U', 'python -m pip uninstall'
    }
    # 1.26.0: every copy of a tool on PATH, in PATH order: the first one is the one that runs
    function Get-ToolCopies([string]$name) {
        $seen = @{}
        @(Get-Command $name -All -CommandType Application -ErrorAction SilentlyContinue | ForEach-Object { $_.Source } |
          Where-Object { $_ -and -not $seen.ContainsKey($_) -and ($seen[$_] = 1) })
    }
    function Test-ToolCopies([string]$tool) {
        $c = @(Get-ToolCopies $tool); if ($c.Count -lt 2) { return }
        $flag = if ($tool -eq 'ffmpeg') { '-version' } else { '--version' }
        $vs = @(foreach ($x in $c) { $vv = "$(& $x $flag 2>$null | Select-Object -First 1)" -replace '^(?:ffmpeg version|deno) (\S+).*', '$1'; "$x ($(if ($vv.Trim()) { $vv.Trim() } else { "doesn't start" }))" })
        Out-Check WARN "$tool copies" "$($c.Count) on PATH, the first one runs: $($vs -join '; ')" "remove the one you don't use, e.g. $(Get-RemoveHint $tool $c[1]), so updates reach the copy that runs"
        Get-CopyFix $tool $c | Add-DocFix   # 1.29.0
    }
    # 1.26.0: the latest tubepacer release on GitHub, asked at most once a day (cached in the state folder)
    function Get-LatestYtdl {
        if ($env:YTDL_TEST_LATEST) { if ($env:YTDL_TEST_LATEST -eq 'none') { return $null } return $env:YTDL_TEST_LATEST }   # test hook
        $cf = Join-Path $stateDir 'latest-release.json'
        try { $c = Get-Content $cf -Raw -ErrorAction Stop | ConvertFrom-Json; if ($c.Tag -and ((Get-Date) - [datetime]$c.Checked).TotalHours -lt 24) { return [string]$c.Tag } } catch { }
        try {
            $r = Invoke-RestMethod 'https://api.github.com/repos/billyreagan/tubepacer/releases/latest' -UseBasicParsing -TimeoutSec 6 -UserAgent 'tubepacer-doctor' -ErrorAction Stop
            $tag = "$($r.tag_name)" -replace '^v', ''
            if ($tag -match '^\d+\.\d+\.\d+$') {
                try { New-Item -ItemType Directory -Force $stateDir | Out-Null; @{ Checked = (Get-Date).ToString('s'); Tag = $tag } | ConvertTo-Json | Set-Content $cf -Encoding ASCII } catch { }
                return $tag
            }
        } catch { }
        $null
    }
    # 1.26.0: is a run holding this folder's lock? (the lock is an exclusively opened file; .info can outlive a crash)
    function Test-FolderLock([string]$dir) {
        try { $t = [IO.File]::Open((Join-Path $dir '.ytdl.lock'), 'Open', 'ReadWrite', 'None'); $t.Dispose(); $false }
        catch [IO.FileNotFoundException], [IO.DirectoryNotFoundException] { $false } catch { $true }
    }
    # 1.26.0: unfinished download files yt-dlp leaves behind (a re-run of the same link resumes them)
    function Get-PartialFiles([string]$dir) {
        @(Get-ChildItem -LiteralPath $dir -Recurse -Depth 3 -File -Force -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -like '*.part' -or $_.Name -like '*.part-Frag*' -or $_.Name -like '*.ytdl' -or $_.Name -like '*.temp.*' })
    }
    # 1.26.0: how the newest run in this folder ended, read from its log, as one line with the fix
    function Get-LastRun([string]$logDir, [bool]$running) {
        $f = @(Get-ChildItem -LiteralPath $logDir -Filter *.log -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending) | Select-Object -First 1
        if (-not $f) { return $null }
        $t = @(Get-Content -LiteralPath $f.FullName -Tail 300 -ErrorAction SilentlyContinue | ForEach-Object { ($_ -replace '^\d\d:\d\d:\d\d ', '').Trim() } | Where-Object { $_ })
        $when = $f.LastWriteTime.ToString('ddd d MMM HH:mm'); $log = "log: $($f.FullName)"
        $err = @($t | Where-Object { $_ -match '^(\[w\d+\] )?ERROR: |: error: ' })
        $e1 = if ($err.Count) { Get-Short ($err[-1] -replace '^(\[w\d+\] )?ERROR: ', '') 110 } else { '' }
        $endL = @($t | Where-Object { $_ -match '^Done\.$|^Finished with errors|Completed videos are kept' })
        $endL = if ($endL.Count) { $endL[-1] } else { '' }
        $bot = $t -match 'not a bot|Sign in to confirm|HTTP Error 429|rate-limiting'
        $o = { param($s, $d, $x) [pscustomobject]@{ State = $s; Text = "$when`: $d"; Fix = $x; Bot = [bool]$bot } }   # Bot: 1.27.0 IPv6 hint
        if ($running) { return (& $o 'INFO' 'running now' $log) }
        if ($endL -eq 'Done.') { return (& $o 'OK' 'finished without errors' '') }
        if ($endL -match '^Stopped by ytdl -Stop') { return (& $o 'INFO' 'stopped with ytdl -Stop' 're-run the same command to resume') }
        if ($endL -match '^YouTube limit guard: ') { return (& $o 'WARN' ('stopped by the ' + (Get-Short ($endL -replace '^YouTube ', '' -replace ' Completed videos are kept.*', '') 110)) "re-run the same command after that to resume; $log") }
        if (-not $endL -and ($t -match 'YouTube limit guard: ')) { return (& $o 'INFO' "didn't start: the YouTube limit guard was on" 'see the limit guard line') }
        if ($t -match 'no such option|error: .*option') { return (& $o 'WARN' "yt-dlp refused an option: $e1" "check -YtdlpArgs and the command line; $log") }
        if ($endL) {
            $d = "finished with errors$(if ($e1) { ": $e1" })"
            $x = if ($bot) { 'YouTube was rate-limiting or asking for bot checks: sign in with -Browser firefox; re-running retries only the failed videos' } else { 're-running the same command retries only the failed videos' }
            return (& $o 'WARN' $d "$x; $log")
        }
        & $o 'WARN' "ended without finishing (window closed, Ctrl+C or a crash)$(if ($e1) { "; last error: $e1" })" "re-run the same command to resume; $log"
    }
    # 1.26.0: -Report hides what identifies the user: links (also proxy logins), account options, the
    # profile folder, the user and the PC name
    function ConvertTo-Redacted([string]$s) {
        $s = $s -replace '(?i)\b[a-z][a-z0-9+.-]*://\S+', '<link>' -replace '(?i)(?<![\w-])(--(?:ap-|video-)?(?:username|password)|--cookies|-u|-p)\s+\S+', '$1 <hidden>'
        foreach ($pr in @(@($env:USERPROFILE, '~'), @($env:USERNAME, '<user>'), @($env:COMPUTERNAME, '<pc>'))) {
            if ("$($pr[0])".Length -ge 3) { $s = $s -ireplace [regex]::Escape($pr[0]), $pr[1] }
        }
        foreach ($h in @($script:docHide)) { if ("$h".Length -ge 3) { $s = $s.Replace("$h", '<video>').Replace((Get-Short "$h" 60), '<video>') } }   # 1.28.0: the -Doctor <url> video
        $s
    }
    # 1.25.1: Pulse, the tubepacer mark, as one line when every check passes: a blue heartbeat,
    # the magenta dip, the green recovery, then the play button (replaces 1.24.0's Pacey face)
    function Write-PulseMark([string]$msg) {
        $w = 'Microsoft.PowerShell.Utility\Write-Host'
        & $w '  --/\/-' -ForegroundColor Cyan -NoNewline
        & $w '\' -ForegroundColor Magenta -NoNewline
        & $w '/-' -ForegroundColor Green -NoNewline
        & $w (' ' + [string][char]0x25B6 + '  ') -ForegroundColor White -NoNewline
        & $w $msg -ForegroundColor Green
    }
    # ---- 1.29.0: -Fix. A check that can repair its problem registers a fix: what it does (Text), the command
    # shown (Cmd), and whether -Yes may run it without asking (Safe). Kinds: install/update (the tool's own
    # manager), remove (an extra copy, by its manager; never one that shares the running copy's package), delete
    # (files inside the download folder or ytdl's state folder only), task (ytdl -Schedule again). Nothing that
    # needs admin (Chocolatey) is offered. YTDL_TEST_FIX=print: Invoke-DocFix returns the command, runs nothing;
    # YTDL_TEST_ANSWERS=y,n,... answers the questions in order.
    $script:docFixes = New-Object 'Collections.Generic.List[object]'
    function New-DocFix([string]$kind, [string]$text, [string]$cmd, [bool]$safe, [hashtable]$more = @{}) {
        $o = [ordered]@{ Kind = $kind; Text = $text; Cmd = $cmd; Safe = $safe }; foreach ($k in $more.Keys) { $o[$k] = $more[$k] }; [pscustomobject]$o
    }
    function Add-DocFix { foreach ($f in @($input)) { if ($f) { $script:docFixes.Add($f) } } }
    # A manager command line (from Get-InstallHint / Get-RemoveHint) as program + arguments, non-interactive
    function Get-ManagerCall([string]$hint, [string]$path) {
        $w = @($hint -split ' ')
        switch -Wildcard ($hint) {
            'scoop *'            { @{ Exe = 'scoop'; Args = @($w | Select-Object -Skip 1) } }
            'pipx *'             { @{ Exe = 'pipx'; Args = @($w | Select-Object -Skip 1) } }
            'winget install *'   { @{ Exe = 'winget'; Args = @('install', '--id', $w[2], '-e', '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity') } }
            'winget uninstall *' { @{ Exe = 'winget'; Args = @('uninstall', '--id', $w[2], '-e', '--accept-source-agreements', '--disable-interactivity') } }
            'python -m pip uninstall *' { $py = if ($path) { Join-Path (Split-Path (Split-Path $path)) 'python.exe' } else { '' }
                                          @{ Exe = $(if ($py -and (Test-Path -LiteralPath $py)) { $py } else { 'python' }); Args = @('-m', 'pip', 'uninstall', '-y', $w[-1]) } }
            default { $null }
        }
    }
    # A missing tool: install it; an old one: update the copy that runs (path '' = not installed)
    function Get-ToolFix([string]$tool, [string]$path, [bool]$scoop) {
        if (-not $path) { $h = Get-InstallHint $tool $scoop; $c = Get-ManagerCall $h ''; return (New-DocFix install "install $tool" $h $true @{ Exe = $c.Exe; Args = $c.Args }) }
        $h = Get-UpdateHint $tool $path; if ($h -like 'choco *') { return }   # needs admin: the hint stays a step for the user
        New-DocFix update "update $tool" $h $true @{ Tool = $tool; Path = $path }
    }
    # Extra copies of a tool (copies[0] runs): each one a manager installed, unless removing it would remove the running copy too
    function Get-CopyFix([string]$tool, [string[]]$copies) {
        for ($i = 1; $i -lt $copies.Count; $i++) {
            $p = $copies[$i]
            if ($p -notmatch '\\scoop\\|\\pipx\\|\\Python[^\\]*\\Scripts\\|\\WinGet\\Packages\\') { continue }   # copied by hand: not ours to delete
            $h = Get-RemoveHint $tool $p
            if ($h -eq (Get-RemoveHint $tool $copies[0])) { continue }   # same package as the copy that runs
            $c = Get-ManagerCall $h $p; if (-not $c) { continue }
            New-DocFix remove "remove the extra $tool copy $p (kept: $($copies[0]))" $h $false @{ Exe = $c.Exe; Args = $c.Args }
        }
    }
    # The saved GitHub answer (latest-release.json) when it is over a day old (GitHub couldn't be asked again) or unreadable
    function Get-ReleaseCacheFix([string]$cf, [datetime]$now) {
        if (-not (Test-Path -LiteralPath $cf)) { return }
        $c = try { Get-Content -LiteralPath $cf -Raw -ErrorAction Stop | ConvertFrom-Json } catch { $null }
        $when = try { [datetime]$c.Checked } catch { $null }
        if ($c.Tag -and $when -and ($now - $when).TotalHours -lt 24) { return }
        New-DocFix delete "delete ytdl's saved answer from GitHub ($(if ($when) { "from $($when.ToString('d MMM HH:mm')), expired" } else { "can't be read" }))" "Remove-Item '$cf'" $true @{ Paths = @($cf) }
    }
    # The scheduled sync, set up again with its own times (ytdl -Schedule): when it is off (asks first: it may be
    # off on purpose), can't find its script, runs another ytdl script, skips missed syncs, or skips on battery
    function Get-TaskFix($t, [string]$self) {
        if (-not $t) { return }
        $c = [int64]$t.LastTaskResult; if ($c -gt 2147483647) { $c -= 4294967296 }
        $why = @()
        if ($t.State -eq 'Disabled') { $why += 'it is turned off' }
        if ($t.LastRunTime -and $c -eq 0x80070002) { $why += "Windows couldn't find its script" }
        if ($self -and $t.Script -and $t.Script -ne $self) { $why += 'it runs another ytdl script' }
        if (-not $t.WakeToRun -and -not $t.StartWhenAvailable) { $why += 'missed syncs are skipped' }
        if ($t.HasBattery -and ($t.DisallowStartIfOnBatteries -or $t.StopIfGoingOnBatteries)) { $why += 'it skips syncs on battery' }
        if (-not $why.Count) { return }
        $kind = if ($t.Kind -eq 'hourly') { 'hourly' } else { 'daily' }; $at = if ("$($t.At)" -match '^\d{1,2}:\d\d$') { $t.At } else { '03:00' }
        New-DocFix task "set up the scheduled sync again, $kind at $at ($($why -join '; '))" "ytdl -Schedule $kind -At $at" ($t.State -ne 'Disabled') @{ Kind2 = $kind; At = $at }
    }
    function Test-DocPathInside([string]$p, [string[]]$roots) {
        $full = try { [IO.Path]::GetFullPath($p) } catch { return $false }
        foreach ($r in $roots) { if ($r) { $rf = [IO.Path]::GetFullPath($r).TrimEnd('\'); if ($full.StartsWith($rf + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true } } }
        $false
    }
    function Invoke-DocFix($f) {
        $res = { param($ok, $msg) [pscustomobject]@{ Ok = [bool]$ok; Msg = "$msg" } }
        $last = { param($lines) Get-Short "$(@(@($lines) | Where-Object { "$_".Trim() }) | Select-Object -Last 1)" 110 }
        if ($env:YTDL_TEST_FIX -eq 'print') { return (& $res $true "would run: $($f.Cmd)") }
        try {
            switch ($f.Kind) {
                'update' { $o = @(Invoke-ToolUpdate $f.Tool $f.Path); return (& $res ($LASTEXITCODE -eq 0) (& $last $o)) }
                'delete' {
                    $outside = @($f.Paths | Where-Object { -not (Test-DocPathInside $_ @($Out, $stateDir)) })
                    if ($outside.Count) { return (& $res $false "refused: not inside the download folder or ytdl's state folder: $($outside[0])") }
                    $gone = 0; foreach ($p in $f.Paths) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction Stop; $gone++ } }
                    return (& $res $true "$gone file(s) deleted")
                }
                'task' { $o = @(& (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Schedule $f.Kind2 -At $f.At 2>&1 | ForEach-Object { "$_" })
                         return (& $res ($LASTEXITCODE -eq 0) (Get-Short "$($o | Select-Object -First 1)" 110)) }
                default { $o = @(& $f.Exe @($f.Args) 2>&1 | ForEach-Object { "$_" }); return (& $res ($LASTEXITCODE -eq 0) (& $last $o)) }
            }
        } catch { & $res $false (Get-Short $_.Exception.Message 110) }
    }
    function Read-DocAnswer([string]$q) {
        if ($null -eq $script:docAnswers -and $env:YTDL_TEST_ANSWERS) { $script:docAnswers = New-Object 'Collections.Generic.Queue[string]'; foreach ($a in $env:YTDL_TEST_ANSWERS -split ',') { $script:docAnswers.Enqueue($a.Trim()) } }
        if ($null -ne $script:docAnswers) { $a = if ($script:docAnswers.Count) { $script:docAnswers.Dequeue() } else { 'n' }; Microsoft.PowerShell.Utility\Write-Host "$q $a"; return $a }
        try { Microsoft.PowerShell.Utility\Read-Host $q } catch { '' }
    }
    # ---- 1.27.0: drive, folder, cookies, network and schedule checks. Each Test-* function judges the facts
    # it is given and returns check lines (New-Check); Get-* functions gather the facts (with test hooks), so
    # the tests feed fake ones: YTDL_TEST_FS, YTDL_TEST_LONGPATHS, YTDL_TEST_CFA, YTDL_TEST_PROCS ('none' = no
    # programs), YTDL_TEST_CLOCK (skew in s, 'none' = no answer), YTDL_TEST_NET and YTDL_TEST_TASK (JSON).
    function New-Check([string]$state, [string]$what, [string]$text, [string]$fix) { [pscustomobject]@{ State = $state; What = $what; Text = $text; Fix = $fix } }
    function Out-Checks { foreach ($c in @($input)) { if ($c) { Out-Check $c.State $c.What $c.Text $c.Fix } } }
    # The drive under the download folder (it may not exist yet): file system, type, network path, OneDrive
    function Get-FolderFacts([string]$dir) {
        $full = [IO.Path]::GetFullPath($dir); $fs = ''; $type = ''
        try { $di = New-Object IO.DriveInfo([IO.Path]::GetPathRoot($full)); $type = "$($di.DriveType)"; $fs = "$($di.DriveFormat)" } catch { }
        if ($env:YTDL_TEST_FS) { $fs = $env:YTDL_TEST_FS }   # test hook
        $od = @(@($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial) | Where-Object { $_ -and ($full.TrimEnd('\') + '\').StartsWith($_.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) }) | Select-Object -First 1
        [pscustomobject]@{ Path = $full; FileSystem = $fs; DriveType = $type; Unc = $full.StartsWith('\\'); OneDrive = "$od" }
    }
    function Test-FolderType($f) {
        $fix = 'download to a folder on a local NTFS drive with -Out'
        if ($f.Unc -or $f.DriveType -eq 'Network') { return (New-Check WARN 'drive' 'a network drive: merging is slow there, and a dropped connection breaks the download being written' $fix) }
        if ($f.OneDrive) { return (New-Check WARN 'drive' "inside OneDrive ($($f.OneDrive)): it uploads each video while it is written and can move finished ones online to free space" "$fix, or right-click the folder > Always keep on this device") }
        if ($f.FileSystem -match '^FAT(32)?$') { return (New-Check WARN 'drive' "$($f.FileSystem): no file can be bigger than 4 GB, so long or 4K videos fail when they are merged" "$fix (or format the drive as NTFS or exFAT)") }
        if ($f.FileSystem -eq 'exFAT') { return (New-Check INFO 'drive' 'exFAT: works; it keeps no journal, so unplugging during a run can damage the file being written' '') }
        $kind = @{ Fixed = 'local disk'; Removable = 'removable drive'; Ram = 'RAM disk'; CDRom = 'CD/DVD drive' }["$($f.DriveType)"]; if (-not $kind) { $kind = 'drive' }
        New-Check $(if ($f.DriveType -eq 'Removable') { 'INFO' } else { 'OK' }) 'drive' "$(if ($f.FileSystem) { $f.FileSystem } else { 'file system unknown' }), $kind$(if ($f.DriveType -eq 'Removable') { ': unplugging it stops the run' })" ''
    }
    # Paths stop at 260 characters unless Windows' long paths are on: the folder + 2 subfolder levels
    # (channel, playlist) + a title of up to ~150 characters and the extension = folder + ~190
    function Test-LongPaths([string]$dir, $enabled) {
        if ("$enabled" -eq '1' -or $dir.Length + 190 -le 260) { return }
        New-Check INFO 'long paths' "off, and this folder's path is $($dir.Length) characters: a long title in a subfolder can pass Windows' 260-character limit and fail to save" 'turn them on in an admin PowerShell: Set-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem LongPathsEnabled 1   (or use a shorter -Out)'
    }
    # Can a file be created here? Defender's Controlled folder access blocks unknown programs in Documents,
    # Videos and Pictures, and the error then looks like a permission problem
    function Get-CfaOn {
        if ($env:YTDL_TEST_CFA) { return $env:YTDL_TEST_CFA -eq '1' }   # test hook
        try { (Get-MpPreference -ErrorAction Stop).EnableControlledFolderAccess -eq 1 } catch { $false }
    }
    function Test-FolderWrite([string]$dir) {
        $p = Join-Path $dir ".ytdl-write-test-$PID"
        try { [IO.File]::WriteAllText($p, 'ytdl'); Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue; return }
        catch {
            $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException }
            $denied = $e -is [UnauthorizedAccessException]
            $fix = if ($denied -and (Get-CfaOn)) { "Windows Security's Controlled folder access is on: allow pwsh.exe (or powershell.exe), yt-dlp.exe and ffmpeg.exe under Virus & threat protection > Ransomware protection > Allow an app, or download elsewhere with -Out" }
                   elseif ($denied) { 'check the folder''s permissions and that it isn''t read-only, or download elsewhere with -Out' } else { 'download elsewhere with -Out' }
            New-Check FAIL 'write test' "can't create a file in this folder ($(Get-Short $e.Message 90))" $fix
        }
    }
    # Why a browser's cookies may not be readable (shown only when the sign-in check didn't pass).
    # -Browser takes yt-dlp's BROWSER[+KEYRING][:PROFILE] form.
    function Test-BrowserCookies([string]$browser, [string[]]$running) {
        $b = ($browser -split '[+:]')[0].ToLower()
        $exe = @{ chrome = 'chrome'; edge = 'msedge'; brave = 'brave'; opera = 'opera'; vivaldi = 'vivaldi'; chromium = 'chromium' }[$b]
        if (-not $exe) { return }
        if ($running -contains $exe) { New-Check WARN 'cookies' "$b is open: Chromium browsers lock their cookie file while they run, so yt-dlp can't copy it" "close $b completely (also its tray icon), then try again; or sign in with -Browser firefox" }
        if ($b -eq 'chrome') { New-Check WARN 'cookies' "Chrome 127 and later encrypt cookies so that only Chrome can read them; yt-dlp often can't" 'sign in to YouTube in Firefox and use -Browser firefox, or export a cookies.txt file and use -Cookies' }
    }
    # A cookies.txt file (Netscape format: domain, flag, path, secure, expiry, name, value; tab-separated)
    function Test-CookiesFile([string]$path, [datetime]$now, [bool]$signOk) {
        $fix = 'sign in to YouTube in the browser, export the file again, or use -Browser firefox'
        $yt = @(foreach ($l in @(Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)) {
            $f = ($l -replace '^#HttpOnly_', '') -split "`t"
            if ($f.Count -ge 7 -and $f[0] -match 'youtube\.com$' -and $f[4] -match '^\d+$') { [pscustomobject]@{ Name = $f[5]; Exp = [int64]$f[4] } } })
        if (-not $yt.Count) { return (New-Check WARN 'cookies file' 'no youtube.com cookies in it (or not in the Netscape cookies.txt format)' $fix) }
        $login = @($yt | Where-Object { $_.Name -in 'LOGIN_INFO', '__Secure-3PSID', '__Secure-1PSID', 'SID', 'SAPISID' })
        if (-not $login.Count) { return (New-Check WARN 'cookies file' 'youtube.com cookies but no sign-in ones: it was exported while signed out' $fix) }
        $exp = @($login | Where-Object { $_.Exp -gt 0 } | ForEach-Object Exp | Sort-Object) | Select-Object -Last 1   # 0 = ends with the browser session
        if ($exp -and $exp -lt [DateTimeOffset]::new($now).ToUnixTimeSeconds()) { return (New-Check WARN 'cookies file' ('its sign-in cookies expired on {0:d MMM yyyy}' -f [DateTimeOffset]::FromUnixTimeSeconds($exp).LocalDateTime) $fix) }
        $age = [int][math]::Floor(($now - (Get-Item -LiteralPath $path).LastWriteTime).TotalDays)
        if ($age -gt 14) { return (New-Check $(if ($signOk) { 'INFO' } else { 'WARN' }) 'cookies file' "exported $age days ago: YouTube replaces sign-in cookies over time, so old exports stop working" 'export a fresh one if sign-in fails') }
        New-Check OK 'cookies file' "$($login.Count) sign-in cookies, saved $age day(s) ago"
    }
    # One HEAD request to youtube.com: reachable? and this PC's clock against its Date header (seconds, + = ahead)
    function Get-ClockSkew {
        if ($env:YTDL_TEST_CLOCK) { if ($env:YTDL_TEST_CLOCK -eq 'none') { return $null }; return [double]$env:YTDL_TEST_CLOCK }   # test hook
        try {
            $q = [Net.WebRequest]::Create('https://www.youtube.com/'); $q.Method = 'HEAD'; $q.Timeout = 6000; $q.AllowAutoRedirect = $false
            $resp = try { $q.GetResponse() } catch [Net.WebException] { if ($_.Exception.Response) { $_.Exception.Response } else { throw } }
            $d = $resp.Headers['Date']; $resp.Close(); if (-not $d) { return $null }
            ([datetime]::UtcNow - [DateTimeOffset]::Parse($d, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime).TotalSeconds
        } catch { $null }
    }
    function Test-Clock($skew) {
        if ($null -eq $skew) { return (New-Check WARN 'internet' "couldn't reach youtube.com" 'check the internet connection, a proxy or the firewall') }
        $a = [math]::Abs([double]$skew)
        if ($a -lt 120) { return (New-Check OK 'internet' ('youtube.com answers; the clock is within {0:N0} s of its time' -f [math]::Max(1, $a))) }
        $by = if ($a -ge 5400) { '{0:N0} hours' -f ($a / 3600) } else { '{0:N0} minutes' -f ($a / 60) }
        New-Check WARN 'clock' "this PC's clock is $by $(if ($skew -gt 0) { 'ahead of' } else { 'behind' }) YouTube's: sign-in and secure connections can fail" 'Settings > Time & language > Date & time > Sync now (or w32tm /resync in an admin shell)'
    }
    # Proxy, VPN and IPv6 facts (values are not shown, only the kind: they can hold addresses and logins)
    function Get-NetFacts {
        if ($env:YTDL_TEST_NET) { return ($env:YTDL_TEST_NET | ConvertFrom-Json) }   # test hook: {"Proxy":[...],"Vpn":[...],"IPv6":true}
        $px = @(foreach ($n in 'HTTPS_PROXY', 'HTTP_PROXY', 'ALL_PROXY') { if ([Environment]::GetEnvironmentVariable($n)) { "$n set" } })
        try { $is = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
              if ($is.ProxyEnable -eq 1 -and $is.ProxyServer) { $px += 'Windows proxy on' } elseif ($is.AutoConfigURL) { $px += 'Windows proxy script' } } catch { }
        $vpn = @(try { Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' -and "$($_.Name) $($_.InterfaceDescription)" -match 'WireGuard|TAP-Windows|OpenVPN|NordLynx|Wintun|ProtonVPN|Mullvad|Surfshark|ExpressVPN|AnyConnect|Fortinet|PANGP|GlobalProtect|WARP' } | ForEach-Object { $_.InterfaceDescription } } catch { })
        $vpn += @(try { Get-VpnConnection -ErrorAction Stop | Where-Object ConnectionStatus -eq 'Connected' | ForEach-Object Name } catch { })
        $v6 = try { [bool](@(Get-NetIPAddress -AddressFamily IPv6 -ErrorAction Stop | Where-Object { $_.IPAddress -match '^[23]' -and "$($_.AddressState)" -eq 'Preferred' }).Count) } catch { $false }
        [pscustomobject]@{ Proxy = $px; Vpn = $vpn; IPv6 = $v6 }
    }
    function Test-ProxyVpn([string[]]$proxy, [string[]]$vpn, [string[]]$ytArgs) {
        $all = @(@($vpn | Where-Object { $_ } | ForEach-Object { "VPN ($_)" }) + @($proxy | Where-Object { $_ }))
        if ($ytArgs -contains '--proxy') { $all += 'yt-dlp --proxy' }
        if (-not $all.Count) { return }
        New-Check INFO 'VPN / proxy' "$($all -join '; '): YouTube asks for bot checks more often from shared VPN and proxy addresses" 'if runs hit bot checks, try without it, or sign in with -Browser'
    }
    function Test-IPv6([bool]$hasV6, [bool]$bot, [string[]]$ytArgs) {
        if (-not ($hasV6 -and $bot) -or $ytArgs -contains '--force-ipv4' -or $ytArgs -contains '-4') { return }
        New-Check INFO 'IPv6' 'this PC has IPv6 and the last run here hit bot checks: YouTube sometimes limits IPv6 addresses sooner' "try IPv4: -YtdlpArgs '--force-ipv4'"
    }
    # The scheduled sync. Task Scheduler's result codes in words (ytdl's own exit codes are 0, 1 and 75).
    function Get-TaskResultText([int64]$code) {
        if ($code -gt 2147483647) { $code -= 4294967296 }   # unsigned -> signed, like the hex literals below
        switch ($code) {
            0 { 'OK', 'finished' }
            1 { 'OK', 'finished, some videos failed (see ytdl -Subscriptions)' }
            75 { 'OK', 'stopped by the YouTube limit guard; the next run carries on' }
            0x41301 { 'OK', 'running now' }
            0x41303 { 'OK', 'not run yet' }
            0x41306 { 'WARN', 'stopped by hand, or by the 12-hour limit' }
            0x8004131F { 'WARN', 'skipped: the run before was still going' }
            0x800710E0 { 'WARN', "skipped: Windows didn't start it (on battery, or the task's conditions weren't met)" }
            0x80070002 { 'WARN', "failed: Windows couldn't find PowerShell or the ytdl script (moved or renamed?)" }
            0xC000013A { 'WARN', 'stopped: its window was closed, or Windows signed out' }
            default { 'WARN', ('ended with code 0x{0:X8}' -f [uint32]$(if ($code -lt 0) { $code + 4294967296 } else { $code })) }
        }
    }
    function Get-TaskFacts([string]$name) {
        if ($env:YTDL_TEST_TASK) { if ($env:YTDL_TEST_TASK -eq 'none') { return $null }; return ($env:YTDL_TEST_TASK | ConvertFrom-Json) }   # test hook
        $tk = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue; if (-not $tk) { return $null }
        $ti = $tk | Get-ScheduledTaskInfo; $s = $tk.Settings
        [pscustomobject]@{ State = "$($tk.State)"; LastTaskResult = [int64]$ti.LastTaskResult
            LastRunTime = $(if ($ti.LastRunTime -and $ti.LastRunTime.Year -gt 2000) { $ti.LastRunTime.ToString('s') } else { '' })
            NextRunTime = $(if ($ti.NextRunTime) { $ti.NextRunTime.ToString('s') } else { '' })
            DisallowStartIfOnBatteries = [bool]$s.DisallowStartIfOnBatteries; StopIfGoingOnBatteries = [bool]$s.StopIfGoingOnBatteries
            WakeToRun = [bool]$s.WakeToRun; StartWhenAvailable = [bool]$s.StartWhenAvailable
            Kind = $(if ("$(@($tk.Triggers)[0].Repetition.Interval)" -eq 'PT1H') { 'hourly' } else { 'daily' })   # 1.29.0: for -Fix
            At = $(try { ([datetime]@($tk.Triggers)[0].StartBoundary).ToString('HH:mm') } catch { '' })
            Script = $(if ("$(@($tk.Actions)[0].Arguments)" -match '-File "([^"]+)"') { $Matches[1] } else { '' })
            HasBattery = $(try { [bool](@(Get-CimInstance Win32_Battery -ErrorAction Stop).Count) } catch { $false }) }
    }
    function Test-ScheduleTask($t, [string]$self = '') {
        if (-not $t) { return (New-Check INFO 'schedule' 'no automatic sync (ytdl -Schedule daily sets one up)' '') }
        $again = 'ytdl -Schedule daily -At 03:00 sets it up again'
        $last = if ($t.LastRunTime) { ([datetime]$t.LastRunTime).ToString('ddd d MMM HH:mm') } else { '' }
        $next = if ($t.NextRunTime) { ([datetime]$t.NextRunTime).ToString('ddd d MMM HH:mm') } else { '-' }
        $st = 'OK'; $words = ''; if ($last) { $st, $words = Get-TaskResultText ([int64]$t.LastTaskResult) }
        if ($t.State -eq 'Disabled') { $st = 'WARN' }
        New-Check $st 'schedule' "$($t.State); $(if ($last) { "last run $last`: $words" } else { 'not run yet' }); next $next" $(if ($t.State -eq 'Disabled') { "turn it on in Task Scheduler, or $again" } else { $again })
        if ($t.HasBattery -and ($t.DisallowStartIfOnBatteries -or $t.StopIfGoingOnBatteries)) { New-Check INFO 'schedule' "$(if ($t.DisallowStartIfOnBatteries) { "won't start" } else { 'stops' }) while the PC runs on battery" $again }
        if (-not $t.WakeToRun -and -not $t.StartWhenAvailable) { New-Check INFO 'schedule' 'a sync missed while the PC sleeps or is off is skipped, not run later' "$again (it runs a missed sync when the PC is next on)" }
        if ($self -and $t.Script -and $t.Script -ne $self) { New-Check WARN 'schedule' "it runs another ytdl script: $($t.Script)" "$again, so it runs this one ($self)" }   # 1.29.0
    }
    # ---- 1.28.0: ytdl -Doctor <url> checks one video: metadata only (yt-dlp -J --no-playlist), one request,
    # counted in the hourly budget and skipped while the limit guard is on. Get-VideoFacts asks (test hook
    # YTDL_TEST_INFO = a file holding -J's JSON or yt-dlp's error text); Test-Video and Test-VideoArchive judge.
    function Get-VideoFacts([string]$u, [string[]]$auth) {
        $t0 = Get-Date; $js = $null; $err = @()
        if ($env:YTDL_TEST_INFO) {   # test hook
            $raw = [IO.File]::ReadAllText($env:YTDL_TEST_INFO)
            if ($raw.TrimStart().StartsWith('{')) { $js = $raw } else { $err = @($raw -split "`r?`n" | Where-Object { $_ }) }
        } else {
            $lines = @(& $ytdlp @auth @userNetArgs --ignore-config --no-warnings -J --no-playlist $u 2>&1 | ForEach-Object { "$_" })
            $js = $lines | Where-Object { $_.StartsWith('{') } | Select-Object -First 1
            $err = @($lines | Where-Object { -not $_.StartsWith('{') })
        }
        $vi = $null; if ($js) { try { $vi = $js | ConvertFrom-Json -ErrorAction Stop } catch { } }
        [pscustomobject]@{ Info = $vi; Err = $err; Sec = ((Get-Date) - $t0).TotalSeconds }
    }
    function Get-ShortSide($f) { if ($f.height -and $f.width) { [math]::Min([int]$f.height, [int]$f.width) } elseif ($f.height) { [int]$f.height } else { 0 } }
    function Get-CodecName([string]$c) { switch -Regex ($c) { '^(avc|h264)' { 'H.264' } '^(vp0?9)' { 'VP9' } '^av01' { 'AV1' } '^(hev|hvc|h265)' { 'H.265' } default { ($c -split '\.')[0] } } }
    function Test-Video($vf, [string]$u, [string]$quality, [bool]$audio, [bool]$signed, [datetime]$now) {
        $in = if ($signed) { 'signed in' } else { 'signed out' }
        $signIn = if ($signed) { '' } else { ' -Browser firefox' }
        $base = "ytdl `"$u`"$(if ($quality -ne 'best') { " -Quality $quality" })$(if ($audio) { ' -AudioOnly' })"
        $vi = $vf.Info
        if (-not $vi) {
            $e = "$(@(@($vf.Err | Where-Object { $_ -match '^ERROR' }) + @($vf.Err)) | Select-Object -First 1)" -replace '^ERROR:\s*(\[[^\]]+\]\s*)?([\w-]{11}:\s*)?', ''
            $why = Get-Short $e 120
            if ($e -match $limitPattern) {
                if ($e -match $limit429Pattern) { return (New-Check FAIL 'video' "$in`: YouTube is rate-limiting this PC (HTTP 429)" 'wait an hour or more before downloading; ytdl''s limit guard paces the next run') }
                return (New-Check FAIL 'video' "$in`: YouTube asked to confirm you're not a bot" $(if ($signed) { 'wait a while; open youtube.com in that browser and check you are signed in' } else { 'sign in: add -Browser firefox (or chrome/edge); or wait a while' }))
            }
            if ($e -match 'Private video') { return (New-Check FAIL 'video' "$in`: private; only the uploader and people they shared it with can watch it" $(if ($signed) { 'nothing to do unless the uploader shares it with this account' } else { 'if it was shared with you: add -Browser firefox' })) }
            if ($e -match 'members-only|Join this channel|channel.s members') { return (New-Check FAIL 'video' "$in`: members-only (the channel's paid membership)" $(if ($signed) { 'this account is not a member of the channel' } else { 'if you are a member: add -Browser firefox' })) }
            if ($e -match 'confirm your age|age.restricted|inappropriate for some users') { return (New-Check FAIL 'video' "$in`: age-restricted; YouTube needs a signed-in adult account" $(if ($signed) { 'confirm the account''s age on youtube.com (open the video there once)' } else { "sign in: $base -Browser firefox" })) }
            if ($e -match 'Premium|requires payment|rent') { return (New-Check FAIL 'video' "$in`: needs YouTube Premium or a purchase" $(if ($signed) { 'this account has no access to it' } else { 'if your account has access: add -Browser firefox' })) }
            if ($e -match 'in your country|geo.?restrict|blocked it in your country') { return (New-Check FAIL 'video' "$in`: not available in this country (region-blocked)" 'it can only be watched from countries the uploader allows') }
            if ($e -match '(?:will begin|Premieres|starts) (in [^.]+)') { return (New-Check WARN 'video' "not started yet: it goes live $($Matches[1])" "$base -Live waits for it and records it") }
            if ($e -match 'live event will begin|is upcoming|has not started') { return (New-Check WARN 'video' 'not started yet (a scheduled stream or premiere)' "$base -Live waits for it and records it") }
            if ($e -match 'removed|terminated|no longer available|does not exist|Video unavailable') { return (New-Check FAIL 'video' "gone: $why" 'nothing to do: YouTube no longer has it') }
            if ($e -match 'PO Token|po_token') { return (New-Check FAIL 'video' "$in`: YouTube wants a PO token for it" "$base -PoToken$signIn") }
            if ($e -match 'Unsupported URL|is not a valid URL|Incomplete YouTube ID') { return (New-Check FAIL 'video' "yt-dlp doesn't read this link: $why" 'copy the link again from the address bar') }
            if ($e -match 'Unable to download|timed out|getaddrinfo|Connection|SSL|resolve') { return (New-Check WARN 'video' "no answer from YouTube: $why" 'check the internet connection, then try again') }
            return (New-Check WARN 'video' "$in`: yt-dlp couldn't read it: $(if ($why) { $why } else { 'no error text' })" 'update yt-dlp (see its line above), then try again')
        }
        $dur = if ($vi.duration) { $ts = [timespan]::FromSeconds([double]$vi.duration); if ($ts.TotalHours -ge 1) { '{0}:{1:mm\:ss}' -f [int][math]::Floor($ts.TotalHours), $ts } else { '{0:m\:ss}' -f $ts } } else { '' }
        $avail = switch ("$($vi.availability)") { 'needs_auth' { 'sign-in only' } 'subscriber_only' { 'members-only' } 'premium_only' { 'Premium' } '' { '' } default { $_ } }
        $what = "'$(Get-Short "$($vi.title)" 60)'$(if ($dur) { ", $dur" })$(if ($avail) { ", $avail" })"
        switch ("$($vi.live_status)") {
            'is_upcoming' {
                $when = if ($vi.release_timestamp) { $lt = [DateTimeOffset]::FromUnixTimeSeconds([int64]$vi.release_timestamp).LocalDateTime; $lt.ToString($(if ($lt.Date -ne $now.Date) { 'ddd d MMM HH:mm' } else { 'HH:mm' })) } else { 'later' }
                return (New-Check WARN 'video' "$what`: not started yet, goes live $(if ($when -ne 'later') { 'at ' })$when" "$base -Live waits for it and records it")
            }
            'is_live' { New-Check OK 'video' "$what`: live now ($in)" ''; New-Check INFO 'command' "$base -Live$signIn" ''; return }
            'post_live' { New-Check WARN 'video' "$what`: the stream just ended; YouTube is still processing it" 'for a few hours only part of it, or a low quality, may download; try again later' }
            default { New-Check OK 'video' "available ($in): $what" '' }
        }
        $fs = @($vi.formats | Where-Object { $_ -and "$($_.ext)" -ne 'mhtml' -and "$($_.format_note)" -notmatch 'storyboard' })
        $vids = @($fs | Where-Object { $_.vcodec -and "$($_.vcodec)" -ne 'none' })
        $auds = @($fs | Where-Object { $_.acodec -and "$($_.acodec)" -ne 'none' -and (-not $_.vcodec -or "$($_.vcodec)" -eq 'none') })
        if ($audio) {
            $ba = $auds | Sort-Object { [double]$_.abr } -Descending | Select-Object -First 1
            if ($ba) { New-Check OK 'formats' ('best audio: {0}, {1:N0} kbps (-AudioOnly converts it to {2})' -f ($ba.acodec -split '\.')[0], [double]$ba.abr, $(if ($AudioFormat) { $AudioFormat } else { 'mp3' })) '' }
            elseif ($vids.Count) { New-Check WARN 'formats' 'no audio-only format came back; ytdl takes the audio from a video file' '' }
            else { New-Check FAIL 'formats' 'no formats came back' 'update yt-dlp and install deno (see above); if it stays, try -PoToken' }
        } elseif (-not $vids.Count) {
            New-Check FAIL 'formats' 'no video formats came back' 'update yt-dlp and install deno (see above); if it stays, try -PoToken'
        } else {
            $best = ($vids | ForEach-Object { Get-ShortSide $_ } | Measure-Object -Maximum).Maximum
            $label = { param($h) $top = @($vids | Where-Object { (Get-ShortSide $_) -eq $h } | Sort-Object { [double]$_.fps } -Descending)[0]
                       "$h" + 'p' + $(if ([double]$top.fps -gt 31) { [int]$top.fps } else { '' }) + " $(Get-CodecName "$($top.vcodec)")" }
            $sep = @($vids | Where-Object { -not $_.acodec -or "$($_.acodec)" -eq 'none' }).Count
            if (-not $sep -and $best -le 360) { New-Check WARN 'formats' "only $(& $label $best) as a single file came back: YouTube's JavaScript challenge probably failed" 'update yt-dlp and install deno (see above); if it stays, try -PoToken' }
            elseif ($quality -eq 'best') { New-Check OK 'formats' "best on offer: $(& $label $best) (-Quality best gets it)" '' }
            else {
                $q = [int]$quality; $got = ($vids | ForEach-Object { Get-ShortSide $_ } | Where-Object { $_ -le $q } | Measure-Object -Maximum).Maximum
                if ($best -lt $q) { New-Check INFO 'formats' "-Quality $q asked, but the best on offer is $(& $label $best): you get that" '' }
                elseif ($got) { New-Check OK 'formats' "-Quality $q gets $(& $label $got) (best on offer: $(& $label $best))" '' }
                else { New-Check INFO 'formats' "nothing at $q`p or below; you get the smallest there is" '' }
            }
        }
        New-Check INFO 'command' "$base$(if ("$($vi.availability)" -in 'needs_auth', 'subscriber_only', 'premium_only') { $signIn })" ''
    }
    function Test-VideoArchive([string]$vid, [string[]]$ids, [string]$arch) {
        if ($vid -and $vid -in $ids) { New-Check INFO 'archive' 'already downloaded into this folder: a run here skips it' "to get it again, use another -Out, or delete the line 'youtube $vid' from $arch" }
    }
    $docHead ="ytdl $YtdlVersion doctor  |  PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))  |  $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    Microsoft.PowerShell.Utility\Write-Host $docHead -ForegroundColor Cyan
    # 1.26.0: ytdl itself against the latest release
    $docLatest = Get-LatestYtdl
    if (-not $docLatest) { Out-Check INFO 'ytdl' "$YtdlVersion (couldn't reach GitHub to check for a newer release)" '' }
    elseif ([version]$docLatest -gt [version]$YtdlVersion) { Out-Check WARN 'ytdl' "$YtdlVersion installed; $docLatest is out" $(if ($docScoop) { 'scoop update tubepacer' } else { 'download it: https://github.com/billyreagan/tubepacer/releases/latest' }) }
    elseif ([version]$docLatest -lt [version]$YtdlVersion) { Out-Check OK 'ytdl' "$YtdlVersion (newer than the latest release, $docLatest)" '' }
    else { Out-Check OK 'ytdl' "$YtdlVersion, the latest release" '' }
    if ($docLatest -and [version]$docLatest -gt [version]$YtdlVersion -and $docScoop) { New-DocFix scoop 'update ytdl (tubepacer) with Scoop' 'scoop update tubepacer' $true @{ Exe = 'scoop'; Args = @('update', 'tubepacer') } | Add-DocFix }   # 1.29.0
    Get-ReleaseCacheFix (Join-Path $stateDir 'latest-release.json') (Get-Date) | Add-DocFix
    # yt-dlp
    $ytSrc = @(Get-ToolCopies 'yt-dlp') | Select-Object -First 1
    $v = if ($ytdlp) { "$(& $ytdlp --version 2>$null | Select-Object -First 1)".Trim() } else { '' }
    if (-not $v) { Out-Check FAIL 'yt-dlp' 'not found or not starting' (Get-InstallHint 'yt-dlp' $docScoop); if (-not $ytSrc) { Get-ToolFix 'yt-dlp' '' $docScoop | Add-DocFix } }
    else {
        $age = $null; if ($v -match '^(\d{4})\.(\d{2})\.(\d{2})') { $age = [int]((Get-Date) - (Get-Date -Year ([int]$Matches[1]) -Month ([int]$Matches[2]) -Day ([int]$Matches[3]))).TotalDays }
        $build = if ($ytdlp -eq $fastExe) { 'fast-starting build' } else { 'one-file build (starts ~0.7 s slower)' }
        $st = if ($null -ne $age -and $age -ge 60) { 'FAIL' } elseif ($null -ne $age -and $age -ge 30) { 'WARN' } else { 'OK' }
        $uh = Get-UpdateHint 'yt-dlp' $ytSrc
        Out-Check $st 'yt-dlp' "$v, $age days old, $build" "$uh$(if ($uh -notlike 'choco *') { '   (or run downloads with -AutoUpdate)' })"
        if ($st -ne 'OK' -and $ytSrc) { Get-ToolFix 'yt-dlp' $ytSrc $docScoop | Add-DocFix }   # 1.29.0
    }
    Test-ToolCopies 'yt-dlp'
    # ffmpeg / ffprobe
    $ff = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if (-not $ff) { Out-Check FAIL 'ffmpeg' 'not found (needed to merge video and audio, and for cover art)' (Get-InstallHint 'ffmpeg' $docScoop); Get-ToolFix 'ffmpeg' '' $docScoop | Add-DocFix }
    else {
        $fv = "$(& $ff.Source -version 2>$null | Select-Object -First 1)" -replace '^ffmpeg version (\S+).*', '$1'
        $fp = Test-Path (Join-Path (Split-Path $ff.Source) 'ffprobe.exe')
        Out-Check $(if ($fp) { 'OK' } else { 'WARN' }) 'ffmpeg' "$fv$(if (-not $fp) { ', but ffprobe.exe is missing next to it' })" "reinstall it: $(Get-RemoveHint 'ffmpeg' $ff.Source), then $((Get-UpdateHint 'ffmpeg' $ff.Source) -replace '^winget upgrade', 'winget install' -replace '^scoop update', 'scoop install' -replace '^choco upgrade', 'choco install')"
    }
    Test-ToolCopies 'ffmpeg'
    # deno (YouTube's JavaScript challenges)
    $dn = Get-Command deno -ErrorAction SilentlyContinue
    if (-not $dn) { Out-Check WARN 'deno' 'not found: yt-dlp may get only some formats (often 360p) or none' (Get-InstallHint 'deno' $docScoop); Get-ToolFix 'deno' '' $docScoop | Add-DocFix }
    else { Out-Check OK 'deno' ("$(& $dn.Source --version 2>$null | Select-Object -First 1)" -replace '^deno ', '') }
    Test-ToolCopies 'deno'
    # 1.22.0: PO-token provider (only used with -PoToken)
    $pd = Join-Path $env:LOCALAPPDATA 'ytdl\pot'
    $pz = Test-Path (Join-Path $pd 'plugins\bgutil-ytdlp-pot-provider.zip'); $pn = @(Get-ChildItem $pd -Directory -Filter 'server-*' -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName 'server\node_modules') })
    if ($pz -and $pn.Count) { Out-Check OK 'PO token' "bgutil $($pn[0].Name -replace '^server-', '') installed (used with -PoToken)" '' }
    else { Out-Check INFO 'PO token' 'not installed; ytdl -PoToken installs it on first use (needs deno)' '' }
    # Sign-in: -Browser/-Cookies given here, else the first subscription that uses one
    $sb = $Browser; $sc = $Cookies; $from = 'given'; $docSignOk = $false
    if (-not $sb -and -not $sc) { foreach ($x in @(Read-Subs)) { if ($x.Options.Browser) { $sb = $x.Options.Browser; $from = 'from your subscriptions'; break } elseif ($x.Options.Cookies) { $sc = $x.Options.Cookies; $from = 'from your subscriptions'; break } } }
    if (-not $sb -and -not $sc) { Out-Check INFO 'sign-in' 'not checked: add -Browser firefox (or -Cookies file) to test it' '' }
    elseif ($sc -and -not (Test-Path -LiteralPath $sc)) { Out-Check FAIL 'sign-in' "cookies file not found: $sc" 'export it again from your browser, or use -Browser' }
    elseif ($v) {
        $auth = if ($sb) { @('--cookies-from-browser', $sb) } else { @('--cookies', $sc) }
        $t0 = Get-Date
        $o = @(& $ytdlp @auth @userNetArgs --ignore-config -s --no-warnings --print '%(id)s %(availability)s' 'https://www.youtube.com/watch?v=jNQXAC9IVRw' 2>&1 | ForEach-Object { "$_" })
        $dt = ((Get-Date) - $t0).TotalSeconds
        $nc = ($o | Where-Object { $_ -match 'Extracted (\d+) cookies' } | ForEach-Object { $Matches[1] } | Select-Object -First 1)
        $who = if ($sb) { "$sb ($from)" } else { "cookies file ($from)" }
        if ($o -match 'not a bot|Sign in to confirm') { Out-Check FAIL 'sign-in' "$who`: YouTube asked to confirm you're not a bot" 'open youtube.com in that browser, check you are signed in, then try again' }
        elseif ($o -match 'cookies are no longer valid') { Out-Check FAIL 'sign-in' "$who`: YouTube says the cookies are no longer valid" 'sign in to YouTube again in that browser' }
        elseif ($o -match 'could not find|Failed to decrypt|Could not copy|database is locked|permission') { Out-Check FAIL 'sign-in' "$who`: couldn't read the browser's cookies ($(($o | Where-Object { $_ -match 'ERROR' } | Select-Object -First 1) -replace '^ERROR: ', ''))" 'close the browser (Chrome/Edge lock their cookies), or use -Browser firefox' }
        elseif ($o -match '^jNQXAC9IVRw') { $docSignOk = $true; Out-Check OK 'sign-in' ("$who`: $(if ($nc) { "$nc cookies read, " })YouTube answered in {0:N1} s" -f $dt) }
        else { Out-Check WARN 'sign-in' "$who`: no answer from YouTube ($(($o | Where-Object { $_ -match 'ERROR' } | Select-Object -First 1) -replace '^ERROR: ', ''))" 'check the internet connection; re-run ytdl -Doctor' }
    }
    # 1.27.0: why a browser's or a file's cookies may not work; the network (one HEAD to youtube.com), VPN/proxy
    if ($sb -and -not $docSignOk) {
        $docProcs = if ($env:YTDL_TEST_PROCS) { @($env:YTDL_TEST_PROCS -split ',') } else { @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object ProcessName) }
        Test-BrowserCookies $sb $docProcs | Out-Checks
    }
    if ($sc -and (Test-Path -LiteralPath $sc)) { Test-CookiesFile $sc (Get-Date) $docSignOk | Out-Checks }
    Test-Clock (Get-ClockSkew) | Out-Checks
    $docNet = Get-NetFacts; $docYtArgs = @($userNetArgs) + @($userDlArgs)
    Test-ProxyVpn @($docNet.Proxy) @($docNet.Vpn) $docYtArgs | Out-Checks
    $qn = @(Read-QueueRaw).Count; if ($qn) { Out-Check INFO 'queue' "$qn link(s) waiting for a download to finish (ytdl -Queue)" '' }   # 1.20.0
    $tb = Get-ToastBlock   # 1.18.1
    if ($Notify -eq 'off') { Out-Check INFO 'notifications' 'off (-Notify off)' '' }
    elseif ($tb) { Out-Check WARN 'notifications' "-Notify can't show anything: $tb" 'turn them on there, or use -Notify off to hide the note at the end of runs' }
    else { Out-Check OK 'notifications' 'Windows will show ytdl''s notifications (as Windows PowerShell)' }
    if ($userNetArgs.Count -or $userDlArgs.Count) { Out-Check INFO '-YtdlpArgs' "connection: $($userNetArgs -join ' ')  |  download: $($userDlArgs -join ' ')" '' }
    # Download folder: free space, pacing state, a run in progress
    $outExists = Test-Path -LiteralPath $Out
    try {
        $drv = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Out)); $free = (New-Object IO.DriveInfo($drv)).AvailableFreeSpace / 1GB
        $st = if ($free -lt $MinFreeGB) { 'FAIL' } elseif ($free -lt [math]::Max(10, $MinFreeGB * 5)) { 'WARN' } else { 'OK' }
        Out-Check $st 'disk' ('{0:N1} GB free on {1} (runs stop below {2} GB)' -f $free, $drv, $MinFreeGB) 'free some space, or download elsewhere with -Out'
    } catch { Out-Check WARN 'disk' "can't read the free space of $Out" '' }
    # 1.27.0: the drive type, long paths, and whether a file can be created in the folder
    Test-FolderType (Get-FolderFacts $Out) | Out-Checks
    $docLp = if ($env:YTDL_TEST_LONGPATHS) { $env:YTDL_TEST_LONGPATHS } else { try { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -ErrorAction Stop).LongPathsEnabled } catch { 0 } }
    Test-LongPaths ([IO.Path]::GetFullPath($Out)) $docLp | Out-Checks
    if ($outExists) { Test-FolderWrite $Out | Out-Checks }
    # 1.25.0: the limit guard (whole PC)
    $gp = Read-GlobalPace
    if ((Get-BreakerLeft $gp) -gt 0) { Out-Check FAIL 'limit guard' ((Get-BreakerText $gp) -replace '^YouTube limit guard: ', '') 'wait for that time; signing in (-Browser) can help once it has passed' }
    elseif ($gp.ProbeNeeded) { Out-Check WARN 'limit guard' 'a YouTube block has expired; the next run checks one video before it starts' 'nothing to do' }
    else { $nowE = Get-Epoch; $nIn = @($gp.LogIn | Where-Object { $_ -gt $nowE - 3600 }).Count; $nOut = @($gp.LogOut | Where-Object { $_ -gt $nowE - 3600 }).Count
           Out-Check OK 'limit guard' "no YouTube block; videos started in the last hour: $nIn signed in (budget 1000), $nOut signed out (budget 150)" '' }
    if ($outExists) {
        $pf = Join-Path $Out '.ytdl-pace.json'
        if (Test-Path $pf) {
            try { $pj = Get-Content $pf -Raw | ConvertFrom-Json; $hrs = ((Get-Date) - [datetime]$pj.Updated).TotalHours
                  $eff = [int]$pj.Level - [math]::Floor($hrs / 2)   # 1.25.0: one level less per 2 clean hours
                  if ($eff -gt 1) { Out-Check WARN 'pacing' ("level $eff after a bot check {0:N0} h ago: runs here start slower; it drops one level per 2 hours without one" -f $hrs) 'nothing to do: it resets by itself; signing in (-Browser) helps' }
                  else { Out-Check OK 'pacing' 'no recent bot check in this folder' } } catch { Out-Check WARN 'pacing' "can't read $pf" '' }
        } else { Out-Check OK 'pacing' 'no bot check ever recorded in this folder' }
        $li = Join-Path $Out '.ytdl.lock.info'
        $docHeld = Test-FolderLock $Out   # 1.26.0: the lock itself, not its note (a crash leaves the note behind)
        if ($docHeld) { Out-Check INFO 'running' "a run is using this folder: $((Get-Content $li -ErrorAction SilentlyContinue) -join ' ')" '' }
        elseif (Test-Path $li) { Out-Check INFO 'running' "nothing is running here (a run that was closed or crashed left a note: $((Get-Content $li -ErrorAction SilentlyContinue) -join ' '))" 'nothing to do: the next run replaces it'
                                   New-DocFix delete 'delete the note a closed or crashed run left (.ytdl.lock.info)' "Remove-Item '$li'" $true @{ Paths = @($li) } | Add-DocFix }   # 1.29.0
        # 1.26.0: how the last run here ended, and unfinished download files
        $docLast = Get-LastRun (Join-Path $Out '.ytdl-logs') $docHeld
        if ($docLast) { Out-Check $docLast.State 'last run' $docLast.Text $docLast.Fix; Test-IPv6 $docNet.IPv6 $docLast.Bot $docYtArgs | Out-Checks }
        $docParts = @(Get-PartialFiles $Out)
        if ($docParts.Count) {
            $pgb = ($docParts | Measure-Object Length -Sum).Sum / 1GB
            if ($docHeld) { Out-Check INFO 'unfinished' ('{0} download file(s), {1:N2} GB: the run in progress is using them' -f $docParts.Count, $pgb) '' }
            else { Out-Check $(if ($pgb -ge 1) { 'WARN' } else { 'INFO' }) 'unfinished' ('{0} leftover download file(s), {1:N2} GB, oldest from {2:d MMM}: re-running the same link resumes them' -f $docParts.Count, $pgb, ($docParts | Sort-Object LastWriteTime | Select-Object -First 1).LastWriteTime) "or delete them: Get-ChildItem '$Out' -Recurse -File -Include *.part,*.part-Frag*,*.ytdl,*.temp.* | Remove-Item"
                   New-DocFix delete ('delete the {0} leftover download file(s), {1:N2} GB (those downloads start over)' -f $docParts.Count, $pgb) "Get-ChildItem '$Out' -Recurse -File -Include *.part,*.part-Frag*,*.ytdl,*.temp.* | Remove-Item" $false @{ Paths = @($docParts | ForEach-Object FullName) } | Add-DocFix }   # 1.29.0: asks first
        }
        $ar = Join-Path $Out '.ytdl-archive.txt'
        Out-Check INFO 'folder' "$Out$(if (Test-Path $ar) { ": $(@(Get-Content $ar).Count) video(s) downloaded so far" } else { ' (nothing downloaded here yet)' })" ''
    } else { Out-Check INFO 'folder' "$Out (doesn't exist yet; created on the first download)" '' }
    # 1.28.0: ytdl -Doctor <url>: can this one video be downloaded, and how
    if ($Url) {
        $vid = if ($Url -notmatch 'youtube\.com/(@|channel/|c/|user/)' -and $Url -match '(?:[?&]v=|youtu\.be/|/shorts/|/live/|/embed/)([\w-]{11})') { $Matches[1] } else { '' }
        $vArch = Join-Path $Out $archName
        $vIds = if (Test-Path -LiteralPath $vArch) { @(Get-Content -LiteralPath $vArch | ForEach-Object { ("$_" -split '\s+')[1] }) } else { @() }
        $vIn = [bool]($Browser -or $Cookies); $vWho = if ($vIn) { 'In' } else { 'Out' }; $vMax = if ($vIn) { 1000 } else { 150 }
        $vUsed = @($gp["Log$vWho"] | Where-Object { $_ -gt (Get-Epoch) - 3600 }).Count
        if (-not $vid) { Out-Check INFO 'video' 'not checked: -Doctor <url> checks one video link (watch?v=..., youtu.be/..., shorts/...), not a playlist or channel' '' }
        elseif (-not $v) { Out-Check INFO 'video' 'not checked: yt-dlp is missing (see above)' '' }
        elseif ((Get-BreakerLeft $gp) -gt 0 -and -not $IgnoreCooldown) { Out-Check INFO 'video' 'not checked: the limit guard is on (see above); asking YouTube now could extend the block' 'wait for that time (-IgnoreCooldown checks anyway)' }
        elseif ($vUsed -ge $vMax) { Out-Check INFO 'video' "not checked: this hour's budget is used ($vUsed of $vMax videos $(if ($vIn) { 'signed in' } else { 'signed out' }))" 'try again within the hour' }
        else {
            $null = Update-GlobalPace { param($g, $now) $g["Log$vWho"] = @($g["Log$vWho"]) + $now }   # one request, counted like a video start
            $vAuth = if ($Browser) { @('--cookies-from-browser', $Browser) } elseif ($Cookies) { @('--cookies', $Cookies) } else { @() }
            $vf = Get-VideoFacts $Url $vAuth
            $vErr = $vf.Err -join "`n"
            if (-not $vf.Info -and $vErr -match $limitPattern) { $null = Add-PaceEvent $(if ($vErr -match $limit429Pattern) { '429' } else { 'bot' }) 0 }
            if ($vf.Info.title) { $script:docHide += "$($vf.Info.title)" }
            Test-Video $vf $Url $Quality ([bool]$AudioOnly) $vIn (Get-Date) | Out-Checks
        }
        if ($vid) { $script:docHide += $vid }
        Test-VideoArchive $vid $vIds $vArch | Out-Checks
    }
    # Subscriptions and the schedule
    $subList = @(Read-Subs)   # not $subs: that is the -Subs switch (names ignore case)
    if ($subList.Count) {
        $failing = @($subList | Where-Object { $_.LastExit -and [int]$_.LastExit -ne 0 })
        Out-Check $(if ($failing.Count) { 'WARN' } else { 'OK' }) 'subscriptions' "$($subList.Count) saved$(if ($failing.Count) { ", $($failing.Count) ended with errors last sync" })" 'see ytdl -Subscriptions, and the failed-videos list in that folder'
        $docTask = Get-TaskFacts $subTask
        Test-ScheduleTask $docTask $PSCommandPath | Out-Checks   # 1.27.0: result codes in words, settings
        Get-TaskFix $docTask $PSCommandPath | Add-DocFix   # 1.29.0
    } else { Out-Check INFO 'subscriptions' 'none (ytdl <channel url> -Subscribe adds one)' '' }
    Microsoft.PowerShell.Utility\Write-Host ''
    $docSum = if ($script:docBad) { "$($script:docBad) problem(s) found; the fix is under each one." } elseif ($script:docWarn) { "Works, with $($script:docWarn) thing(s) worth a look." } else { 'Everything ytdl needs is in order.' }
    if ($script:docBad) { Microsoft.PowerShell.Utility\Write-Host $docSum -ForegroundColor Red }
    elseif ($script:docWarn) { Microsoft.PowerShell.Utility\Write-Host $docSum -ForegroundColor Yellow }
    else { Write-PulseMark $docSum }
    # 1.29.0 -Fix: each fix with its command, asked one by one (-Yes: the safe ones run, the others are skipped),
    # what happened, then the checks once more (with PATH as Windows has it now, so new installs are found;
    # without the video link, so no second request for it). Without -Fix: one line saying how many it could make.
    $w = 'Microsoft.PowerShell.Utility\Write-Host'; $fx = $script:docFixes.ToArray()
    if (-not $Fix -and $fx.Count) { & $w "ytdl -Doctor -Fix can make $($fx.Count) of these fixes for you (it asks before each one)." -ForegroundColor Cyan }
    if ($Fix -and -not $fx.Count) { & $w "-Fix: nothing here that ytdl can fix by itself$(if ($script:docBad -or $script:docWarn) { '; the steps under each problem are for you' })." -ForegroundColor DarkGray }
    if ($Fix -and $fx.Count) {
        & $w ''; & $w "Fixes ytdl can make: $($fx.Count)$(if ($Yes) { ' (-Yes: the safe ones run; removing and deleting are skipped, run -Fix without -Yes for those)' })" -ForegroundColor Cyan
        $nDone = 0; $nFail = 0; $nSkip = 0; $n = 0
        foreach ($f in $fx) {
            $n++; & $w ('  {0}. {1}' -f $n, $f.Text); & $w ('     runs: {0}' -f $f.Cmd) -ForegroundColor DarkGray
            $go = if ($Yes) { $f.Safe } else { "$(Read-DocAnswer '     do it? [y/N]')".Trim() -match '^(y|yes)$' }
            if (-not $go) { $nSkip++; & $w "     skipped$(if ($Yes -and -not $f.Safe) { ': it asks first' })" -ForegroundColor DarkGray; continue }
            $r = Invoke-DocFix $f
            if ($r.Ok) { $nDone++; & $w "     done$(if ($r.Msg) { ": $($r.Msg)" })" -ForegroundColor Green }
            else { $nFail++; & $w "     failed$(if ($r.Msg) { ": $($r.Msg)" })" -ForegroundColor Red }
        }
        & $w ''; & $w "Fixes: $nDone done, $nFail failed, $nSkip skipped." -ForegroundColor $(if ($nFail) { 'Yellow' } else { 'Cyan' })
        if ($nDone -or $nFail) {
            & $w ''; & $w 'Checking again:' -ForegroundColor Cyan
            $env:PATH = (@([Environment]::GetEnvironmentVariable('Path', 'Machine'), [Environment]::GetEnvironmentVariable('Path', 'User'), $env:PATH) | Where-Object { $_ }) -join ';'
            $again = @{}; foreach ($k in @($PSBoundParameters.Keys)) { if ($k -notin 'Fix', 'Yes', 'Url') { $again[$k] = $PSBoundParameters[$k] } }
            $again['Doctor'] = [switch]$true
            & $PSCommandPath @again   # its own exit ends only that run; -Report (if given) is written there, after the fixes
            exit $LASTEXITCODE
        }
    }
    # 1.26.0 -Report: the results as a text file (and on the clipboard) for a GitHub issue, identifying parts hidden
    if ($Report) {
        $osName = try { $c = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop; "$($c.Caption) $($c.Version)" } catch { [Environment]::OSVersion.VersionString }
        $body = @("tubepacer doctor report (user, PC, folder names and links are hidden)", $docHead,
                  "Windows: $osName  |  installed: $(if ($docScoop) { 'Scoop' } else { 'by hand (zip or git)' })  |  console: $([Console]::OutputEncoding.WebName)", '') +
                @($script:docLines) + @('', $docSum) | ForEach-Object { ConvertTo-Redacted $_ }
        $rd = [Environment]::GetFolderPath('Desktop'); if (-not $rd -or -not (Test-Path -LiteralPath $rd)) { $rd = [IO.Path]::GetTempPath() }
        $rp = Join-Path $rd ('ytdl-doctor-{0:yyyyMMdd-HHmm}.txt' -f (Get-Date))
        try {
            $body | Set-Content -LiteralPath $rp -Encoding UTF8 -ErrorAction Stop
            $clip = try { ($body -join "`r`n") | Set-Clipboard -ErrorAction Stop; ' and copied to the clipboard' } catch { '' }
            Microsoft.PowerShell.Utility\Write-Host "Report saved to $rp$clip. Read it, then paste it into an issue: https://github.com/billyreagan/tubepacer/issues/new" -ForegroundColor Cyan
        } catch { Microsoft.PowerShell.Utility\Write-Host "Couldn't save the report to $rp ($($_.Exception.Message))" -ForegroundColor Yellow }
    }
    Restore-Console
    exit $(if ($script:docBad) { 1 } else { 0 })
}

New-Item -ItemType Directory -Force -Path $Out | Out-Null

# ---- folder lock (R1) and run log (R4) ----------------------------------------------------
# One ytdl run per output folder: two at once would download the same videos and both write
# the archive and ETA history. The lock is an exclusively opened file, so Windows releases it
# automatically if ytdl crashes; it can never go stale. Workers run under their coordinator's
# lock; -Estimate only reads, so neither takes it.
$lockStream = $null
$lockPath   = Join-Path $Out '.ytdl.lock'
function Release-Lock {
    if ($script:lockStream) { try { $script:lockStream.Dispose() } catch { }; $script:lockStream = $null
        Remove-Item "$lockPath.info", $lockPath -Force -ErrorAction SilentlyContinue }
    if ($script:runLog) { try { $script:runLog.Dispose() } catch { }; $script:runLog = $null }
}
if ($Worker -eq 0 -and -not $Estimate) {
    try { $lockStream = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
    catch {
        $info = (Get-Content "$lockPath.info" -ErrorAction SilentlyContinue) -join ' '
        Write-Host "Another ytdl run is already downloading to $Out ($info)." -ForegroundColor Yellow
        Write-Host "Wait for it to finish, or stop it with 'ytdl -Stop', then run this again." -ForegroundColor Yellow
        Restore-Console; exit 3
    }
    "pid $PID, started $((Get-Date).ToString('s')), $Url" | Set-Content "$lockPath.info" -Encoding UTF8
    Register-Run $Url   # 1.20.0

    $logDir = Join-Path $Out '.ytdl-logs'
    try {
        New-Item -ItemType Directory -Force $logDir | Out-Null
        $logPath = Join-Path $logDir ('{0:yyyyMMdd-HHmmss}-{1}.log' -f (Get-Date), $PID)
        $script:runLog = New-Object IO.StreamWriter($logPath, $false, (New-Object Text.UTF8Encoding($false)))
        $script:runLog.AutoFlush = $true
        Write-LogOnly "ytdl $YtdlVersion | $($MyInvocation.Line)"
        Write-LogOnly "[ytdl-event] yt-dlp: $ytdlp"
        Get-ChildItem $logDir -Filter *.log | Sort-Object LastWriteTime -Descending | Select-Object -Skip 50 | Remove-Item -Force -ErrorAction SilentlyContinue
    } catch { $script:runLog = $null }
}

# Output layout:
#   playlist -> <Out>\<Playlist Title>\001 - <Video Title> [id].ext
#   single   -> <Out>\YouTube\<Video Title> [id].ext
# One template for both cases: playlist fields are used when present, else fall back.
$dir  = if ($Folder) { $Folder } else { '%(playlist_title|YouTube)s' }
$name = if ($isChannelTab) { '%(upload_date>%Y-%m-%d&{} - |)s%(title)s [%(id)s].%(ext)s' }   # 1.15.0
        else { '%(playlist_index&{:03d} - |)s%(title)s [%(id)s].%(ext)s' }
# 1.19.0 -Library: a show per channel (or -Folder), a season per upload year, date-based episode names that
# Plex and Jellyfin both read ("Show - 2026-11-13 - Title"). A video without a date goes to Season 0000.
$libArgs = @()
if ($Library) {
    $show = if ($Folder) { $Folder -replace '%', '%%' } else { '%(channel,uploader,playlist_title|YouTube)s' }
    $dir  = "$show/Season %(upload_date>%Y|0000)s"
    # 1.20.1: numbered, not date-named. Season = upload year, episode = month, day and upload hour (MMDDHH), so two
    # uploads on one day differ (1.19.0 named both "Show - <date>", which Plex can merge into one episode).
    $ep   = '%(upload_date>%m%d|0000)s%(timestamp>%H|00)s'
    $base = "$show - s%(upload_date>%Y|0000)se$ep - %(title)s [%(id)s]"
    $name = "$base.%(ext)s"
    # Episode image next to each video (Jellyfin: <name>-thumb.jpg; Plex: <name>.jpg) and the playlist or
    # channel image as the show's poster.jpg; jpg because both servers read it
    $thumbName = if ($Library -eq 'jellyfin') { "$dir/$base-thumb.%(ext)s" } else { "$dir/$base.%(ext)s" }
    if ($Template) { Write-Host "[ytdl] -Template doesn't go with -Library (the media-server layout names the files); ignoring -Template." -ForegroundColor Yellow }
    $libArgs = @('--write-thumbnail', '--convert-thumbnails', 'jpg', '-o', "thumbnail:$thumbName", '-o', "pl_thumbnail:$show/poster.%(ext)s")
    if ($Library -eq 'jellyfin') {
        # One-line episode .nfo written by yt-dlp after the move (%(..)h = HTML-escaped). Season = year,
        # episode = MMDD, so episodes sort by date; the uniqueid lets Jellyfin match the YouTube video.
        $nfo = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><episodedetails><title>%(title)h</title>' +
                '<showtitle>%(channel,uploader,playlist_title)h</showtitle><season>%(upload_date>%Y|0)s</season>' +
                '<episode>' + $ep + '</episode><aired>%(upload_date>%Y-%m-%d)s</aired><plot>%(description)h</plot>' +
                '<runtime>%(duration>%M|0)s</runtime><uniqueid type="youtube" default="true">%(id)s</uniqueid></episodedetails>'
        $libArgs += @('--print-to-file', "after_move:$nfo", "$(($Out -replace '%', '%%').TrimEnd('\'))/$dir/$base.nfo")
    }
}

# 1.23.0 -Template: the file name only; the folder stays ytdl's
if ($Template -and -not $Library) {
    $name = $Template.Trim()
    if ($name -notmatch '%\(ext\)s$') { $name += '.%(ext)s' }
    if ($name -notmatch '%\(id\)s' -and $Worker -eq 0) { Write-Host "[ytdl] Note: -Template has no [%(id)s]. Repeats are still skipped (the archive), but two videos with the same title can collide, and the id is how the file can be matched to its video later." -ForegroundColor DarkGray }
}
# 1.23.0 -Section: the clip's times in its name, so clips of one video don't overwrite each other
if ($clipTag) { $name = $name -replace '\.%\(ext\)s$', " ($clipTag).%(ext)s" }
# 1.23.0 -Codec / -Container: preferences after the height (res stays first, so -Quality still decides)
$fmtSort = 'res'
switch ($Codec) { 'h264' { $fmtSort += ',vcodec:h264,acodec:aac' } 'vp9' { $fmtSort += ',vcodec:vp9' } 'av1' { $fmtSort += ',vcodec:av01' } }
if ($Container -eq 'webm') { $fmtSort += ',ext:webm:webm' }
$fmtSort += ',proto'

$ytArgs = @(
    '--paths', $Out,
    '-o', "$dir/$name",
    '--yes-playlist',
    '--ignore-errors',                       # skip private/removed videos instead of stopping
    '--download-archive', (Join-Path $Out $archName),  # re-runs skip finished videos (1.23.0: clips keep their own)
    '--no-overwrites',
    '--continue',


    '--windows-filenames',
    '--progress',
    '--progress-delta', $progressDelta,      # output is piped (to detect errors), so throttle progress lines (1.17.0: 1 s with the bar)
    '--socket-timeout', '30',                # fail a dead connection instead of waiting forever
    '--retries', '10',
    '--fragment-retries', '10',
    '--abort-on-unavailable-fragments',      # a video with missing pieces fails (and is retried) instead of saving a broken file
    '-S', $fmtSort                           # same resolution: prefer plain https over fragmented (HLS/DASH) streams
)
# 1.25.0: back off between yt-dlp's own retries (they used to fire back to back, adding requests to a block)
if (@($userDlArgs) -notcontains '--retry-sleep') {
    $ytArgs += @('--retry-sleep', 'extractor:exp=5:300', '--retry-sleep', 'http:exp=1:30', '--retry-sleep', 'fragment:exp=1:20')
}

if ($AudioOnly) {
    # 1.21.0: m4a and opus keep YouTube's own stream (yt-dlp only rewraps it when the codec already matches)
    switch ($(if ($AudioFormat) { $AudioFormat } else { 'mp3' })) {
        'm4a'   { $fmt = 'bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/bestaudio'; $ytArgs += @('-f', $fmt, '-x', '--audio-format', 'm4a') }
        'opus'  { $fmt = 'bestaudio[acodec=opus]/bestaudio'; $ytArgs += @('-f', $fmt, '-x', '--audio-format', 'opus') }
        'best'  { $fmt = 'bestaudio/best'; $ytArgs += @('-f', $fmt, '-x', '--audio-format', 'best') }
        default { $fmt = 'bestaudio/best'; $ytArgs += @('-f', $fmt, '-x', '--audio-format', 'mp3', '--audio-quality', '0') }
    }
} else {
    # 1.18.2: the limit applies to the shorter side, so vertical videos (Shorts) get the same class as wide ones.
    # Height alone gave a vertical 360p request the 144x256 stream and a 1080p one 608x1080 (benchmark E5S: 6 of
    # 120 videos at 256 px). Unknown aspect ratio counts as landscape (the old filter).
    $fmt = if ($Quality -eq 'best') { 'bv*+ba/b' } else { "bv*[height<=$Quality][aspect_ratio>=?1]+ba/bv*[width<=$Quality][aspect_ratio<1]+ba/b[height<=$Quality][aspect_ratio>=?1]/b[width<=$Quality][aspect_ratio<1]" }
    if ($Fast360) {
        if ($Quality -eq '360') { $fmt = "18/$fmt" }
        else { Write-Host "[ytdl] -Fast360 only applies with -Quality 360; ignoring it." -ForegroundColor Yellow }
    }
    $merge = switch ($Container) { 'mkv' { 'mkv' } 'webm' { 'webm/mkv' } default { 'mp4' } }   # 1.23.0
    $ytArgs += @('-f', $fmt, '--merge-output-format', $merge)
}

# 1.23.0: -SubLangs picks the languages (implies -Subs); -LiveChat adds the chat replay (a .json file, never embedded)
$subList = @()
if ($Subs -or $SubLangs) {
    $subList += $(if ($SubLangs -eq 'all') { @('all', '-live_chat') } elseif ($SubLangs) { @($SubLangs -split '\s*,\s*' | Where-Object { $_ }) } else { @('en.*') })
}
if ($LiveChat) { $subList += 'live_chat' }
if ($subList) {
    $ytArgs += @('--write-subs', '--sub-langs', ($subList -join ','))
    if ($Subs -or $SubLangs) { $ytArgs += @('--write-auto-subs', '--embed-subs') }
}
if ($Section) {
    foreach ($sp in @($Section -split '\s*,\s*' | Where-Object { $_ })) { $ytArgs += @('--download-sections', "*$sp") }
    $ytArgs += '--force-keyframes-at-cuts'   # exact cut points (re-encodes the edges) instead of the nearest keyframe
}
# 1.23.0 -Live: record a stream from its start (or wait for it to start, checking every minute). A live stream
# drops pieces now and then; skip them instead of failing the whole recording.
if ($Live) {
    $ytArgs = @($ytArgs | Where-Object { $_ -ne '--abort-on-unavailable-fragments' })
    $ytArgs += @('--live-from-start', '--wait-for-video', '60', '--skip-unavailable-fragments')
}
if ($SplitChapters) { $ytArgs += @('--split-chapters', '-o', "chapter:$dir/%(title)s [%(id)s]/%(section_number)03d - %(section_title)s.%(ext)s") }
if ($ItemsStr) { $ytArgs += @('--playlist-items', $ItemsStr) }

# 1.16.0 filters, for yt-dlp. One --match-filters holding all conditions (several are OR'ed). In a
# quoted value yt-dlp needs ' and & escaped. A video whose duration is unknown passes the length limits.
function ConvertTo-FilterValue([string]$s) { "'" + ($s -replace "'", "\'" -replace '&', '\&') + "'" }
$mf = @()
if ($MinMinutes -gt 0) { $mf += "duration>=?$([int][math]::Round($MinMinutes * 60))" }
if ($MaxMinutes -gt 0) { $mf += "duration<=?$([int][math]::Round($MaxMinutes * 60))" }
if ($Match)   { $mf += 'title~=' + (ConvertTo-FilterValue "(?i)$Match") }
if ($Exclude) { $mf += 'title!~=' + (ConvertTo-FilterValue "(?i)$Exclude") }
if ($mf) { $ytArgs += @('--match-filters', ($mf -join ' & ')) }
# -After: the scan already trims by approximate date (Select-Filtered); yt-dlp checks the exact date.
# A channel tab lists newest first, so there the first older video ends the run (--break-match-filters;
# yt-dlp exits 101, which counts as success). Not together with --dateafter: yt-dlp applies that first,
# and its rejection skips the break check, so every old video was opened (seen in a real test).
$breakFilter = $false
if ($afterDate) {
    $ad = $afterDate.ToString('yyyyMMdd')
    if ($isChannelTab) { $ytArgs += @('--break-match-filters', "upload_date>=?$ad"); $breakFilter = $true }   # ?: no date (premiere) doesn't end it
    else { $ytArgs += @('--dateafter', $ad) }
}
# -Sync: record each finished file (upload date, id, final path) for the subscription's -Keep/-KeepDays
if ($FileList) { $ytArgs += @('--print-to-file', "after_move:%(upload_date)s`t%(id)s`t%(filepath)s", $FileList) }
# 1.23.0: every finished file goes into the history (ytdl -History). yt-dlp reads % in the file name as a field.
try { [void](New-Item -ItemType Directory -Force -Path $stateDir) } catch { }
$ytArgs += @('--print-to-file', "after_move:%(epoch)s`t%(id)s`t%(height|)s`t%(filepath)s`t%(title)s", ($historyFile -replace '%', '%%'))

$authArgs = @()
if ($Browser) { $authArgs += @('--cookies-from-browser', $Browser) }
if ($Cookies) {
    if (-not (Test-Path $Cookies)) { Write-Error "Cookies file not found: $Cookies" }
    $authArgs += @('--cookies', $Cookies)
}
$authArgs += $userNetArgs   # 1.18.0: -YtdlpArgs connection options reach every yt-dlp call (all of them include $authArgs)
if (-not $NoMetadata)  { $ytArgs += '--embed-metadata' }
if (-not $NoThumbnail) {
    # 1.23.0: yt-dlp can't put a thumbnail inside webm, so it is saved next to the file instead
    if ($Container -eq 'webm' -and -not $AudioOnly) { if (-not $Library) { $ytArgs += @('--write-thumbnail', '--convert-thumbnails', 'jpg') } }
    else { $ytArgs += '--embed-thumbnail' }
}
$ytArgs += $libArgs   # 1.19.0
# 1.21.0 -SponsorBlock: download only (lookups don't need it); marks become chapters, removal cuts the file
if ($SponsorBlock -eq 'mark') { $ytArgs += @('--sponsorblock-mark', 'all') }
elseif ($SponsorBlock -eq 'remove') { $ytArgs += @('--sponsorblock-remove', 'sponsor,selfpromo,interaction') }
# 1.21.0 -LimitRate: yt-dlp's --limit-rate applies per download stream, so each worker gets its share of the
# total (a single run all of it); pieces are turned off below (with them a 1M cap measured up to 2.2 MiB/s)
if ($limitBytes -gt 0) {
    $share = if ($Worker -gt 0) { [math]::Max(1, $WorkerCount) } else { 1 }
    $ytArgs += @('--limit-rate', [string][int64][math]::Floor($limitBytes / $share))
}
$ytArgs += $authArgs
$ytArgs += $userDlArgs    # 1.18.0: the other -YtdlpArgs options, for the download only

# ---- pacing (S1 adaptive, R7 shared between workers) ----------------------------------------
# Pauses (sleep between videos + sleep before each page request) were ~14 of the ~25 s fixed
# cost per video at the old fixed -Sleep 5. With -Sleep auto (default), a signed-in run starts
# at the fastest level and steps up on any bot check / rate limit. The level is shared through
# <Out>\.ytdl-pace.json: parallel workers follow the slowest, and the next run within 24 h starts
# where the last bot check left off. An explicit -Sleep N keeps the old fixed behaviour.
# 1.5.0: L0 = no pauses at all (360p benchmark: 28% faster than the 0.5 s request pause, no bot
# checks); L1 = the 1.4.x L0 (0.5 s per request), then 3 / 5 / 10 / 20 s. Bot checks step up as before.
$paceLevels = @(@{ S = 0; R = 0 }, @{ S = 0; R = 0.5 }, @{ S = 3; R = 1 }, @{ S = 5; R = 1 }, @{ S = 10; R = 2 }, @{ S = 20; R = 3 })
$autoPace   = ($Sleep -lt 0)
$paceFile   = Join-Path $Out '.ytdl-pace.json'
# 1.17.1: test hook, for benchmarks only. YTDL_TEST_BOTCHECK=N turns the Nth download progress line into
# the bot-check message yt-dlp prints, once per output folder (shared by all workers), so ytdl's real
# recovery (stop, slow down one level, tell the other workers, resume the partial file) can be timed.
$testBot = 0; [void][int]::TryParse("$env:YTDL_TEST_BOTCHECK", [ref]$testBot)
$testBotFlag = Join-Path $Out '.ytdl-testbot'; $testBotN = 0; $testBotFired = $false
$paceLevel  = 2
# 1.25.0 (AIMD): the floor is where a run starts and the lowest it speeds back down to. Signed in starts
# at L1 (0.5 s per request), not L0; a batch of 20 or fewer videos still gets L0 (set after the scan).
$paceIdent  = if ($Browser -or $Cookies) { 'In' } else { 'Out' }
$paceFloor  = 0
$decayVideos = 25        # clean videos in a row before speeding up one level (within a run)
if ($autoPace) {
    $paceFloor = if ($paceIdent -eq 'In') { 1 } else { 3 }   # unsigned: 5 s pauses, as before
    if ($StartFloor -ge 0) { $paceFloor = [math]::Min($paceFloor, $StartFloor) }
    $paceLevel = $paceFloor
    # A saved level loses one step per 2 hours since the last bot check (it used to hold for 24 h, then drop to the floor).
    if (Test-Path $paceFile) {
        try { $pf = Get-Content $paceFile -Raw | ConvertFrom-Json
              $saved = [int]$pf.Level; if (-not $pf.Scheme) { $saved++ }   # 1.3/1.4 numbering had no no-pause level
              $saved = [math]::Min($saved, $paceLevels.Count - 1) - [math]::Floor(((Get-Date) - [datetime]$pf.Updated).TotalHours / 2)
              if ($saved -gt $paceLevel) { $paceLevel = [int]$saved } } catch { }
    }
    # ...and so does the level the last trip on this PC reached (any folder: YouTube limits the IP, not the folder)
    $gp0 = Read-GlobalPace
    $held = [math]::Min($gp0.Level, $paceLevels.Count - 1) - [math]::Floor(((Get-Epoch) - $gp0.LevelAt) / 7200)
    if ($held -gt $paceLevel) { $paceLevel = [int]$held }
}
function Get-PaceSleep { if ($autoPace) { $paceLevels[$script:paceLevel].S } else { $Sleep } }
function Get-PaceReq   { if ($autoPace) { $paceLevels[$script:paceLevel].R } elseif ($Sleep -gt 0) { 1 } else { 0 } }
function Get-PaceArgs {
    $s = Get-PaceSleep; $r = [double](Get-PaceReq)
    # 1.25.0: +/-50% on the request pause, new each launch (yt-dlp's own value is fixed, which is a pattern)
    if ($autoPace -and $r -gt 0) { $r = [math]::Round($r * (0.5 + (Get-Random -Minimum 0.0 -Maximum 1.0)), 2) }
    $a = @()
    if ($s -gt 0) { $a += @('--sleep-interval', $s, '--max-sleep-interval', ($s * 2)) }
    if ($r -gt 0) { $a += @('--sleep-requests', $r.ToString([Globalization.CultureInfo]::InvariantCulture)) }
    # 1.25.0: captions have a stricter limit of their own; after a subtitle 429, pause 10 s before each one
    if ($subList) { $ss = if ($script:subSlow) { 10 } elseif ($s -gt 0 -or $r -gt 0) { 2 } else { 0 }; if ($ss -gt 0) { $a += @('--sleep-subtitles', $ss) } }
    $a
}
function Get-PaceLabel {
    $s = Get-PaceSleep
    if ($autoPace) {
        if ($s -le 0 -and (Get-PaceReq) -le 0) { "level $($script:paceLevel) (no pauses)" }
        elseif ($s -le 0) { "level $($script:paceLevel) ($(Get-PaceReq) s per request, no pause between videos)" }
        else { "level $($script:paceLevel) ($s-$($s * 2) s between videos)" } }
    elseif ($s -gt 0) { "fixed -Sleep $s" } else { 'no pauses' }
}
# 1.25.0: one-line pace status, at the start and after each level change
function Get-PaceStatus {
    $now = Get-Epoch; $n = @((Read-GlobalPace)["Log$paceIdent"] | Where-Object { $_ -gt $now - 3600 }).Count
    $who = if ($paceIdent -eq 'In') { 'signed in' } else { 'signed out' }
    $lv = if ($autoPace) { "L$($script:paceLevel)" } else { Get-PaceLabel }
    "pace $lv | $who | $n of $budgetMax videos this hour on this PC | clean for $($script:cleanVids) video(s)"
}
function Save-PaceLevel { try { @{ Level = $script:paceLevel; Scheme = 2; Updated = (Get-Date).ToString('s') } | ConvertTo-Json | Set-Content $paceFile -Encoding ASCII } catch { } }

# 1.25.0: the hourly budget (about half of yt-dlp's wiki figures: guest ~300 videos/h, account ~2000/h).
$budgetMax = if ($paceIdent -eq 'In') { 1000 } else { 150 }
$tb = 0; if ([int]::TryParse("$env:YTDL_TEST_BUDGET", [ref]$tb) -and $tb -gt 0) { $budgetMax = $tb }   # test hook
$breakerOn = -not $IgnoreCooldown
$breakerStop = $false; $budgetStepped = $false; $budgetLastId = $null; $budgetWait = 0; $budgetUsed = 0
$cleanVids = 0; $subSlow = $false; $botAdvised = $false; $unavailN = 0; $maxTrips = 0; $paceSim = $false
# The breaker: refuse to start while it's open; after it closes, check one video before the real run.
if ($breakerOn) {
    $gp = Read-GlobalPace
    if ((Get-BreakerLeft $gp) -gt 0) {
        Write-Host "[ytdl] $(Get-BreakerText $gp)" -ForegroundColor Yellow
        Release-Lock; Unregister-Run; Restore-Console; exit 75
    }
    if ($gp.ProbeNeeded -and $Worker -eq 0 -and $Url) {
        Write-Host "[ytdl] A YouTube block on this PC has expired; checking one video before starting..." -ForegroundColor DarkGray
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'   # stderr lines must not terminate
        $po = @(& $ytdlp --simulate --no-warnings --playlist-items 1 --print id @authArgs $Url 2>&1 | ForEach-Object { "$_" })
        $ErrorActionPreference = $eap
        $hit = @($po | Where-Object { $_ -match $limitPattern -and $_ -notmatch $limitSkipPattern })
        if ($hit.Count) {
            Write-LogOnly "[ytdl-event] limit probe failed: $($hit[0])"
            Open-Breaker $(if ($hit[0] -match $limit429Pattern) { '429' } else { 'bot' })
            Write-Host "[ytdl] Still blocked. $(Get-BreakerText (Read-GlobalPace))" -ForegroundColor Yellow
            Release-Lock; Unregister-Run; Restore-Console; exit 75
        }
        [void](Update-GlobalPace { param($g, $now) $g.ProbeNeeded = $false })
        Write-Host "[ytdl] The check passed; starting at pacing $(Get-PaceLabel)." -ForegroundColor DarkGray
    }
}

# ---- fast extraction (1.4.0) ----------------------------------------------------------------
# yt-dlp's default client set makes ~6 requests per video; web_embedded with HLS skipped makes ~4
# and picked the identical formats for 20/20 test cases (5 videos x best/1080/480/360), saving
# ~1.4 s per video. web_embedded can't see videos with embedding disabled (or age-restricted), so
# any such error makes ytdl fall back to the default clients for the rest of the run, and the
# URL is remembered in <Out>\.ytdl-client.json for 7 days.
# 1.11.0: per URL, not per folder. One playlist of embedding-disabled uploads switched the whole
# Videos folder (every playlist downloaded there) to the slower default clients for 7 days.
# The 1.4.0-1.10.0 file format ({Fast, Updated} for the whole folder) is ignored.
$clientFile = Join-Path $Out '.ytdl-client.json'
$fastClient = -not $NoFastClient
function Read-ClientFile {
    $m = @{}
    try { $cf = Get-Content $clientFile -Raw | ConvertFrom-Json
          if ($cf.Urls) { $cf.Urls.PSObject.Properties | ForEach-Object { try { $m[$_.Name] = [datetime]$_.Value } catch { } } } } catch { }
    $m
}
if ($fastClient -and (Test-Path $clientFile)) {
    $cm = Read-ClientFile
    if ($cm.ContainsKey($Url) -and ((Get-Date) - $cm[$Url]).TotalDays -lt 7) { $fastClient = $false }
}
function Get-ClientArgs { if ($script:fastClient) { @('--extractor-args', 'youtube:player_client=web_embedded;skip=hls') } else { @() } }
function Save-ClientFallback {
    try {
        $cm = Read-ClientFile; $now = Get-Date; $keep = [ordered]@{}
        foreach ($k in $cm.Keys) { if (($now - $cm[$k]).TotalDays -lt 7) { $keep[$k] = $cm[$k].ToString('s') } }
        $keep[$Url] = $now.ToString('s')
        @{ Urls = $keep } | ConvertTo-Json -Depth 3 | Set-Content $clientFile -Encoding UTF8
    } catch { }
}
$clientFallbackPattern = 'Playback on other websites has been disabled|embedding (has been )?disabled|Requested format is not available|Video unavailable|This video is not available|Sign in to confirm your age|age.restricted|inappropriate for some users'
# 1.22.1: YouTube's account rate limit arrives as "Video unavailable. This content isn't available, try again
# later. Your account has been rate-limited ... for up to an hour." It matched 'Video unavailable' above and in
# $permPattern, so it switched clients and was labeled "won't fix itself". It is transient: these words win.
$transientPattern = 'try again later|rate.?limit|HTTP Error 429|Too Many Requests'

$ytArgs += $Url

$archive = Join-Path $Out $archName   # 1.23.0: a clip run uses its own
# 1.7.0: the archive is held in memory and only newly appended lines are read (yt-dlp appends one
# line per finished video). 1.6.x searched the whole file once per video: 1,463 searches at the start
# of a real run and one per finished video, growing with the archive.
$archSet = New-Object 'System.Collections.Generic.HashSet[string]'
$archPos = 0L
function Update-ArchiveSet {
    if (-not (Test-Path -LiteralPath $archive)) { return }
    try {
        $fs = [IO.File]::Open($archive, 'Open', 'Read', 'ReadWrite')
        try {
            if ($fs.Length -lt $script:archPos) { $script:archSet.Clear(); $script:archPos = 0L }   # rewritten/truncated
            if ($fs.Length -eq $script:archPos) { return }
            [void]$fs.Seek($script:archPos, 'Begin')
            $buf = New-Object byte[] ($fs.Length - $script:archPos)
            $got = 0; while ($got -lt $buf.Length) { $r = $fs.Read($buf, $got, $buf.Length - $got); if ($r -le 0) { break }; $got += $r }
            $end = [array]::LastIndexOf($buf, [byte]10, $got - 1)   # complete lines only; a half-written one waits
            if ($got -le 0 -or $end -lt 0) { return }
            $text = [Text.Encoding]::UTF8.GetString($buf, 0, $end + 1)
            $script:archPos += $end + 1
            foreach ($ln in ($text -split "`r?`n")) { $t = $ln.Trim().TrimStart([char]0xFEFF); if ($t) { [void]$script:archSet.Add($t) } }
        } finally { $fs.Dispose() }
    } catch { }
}
function Get-ArchiveCount { Update-ArchiveSet; $archSet.Count }
$archStart0 = 0; if ($Worker -eq 0 -and -not $Estimate) { try { $archStart0 = Get-ArchiveCount } catch { } }   # 1.18.0: for the notification's count

# ---- ETA ------------------------------------------------------------------------------------
# Model, per video:   wall time = overhead + size_MiB * secPerMiB
#   overhead  : fixed cost (sleeps, page/player requests, merge, embed). Measured directly per
#               finished video as wall time minus its exact transfer time ("100% of X in hh:mm:ss").
#   secPerMiB : bandwidth. Measured LIVE in this run from progress lines (even mid-download), so the
#               first estimate reflects today's speed instead of last run's. Falls back to saved history.
#   size_MiB  : exact with -Precise; otherwise runtime * bitrate, where bitrate (MiB per second of
#               video) is learned per quality. Bitrate is a property of the videos, not the network,
#               so it stays stable between runs, unlike bandwidth.
# History (<Out>\.ytdl-rate.json) is decayed on load so it never outweighs fresh measurements.
# Earlier designs: runtime-ratio (0.7.0) was off by up to 141%; one a*x+b regression (0.7.1) worked
# at 360p but inherited the previous run's bandwidth (+34% on a run's first estimate).
$rateFile = Join-Path $Out '.ytdl-rate.json'
$ci = [Globalization.CultureInfo]::InvariantCulture

function Format-Dur([double]$sec) {
    $t = [timespan]::FromSeconds([math]::Max(0, [math]::Round($sec)))
    if ($t.TotalHours -ge 1) { '{0}h {1:D2}m' -f [int][math]::Floor($t.TotalHours), $t.Minutes }
    else { '{0}m {1:D2}s' -f $t.Minutes, $t.Seconds }
}

function Test-Archived([string]$id, [switch]$NoRefresh) {
    if (-not $NoRefresh) { Update-ArchiveSet }
    $archSet.Contains("youtube $id")
}

# One cheap listing request (no per-video page loads): id + duration (+ playlist position) for every item.
$queueIndex = @{}   # id -> playlist_index (used by -Parallel to split work)
$queueTitle = @{}   # id -> title (1.16.0: for the failed-videos list and the title filters)
$queueDate  = @{}   # id -> approximate upload date yyyyMMdd (1.16.0: channel tabs, for -After)
# 1.16.0: the title is printed last, so its spaces don't shift the other fields. approximate_date makes
# a channel tab's flat listing carry upload dates ("2 weeks ago", so +-days) at no extra cost.
function Get-ScanArgs {
    $scan = @('--flat-playlist', '--yes-playlist', '--extractor-args', 'youtubetab:approximate_date',
              '--print', '%(id)s %(duration)s %(playlist_index)s %(upload_date)s %(title)s') + $authArgs
    if ($ItemsStr) { $scan += @('--playlist-items', $ItemsStr) }
    $scan + $Url
}
function ConvertFrom-ScanLines($lines) {
    $q = [ordered]@{}
    foreach ($l in $lines) {
        $p = "$l".Trim() -split ' ', 5
        if ($p[0] -match '^[\w-]{11}$') {
            $d = 0.0
            if ($p.Count -ge 2) { [void][double]::TryParse($p[1], [Globalization.NumberStyles]::Float, $ci, [ref]$d) }
            $q[$p[0]] = $d
            $pi = 0
            if ($p.Count -ge 3 -and [int]::TryParse($p[2], [ref]$pi)) { $script:queueIndex[$p[0]] = $pi }
            if ($p.Count -ge 4 -and $p[3] -match '^\d{8}$') { $script:queueDate[$p[0]] = $p[3] }
            if ($p.Count -ge 5 -and $p[4] -and $p[4] -ne 'NA') { $script:queueTitle[$p[0]] = $p[4] }
        }
    }
    return $q
}
function Get-Queue {
    $scan = Get-ScanArgs
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $lines = & $ytdlp @scan 2>$null
    $ErrorActionPreference = $eap
    return (ConvertFrom-ScanLines $lines)
}
# 1.16.0: the filters applied to the scan, so filtered videos aren't counted, estimated or handed to
# workers. -After uses the approximate dates: YouTube rounds "time ago" down ("1 month ago" = 30-59
# days), so an approximate date is never older than the real one; one before the cutoff (less 2 days
# for time zones) is certainly older. Near the cutoff yt-dlp's exact date decides. A real -After 30 days
# sync of a 1,218-video channel otherwise opened every old video just to reject it (610 in 10 minutes).
function Select-Filtered($q) {
    if (-not ($MinMinutes -gt 0 -or $MaxMinutes -gt 0 -or $Match -or $Exclude -or $afterDate)) { return $q }
    $keep = [ordered]@{}; $out = 0; $today = (Get-Date).Date
    foreach ($id in $q.Keys) {
        $d = [double]$q[$id]; $t = [string]$script:queueTitle[$id]
        $ok = $true
        if ($afterDate -and $script:queueDate.ContainsKey($id)) {
            $up = [datetime]::ParseExact($script:queueDate[$id], 'yyyyMMdd', $ci)
            if ($up -lt $afterDate.AddDays(-2)) { $ok = $false }
        }
        if ($d -gt 0 -and $MinMinutes -gt 0 -and $d -lt $MinMinutes * 60) { $ok = $false }
        if ($d -gt 0 -and $MaxMinutes -gt 0 -and $d -gt $MaxMinutes * 60) { $ok = $false }
        if ($t -and $Match -and $t -notmatch $Match) { $ok = $false }
        if ($t -and $Exclude -and $t -match $Exclude) { $ok = $false }
        if ($ok) { $keep[$id] = $q[$id] } else { $out++ }
    }
    if ($out) { Write-Host "[ytdl] Filters leave out $out of $($q.Count) video(s)." -ForegroundColor DarkGray }
    $keep
}

# Quotes one argument for a Start-Process command line (moved up in 1.18.2: Get-Sizes needs it)
function Quote-Arg([string]$a) { '"' + ($a -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' }

# -Precise: full metadata lookup for the given ids at the download's format, returning exact sizes.
# 1.18.2: 3 yt-dlp processes at once (ids dealt round-robin), the fast extraction client, and the pacing
# level's pause per request instead of a fixed 1 s (signed in: none). 1.18.1 looked them up one at a time
# with 1 s per request: 12 videos 103 s, 50 videos 409 s, slower than yt-dlp -s (38 / 153 s). Ids the fast
# client can't answer are tried once more with yt-dlp's default clients.
function Get-Sizes([string[]]$ids) {
    $out = @{}
    $passes = @(, (Get-ClientArgs)); if ($script:fastClient) { $passes += , @() }
    foreach ($clientArgs in $passes) {
        $todo = @($ids | Where-Object { -not $out.ContainsKey($_) }); if (-not $todo.Count) { break }
        $nP = [math]::Min(3, $todo.Count)
        $procs = for ($k = 0; $k -lt $nP; $k++) {
            $mine = @(for ($i = $k; $i -lt $todo.Count; $i += $nP) { $todo[$i] })
            $batch = Join-Path $env:TEMP "ytdl-probe-$PID-$k.txt"
            $mine | ForEach-Object { "https://www.youtube.com/watch?v=$_" } | Set-Content $batch -Encoding ASCII
            $probe = @('--ignore-errors', '--no-warnings', '--sleep-requests', [string](Get-PaceReq), '-f', $fmt, '--print', '%(id)s %(filesize,filesize_approx)s', '-a', $batch) + $authArgs + $clientArgs
            $o = "$batch.out"
            $p = Start-Process -FilePath $ytdlp -ArgumentList (($probe | ForEach-Object { Quote-Arg ([string]$_) }) -join ' ') -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError "$o.err"
            $null = $p.Handle
            @{ P = $p; B = $batch; O = $o }
        }
        foreach ($pr in $procs) {
            $pr.P.WaitForExit()
            foreach ($l in @(Get-Content -LiteralPath $pr.O -ErrorAction SilentlyContinue)) {
                $q = "$l".Trim() -split ' '
                if ($q.Count -ge 2 -and $q[0] -match '^[\w-]{11}$' -and $q[1] -match '^\d+$') { $out[$q[0]] = [double]$q[1] / 1MB }
            }
            Remove-Item -LiteralPath $pr.B, $pr.O, "$($pr.O).err" -Force -ErrorAction SilentlyContinue
        }
    }
    return $out
}
function ConvertTo-MiB([double]$v, [string]$unit) {
    switch ($unit) { 'KiB' { $v / 1024 } 'GiB' { $v * 1024 } default { $v } }
}

# ---- priors (used until real measurements exist; shrunk away as data arrives) ----
# Prior fixed cost per video follows the pacing (1.4.1, fitted to 1.0-1.4 measurements):
#   3 x S   yt-dlp pauses before EACH stream (video and audio), average 1.5 x S each
#   n x R   page requests: ~4 with the fast client, ~6 with yt-dlp's default clients
#   + 4 s   extraction work, merge, metadata, thumbnail
# 1.4.0 L0 (S 0, R 0.5, fast): 6.0 s (measured 6.3). Old -Sleep 5, default clients: 25 s (measured 24-25).
function Get-PriorOverhead {
    $n = if ($script:fastClient) { 4 } else { 6 }
    3 * (Get-PaceSleep) + $n * (Get-PaceReq) + 5.5   # 1.6.1: +4 -> +5.5 (real runs at L0: 5.9 s single and per parallel worker)
}
# Typical YouTube bitrate, MiB per second of video, by quality cap (rough; data takes over quickly).
# Measured on Blender uploads: 360p 0.0235, 480p 0.0287 (1.1.0), 720p 0.0545, 1080p 0.0799 (1.2.1) MiB/s.
$priorBitrate = @{ 'q144' = 0.012; 'q240' = 0.018; 'q360' = 0.025; 'q480' = 0.03; 'q720' = 0.055; 'q1080' = 0.08; 'q1440' = 0.3
                   'q2160' = 0.6; 'q4320' = 1.6; 'qbest' = 0.15; 'audio' = 0.016 }   # 1.22.0: 144, 240, 4320 guessed
# At 480p and below (and audio) transfer is only ~10-25% of each video's time, so a guessed
# bandwidth costs little accuracy and allows an ETA before the first download completes.
# Above 480p transfer dominates, so those wait for a real measurement.
$lowRes        = $AudioOnly -or $Quality -in '144', '240', '360', '480' -or $LowResContent
# (bandwidth prior: see "bandwidth model (1.4.2)" below; learned, 7.7 MiB/s until there is data)
$ovShrinkN   = 1.0      # prior overhead counts as this many videos
$brShrinkSec = 1200.0   # prior bitrate counts as this many seconds of video (a few 4K shorts can't swing it)
$capOvN      = 5.0      # saved history counts as at most 5 videos' overhead...
$capBrSec    = 7200.0   # ...2 h of video for bitrate...
# 1.24.2: ...but only 10 min once this run has sizes of its own (sampled, probed or downloaded). Bitrate is
# a property of the content, and a folder's history is often other content: a real 13-video 1080p/1440p
# run first read 434 MB for ~970 MB (2 h of 0.11 MiB/s history vs 3 samples at ~0.3). Replay of 4 distinct
# contents, 3 samples each (bench\bitrate-blend.ps1): run bitrate error 66% at 2 h, 28% at 10 min, 22% at 0.
$capBrRunSec = 600.0
$capBwMiB    = 150.0    # ...and 150 MiB of transfer for bandwidth (this run's transfers soon outweigh it)

# Keys: bitrate depends on quality only; overhead and bandwidth depend on -Sleep and on how many
# workers share the connection (-Parallel).
$qualKey  = if ($AudioOnly) { 'audio' } elseif ($ContentHeight -gt 0) { "q$(if ($ContentHeight -le 360) { 360 } else { 480 })" } else { "q$Quality" }
$workersN = if ($Worker -gt 0) { $WorkerCount } else { $Parallel }
$netKey   = "s$(Get-PaceSleep)r$(Get-PaceReq)-p$workersN"
# Workers share one connection: 3 workers measured 2.4x faster than 1 (30 videos at 360p), not 3x.
# (1.8.0: only the fallback now; see Get-StreamShare.)
function Get-ParallelSpeedup([int]$n) { if ($n -le 1) { 1.0 } else { 1 + 0.7 * ($n - 1) } }
# 1.8.0: the coordinator's estimate is (sum of per-video times at the SHARED per-download speed) / n.
# 1.6.1-1.7.0 divided by speedup(n) on top of an already shared speed when -Parallel was given (+29% at 4).
$etaDiv   = if ($isCoordinator) { $Parallel } else { 1 }
$launchGap = 3   # seconds between worker launches (also used by the coordinator's estimate, 1.14.0)

$eta = @{ Queue = $null; Pending = $null; Total = 0; AvgDur = 0.0; Size = [hashtable]::Synchronized(@{})
          Cur = $null; CurStart = $null; CurXferSec = 0.0; CurMiB = 0.0
          OvN = 0.0; OvSum = 0.0                 # overhead samples (steady state)
          RunN = 0; FirstOv = $null              # this run's first video: start-up cost, kept apart
          BrMiB = 0.0; BrSec = 0.0               # bitrate samples (MiB, runtime s), this run
          HBrMiB = 0.0; HBrSec = 0.0             # saved bitrate history (capped at $capBrSec)
          HBwSec = 0.0; HBwMiB = 0.0             # saved bandwidth history
          LBwSec = 0.0; LBwMiB = 0.0             # this run: completed transfers
          HDraws = @(); Draws = (New-Object System.Collections.ArrayList)   # per-stream s/MiB draws (1.4.2)
          PSize = 0.0; PPct = 0.0; PStartPct = 0.0; PStartT = $null; PartMiB = 0.0; PartSec = 0.0   # in-progress file
          LiveAnnounced = $false; LastShown = Get-Date }

$savedRates = @{}
if (Test-Path $rateFile) {
    try {
        $json = Get-Content $rateFile -Raw | ConvertFrom-Json
        foreach ($p in $json.PSObject.Properties) { $savedRates[$p.Name] = $p.Value }
        $h = $savedRates["br-$qualKey"]
        if ($h -and $h.Sec -gt 0) { $w = [math]::Min(1.0, $capBrSec / [double]$h.Sec); $eta.HBrMiB = $h.MiB * $w; $eta.HBrSec = $h.Sec * $w }
    } catch { }
}
# Overhead and bandwidth history for this pacing level and worker count (reloaded when either changes).
function Read-NetHistory {
    $eta.OvN = 0.0; $eta.OvSum = 0.0; $eta.HBwSec = 0.0; $eta.HBwMiB = 0.0; $eta.HDraws = @()
    $h = $savedRates["ov-$script:netKey"]
    if ($h -and $h.N -gt 0) { $w = [math]::Min(1.0, $capOvN / [double]$h.N); $eta.OvN = $h.N * $w; $eta.OvSum = $h.Sum * $w }
    $h = $savedRates["bw-$script:netKey"]
    if ($h -and $h.MiB -gt 0) { $w = [math]::Min(1.0, $capBwMiB / [double]$h.MiB); $eta.HBwSec = $h.Sec * $w; $eta.HBwMiB = $h.MiB * $w }
    if ($h -and $h.Draws) { $eta.HDraws = @($h.Draws | ForEach-Object { [double]$_ } | Select-Object -Last 10) }
}
Read-NetHistory

# ---- bandwidth model (1.4.2) ----------------------------------------------------------------
# Per-stream download speeds vary at random within a run (2-19 MiB/s seen in one run), so one big
# slow file must not set the speed for everything after it. Each completed stream of >= 10 MiB
# is one speed draw, counted equally (not weighted by size), and the mean is shrunk toward a
# typical speed worth 4 streams. That typical speed is LEARNED: the median of the last 50 stream
# speeds across all runs (%LOCALAPPDATA%\ytdl\bandwidth.json), 7.7 MiB/s until there are 5.
# Replay of 6 transfer-heavy runs, every 30 s: mean error 36.1% -> 24.0%, worst 190% -> 130%,
# together with the progress-aware current video (see Get-EtaSeconds). A fixed 5 MiB/s prior
# would have made it worse (39.6%), which is why the prior is learned rather than fixed.
$bwGlobalFile = Join-Path $env:LOCALAPPDATA 'ytdl\bandwidth.json'
$bwGlobal = @(); $bwCaps = @(); $bwPar = @{}
if (Test-Path $bwGlobalFile) { try { $bwj = Get-Content $bwGlobalFile -Raw | ConvertFrom-Json
    $bwGlobal = @($bwj.Draws | ForEach-Object { [double]$_ }); if ($bwj.Caps) { $bwCaps = @($bwj.Caps | ForEach-Object { [double]$_ }) }
    if ($bwj.PDraws) { foreach ($p in $bwj.PDraws.PSObject.Properties) { $bwPar[$p.Name] = @($p.Value | ForEach-Object { [double]$_ }) } } } catch { } }
$bwPriorMiBps = 7.7
if ($bwGlobal.Count -ge 5) { $sortedBw = @($bwGlobal | Sort-Object); $bwPriorMiBps = $sortedBw[[int][math]::Floor($sortedBw.Count / 2)] }
# 1.8.0: the connection saturates. Three real parallel runs moved 13.7, 14.5 (3 workers) and 14.9 MiB/s
# (4 workers) in total, while one download alone runs at ~8 MiB/s: 3 workers got 6.7 per download,
# 4 got 5.1, not the 6.0 the 1.6.1 rule (speedup 1+0.7(n-1)) predicted. Model: each worker is
# downloading for a fraction d of its time (the rest is page requests, merge, tagging), so about n*d
# downloads run at once and each gets min(single, cap / (n*d)). The cap is learned by the coordinator
# (total MiB / wall time of 3+-worker runs, last 10, median; Caps in bandwidth.json). Replayed on the
# 2002 and 2003 runs' first estimates: -6% -> -4% and +9% -> 0%. Without a learned cap: the old rule.
$bwCap = 0.0
if ($bwCaps.Count -ge 1) { $sc = @($bwCaps | Sort-Object); $bwCap = $sc[[int][math]::Floor($sc.Count / 2)] }
# 1.24.1: the n*d rule above read each download ~1.4-2.5x too fast. In 654 downloads of 10+ MiB from
# 3-worker bench runs the median was 4.9 MiB/s (4.2-6.0 at every size from 10 MiB to 1 GB) against
# 6.4-11 from the rule (d came out small because it priced transfer at the single-download speed), and
# worker estimates ran 18% low in the first quarter of a run. Now: the median of the last 50 downloads
# from runs with this many workers (PDraws in bandwidth.json), and cap / n until there are 5.
function Get-StreamShare([int]$n) {
    if ($n -le 1) { return 1.0 }
    $pd = $bwPar["$n"]
    if ($pd -and $pd.Count -ge 5) { $s = @($pd | Sort-Object); return $s[[int][math]::Floor($s.Count / 2)] / $bwPriorMiBps }
    if ($bwCap -gt 0) { return [math]::Min(1.0, $bwCap / ($n * $bwPriorMiBps)) }
    return (Get-ParallelSpeedup $n) / $n
}
function Update-BwPrior {
    $script:bwShare = Get-StreamShare $script:workersN
    $script:bwPriorSecPerMiB = 1 / [math]::Max(0.5, $bwPriorMiBps * $script:bwShare)
}
# Called when the worker count changes (the resolution check can switch a run to 3 workers).
function Set-RunWorkers([int]$n) {
    $script:workersN = $n
    $script:netKey = "s$(Get-PaceSleep)r$(Get-PaceReq)-p$n"
    Read-NetHistory; Update-BwPrior
    $script:etaDiv = if ($script:isCoordinator) { $n } else { 1 }
}
$bwShare = 1.0; $bwPriorSecPerMiB = 1 / $bwPriorMiBps
Update-BwPrior   # refined again once the video list (and so the typical video size) is known
$bwShrinkDraws = 4

# The first video of a run pays a start-up cost (player JS download, challenge solving, cookie
# read) of a few seconds that later videos don't. It's used only until a second video finishes,
# and never saved as history. (1.1.0 backtest: overall error 8.4% -> 7.6%.)
function Get-Overhead {
    $sum = $eta.OvSum; $n = $eta.OvN
    if ($eta.RunN -eq 1 -and $null -ne $eta.FirstOv) { $sum += $eta.FirstOv; $n += 1 }
    ($sum + (Get-PriorOverhead) * $ovShrinkN) / ($n + $ovShrinkN)
}

# 1.6.0: sizes already known for videos not yet downloaded (background probe, -Precise, the resolution
# check) are bitrate samples too, so unprobed videos stop using the generic prior as soon as a few
# sizes are in. In a real 234-video "best" run (actually 480p), the 0.15 MiB/s 'best' prior lingered
# and the first 10 minutes of estimates ran +15-20% high. Cached for 2 s: Get-X calls this per video.
$brCache = @{ T = [datetime]::MinValue; V = 0.0 }
function Get-Bitrate {
    if (((Get-Date) - $brCache.T).TotalSeconds -lt 2) { return $brCache.V }
    $p = $priorBitrate[$qualKey]; if (-not $p) { $p = 0.15 }
    $m = $eta.BrMiB; $s = $eta.BrSec
    if ($eta.Pending -and $eta.Size.Count) {
        foreach ($id in @($eta.Size.Keys)) {
            if ($eta.Pending.Contains($id) -and $eta.Size[$id] -gt 0) { $d = $eta.Queue[$id]; if ($d -gt 0) { $m += $eta.Size[$id]; $s += $d } }
        }
    }
    $hs = $eta.HBrSec; $hm = $eta.HBrMiB
    if ($s -gt 0 -and $hs -gt $capBrRunSec) { $hm *= $capBrRunSec / $hs; $hs = $capBrRunSec }   # 1.24.2: this run's own sizes outweigh history
    $brCache.V = ($m + $hm + $p * $brShrinkSec) / ($s + $hs + $brShrinkSec); $brCache.T = Get-Date
    return $brCache.V
}

# Seconds per MiB from COMPLETED transfers only (this run blended with capped history).
# Partial progress lines were tried and read ~2x too slow (each download's ramp-up), which
# pushed estimates up to +172%.
# 1.24.1: under -LimitRate a download can't beat its share of the limit. A 15-video 1080p run at 2 MB/s
# first read 170 s for 1,726 s (-90%): the model and history speeds ignored the limit.
function Get-SecPerMiB {
    $spm = Get-SecPerMiBModel
    if ($limitBytes -le 0) { return $spm }
    $sh = if ($Worker -gt 0) { [math]::Max(1, $WorkerCount) } elseif ($isCoordinator) { [math]::Max(1, $workersN) } else { 1 }
    $floor = $sh * 1MB / $limitBytes
    if ($null -eq $spm) { if ($floor -gt $bwPriorSecPerMiB) { return $floor }; return $null }   # a limit under the typical speed sets it
    return [math]::Max($spm, $floor)
}
function Get-SecPerMiBModel {
    # 1) per-stream draws (this run + the folder's last 10), shrunk toward the learned typical speed
    $draws = @($eta.HDraws) + @($eta.Draws)
    if ($draws.Count -gt 0) {
        return (($draws | Measure-Object -Sum).Sum + $bwPriorSecPerMiB * $bwShrinkDraws) / ($draws.Count + $bwShrinkDraws)
    }
    # 2) only small streams so far (< 10 MiB, e.g. 360p audio): their bytes, blended with the prior
    if ($eta.LBwMiB -gt 0 -and $eta.LBwSec -gt 0) { return ($eta.LBwSec + $bwPriorSecPerMiB * 30) / ($eta.LBwMiB + 30) }
    # 3) older saved history without draws
    if ($eta.HBwMiB -gt 0 -and $eta.HBwSec -gt 0) { return $eta.HBwSec / $eta.HBwMiB }
    # 4) nothing measured: low resolutions use the typical speed (transfer is a small share there)
    if ($lowRes) { return $bwPriorSecPerMiB }
    return $null
}

function Test-BandwidthGuessed { ($eta.HBwMiB + $eta.LBwMiB) -le 0 }

# Estimated size of one video in MiB (exact with -Precise when its probe succeeded).
function Get-X([string]$id) {
    if ($eta.Size.ContainsKey($id) -and $eta.Size[$id] -gt 0) { return [double]$eta.Size[$id] }
    $d = $eta.Queue[$id]; if ($d -le 0) { $d = $eta.AvgDur }
    return $d * (Get-Bitrate)
}

# Kept for the -Parallel coordinator's load balancing: @(secPerMiB, overhead), or $null.
function Get-Fit {
    $spm = Get-SecPerMiB
    if ($null -eq $spm) { return $null }
    return @($spm, (Get-Overhead))
}

# 1.24.1: -Parallel's combined finish once a worker is done. Each worker's estimate uses the speed it got
# sharing the connection with all n workers, but downloads speed up as workers finish (bench: ~7.5 MiB/s
# alone, 5.2 two at once, 4.3 three at once, i.e. v1 / (1 + 0.4 (k - 1))), so the last worker's estimate
# ran +34% high in the last quarter of a run. This splits each running worker's time left into fixed
# cost (videos left x overhead) and transfer, and replays the finishes with transfer rescaled to the
# workers still running. Only after a first finish: applied earlier it made the start (already low)
# worse. Replay on 312 combined-ETA points of the bench logs: last quarter 38% -> 34% mean error, the
# rest unchanged (bench\tail-replay.ps1 -OnlyAfterFirst). $null while all n are still running.
$tailA = 0.4
function Get-TailFinish($run, [int]$n) {
    $now = Get-Date; $ovPV = Get-Overhead
    $live = @(foreach ($w in $run) { if ($null -eq $w.Eta) { continue }; $r = ($w.Eta - $now).TotalSeconds
        if ($r -gt 0) { $ov = [math]::Min($r, [math]::Max(0, $w.Total - $w.Done) * $ovPV); @{ Ov = $ov; X = $r - $ov; P = 0.0; T = 0.0 } } })
    if ($live.Count -eq 0 -or $live.Count -ge $n) { return $null }
    $t = 0.0
    while ($live.Count) {
        $m = $live.Count; $dsum = 0.0
        foreach ($w in $live) { $dsum += $w.X / [math]::Max(0.001, $w.Ov + $w.X) }
        $d = $dsum / $m
        $g = (1 + $tailA * $d * ($m - 1)) / (1 + $tailA * $d * ($n - 1))
        $best = [double]::MaxValue
        foreach ($w in $live) { $w.T = [math]::Max(0.001, $w.Ov + $w.X * $g); $left = (1 - $w.P) * $w.T; if ($left -lt $best) { $best = $left } }
        $t += $best
        foreach ($w in $live) { $w.P += $best / $w.T }
        $live = @($live | Where-Object { $_.P -lt 0.9999 })
    }
    return $t
}

function Get-EtaSeconds {
    $spm = Get-SecPerMiB
    if ($null -eq $spm) { return $null }
    $ov = Get-Overhead; $total = 0.0; $now = Get-Date
    # 1.14.0: the coordinator's estimate (before the workers report their own) simulates the real
    # schedule instead of dividing the total by the worker count: biggest videos first onto the
    # least-loaded worker, and worker k starting (k-1) x $launchGap s late (launches are 3 s apart).
    # Real 2-video runs read 15 s against 21-28 s: the total was divided by 3 (the default) though
    # only 2 workers ran, the second started 3-4 s late, and one bigger video set the finish.
    if ($etaDiv -gt 1) {
        $times = @(foreach ($id in $eta.Pending) { $ov + (Get-X $id) * $spm }) | Sort-Object -Descending
        $n = [math]::Max(1, [math]::Min([int]$etaDiv, $times.Count))
        # Each worker also needs ~2 s to start (PowerShell, yt-dlp, cookies) plus ~0.5 s per 100 playlist
        # entries it pages through to reach its items: launch to first video was 2-4 s in 250-video
        # playlists and 6-9 s in a 1,463-video one (27 workers, 1.7.0+).
        $maxIdx = 0; foreach ($id in $eta.Pending) { $pi = [int]$queueIndex[$id]; if ($pi -gt $maxIdx) { $maxIdx = $pi } }
        $startup = 2 + 0.005 * $maxIdx
        $loads = New-Object double[] $n
        for ($k = 0; $k -lt $n; $k++) { $loads[$k] = $k * $launchGap + $startup }
        foreach ($t in $times) { $k = 0; for ($j = 1; $j -lt $n; $j++) { if ($loads[$j] -lt $loads[$k]) { $k = $j } }; $loads[$k] += $t }
        return ($loads | Measure-Object -Maximum).Maximum
    }
    foreach ($id in $eta.Pending) {
        if ($id -eq $eta.Cur -and $eta.CurStart) {
            # 1.4.2: the video in progress is estimated from what's actually left of it: bytes not yet
            # downloaded (finished streams + the latest progress line) at a 50/50 mix of the current
            # stream's measured speed and the model speed, plus whatever fixed cost is still to come.
            # (The 1.4.1 rule, estimate minus elapsed, missed slow long downloads entirely.)
            $elapsed = ($now - $eta.CurStart).TotalSeconds
            $doneMiB = $eta.CurMiB; $xfer = $eta.CurXferSec; $useSpm = $spm
            if ($eta.PStartT) {
                $doneMiB += $eta.PPct / 100 * $eta.PSize; $xfer += ($now - $eta.PStartT).TotalSeconds
                if ($eta.PartSec -ge 10 -and $eta.PartMiB -gt 0) { $useSpm = 0.5 * ($eta.PartSec / $eta.PartMiB) + 0.5 * $spm }
            }
            $total += [math]::Max(0, (Get-X $id) - $doneMiB) * $useSpm + [math]::Max(1.5, $ov - [math]::Max(0, $elapsed - $xfer))
        } else {
            $total += $ov + (Get-X $id) * $spm
        }
    }
    return $total / $etaDiv
}

function Show-Eta([string]$note) {
    if (-not $eta.Queue) { return }
    if ($script:bgScan) { return }   # 1.16.0: single video, duration not known yet (Merge-BgScan shows it)
    if ($Section -or $Live) { return }   # 1.23.0: a clip or a live stream has no size to estimate from
    $left  = $eta.Pending.Count
    $media = 0.0; $mib = 0.0
    foreach ($id in $eta.Pending) { $d = $eta.Queue[$id]; if ($d -le 0) { $d = $eta.AvgDur }; $media += $d; $mib += Get-X $id }
    # 1.17.2: no "~" only when every size left is a looked-up one (was: whenever -Precise was given, so
    # -Estimate -Precise with 3 workers showed the runtime-based guess as if it were exact)
    $unknown = 0; if ($Precise) { foreach ($id in $eta.Pending) { if (-not ($eta.Size.ContainsKey($id) -and $eta.Size[$id] -gt 0)) { $unknown++; break } } }
    $approx = if ($Precise -and $unknown -eq 0) { '' } else { '~' }
    $msg = "[ytdl] $($eta.Total - $left) of $($eta.Total) done | $left left ($(Format-Dur $media) of video, $approx$(if ($mib -ge 1024) { '{0:N2} GB' -f ($mib / 1024) } else { '{0:N0} MB' -f $mib }))"
    $s = Get-EtaSeconds
    if ($left -eq 0)          { $msg += ' | nothing left to download' }
    elseif ($null -ne $s)     { $msg += " | ETA ~$(Format-Dur $s) (finish ~$((Get-Date).AddSeconds($s).ToString('ddd h:mm tt')))" }
    else                      { $msg += ' | ETA in a few seconds, once download speed is measured' }
    if (-not $note -and $left -gt 0 -and $breakFilter) { $note = 'at most: -After stops at the first older video' }   # 1.16.0
    if (-not $note -and $null -ne $s -and $left -gt 0 -and (Test-BandwidthGuessed)) { $note = 'rough: speed not measured yet' }
    if ($note) { $msg += " [$note]" }
    Write-Host $msg -ForegroundColor Cyan
    $eta.LastShown = Get-Date
}

# Per progress line of the file currently downloading: track transfer for live bandwidth.
function Update-Partial([double]$pct, [double]$sizeMiB) {
    $now = Get-Date
    if (-not $eta.PStartT -or [math]::Abs($sizeMiB - $eta.PSize) -gt 0.01 -or $pct -lt $eta.PPct) {
        $eta.PSize = $sizeMiB; $eta.PStartPct = $pct; $eta.PStartT = $now; $eta.PartMiB = 0.0; $eta.PartSec = 0.0
    } else {
        $eta.PartMiB = ($pct - $eta.PStartPct) / 100 * $sizeMiB
        $eta.PartSec = ($now - $eta.PStartT).TotalSeconds
    }
    $eta.PPct = $pct
    if ($null -ne (Get-SecPerMiB) -and ($now - $eta.LastShown).TotalSeconds -ge 120) { Show-Eta '' }   # long downloads
}

# 1.17.0: the progress bar's numbers for a one-worker run (a worker's own share never draws a bar).
# Done = finished videos + finished streams of the current one + the current stream's progress. Total =
# that + the current video's estimate (at least what's known of it) + estimates for the rest, which is
# re-added only when the queue changes (a 1,000-video playlist would otherwise cost a sum per redraw).
$barCache = @{ Key = ''; Rest = 0.0; At = [datetime]::MinValue; CurId = $null; CurEst = 0.0 }
function Get-RunBarState {
    $partial = if ($eta.PSize -gt 0) { [double]$eta.PPct / 100 * $eta.PSize } else { 0.0 }
    $done = [double]$eta.DoneMiB + $eta.CurMiB + $partial
    $fd = 0; $ft = 0
    if ($eta.Queue -and $eta.Pending -and -not $script:bgScan) {
        $key = "$($eta.Pending.Count)|$($eta.Cur)"
        if ($key -ne $barCache.Key -or ((Get-Date) - $barCache.At).TotalSeconds -ge 10) {
            $rest = 0.0; foreach ($id in $eta.Pending) { if ($id -ne $eta.Cur) { $rest += Get-X $id } }
            $barCache.Key = $key; $barCache.Rest = $rest; $barCache.At = Get-Date
        }
        # The current video's estimate is fixed when it starts (or when its details arrive), then only
        # grows to what's known of it: Get-X shifts as bitrate is learned mid-video, and recomputing it on
        # every redraw moved the total 187 -> 319 -> 188 -> 315 MB in a test.
        $cur = 0.0
        if ($eta.Cur -and $eta.Pending.Contains($eta.Cur)) {
            if ($barCache.CurId -ne $eta.Cur) { $barCache.CurId = $eta.Cur; $barCache.CurEst = Get-X $eta.Cur }
            $cur = [math]::Max([double]$barCache.CurEst, [double]$eta.CurMiB + $eta.PSize)
        }
        $total = [double]$eta.DoneMiB + $cur + $barCache.Rest
        $fd = $eta.Total - $eta.Pending.Count; $ft = $eta.Total
    } else { $total = [double]$eta.DoneMiB + $eta.CurMiB + $eta.PSize }   # no estimate yet: what's known
    $speed = if ($eta.PartSec -ge 1 -and $eta.PartMiB -gt 0) { $eta.PartMiB / $eta.PartSec } elseif ($eta.LBwSec -gt 0) { $eta.LBwMiB / $eta.LBwSec } else { 0.0 }
    @{ Done = $done; Total = $total; FilesDone = $fd; FilesTotal = $ft; Speed = $speed; Paused = [bool]($runState -and $runState.Paused) }
}

# A stream finished ("100% of X in hh:mm:ss"): exact transfer for this video and for bandwidth.
function Add-Transfer([double]$mib, [double]$sec) {
    $eta.CurMiB += $mib; $eta.CurXferSec += $sec
    $first = ($eta.LBwMiB -le 0)
    $learn = -not (Test-PausedDuring)   # 1.16.0: yt-dlp's time for a paused stream includes the pause
    if ($learn -and $sec -gt 0) { $eta.LBwMiB += $mib; $eta.LBwSec += $sec }
    if ($learn -and $sec -gt 0 -and $mib -ge 10) { [void]$eta.Draws.Add($sec / $mib) }   # one speed draw per big stream
    $eta.PStartT = $null; $eta.PartMiB = 0.0; $eta.PartSec = 0.0; $eta.PSize = 0.0; $eta.PPct = 0.0
    if ($first -and $learn -and $sec -gt 0 -and -not $eta.LiveAnnounced) {
        $eta.LiveAnnounced = $true
        Show-Eta ('speed measured: {0:N1} MiB/s' -f ($eta.LBwMiB / $eta.LBwSec))
    }
}

# Transfer seconds for a "100% of X in hh:mm:ss at Y/s" line. The whole-second time rounds
# down (2-4 s files at 360p lose up to 50%), so prefer size / reported average speed.
function Get-XferSec([double]$mib, [int]$hmsSec, [string]$speed, [string]$unit) {
    if ($speed) {
        $sp = if ($unit -eq 'B') { [double]::Parse($speed, $ci) / 1MB } else { ConvertTo-MiB ([double]::Parse($speed, $ci)) $unit }
        if ($sp -gt 0) { return $mib / $sp }
    }
    return [double]$hmsSec
}

function Start-Video([string]$id) {
    $eta.Cur = $id; $eta.CurStart = Get-Date; $eta.CurMiB = 0.0; $eta.CurXferSec = 0.0
    $eta.CurPauseMark = if ($runState) { [double]$runState.PausedSec } else { 0.0 }
}

# Called when the next video starts (or the pass ends): if the previous video made it into the
# archive, record its overhead and bitrate, then print an updated ETA.
function Complete-Current {
    Merge-BgScan
    if (-not $eta.Queue -or -not $eta.Cur) { return }
    $id = $eta.Cur; $eta.Cur = $null
    if ($eta.Pending.Contains($id) -and (Test-Archived $id)) {
        [void]$eta.Pending.Remove($id)
        $eta.DoneMiB = [double]$eta.DoneMiB + $eta.CurMiB   # 1.17.0: progress bar total
        if ($eta.CurStart -and -not (Test-PausedDuring)) {   # 1.16.0: not from a video that was paused
            $wall = ((Get-Date) - $eta.CurStart).TotalSeconds
            if ($eta.CurMiB -gt 0) {
                $ov = [math]::Max(0, $wall - $eta.CurXferSec)
                $eta.RunN++
                if ($eta.RunN -eq 1) { $eta.FirstOv = $ov } else { $eta.OvN += 1; $eta.OvSum += $ov }
                $d = $eta.Queue[$id]
                if ($d -gt 0) { $eta.BrMiB += $eta.CurMiB; $eta.BrSec += $d }
            }
        }
        Show-Eta ''
    }
}

function Save-Rate {
    if ($NoScan) { return }   # workers: the coordinator records measurements
    if ($eta.OvN -le 0 -and $eta.LBwMiB -le 0 -and $null -eq $eta.FirstOv) { return }
    try {
        $now = (Get-Date).ToString('s')
        # A single-video run has only its start-up-inflated sample; keep it rather than nothing.
        if ($eta.OvN -le 0 -and $null -ne $eta.FirstOv) { $eta.OvN = 1; $eta.OvSum = $eta.FirstOv }
        if ($eta.OvN -gt 0) { $savedRates["ov-$netKey"] = @{ N = $eta.OvN; Sum = $eta.OvSum; AvgSec = [math]::Round((Get-Overhead), 1); Updated = $now } }
        if ($eta.BrSec -gt 0) { $savedRates["br-$qualKey"] = @{ MiB = $eta.HBrMiB + $eta.BrMiB; Sec = $eta.HBrSec + $eta.BrSec; MiBPerVideoSec = [math]::Round((Get-Bitrate), 4); Updated = $now } }
        $bm = $eta.HBwMiB + $eta.LBwMiB; $bs = $eta.HBwSec + $eta.LBwSec
        $allDraws = @(@($eta.HDraws) + @($eta.Draws) | Select-Object -Last 10)
        # 1.24.1: speeds under -LimitRate say nothing about the connection. E10 (2 MB/s) saved its slow
        # draws and a 2.17 MiB/s cap, and the next 4 unlimited runs first read +168% to +435%.
        $learnBw = ($limitBytes -le 0)
        if ($bm -gt 0 -and $learnBw) { $savedRates["bw-$netKey"] = @{ MiB = $bm; Sec = $bs; MiBPerSec = [math]::Round($bm / $bs, 2); Draws = @($allDraws | ForEach-Object { [math]::Round($_, 5) }); Updated = $now } }
        # 1.8.0: drop pre-1.0 keys (runtime-ratio/regression ETA models) no version reads any more.
        foreach ($k in @($savedRates.Keys)) { if ($k -notmatch '^(ov|br|bw)-') { $savedRates.Remove($k) } }
        $savedRates | ConvertTo-Json -Depth 3 | Set-Content -Path $rateFile -Encoding ASCII
        # learned typical speed for every folder: last 50 single-download speeds (MiB/s) across all runs.
        # 1.8.0: once the connection's cap is known, parallel workers' speeds say more about the cap than
        # about a single download (dividing them by the share inflated or deflated them), so only
        # one-at-a-time runs add here; the coordinator records the cap instead.
        # 1.24.1: parallel workers also keep their own downloads' speeds by worker count (PDraws, see Get-StreamShare).
        if ($learnBw -and $eta.Draws.Count -gt 0) {
            $cur = $bwGlobal; $caps = $bwCaps; $par = @{}; foreach ($k in $bwPar.Keys) { $par[$k] = $bwPar[$k] }
            $lowRun = 0
            try { $j = Get-Content $bwGlobalFile -Raw | ConvertFrom-Json; $cur = @($j.Draws | ForEach-Object { [double]$_ }); if ($j.Caps) { $caps = @($j.Caps | ForEach-Object { [double]$_ }) }; if ($j.CapLowRun) { $lowRun = [int]$j.CapLowRun }
                  if ($j.PDraws) { $par = @{}; foreach ($p in $j.PDraws.PSObject.Properties) { $par[$p.Name] = @($p.Value | ForEach-Object { [double]$_ }) } } } catch { }
            $g = @($cur)
            if ($workersN -le 1 -or $bwCap -le 0) { $g = @(@($cur) + @($eta.Draws | ForEach-Object { [math]::Round((1 / $_) / $bwShare, 2) }) | Select-Object -Last 50) }
            if ($workersN -gt 1) { $par["$workersN"] = @(@($par["$workersN"]) + @($eta.Draws | ForEach-Object { [math]::Round(1 / $_, 2) }) | Where-Object { $_ -gt 0 } | Select-Object -Last 50) }
            New-Item -ItemType Directory -Force (Split-Path $bwGlobalFile) | Out-Null
            @{ Draws = $g; Caps = @($caps); CapLowRun = $lowRun; PDraws = $par; Updated = $now } | ConvertTo-Json -Depth 3 | Set-Content -Path $bwGlobalFile -Encoding ASCII
        }
    } catch { }
}

# 1.7.0: a -Parallel worker gets its share of the coordinator's scan in -QueueFile instead of
# listing the playlist again (8-9 s per worker before its first download in a real 1,463-video run).
$fromCoordinator = $false
if ($NoScan) { $queue = @{} }
elseif ($QueueFile -and (Test-Path -LiteralPath $QueueFile)) {
    $queue = [ordered]@{}
    try {
        $parsed = Get-Content -LiteralPath $QueueFile -Raw | ConvertFrom-Json   # (assigned first: 5.1 emits a JSON array as one object)
        foreach ($e in $parsed) {
            $queue[[string]$e.Id] = [double]$e.D
            if ($e.I) { $queueIndex[[string]$e.Id] = [int]$e.I }
            if ($e.S -gt 0) { $eta.Size[[string]$e.Id] = [double]$e.S }
            if ($e.T) { $queueTitle[[string]$e.Id] = [string]$e.T }
        }
        $fromCoordinator = $true
    } catch { $queue = [ordered]@{} }
    Remove-Item -LiteralPath $QueueFile -Force -ErrorAction SilentlyContinue
    Write-LogOnly "[ytdl-event] video list from the coordinator: $($queue.Count) video(s)"
}
# Playlist positions as yt-dlp's --playlist-items text: 1,2,3,7 -> "1-3,7"
function Compress-Items([int[]]$nums) {
    $nums = @($nums | Sort-Object -Unique); $parts = @(); $i = 0
    while ($i -lt $nums.Count) {
        $j = $i; while ($j + 1 -lt $nums.Count -and $nums[$j + 1] -eq $nums[$j] + 1) { $j++ }
        $parts += if ($j -gt $i) { "$($nums[$i])-$($nums[$j])" } else { "$($nums[$i])" }
        $i = $j + 1
    }
    $parts -join ','
}
# 1.16.0 fast start for a single video. The up-front listing of one video is a full extraction
# (1.2-3.6 s in real logs), and the download repeats it, so ytdl started moving data 1-2 s after plain
# yt-dlp (1080p benchmark: a tie on 1 video, 13.6 s vs 14.0, against 1.55x on 6). Now the listing runs
# in the background while the download starts; its duration feeds the estimate when it arrives.
$bgScan = $null; $bgScanHandle = $null; $bgScanT0 = $null
$singleId = $null
if (-not $NoScan -and -not $fromCoordinator -and $Worker -eq 0 -and -not $Estimate -and $Url -notmatch '[?&]list=' -and
    $Url -match '(?:youtube\.com/(?:watch\?(?:[^#]*&)?v=|shorts/|live/|embed/)|youtu\.be/)([\w-]{11})') { $singleId = $Matches[1] }
if ($singleId) {
    $queue = [ordered]@{ $singleId = 0.0 }
    Update-ArchiveSet
    if (-not (Test-Archived $singleId -NoRefresh)) {
        $bgScan = [powershell]::Create()
        [void]$bgScan.AddScript({ param($exe, $a) $ErrorActionPreference = 'Continue'; & $exe @a 2>$null }).AddArgument($ytdlp).AddArgument(@(Get-ScanArgs))
        $bgScanT0 = Get-Date
        $bgScanHandle = $bgScan.BeginInvoke()
        Write-LogOnly "[ytdl-event] single video: listing it in the background while the download starts"
    }
}
elseif (-not $NoScan -and -not $fromCoordinator) {
    Write-Host "Scanning URL for video list..." -ForegroundColor DarkGray
    $scanT0 = Get-Date
    $queue = Get-Queue
    Write-LogOnly ("[ytdl-event] playlist scan: {0} video(s) in {1:N1} s" -f $queue.Count, ((Get-Date) - $scanT0).TotalSeconds)
    $n0 = $queue.Count
    $queue = Select-Filtered $queue
    if ($n0 -gt 0 -and $queue.Count -eq 0) {
        Write-Host "[ytdl] Nothing to download: the filters leave out all $n0 video(s)." -ForegroundColor Yellow
        Release-Lock; Restore-Console; exit 0
    }
    # Download only the kept positions: yt-dlp would otherwise open each filtered video before rejecting it.
    if ($queue.Count -lt $n0 -and @($queue.Keys | Where-Object { -not ($queueIndex[$_] -gt 0) }).Count -eq 0) {
        $kept = Compress-Items ([int[]]@($queue.Keys | ForEach-Object { $queueIndex[$_] }))
        $ix = [array]::IndexOf($ytArgs, '--playlist-items')
        if ($ix -ge 0) { $ytArgs[$ix + 1] = $kept } else { $ytArgs += @('--playlist-items', $kept) }
    }
}
# Called on each yt-dlp line: once the background listing is in, take its duration and show the estimate.
function Merge-BgScan {
    if (-not $script:bgScan -or -not $script:bgScanHandle.IsCompleted) { return }
    $lines = @(); try { $lines = @($script:bgScan.EndInvoke($script:bgScanHandle)) } catch { }
    try { $script:bgScan.Dispose() } catch { }
    $script:bgScan = $null
    $q = ConvertFrom-ScanLines $lines
    Write-LogOnly ("[ytdl-event] background listing: {0} video(s) in {1:N1} s" -f $q.Count, ((Get-Date) - $script:bgScanT0).TotalSeconds)
    if (-not $eta.Queue) { return }
    if ($barCache) { $barCache.CurId = $null }   # 1.17.0: re-estimate the current video with its real duration
    foreach ($k in @($q.Keys)) { if ($eta.Queue.Contains($k)) { $eta.Queue[$k] = $q[$k] } }
    $known = @($eta.Queue.Values | Where-Object { $_ -gt 0 })
    if ($known.Count) { $eta.AvgDur = ($known | Measure-Object -Average).Average }
    Show-Eta ''
}
if ($NoScan) { }
elseif ($queue.Count -gt 0) {
    $eta.Queue   = $queue
    $eta.Total   = $queue.Count
    $eta.Pending = New-Object 'System.Collections.Generic.HashSet[string]'
    Update-ArchiveSet
    foreach ($id in $queue.Keys) { if (-not (Test-Archived $id -NoRefresh)) { [void]$eta.Pending.Add($id) } }
    $known = @($queue.Values | Where-Object { $_ -gt 0 })
    if ($known.Count) { $eta.AvgDur = ($known | Measure-Object -Average).Average }
    # 1.25.0: a small signed-in batch (20 videos or fewer to download) starts with no pauses at all
    if ($autoPace -and $Worker -eq 0 -and $paceIdent -eq 'In' -and $paceFloor -eq 1 -and $StartFloor -lt 0 -and $eta.Pending.Count -le 20) {
        $paceFloor = 0
        if ($paceLevel -eq 1) { $paceLevel = 0; Set-RunWorkers $workersN }
    }
    # 1.9.0: the default 3 workers need 2+ videos left with playlist positions (a single video URL has
    # none). Otherwise this is a one-worker run from the start, so its estimate isn't divided by 3.
    if ($autoParallel -and $isCoordinator) {
        $withPos = @($eta.Pending | Where-Object { $queueIndex[$_] -gt 0 }).Count
        if ($withPos -lt 2) { $Parallel = 1; $autoParallel = $false; $isCoordinator = $false; Set-RunWorkers 1 }
    }
    # 1.14.0: fewer videos than workers (2 videos at the default 3) means fewer workers actually run;
    # use that count for the estimate, the shared-speed model and its saved history (the workers get
    # -WorkerCount of the same number).
    if ($isCoordinator) {
        $withPos = @($eta.Pending | Where-Object { $queueIndex[$_] -gt 0 }).Count
        if ($withPos -ge 2 -and $withPos -lt $workersN) { Set-RunWorkers $withPos }
    }

    # Under -Parallel, each worker probes its own share instead of the coordinator probing everything.
    # 1.17.2: with -Estimate no workers start, so the coordinator looks up every size itself.
    if ($Precise -and (-not $isCoordinator -or $Estimate) -and $eta.Pending.Count -gt 0) {
        $n = $eta.Pending.Count
        Write-Host "[ytdl] -Precise: looking up exact sizes for $n video(s) (~$(Format-Dur ([math]::Max(5, $n * 1.5))))..." -ForegroundColor DarkGray
        $probed = Get-Sizes @($eta.Pending); foreach ($k in $probed.Keys) { $eta.Size[$k] = $probed[$k] }
        # (Get-Bitrate counts these known sizes itself since 1.6.0; adding them here too would double-count.)
        $miss = $n - $eta.Size.Count
        if ($miss -gt 0) { Write-Host "[ytdl] $miss size lookup(s) failed; estimating those from runtime." -ForegroundColor DarkYellow }
    }
    Update-BwPrior
    # 1.8.0: when the resolution check below will run, its result changes the bitrate, the worker count
    # and so the estimate (real runs: a 56-60 min first ETA for runs that took 29-30), so wait for it.
    $willCheck = ($Worker -eq 0 -and -not $LowResContent -and -not $AudioOnly -and $Quality -notin '360', '480' -and $eta.Pending.Count -ge 8)
    if ($willCheck) {
        $media = 0.0; foreach ($id in $eta.Pending) { $d = $eta.Queue[$id]; if ($d -le 0) { $d = $eta.AvgDur }; $media += $d }
        Write-Host "[ytdl] $($eta.Total - $eta.Pending.Count) of $($eta.Total) done | $($eta.Pending.Count) left ($(Format-Dur $media) of video) | checking the resolution for the estimate..." -ForegroundColor Cyan
    } else { Show-Eta }
} else {
    Write-Host "[ytdl] Couldn't list the videos up front (bot check or unsupported URL); no ETA this run." -ForegroundColor DarkYellow
}

# ---- yt-dlp helper plugins (1.7.0 thumbnails, 1.9.0 formats) --------------------------------
# Written to %LOCALAPPDATA%\ytdl\plugins and loaded with --plugin-dirs. If yt-dlp can't load them,
# ytdl restarts without them (see Invoke-Pass).
# 1.9.0 format check: about 1 in 12 replies to the fast (web_embedded) client offers only the 360p
# combined format 18 (YouTube's "SABR-only" experiment), and yt-dlp then silently downloads 360p:
# 2 of 6 videos in a signed-out 1080p test, 5 of 60 test lookups. Asking the same client again in the
# same process gets the same answer (4 of 4); yt-dlp's default clients got the full list 5 of 5 times
# (~2 s extra, only for those videos). The plugin wraps the YouTube extractor to do that. It also
# keeps the resolution check and size probe from mistaking such a reply for 360p content.
$helperDir = Join-Path $env:LOCALAPPDATA 'ytdl\plugins'
$formatsPluginPy = @'
# ytdl helper (written by ytdl.ps1; safe to delete). When YouTube's reply offers only the 360p
# combined format (no separate video/audio formats), asks again with yt-dlp's default clients.
# With YTDL_FRAGMENTS=1 in the environment, direct-download formats of known size are turned into
# 10 MiB range fragments (what yt-dlp's formats=dashy does), so -N can fetch several at once;
# formats without a known size are left as they are (dashy would drop them).
import copy
import os

from yt_dlp.extractor.youtube import YoutubeIE
from yt_dlp.utils import update_url_query

_CHUNK = 10 << 20


def _fragmentize(info):
    if os.environ.get('YTDL_FRAGMENTS') != '1' or not isinstance(info, dict):
        return 0
    n = 0
    for f in info.get('formats') or []:
        size = f.get('filesize')
        if (not size or not f.get('url') or f.get('fragments') or f.get('protocol') not in (None, 'https')
                or not (f.get('downloader_options') or {}).get('http_chunk_size')):
            continue
        url = f['url']
        f['fragments'] = [{'url': update_url_query(url, {'range': '%d-%d' % (s, min(s + _CHUNK - 1, size))})}
                          for s in range(0, size, _CHUNK)]
        f['protocol'] = 'http_dash_segments'
        f.pop('downloader_options', None)
        n += 1
    return n


def _only_combined(info):
    if not isinstance(info, dict) or info.get('is_live') or info.get('live_status') in ('is_live', 'is_upcoming', 'post_live'):
        return False
    av = [f for f in (info.get('formats') or []) if f.get('vcodec') not in (None, 'none') or f.get('acodec') not in (None, 'none')]
    return bool(av) and not any(f.get('vcodec') in (None, 'none') or f.get('acodec') in (None, 'none') for f in av)


class YtdlYoutubeIE(YoutubeIE, plugin_name='ytdl'):
    def _real_extract(self, url):
        info = self._recheck(url)
        try:
            _fragmentize(info)
        except Exception as e:
            self.report_warning('ytdl fragment setup skipped: %s' % e)
        return info

    def _recheck(self, url):
        info = super()._real_extract(url)
        try:
            if not _only_combined(info):
                return info
            self.to_screen('%s: YouTube offered only the 360p combined format; asking again with the default clients' % info.get('id'))
            params = self._downloader.params
            saved = params.get('extractor_args')
            ea = copy.deepcopy(saved or {})
            ea.setdefault('youtube', {})['player_client'] = ['default']
            params['extractor_args'] = ea
            try:
                again = super()._real_extract(url)
            finally:
                params['extractor_args'] = saved
            if not _only_combined(again):
                self.to_screen('%s: full format list received' % info.get('id'))
                return again
            self.to_screen('%s: still only the 360p combined format' % info.get('id'))
        except Exception as e:
            self.report_warning('ytdl format re-check failed: %s' % e)
        return info


YtdlYoutubeIE.IE_NAME = YoutubeIE.IE_NAME   # keep "[youtube] <id>: ..." log lines (ytdl parses them)
'@
function Install-Helper([string]$rel, [string]$text) {
    $p = Join-Path $helperDir $rel
    $cur = if (Test-Path -LiteralPath $p) { [IO.File]::ReadAllText($p) } else { '' }
    if ($cur -ne $text) {
        New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null
        $tmp = "$p.$PID.tmp"; [IO.File]::WriteAllText($tmp, $text, (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tmp -Destination $p -Force
    }
}
$formatsPlugin = $false; $thumbPlugin = $false
# (1.12.0: always, since it also sets up -Fragments; without a reduced reply or YTDL_FRAGMENTS it changes nothing)
try { Install-Helper 'ytdl\yt_dlp_plugins\extractor\ytdl_formats.py' $formatsPluginPy; $formatsPlugin = $true } catch { }
function Get-HelperArgs {
    $a = @()
    if ($script:formatsPlugin -or $script:thumbPlugin) { $a += @('--plugin-dirs', $helperDir) }
    if ($script:thumbPlugin) { $a += @('--use-postprocessor', 'YtdlThumbs:when=pre_process') }
    $a + (Get-PotArgs)
}

# ---- 1.22.0 -PoToken: bgutil PO-token provider (yt-dlp plugin + a local HTTP server run on deno) --------
# The plugin (a zip) lives in its own plugin folder, loaded with --plugin-dirs only when -PoToken is given,
# so runs without it are unchanged. The server listens on 127.0.0.1:4416 (the plugin's default). It is
# started detached (not a child of this process): ytdl kills its own process tree on every restart, and
# the server must outlive those. Any ytdl process starts it when it's down; the run that started it stops it.
$potVer     = '2.0.2'
$potDir     = Join-Path $env:LOCALAPPDATA 'ytdl\pot'
$potPlugins = Join-Path $potDir 'plugins'
$potZip     = Join-Path $potPlugins 'bgutil-ytdlp-pot-provider.zip'
$potServer  = Join-Path $potDir "server-$potVer\server"
$potPort    = 4416
$script:potOn = $false; $script:potPid = 0; $script:potCheck = [datetime]::MinValue
function Test-PotPort {
    $c = New-Object Net.Sockets.TcpClient
    try { $c.ConnectAsync('127.0.0.1', $potPort).Wait(500) -and $c.Connected } catch { $false } finally { $c.Dispose() }
}
function Install-PoToken {
    if ((Test-Path $potZip) -and (Test-Path (Join-Path $potServer 'node_modules'))) { return }
    $dn = Get-Command deno -ErrorAction SilentlyContinue
    if (-not $dn) { throw 'deno is needed for -PoToken (winget install DenoLand.Deno)' }
    Write-Host "[ytdl] Installing the PO-token provider (bgutil $potVer) into $potDir (once)..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force $potPlugins | Out-Null
    $rel = "https://github.com/Brainicism/bgutil-ytdlp-pot-provider"
    Invoke-WebRequest "$rel/releases/download/$potVer/bgutil-ytdlp-pot-provider.zip" -OutFile $potZip -UseBasicParsing
    $src = Join-Path $potDir "src-$potVer.zip"
    Invoke-WebRequest "$rel/archive/refs/tags/$potVer.zip" -OutFile $src -UseBasicParsing
    $tmp = Join-Path $potDir "x-$potVer"; Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    Expand-Archive $src $tmp -Force
    $top = @(Get-ChildItem $tmp -Directory)[0].FullName
    Remove-Item -Recurse -Force (Split-Path $potServer) -ErrorAction SilentlyContinue
    Move-Item $top (Split-Path $potServer)
    Remove-Item -Recurse -Force $tmp, $src -ErrorAction SilentlyContinue
    Push-Location $potServer
    try { & $dn.Source install --allow-scripts=npm:canvas --frozen 2>&1 | Select-Object -Last 3 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray } } finally { Pop-Location }
    if (-not (Test-Path (Join-Path $potServer 'node_modules'))) { throw "deno install failed in $potServer" }
}
function Start-PoServer {
    if (Test-PotPort) { return $true }
    $dn = (Get-Command deno -ErrorAction SilentlyContinue).Source; if (-not $dn) { return $false }
    $nm = Join-Path $potServer 'node_modules'
    $cmd = "`"$dn`" run --allow-env --allow-net --allow-ffi=. --allow-read=. ../src/main.ts"
    # Win32_Process.Create: no parent link, so ytdl's own process-tree kills leave the server running
    $r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmd; CurrentDirectory = $nm; ProcessStartupInformation = (New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]0 }) }
    if ($r.ReturnValue -ne 0) { return $false }
    if ($Worker -eq 0 -and -not $script:potPid) { $script:potPid = [int]$r.ProcessId }
    for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Milliseconds 250; if (Test-PotPort) { return $true } }
    $false
}
function Stop-PoServer {
    if (-not $script:potPid) { return }
    try { Stop-Process -Id $script:potPid -Force -ErrorAction Stop } catch { }
    $script:potPid = 0
}
# --plugin-dirs for the provider; checks the server at most every 30 s and restarts it if it went away
function Get-PotArgs {
    if (-not $script:potOn) { return @() }
    if (((Get-Date) - $script:potCheck).TotalSeconds -gt 30) {
        $script:potCheck = Get-Date
        if (-not (Start-PoServer)) { Write-Host "[ytdl] The PO-token server didn't start; continuing without tokens." -ForegroundColor Yellow; $script:potOn = $false; return @() }
    }
    @('--plugin-dirs', $potPlugins)
}
if ($PoToken -and -not $Doctor -and -not $Version) {
    try { Install-PoToken; $script:potOn = $true; [void](Get-PotArgs) }
    catch { Write-Host "[ytdl] -PoToken: $($_.Exception.Message); continuing without it." -ForegroundColor Yellow }
}
$helperFailPattern = "KeyError: 'YtdlThumbs|no such option: --(plugin-dirs|use-postprocessor)|ytdl_thumbs|ytdl_formats|YtdlYoutube"

# ---- resolution check (1.6.0) ---------------------------------------------------------------
# "best" (or 720p+) on old uploads often resolves to 480p or less: a real 234-video run asked for
# best and got 135+251 (480p) or 243+251 (360p) every time, yet ran one video at a time with the
# 'best' ETA priors. Look up 3 sample videos (first, middle, last) in one yt-dlp call; if all are
# <= 480p, use the 480p-and-below settings: -Parallel 3 (unless -Parallel was given), no background
# probe, early ETA, and the samples' sizes seed the bitrate.
$detectedLowRes = $false
# 1.9.0: the result is remembered per URL and quality for 7 days (%LOCALAPPDATA%\ytdl\content.json),
# so re-running the same playlist (after a stop, or after -Estimate) skips the ~7 s lookups. A stale
# answer could only affect the estimate and the 480p-and-below settings; yt-dlp still picks formats.
$resCacheFile = Join-Path $env:LOCALAPPDATA 'ytdl\content.json'
$resKey = "$Url|$Quality"
# Only worth it with 8+ videos left.
if ($willCheck -and $eta.Queue) {
    $resCache = @{}
    if (Test-Path $resCacheFile) { try { (Get-Content $resCacheFile -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $resCache[$_.Name] = $_.Value } } catch { } }
    $heights = @(); $resOk = $false
    $hit = $resCache[$resKey]
    if ($hit -and [int]$hit.H -gt 0 -and $(try { ((Get-Date) - [datetime]$hit.Updated).TotalDays -lt 7 } catch { $false })) {
        $heights = @([int]$hit.H); $resOk = $true
        Write-LogOnly "[ytdl-event] resolution check: $($hit.H)p remembered from $($hit.Updated)"
    } else {
    $pend = @($eta.Queue.Keys | Where-Object { $eta.Pending.Contains($_) })
    $sample = @(@($pend[0], $pend[[int][math]::Floor($pend.Count / 2)], $pend[-1]) | Select-Object -Unique)
    $chkT0 = Get-Date
    # 1.8.0: one yt-dlp per sample, all at once (9-11 s one after another in real runs). Each gets 60 s.
    # 1.11.0: samples the fast client can't see (embedding disabled: 2 of 3 in a real run, which left
    # that run without the 480p-and-below settings and cost it 619 thumbnail misses) are asked again
    # with the default clients, and the URL is then marked for them, so the workers start with them
    # instead of each failing on its first video and restarting (~6 s each).
    $answered = @{}
    foreach ($round in 1, 2) {
        $ids = @($sample | Where-Object { -not $answered.ContainsKey($_) })
        if (-not $ids.Count) { break }
        if ($round -eq 2) {
            if (-not $fastClient -or -not $chkErr -or ($chkErr -join "`n") -notmatch $clientFallbackPattern) { break }
            $fastClient = $false
        }
        $before = $answered.Count
        $chkBase = @('--ignore-errors', '--no-warnings', '-s', '-f', $fmt, '--print', '%(id)s %(height)s %(filesize,filesize_approx)s %(width)s')   # 1.18.2: width too (shorter side) + $authArgs + (Get-ClientArgs) + (Get-HelperArgs)
        $chkProcs = foreach ($sid in $ids) {
            $o = Join-Path $env:TEMP "ytdl-$PID-res-$sid.txt"
            $argStr = (@($chkBase) + "https://www.youtube.com/watch?v=$sid" | ForEach-Object { Quote-Arg ([string]$_) }) -join ' '
            try { $p = Start-Process -FilePath $ytdlp -ArgumentList $argStr -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError "$o.err"
                  $null = $p.Handle; [pscustomobject]@{ P = $p; O = $o } } catch { }
        }
        $deadline = (Get-Date).AddSeconds(60)
        foreach ($cp in $chkProcs) {
            $ms = [int][math]::Max(1, ($deadline - (Get-Date)).TotalMilliseconds)
            if (-not $cp.P.WaitForExit($ms)) { & taskkill.exe /T /F /PID $cp.P.Id 2>&1 | Out-Null }
        }
        $chkOut = @(); $chkErr = @()
        foreach ($cp in $chkProcs) {
            $chkOut += @(Get-Content -LiteralPath $cp.O -ErrorAction SilentlyContinue)
            $chkErr += @(Get-Content -LiteralPath "$($cp.O).err" -ErrorAction SilentlyContinue | Where-Object { $_ -match '^ERROR' })
            Remove-Item -LiteralPath $cp.O, "$($cp.O).err" -Force -ErrorAction SilentlyContinue
        }
        foreach ($l in $chkOut) {
            $q = "$l".Trim() -split ' '
            if ($q.Count -ge 2 -and $q[0] -match '^[\w-]{11}$') {
                $hh = 0; if ([int]::TryParse($q[1], [ref]$hh)) { $ww = 0; if ($q.Count -ge 4 -and [int]::TryParse($q[3], [ref]$ww) -and $ww -gt 0 -and $ww -lt $hh) { $hh = $ww }; $heights += $hh; $answered[$q[0]] = $true }   # 1.18.2: shorter side
                if ($q.Count -ge 3 -and $q[2] -match '^\d+$') { $eta.Size[$q[0]] = [double]$q[2] / 1MB }
            }
        }
        if ($round -eq 2) {
            if ($answered.Count -gt $before) {
                Save-ClientFallback
                Write-Host "[ytdl] Some of these videos don't allow embedding, so this playlist uses yt-dlp's default clients (remembered 7 days)." -ForegroundColor DarkGray
            } else { $fastClient = $true }
        }
    }
    Write-LogOnly ("[ytdl-event] resolution check: {0} of {1} sample(s), heights {2}, {3:N1} s" -f $heights.Count, $sample.Count, ($heights -join ','), ((Get-Date) - $chkT0).TotalSeconds)
    $resOk = ($heights.Count -eq $sample.Count -and $heights.Count -gt 0)
    if ($resOk) {
        try {
            $now = Get-Date; $resKeep = @{}
            foreach ($k in @($resCache.Keys)) { try { $u = [datetime]$resCache[$k].Updated; if (($now - $u).TotalDays -lt 30) { $resKeep[$k] = @{ H = [int]$resCache[$k].H; Updated = $u.ToString('s') } } } catch { } }
            $resKeep[$resKey] = @{ H = [int]($heights | Measure-Object -Maximum).Maximum; Updated = $now.ToString('s') }
            New-Item -ItemType Directory -Force (Split-Path $resCacheFile) | Out-Null
            $resKeep | ConvertTo-Json -Depth 3 | Set-Content -Path $resCacheFile -Encoding UTF8
        } catch { }
    }
    }
    if ($resOk -and ($heights | Measure-Object -Maximum).Maximum -le 480) {
        $detectedLowRes = $true; $lowRes = $true
        # Use the detected resolution's bitrate prior and history, not 'best' (replay of the real run:
        # first-10-minute ETA error 20.0% -> 7.4% with this plus the 3 sample sizes).
        $hmax = ($heights | Measure-Object -Maximum).Maximum
        $qualKey = "q$(if ($hmax -le 360) { 360 } else { 480 })"; $brCache.T = [datetime]::MinValue
        $eta.BrMiB = 0.0; $eta.BrSec = 0.0; $eta.HBrMiB = 0.0; $eta.HBrSec = 0.0
        $h = $savedRates["br-$qualKey"]
        if ($h -and $h.Sec -gt 0) { $w = [math]::Min(1.0, $capBrSec / [double]$h.Sec); $eta.HBrMiB = $h.MiB * $w; $eta.HBrSec = $h.Sec * $w }
        Set-RunWorkers $workersN   # the new bitrate changes each download's share of the connection
        Write-Host ("[ytdl] Best available for these videos is {0}p, so this run uses the 480p-and-below settings." -f $hmax) -ForegroundColor Cyan
    } else { Update-BwPrior }
    Show-Eta ''
}

# ---- thumbnail misses (1.7.0) ---------------------------------------------------------------
# yt-dlp tries guessed thumbnail URLs (maxresdefault, hq720, sddefault...) one at a time, best first.
# Old uploads lack most of them: a real 251-video 480p run spent 1.65 s per video on ~4 misses in a
# row. A tiny yt-dlp plugin (pre_process) checks those guesses all at once and drops the 404s, so
# yt-dlp embeds the same thumbnail without the misses (6 old videos: identical files, 0 misses).
# Only at 480p and below: newer uploads have the big thumbnails, and the check would cost ~0.3 s.
# If yt-dlp can't load the plugin, ytdl restarts without it (see Invoke-Pass).
$thumbPluginPy = @'
# ytdl helper (written by ytdl.ps1; safe to delete). Drops guessed thumbnail URLs that return 404
# before yt-dlp tries them one by one. Anything unexpected leaves yt-dlp's list unchanged.
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

from yt_dlp.postprocessor.common import PostProcessor


class YtdlThumbsPP(PostProcessor):
    def run(self, info):
        try:
            th = list(info.get('thumbnails') or [])
            top = max((i for i, t in enumerate(th) if t.get('width')), default=-1)
            cand = [i for i in range(top + 1, len(th)) if th[i].get('url') and not th[i].get('width')]
            if not cand:
                return [], info

            def missing(i):
                try:
                    req = urllib.request.Request(th[i]['url'], method='HEAD', headers={'User-Agent': 'Mozilla/5.0'})
                    urllib.request.urlopen(req, timeout=5).close()
                    return False
                except urllib.error.HTTPError as e:
                    return e.code == 404
                except Exception:
                    return False

            with ThreadPoolExecutor(max_workers=min(8, len(cand))) as ex:
                gone = {i for i, m in zip(cand, ex.map(missing, cand)) if m}
            if gone:
                info['thumbnails'] = [t for i, t in enumerate(th) if i not in gone]
        except Exception:
            pass
        return [], info
'@
if ($lowRes -and -not $NoThumbnail -and -not $Estimate) {
    try { Install-Helper 'ytdl\yt_dlp_plugins\postprocessor\ytdl_thumbs.py' $thumbPluginPy; $thumbPlugin = $true } catch { $thumbPlugin = $false }
}

# ---- disk space (R2) ----------------------------------------------------------------------
$drive = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Out))
function Get-FreeBytes { try { (New-Object IO.DriveInfo($drive)).AvailableFreeSpace } catch { [double]::MaxValue } }
if (-not $Estimate -and $Worker -eq 0 -and -not $NoSpaceCheck -and $eta.Queue -and $eta.Pending.Count -gt 0) {
    $estMiB = 0.0; $maxMiB = 0.0
    foreach ($id in $eta.Pending) { $x = Get-X $id; $estMiB += $x; if ($x -gt $maxMiB) { $maxMiB = $x } }
    # Merging writes the finished file while its video and audio parts still exist: allow one
    # extra largest-file, 10% for estimate error, and the -MinFreeGB floor.
    $needBytes = ($estMiB * 1.1 + $maxMiB) * 1MB + $MinFreeGB * 1GB
    $free = Get-FreeBytes
    if ($free -lt $needBytes) {
        Write-Host ("[ytdl] Not enough disk space on {0}: ~{1:N1} GB needed (estimated {2:N1} GB download + merge room + {3} GB floor), {4:N1} GB free." -f $drive, ($needBytes / 1GB), ($estMiB / 1024), $MinFreeGB, ($free / 1GB)) -ForegroundColor Red
        Write-Host "[ytdl] Free some space, choose another -Out, use -Items for part of the list, or pass -NoSpaceCheck to start anyway." -ForegroundColor Yellow
        Release-Lock; Restore-Console; exit 2
    }
}

if ($Estimate) {
    if ($eta.Queue -and -not (Get-Fit)) {
        Write-Host "[ytdl] No saved download speed for this folder ($(Get-PaceLabel), $workersN worker(s)) yet; a real run measures it within seconds." -ForegroundColor DarkGray
    }
    exit 0
}

# ---- -Parallel coordinator ----------------------------------------------------------------
# Splits the pending playlist positions across N worker processes, each a full ytdl run
# (-Items <its share> -Worker k), so every worker keeps retries, cookie restarts, the watchdog
# and the error-loop breaker. Using playlist positions (not bare video URLs) keeps the
# playlist folder name and NNN numbering. Workers write to log files; this loop tails them,
# prefixes each line with [wK], and prints an overall ETA (the latest worker finish time).
# (Compress-Items is defined with the scan, which uses it too since 1.16.0.)

# ---- 1.16.0: failed-videos list ---------------------------------------------------------------------
# Each run notes the last ERROR per video. At the end, the ones still missing from the archive are
# listed with title, link and reason, and saved in <Out>\ytdl-failed.txt (readable) with
# <Out>\.ytdl-failed.json behind it, one section per URL. Videos that later download, by any run,
# drop out; the files go away when nothing is left. Workers print their failures as [ytdl-fail]
# lines for the coordinator, which keeps them out of the console and saves one list for the run.
$failStore = Join-Path $Out '.ytdl-failed.json'
$failText  = Join-Path $Out 'ytdl-failed.txt'
$permPattern = 'Private video|Video unavailable|video is unavailable|has been removed|has been terminated|copyright|members-only|Join this channel|not available in your country|blocked it in your country|confirm your age|age-restricted|inappropriate for some users|Premieres in|live event will begin|removed by the uploader|does not exist'
function Get-ShortReason([string]$r) { $r = ($r -replace '\s+', ' ').Trim(); if ($r.Length -gt 160) { $r.Substring(0, 157) + '...' } else { $r } }
function New-FailItem([string]$id, [string]$title, [string]$reason) {
    [pscustomobject]@{ Id = $id; Title = $title; Reason = (Get-ShortReason $reason); Permanent = [bool]($reason -match $permPattern -and $reason -notmatch $transientPattern) }
}
# 1.22.1: the label shown after a failed video's reason. Worked out from the reason text, so items saved
# by older versions (rate limits stored as Permanent) are labeled right too.
function Get-FailTag($f) {
    if ("$($f.Reason)" -match $transientPattern) { 'rate-limited, retry later' } elseif ($f.Permanent) { "won't fix itself" } else { '' }
}
function Save-FailedList([string]$url, $items) {
    try {
        $all = [ordered]@{}
        if (Test-Path -LiteralPath $failStore) {
            $j = Get-Content -LiteralPath $failStore -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $j.PSObject.Properties) { $all[$p.Name] = $p.Value }
        }
        if (@($items).Count) { $all[$url] = [pscustomobject]@{ When = (Get-Date).ToString('s'); Items = @($items) } }
        elseif ($all.Contains($url)) { $all.Remove($url) }
        Update-ArchiveSet
        foreach ($k in @($all.Keys)) {
            $left = @($all[$k].Items | Where-Object { $_ -and -not (Test-Archived ([string]$_.Id) -NoRefresh) })
            if ($left.Count) { $all[$k] = [pscustomobject]@{ When = $all[$k].When; Items = $left } } else { $all.Remove($k) }
        }
        if (-not $all.Count) { Remove-Item -LiteralPath $failStore, $failText -Force -ErrorAction SilentlyContinue; return }
        ConvertTo-Json -InputObject $all -Depth 5 | Set-Content -LiteralPath $failStore -Encoding UTF8
        $t = @("Videos ytdl couldn't download (updated $((Get-Date).ToString('yyyy-MM-dd HH:mm'))).",
               "Re-running the same command retries a URL's videos; ones marked 'won't fix itself' will keep failing.", '')
        foreach ($k in $all.Keys) {
            $t += "== $k   (last run $(Format-When $all[$k].When))"
            foreach ($f in $all[$k].Items) {
                $t += "   $(if ($f.Title) { $f.Title } else { $f.Id })   https://www.youtube.com/watch?v=$($f.Id)"
                $t += "      $($f.Reason)$(if ($tag = Get-FailTag $f) { "   [$tag]" })"
            }
            $t += ''
        }
        Set-Content -LiteralPath $failText -Value $t -Encoding UTF8
    } catch { Write-LogOnly "[ytdl-event] failed-videos list not saved: $($_.Exception.Message)" }
}
function Show-FailedList($items) {
    $items = @($items); $n = $items.Count
    if (-not $n) { return }
    $tags = @($items | ForEach-Object { Get-FailTag $_ })
    $perm = @($tags | Where-Object { $_ -eq "won't fix itself" }).Count
    $rate = @($tags | Where-Object { $_ -like 'rate-limited*' }).Count
    Write-Host ''
    Write-Host "[ytdl] $n video(s) couldn't be downloaded:" -ForegroundColor Yellow
    foreach ($f in ($items | Select-Object -First 15)) {
        Write-Host "  $(if ($f.Title) { $f.Title } else { $f.Id })  https://www.youtube.com/watch?v=$($f.Id)"
        Write-Host "     $($f.Reason)$(if ($tag = Get-FailTag $f) { "  ($tag)" })" -ForegroundColor DarkGray
    }
    if ($n -gt 15) { Write-Host "  ...and $($n - 15) more." }
    if ($rate) { Write-Host "  $rate refused because YouTube rate-limited this account (it says for up to an hour): re-run the same command later to get them." -ForegroundColor Yellow }
    if ($n - $perm - $rate) { Write-Host "  Re-run the same command to retry the $($n - $perm - $rate) that may still work." -ForegroundColor Yellow }
    if ($perm) { Write-Host "  $perm won't fix itself (private, removed, blocked, age- or members-only)." -ForegroundColor DarkGray }
    Write-Host "  List saved: $failText" -ForegroundColor DarkGray
}



if ($isCoordinator) {
    $work = @()
    if ($eta.Queue) {
        foreach ($id in $eta.Pending) {
            if ($queueIndex.ContainsKey($id) -and $queueIndex[$id] -gt 0) {
                $work += [pscustomobject]@{ Id = $id; I = $queueIndex[$id]; X = (Get-X $id) }
            }
        }
    }
    if ($work.Count -lt 2) {
        if (-not $autoParallel) { Write-Host "[ytdl] -Parallel needs a playlist with 2+ videos left; downloading with a single worker." -ForegroundColor DarkYellow }
        $isCoordinator = $false; Set-RunWorkers 1
    }
}

if ($isCoordinator) {
    $n = [math]::Min($Parallel, $work.Count)

    # Balance by predicted time (longest first onto the least-loaded worker).
    $fit = Get-Fit
    if (-not $fit) { $fit = @(0.2, (Get-Overhead)) }   # x is MiB in both modes; ~5 MiB/s guess
    $loads = New-Object double[] $n
    $shares = @(); for ($k = 0; $k -lt $n; $k++) { $shares += , (New-Object System.Collections.ArrayList) }
    foreach ($w in ($work | Sort-Object X -Descending)) {
        $k = 0; for ($j = 1; $j -lt $n; $j++) { if ($loads[$j] -lt $loads[$k]) { $k = $j } }
        [void]$shares[$k].Add($w.I); $loads[$k] += $fit[0] * $w.X + $fit[1]
    }

    # Rebuild this command line for the workers (minus coordinator-only options).
    $hostExe = (Get-Process -Id $PID).Path
    $common = @()
    foreach ($key in $PSBoundParameters.Keys) {
        if ($key -in 'Url', 'Parallel', 'Items', 'Estimate', 'Worker', 'WorkerCount', 'Dynamic', 'Chunk') { continue }
        $val = $PSBoundParameters[$key]
        if ($val -is [System.Management.Automation.SwitchParameter]) { if ($val.IsPresent) { $common += "-$key" } }
        elseif ("$val" -like '-*') { $common += "-${key}:$val" }   # 1.18.0: see Get-SubArgs (pwsh -File)
        else { $common += "-$key"; $common += [string]$val }
    }
    if (-not $PSBoundParameters.ContainsKey('Out')) { $common += '-Out'; $common += $Out }
    if ($detectedLowRes) { $common += @('-LowResContent', '-ContentHeight', $hmax) }
    if ($autoPace) { $common += @('-StartFloor', $paceFloor) }   # 1.25.0

    # Worker logs from coordinators that ended abruptly (window closed) are left in %TEMP%; drop
    # the ones whose coordinator process no longer exists.
    Get-ChildItem $env:TEMP -Filter 'ytdl-*-w*.log*' -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -match '^ytdl-(\d+)-w') { if (-not (Get-Process -Id ([int]$Matches[1]) -ErrorAction SilentlyContinue)) { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue } }
    }
    Clear-StopFiles
    Write-Host "ytdl $YtdlVersion | -Parallel: $($work.Count) videos across $n workers$(if ($autoParallel) { ' (default; -Parallel 1 for one at a time)' })$(if ($limitBytes -gt 0) { " | at most $LimitRate/s in total" }) -> $Out" -ForegroundColor Cyan
    Write-Host "To stop: press Ctrl+C here, or run 'ytdl -Stop' in another terminal. To pause: press P (P again resumes), or ytdl -Pause / -Resume." -ForegroundColor DarkGray

    # Batches to hand out. Fixed split: one pre-balanced batch per slot. -Dynamic: a shared queue of
    # -Chunk-sized batches, biggest videos first, so the small ones fill in at the end.
    $batches = New-Object System.Collections.ArrayList
    if ($Dynamic) {
        $ordered = @($work | Sort-Object X -Descending)
        for ($b = 0; $b -lt $ordered.Count; $b += $Chunk) {
            $grp = @($ordered[$b..([math]::Min($b + $Chunk, $ordered.Count) - 1)])
            [void]$batches.Add([pscustomobject]@{ I = [int[]]@($grp | ForEach-Object I); X = @($grp | ForEach-Object X) })
        }
        Write-Host "[ytdl] -Dynamic: $($batches.Count) batch(es) of up to $Chunk video(s), handed to whichever worker is free" -ForegroundColor DarkGray
    } else {
        foreach ($sh in $shares) { if ($sh.Count) { [void]$batches.Add([pscustomobject]@{ I = [int[]]$sh.ToArray(); X = @() }) } }
    }
    $total = $work.Count; $doneBatches = 0; $launches = 0; $lastLaunch = [datetime]::MinValue
    $slots = @(); for ($k = 1; $k -le $n; $k++) { $slots += [pscustomobject]@{ K = $k; W = $null } }
    $workers = @()
    $workByI = @{}; foreach ($wk in $work) { $workByI[$wk.I] = $wk }
    function Start-Batch($slot, $batch) {
        $script:launches++
        $items = Compress-Items $batch.I
        $log = Join-Path $env:TEMP "ytdl-$PID-w$($slot.K)-$($script:launches).log"
        # This batch's part of the scan (id, duration, position, known size), so the worker doesn't rescan.
        $qf = "$log.queue.json"
        $entries = @(foreach ($i in ($batch.I | Sort-Object)) {
            $wk = $workByI[$i]; $s = 0.0; if ($eta.Size.ContainsKey($wk.Id)) { $s = [double]$eta.Size[$wk.Id] }
            [ordered]@{ Id = $wk.Id; D = [double]$eta.Queue[$wk.Id]; I = $i; S = [math]::Round($s, 3); T = [string]$queueTitle[$wk.Id] }
        })
        try { ConvertTo-Json -InputObject $entries -Depth 3 -Compress | Set-Content -LiteralPath $qf -Encoding UTF8 } catch { $qf = $null }
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, $Url) + $common +
                   @('-Items', $items, '-Worker', $slot.K, '-WorkerCount', $n)
        if ($qf) { $argList += @('-QueueFile', $qf) }
        $argStr = ($argList | ForEach-Object { Quote-Arg ([string]$_) }) -join ' '
        $p = Start-Process -FilePath $hostExe -ArgumentList $argStr -NoNewWindow -PassThru `
                           -RedirectStandardOutput $log -RedirectStandardError "$log.err"
        $null = $p.Handle   # cache the handle now, or ExitCode reads as empty after the process exits
        $w = [pscustomobject]@{ K = $slot.K; Proc = $p; Logs = @($log, "$log.err"); QFile = $qf; Readers = @{}; Buf = @{}
                                Done = 0; Total = $batch.I.Count; Eta = $null; Counted = $false; Part = 0.0 }   # Part: 1.17.0 bar
        $slot.W = $w; $script:workers += $w; $script:lastLaunch = Get-Date
        Write-Host "[w$($slot.K)] started: items $items" -ForegroundColor DarkGray
    }
    $capMiB = 0.0; $capT0 = Get-Date   # 1.8.0: total transferred by all workers, for the learned connection cap
    $coordFails = [ordered]@{}         # 1.16.0: id -> failure reported by a worker
    $keysOn = $true                    # 1.16.0: P/R keys (off when there is no console)
    # 1.17.0: one bar for the whole run. Done = every stream the workers finished ($capMiB) + each worker's
    # current stream; total = the estimates of all the videos handed out. Speed is smoothed over 2 s steps.
    # Workers print a progress line every second for it (YTDL_PROGRESS_DELTA, inherited by Start-Process).
    $coordTotalMiB = [double](($work | Measure-Object X -Sum).Sum)
    $barSpeed = @{ T = Get-Date; Done = 0.0; MiBps = 0.0 }
    if ($script:barOn) { $env:YTDL_PROGRESS_DELTA = '1' }
    $script:barState = {
        $dn = $capMiB + [double](($workers | Measure-Object Part -Sum).Sum)
        @{ Done = $dn; Total = [math]::Max($coordTotalMiB, $dn); FilesDone = [int](($workers | Measure-Object Done -Sum).Sum); FilesTotal = $total
           Speed = $barSpeed.MiBps; Paused = [bool](Test-PauseRequested) }
    }
    $coordBreak = $false; $lastBrkCheck = [datetime]::MinValue
    try {
        $lastOverall = ''
        while ($true) {
            # 1.25.0: no launches while the limit guard's breaker is open (a worker or another run opened it)
            if ($breakerOn -and -not $coordBreak -and ((Get-Date) - $lastBrkCheck).TotalSeconds -ge 5) {
                $lastBrkCheck = Get-Date; $coordBreak = (Get-BreakerLeft (Read-GlobalPace)) -gt 0
            }
            # Hand out batches to free slots (never after a stop), at most one launch every 3 s.
            foreach ($sl in $slots) {
                if ($batches.Count -eq 0 -or (Test-StopRequested) -or (Test-PauseRequested) -or $coordBreak) { break }   # 1.16.0: no launches while paused
                if ($sl.W -and -not $sl.W.Proc.HasExited) { continue }
                if (((Get-Date) - $lastLaunch).TotalSeconds -lt $launchGap) { break }
                $bt = $batches[0]; $batches.RemoveAt(0); Start-Batch $sl $bt
            }
            $alive = @($workers | Where-Object { -not $_.Proc.HasExited }).Count
            foreach ($w in $workers) {
                foreach ($log in $w.Logs) {
                    if (-not $w.Readers[$log]) {
                        if (-not (Test-Path $log)) { continue }
                        $fs = [IO.File]::Open($log, 'Open', 'Read', 'ReadWrite')
                        $w.Readers[$log] = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
                        $w.Buf[$log] = ''
                    }
                    $chunkText = $w.Readers[$log].ReadToEnd()
                    if (-not $chunkText) { continue }
                    $lines = ($w.Buf[$log] + $chunkText) -split "`r?`n"
                    $w.Buf[$log] = $lines[-1]                    # keep a partial last line for next time
                    foreach ($line in $lines[0..($lines.Count - 2)]) {
                        if (-not $line) { continue }
                        if ($line -match "^\[ytdl-fail\] ([\w-]{11})`t([^`t]*)`t(.*)$") {   # 1.16.0
                            $coordFails[$Matches[1]] = New-FailItem $Matches[1] $Matches[2] $Matches[3]; continue
                        }
                        # Count a finished stream before anything prints: printing redraws the bar, which
                        # otherwise showed the worker's stream gone but not yet added (dips of ~25% in a test).
                        if ($line -match '^\[download\]\s+100% of\s+~?\s*([\d.]+)(KiB|MiB|GiB) in') { $capMiB += ConvertTo-MiB ([double]::Parse($Matches[1], $ci)) $Matches[2] }
                        if ($line -match '^\[download\]\s+([\d.]+)% of\s+~?\s*([\d.]+)(KiB|MiB|GiB)') {   # 1.17.0: bar
                            $pc = [double]::Parse($Matches[1], $ci)
                            $w.Part = if ($pc -ge 100) { 0.0 } else { $pc / 100 * (ConvertTo-MiB ([double]::Parse($Matches[2], $ci)) $Matches[3]) }
                            if ($script:barOn -and $pc -lt 100) { Write-LogOnly "[w$($w.K)] $line"; continue }   # the bar shows it
                        }
                        $color = if ($line -match '^ERROR') { 'Red' } elseif ($line -match '^WARNING') { 'Yellow' }
                                 elseif ($line -match '^\[ytdl\]|^===') { 'Cyan' } else { 'Gray' }
                        Write-Host "[w$($w.K)] $line" -ForegroundColor $color
                        if ($line -match '^\[ytdl\] (\d+) of (\d+) done') {
                            $w.Done = [int]$Matches[1]; $w.Total = [int]$Matches[2]
                            if ($line -match 'ETA ~(?:(\d+)h (\d+)m|(\d+)m (\d+)s)') {
                                $sec = if ($Matches[1]) { [int]$Matches[1] * 3600 + [int]$Matches[2] * 60 } else { [int]$Matches[3] * 60 + [int]$Matches[4] }
                                $w.Eta = (Get-Date).AddSeconds($sec)
                            } elseif ($line -match 'nothing left') { $w.Eta = Get-Date }
                            $done = ($workers | Measure-Object Done -Sum).Sum
                            $msg  = "[ytdl] ALL: $done of $total done"
                            $run  = @($workers | Where-Object { -not $_.Proc.HasExited -and $_.Done -lt $_.Total })
                            $etas = @($run | ForEach-Object Eta)
                            # 1.6.1: with the fixed split, wait until every worker has started and reported its
                            # own estimate; earlier, a partial set gave -61% at the start of a real 251-video run.
                            $allIn = $Dynamic -or ($batches.Count -eq 0 -and $workers.Count -ge $n)
                            if ($allIn -and $etas.Count -and -not ($etas -contains $null)) {
                                if ($Dynamic) {
                                    # time left on running batches + estimated time of queued videos, shared by N slots
                                    $fitQ = Get-Fit; if (-not $fitQ) { $fitQ = @(0.2, (Get-Overhead)) }
                                    $left = 0.0; foreach ($e in $etas) { $left += [math]::Max(0, ($e - (Get-Date)).TotalSeconds) }
                                    foreach ($bt in $batches) { foreach ($x in $bt.X) { $left += $fitQ[1] + $fitQ[0] * $x } }
                                    $secAll = $left / $n
                                    $fin = (Get-Date).AddSeconds($secAll)
                                } else {
                                    $fin = ($etas | Measure-Object -Maximum).Maximum
                                    $tf = Get-TailFinish $run $n; if ($null -ne $tf) { $fin = (Get-Date).AddSeconds($tf) }   # 1.24.1
                                }
                                $msg += " | ETA ~$(Format-Dur ($fin - (Get-Date)).TotalSeconds) (finish ~$($fin.ToString('ddd h:mm tt')))"
                            }
                            if ($msg -ne $lastOverall) { Write-Host $msg -ForegroundColor Cyan; $lastOverall = $msg }
                        }
                    }
                }
            }
            if ($alive -eq 0 -and ($batches.Count -eq 0 -or (Test-StopRequested) -or $coordBreak)) { break }
            # 1.16.0: P pauses all workers (their watchdogs suspend their yt-dlp), P or R resumes.
            if ($keysOn) {
                try {
                    while ([Console]::KeyAvailable) {
                        $k = [Console]::ReadKey($true)
                        if ($k.Key -ne 'P' -and $k.Key -ne 'R') { continue }
                        if (Test-PauseRequested) { Remove-Item $folderPause, $pauseFile -Force -ErrorAction SilentlyContinue; Write-Host "[ytdl] Resuming all workers." -ForegroundColor Green }
                        elseif ($k.Key -eq 'P') {
                            New-Item -ItemType File -Force -Path $folderPause | Out-Null; Add-Content -LiteralPath $pauseList -Value $folderPause
                            Write-Host "[ytdl] Pausing all workers. Press P (or R) to resume; Ctrl+C stops." -ForegroundColor Yellow
                        }
                    }
                } catch { $keysOn = $false }
            }
            if ($script:barOn) {   # 1.17.0
                $nowT = Get-Date; $dt = ($nowT - $barSpeed.T).TotalSeconds
                if ($dt -ge 2) {
                    $dn = $capMiB + [double](($workers | Measure-Object Part -Sum).Sum)
                    $inst = [math]::Max(0, ($dn - $barSpeed.Done) / $dt)
                    $barSpeed.MiBps = if ($barSpeed.MiBps -gt 0) { 0.6 * $barSpeed.MiBps + 0.4 * $inst } else { $inst }
                    $barSpeed.Done = $dn; $barSpeed.T = $nowT
                }
                Update-Bar
            }
            Start-Sleep -Milliseconds 300
        }    } finally {
        if ($batches.Count -eq 0 -and @($workers | Where-Object { -not $_.Proc.HasExited -or $_.Proc.ExitCode -ne 0 }).Count -eq 0) { $script:barFinal = $true }
        Close-Bar   # 1.17.0
        # Normal exit, Ctrl+C, or error: make sure no worker (or its yt-dlp) is left running.
        foreach ($w in $workers) {
            if (-not $w.Proc.HasExited) { & taskkill.exe /T /F /PID $w.Proc.Id 2>&1 | Out-Null }
            foreach ($r in $w.Readers.Values) { $r.Dispose() }
            foreach ($log in $w.Logs) { Remove-Item $log -Force -ErrorAction SilentlyContinue }
            if ($w.QFile) { Remove-Item -LiteralPath $w.QFile -Force -ErrorAction SilentlyContinue }
        }
        Clear-StopFiles; Stop-PoServer   # 1.22.0
    }

    $codes = @($workers | ForEach-Object { $_.Proc.ExitCode })
    $final = if ($codes -contains 75 -or $coordBreak) { 75 } elseif ($codes -contains 2) { 2 } elseif (@($codes | Where-Object { $_ -ne 0 }).Count) { 1 } else { 0 }
    $color = if ($final -eq 0) { 'Green' } else { 'Yellow' }
    # 1.8.0: learn the connection's total throughput from full 3+-worker runs (not stopped, 1+ GB, 5+ min:
    # start-up made a 37 s test run read 5.8 MiB/s against ~14.5 in real 22-30 min runs).
    $capSec = ((Get-Date) - $capT0).TotalSeconds
    if ($n -ge 3 -and $final -notin 2, 75 -and $capMiB -ge 1024 -and $capSec -ge 300 -and $limitBytes -le 0) {   # 1.24.1: not under -LimitRate
        $capNow = [math]::Round($capMiB / $capSec, 2)
        try {
            $j = $null; if (Test-Path $bwGlobalFile) { $j = Get-Content $bwGlobalFile -Raw | ConvertFrom-Json }
            $dr = @(); $cp = @(); if ($j) { $dr = @($j.Draws | ForEach-Object { [double]$_ }); if ($j.Caps) { $cp = @($j.Caps | ForEach-Object { [double]$_ }) } }
            # 1.11.0: a run held back by something else (a 240p playlist of small files and per-video
            # overhead read 8.8 against ~14.5) says nothing about the connection. With 3+ caps known, a
            # reading under 70% of their median is skipped, unless 3 runs in a row read that low (then
            # the connection itself has probably got slower, and it's learned).
            $lowRun = 0; if ($j -and $j.CapLowRun) { $lowRun = [int]$j.CapLowRun }
            $use = $true
            if ($cp.Count -ge 3) {
                $sc = @($cp | Sort-Object); $med = $sc[[int][math]::Floor($sc.Count / 2)]
                if ($capNow -lt 0.7 * $med) { $lowRun++; $use = ($lowRun -ge 3) } else { $lowRun = 0 }
            }
            if ($use) { $cp = @(@($cp) + $capNow | Select-Object -Last 10); if ($lowRun -ge 3) { $lowRun = 0 } }
            New-Item -ItemType Directory -Force (Split-Path $bwGlobalFile) | Out-Null
            $o = @{ Draws = @($dr); Caps = @($cp); CapLowRun = $lowRun; Updated = (Get-Date).ToString('s') }; if ($j -and $j.PDraws) { $o.PDraws = $j.PDraws }
            $o | ConvertTo-Json -Depth 3 | Set-Content -Path $bwGlobalFile -Encoding ASCII
            Write-LogOnly ("[ytdl-event] connection cap: {0:N0} MiB in {1:N0} s = {2} MiB/s across {3} workers{4}" -f $capMiB, $capSec, $capNow, $n, $(if ($use) { '' } else { " (not learned: under 70% of the usual; $lowRun low in a row)" }))
        } catch { }
    }
    Write-Host "`n[ytdl] All workers finished (exit codes: $($codes -join ', '))." -ForegroundColor $color
    if ($final -eq 75) { Write-Host "[ytdl] $(Get-BreakerText (Read-GlobalPace)) Completed videos are kept; re-run the same command after that to resume." -ForegroundColor Yellow }   # 1.25.0
    $fl = @($coordFails.Values)
    Save-FailedList $Url $fl; Show-FailedList $fl
    Send-RunToast $final $fl.Count $(if ($final -in 2, 75) { 'Stopped.' } else { '' })   # 1.18.0
    Release-Lock
    if ($final -notin 2, 75) { $qc = Invoke-QueueDrain; if ($final -eq 0 -and $qc) { $final = $qc } }   # 1.20.0
    Unregister-Run; Restore-Console
    exit $final
}

# Messages that mean "auth/session problem", which is transient and fixed by fresh cookies,
# as opposed to a permanently unavailable video.
$authPattern = 'cookies are no longer valid|Sign in to confirm|not a bot|cookies.*(invalid|expired)'
# Lines that mean a video finished (or was already done), which resets the error-loop counter.
$okPattern   = '^\[(Merger|ExtractAudio|EmbedThumbnail|Metadata)\]|has already been recorded in the archive'

# ---- Shared state + watchdog --------------------------------------------------------------
# The main thread is blocked reading yt-dlp output, so it can't notice a hang (no output) or
# a stop request on its own. A watchdog thread checks every 2 s and kills yt-dlp if needed.
$runState = [hashtable]::Synchronized(@{
    Last = Get-Date; Running = $false; Done = $false; Abort = $null
    StopFile = $stopFile; FolderStop = $folderStop; StallMinutes = $StallMinutes; ParentPid = $PID
    Drive = $drive; MinFreeBytes = [double]($MinFreeGB * 1GB); LastDiskCheck = [datetime]::MinValue
    AutoPace = $autoPace; PaceFile = $paceFile; Level = $paceLevel; LastPaceCheck = [datetime]::MinValue
    BreakerOn = $breakerOn; BreakerFile = $globalPaceFile; LastBreakerCheck = [datetime]::MinValue   # 1.25.0
    # 1.16.0 pause/resume
    PauseFile = $pauseFile; FolderPause = $folderPause; PauseList = $pauseList; ReadKeys = ($Worker -eq 0)
    Paused = $false; PausedAt = $null; PausedSec = 0.0; Suspended = @{}; LastSuspendScan = [datetime]::MinValue
    ProcCs = @'
using System; using System.Runtime.InteropServices;
public static class YtdlProc {
    [DllImport("ntdll.dll")] static extern int NtSuspendProcess(IntPtr h);
    [DllImport("ntdll.dll")] static extern int NtResumeProcess(IntPtr h);
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(int access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    public static bool Set(int pid, bool suspend) {
        IntPtr h = OpenProcess(0x0800, false, pid);   // PROCESS_SUSPEND_RESUME
        if (h == IntPtr.Zero) return false;
        try { return (suspend ? NtSuspendProcess(h) : NtResumeProcess(h)) == 0; } finally { CloseHandle(h); }
    }
}
'@
})
# 1.16.0: the paused time since a video started; a video paused part-way says nothing about speed.
function Test-PausedDuring { $runState -and ($runState.Paused -or [double]$runState.PausedSec -ne [double]$eta.CurPauseMark) }

$killTree = {
    param($parentPid)
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$parentPid" -ErrorAction SilentlyContinue |
        Where-Object Name -like 'yt-dlp*' |
        ForEach-Object { & taskkill.exe /T /F /PID $_.ProcessId 2>&1 | Out-Null }
}

# Background runspace (works in both Windows PowerShell 5.1 and PowerShell 7; Start-ThreadJob
# is 7-only). Same process, so the watchdog's notion of $PID matches ours.
$watchdog = [powershell]::Create()
[void]$watchdog.AddScript({
    param($s, $killTreeText)
    $kill = [scriptblock]::Create($killTreeText)
    # 1.16.0 pause: messages go straight to the console (this thread has no host). Workers' consoles are
    # their log files, so the coordinator shows their lines as usual.
    function Say([string]$t, [ConsoleColor]$c) { try { if ($s.ReadKeys) { [Console]::Write("`r" + (' ' * ([math]::Max(40, [Console]::WindowWidth) - 1)) + "`r") }; $o = [Console]::ForegroundColor; [Console]::ForegroundColor = $c; [Console]::WriteLine($t); [Console]::ForegroundColor = $o } catch { } }
    # Suspend every process under this run except other PowerShell processes (parallel workers have
    # their own watchdog), or resume the ones suspended. Re-scanned while paused, so a yt-dlp started
    # during the pause (a restart) is caught too.
    $setTree = {
        param($s, [bool]$suspend)
        if (-not ('YtdlProc' -as [type])) { Add-Type -TypeDefinition $s.ProcCs }
        if (-not $suspend) { foreach ($id in @($s.Suspended.Keys)) { [void][YtdlProc]::Set([int]$id, $false) }; $s.Suspended.Clear(); return }
        $kids = @{}
        foreach ($p in @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, Name -ErrorAction SilentlyContinue)) {
            $pp = [int]$p.ParentProcessId; if (-not $kids.ContainsKey($pp)) { $kids[$pp] = New-Object System.Collections.ArrayList }; [void]$kids[$pp].Add($p)
        }
        $todo = New-Object System.Collections.Stack; $todo.Push([int]$s.ParentPid)
        while ($todo.Count) {
            $pp = $todo.Pop()
            if (-not $kids.ContainsKey($pp)) { continue }
            foreach ($c in $kids[$pp]) {
                if ($c.Name -match '^(pwsh|powershell|conhost)\.exe$') { continue }
                $id = [int]$c.ProcessId; $todo.Push($id)
                if (-not $s.Suspended.ContainsKey($id) -and [YtdlProc]::Set($id, $true)) { $s.Suspended[$id] = $true }
            }
        }
    }
    while (-not $s.Done) {
        # 1.16.1: 10 x 100 ms, leaving as soon as the run is done. A plain 1 s sleep made every run wait
        # up to 1 s at exit for this thread (benchmark times all ended in .6 s).
        for ($t = 0; $t -lt 10 -and -not $s.Done; $t++) { Start-Sleep -Milliseconds 100 }
        if ($s.Done) { break }
        if ($s.ReadKeys) {
            try {
                while ([Console]::KeyAvailable) {
                    $k = [Console]::ReadKey($true)
                    if ($k.Key -ne 'P' -and $k.Key -ne 'R') { continue }
                    if ((Test-Path $s.FolderPause) -or (Test-Path $s.PauseFile)) { Remove-Item $s.FolderPause, $s.PauseFile -Force -ErrorAction SilentlyContinue }
                    elseif ($k.Key -eq 'P') { New-Item -ItemType File -Force -Path $s.FolderPause | Out-Null; Add-Content -LiteralPath $s.PauseList -Value $s.FolderPause }
                }
            } catch { $s.ReadKeys = $false }   # no console (scheduled task, redirected input)
        }
        if ((Test-Path $s.PauseFile) -or (Test-Path $s.FolderPause)) {
            if ((Test-Path $s.StopFile) -or (Test-Path $s.FolderStop)) {
                if ($s.Running) { $s.Abort = 'stop'; $s.Running = $false; & $kill $s.ParentPid }
                continue
            }
            if (-not $s.Paused) {
                $s.Paused = $true; $s.PausedAt = Get-Date
                Say "[ytdl] Paused. Press P (or R) to resume, or run ytdl -Resume; Ctrl+C stops." Yellow
            }
            if (((Get-Date) - $s.LastSuspendScan).TotalSeconds -ge 5) { $s.LastSuspendScan = Get-Date; try { & $setTree $s $true } catch { } }
            continue
        } elseif ($s.Paused) {
            try { & $setTree $s $false } catch { }
            $s.PausedSec += ((Get-Date) - $s.PausedAt).TotalSeconds
            $s.Paused = $false; $s.Last = Get-Date; $s.LastSuspendScan = [datetime]::MinValue
            Say ("[ytdl] Resumed after {0:N0} s." -f ((Get-Date) - $s.PausedAt).TotalSeconds) Green
        }
        if (-not $s.Running) { continue }
        if ((Test-Path $s.StopFile) -or (Test-Path $s.FolderStop)) {
            $s.Abort = 'stop'; $s.Running = $false; & $kill $s.ParentPid
        } elseif ($s.StallMinutes -gt 0 -and ((Get-Date) - $s.Last).TotalMinutes -ge $s.StallMinutes) {
            $s.Abort = 'stall'; $s.Running = $false; & $kill $s.ParentPid
        } elseif ($s.MinFreeBytes -gt 0 -and ((Get-Date) - $s.LastDiskCheck).TotalSeconds -ge 20) {
            $s.LastDiskCheck = Get-Date
            $free = try { (New-Object IO.DriveInfo($s.Drive)).AvailableFreeSpace } catch { [double]::MaxValue }
            if ($free -lt $s.MinFreeBytes) { $s.Abort = 'disk'; $s.Running = $false; & $kill $s.ParentPid }
        } elseif ($s.BreakerOn -and ((Get-Date) - $s.LastBreakerCheck).TotalSeconds -ge 10) {
            # 1.25.0: another run or worker on this PC hit a YouTube limit and opened the breaker: stop too.
            $s.LastBreakerCheck = Get-Date
            $until = 0
            try { $until = [long]([IO.File]::ReadAllText($s.BreakerFile) | ConvertFrom-Json).CooldownUntil } catch { }
            if ($until -gt [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) { $s.Abort = 'breaker'; $s.Running = $false; & $kill $s.ParentPid }
        } elseif ($s.AutoPace -and ((Get-Date) - $s.LastPaceCheck).TotalSeconds -ge 10) {
            # R7: another worker (or run) on this folder slowed down after a bot check: follow it.
            $s.LastPaceCheck = Get-Date
            $lvl = -1
            try { $pf = Get-Content $s.PaceFile -Raw -ErrorAction Stop | ConvertFrom-Json; $lvl = [int]$pf.Level } catch { }
            if ($lvl -gt $s.Level) { $s.Abort = 'pacesync'; $s.NewLevel = $lvl; $s.Running = $false; & $kill $s.ParentPid }
        }
    }
}).AddArgument($runState).AddArgument($killTree.ToString())
$watchdogHandle = $watchdog.BeginInvoke()

# Sleep in 1 s steps so a stop request during a wait is honoured promptly.
function Wait-OrStop([int]$seconds) {
    for ($i = 0; $i -lt $seconds; $i++) {
        if (Test-StopRequested) { return $false }
        while (Test-PauseRequested) { if (Test-StopRequested) { return $false }; Start-Sleep -Seconds 1 }   # 1.16.0
        Start-Sleep -Seconds 1
    }
    return -not (Test-StopRequested)
}

# 1.25.0: count one video start against this PC's hourly budget (shared by all runs and workers).
# Over budget: stop and wait until the oldest start leaves the hour. Near it (80%): one level slower.
# 25 clean videos in a row: one level faster again (AIMD), down to the floor.
function Step-Budget {
    $id = $paceIdent
    $g = Update-GlobalPace { param($g, $now) $g["Log$id"] = @($g["Log$id"]) + $now }
    $log = @($g["Log$id"] | Sort-Object); $now = Get-Epoch
    $script:budgetUsed = $log.Count; $script:cleanVids++
    $top = $paceLevels.Count - 1
    if ($log.Count -gt $budgetMax) {
        $script:budgetWait = [int][math]::Max(5, [math]::Ceiling($log[$log.Count - $budgetMax] + 3600 - $now + 5))
        $runState.Abort = 'budget'; $runState.Running = $false; & $killTree $PID
    } elseif ($autoPace -and $log.Count -ge [math]::Ceiling(0.8 * $budgetMax) -and -not $script:budgetStepped -and $script:paceLevel -lt $top) {
        $script:budgetStepped = $true; $script:budgetWait = 0
        $runState.Abort = 'budget'; $runState.Running = $false; & $killTree $PID
    } elseif ($autoPace -and $script:cleanVids -ge $decayVideos -and $script:paceLevel -gt $paceFloor) {
        $runState.Abort = 'decay'; $runState.Running = $false; & $killTree $PID
    }
}

# Run yt-dlp once, echoing its output live while scanning it for auth errors and error loops.
function Invoke-Pass([string[]]$passArgs) {
    $script:authHit = $false
    $script:rateHit = $false
    $script:thumbFail = $false
    $script:frag404 = 0
    $script:frag403 = 0
    $script:consecErrors = 0
    $runState.Abort = $null; $runState.Last = Get-Date; $runState.Running = $true
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'   # stderr lines must not terminate
    try {
        & $ytdlp @passArgs 2>&1 | ForEach-Object {
            $runState.Last = Get-Date
            $line = "$_"
            if ($testBot -gt 0 -and -not $script:testBotFired -and $line -match '^\[download\]\s+[\d.]+% of') {   # 1.17.1 test hook
                if (Test-Path $testBotFlag) { $script:testBotFired = $true }
                elseif (++$script:testBotN -ge $testBot) {
                    $script:testBotFired = $true; New-Item -ItemType File -Force $testBotFlag | Out-Null
                    $line = "ERROR: [youtube] $($eta.Cur): Sign in to confirm you're not a bot. Use --cookies-from-browser or --cookies for the authentication. [simulated by YTDL_TEST_BOTCHECK]"
                }
            }
            if ($script:bgScan) { Merge-BgScan }

            # ETA bookkeeping: a new video id starting means the previous one is finished;
            # progress and "100% of X in hh:mm:ss" lines feed the live bandwidth measurement.
            if ($eta.Queue) {
                if ($line -match '^\[youtube\] ([\w-]{11}): Downloading webpage') {
                    $newId = $Matches[1]
                    if ($newId -ne $eta.Cur) { Complete-Current; Start-Video $newId }
                } elseif ($line -match '^\[download\] ([\w-]{11}): .*already been recorded') {
                    [void]$eta.Pending.Remove($Matches[1])
                } elseif ($line -match '^\[download\]\s+100% of\s+~?\s*([\d.]+)(KiB|MiB|GiB) in (\d+):(\d+):(\d+)(?:\s+at\s+~?\s*([\d.]+)(B|KiB|MiB|GiB)/s)?') {
                    $mib = ConvertTo-MiB ([double]::Parse($Matches[1], $ci)) $Matches[2]
                    $hms = [int]$Matches[3] * 3600 + [int]$Matches[4] * 60 + [int]$Matches[5]
                    Add-Transfer $mib (Get-XferSec $mib $hms $Matches[6] $Matches[7])
                } elseif ($line -match '^\[download\]\s+([\d.]+)% of\s+~?\s*([\d.]+)(KiB|MiB|GiB)') {
                    Update-Partial ([double]::Parse($Matches[1], $ci)) (ConvertTo-MiB ([double]::Parse($Matches[2], $ci)) $Matches[3])
                }
            }
            # 1.17.0: with the progress bar up, yt-dlp's own percentage lines go to the log only (the bar
            # shows the run's total instead); the "100% of" line that ends each stream still prints.
            if ($script:barOn -and $line -match '^\[download\]\s+[\d.]+% of' -and $line -notmatch '^\[download\]\s+100% of') {
                Write-LogOnly $line; Update-Bar; return
            }
            # Harmless: yt-dlp skips DRM-protected formats from one of its clients and uses the
            # regular formats instead. It's never counted as an error; keep it out of the console.
            if ($line -match 'formats have been skipped as they are DRM protected') { Write-LogOnly $line; return }
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $color = if ($line -match '^ERROR') { 'Red' } elseif ($line -match '^WARNING') { 'Yellow' } else { 'Gray' }
                Write-Host $line -ForegroundColor $color
            } else {
                Write-Host $line
            }
            # 1.16.0: the last error per video, for the failed-videos list
            if ($line -match '^\[youtube\] ([\w-]{11}): ') { $script:curVid = $Matches[1] }
            if ($line -match '^ERROR: (?:\[[^\]]+\] )?([\w-]{11}): (.+)$') { $failInfo[$Matches[1]] = $Matches[2] }
            elseif ($line -match '^ERROR: (.+)$' -and $script:curVid) { $failInfo[$script:curVid] = $Matches[1] }
            if ($line -match $authPattern) { $script:authHit = $true }
            if ($line -match '^ERROR' -and $line -match $transientPattern) { $script:rateHit = $true }
            if (($script:thumbPlugin -or $script:formatsPlugin) -and $line -match $helperFailPattern) { $script:thumbFail = $true }

            # S1: a bot check or rate limit means we're going too fast. Stop now and restart one
            # pacing level slower, before the rest of the list gets refused too.
            # 1.4.0: under the fast client, an embedding/age/format error means this video needs the
            # default clients. Restart with them (not counted as a pass).
            if ($script:fastClient -and -not $runState.Abort -and $line -match '^ERROR' -and $line -match $clientFallbackPattern -and $line -notmatch $transientPattern) {
                $runState.Abort = 'client'; $runState.Running = $false
                & $killTree $PID
            }
            # 1.25.0: every limit signal is handled, at any level and with fixed pacing too (the pass loop
            # decides: slower, or the breaker). A subtitle 429 is the stricter caption limit: slow captions only.
            if (-not $runState.Abort -and $line -match $limitPattern -and $line -notmatch $limitSkipPattern) {
                if ($line -match $limit429Pattern -and $line -match 'subtitle') {
                    if (-not $script:subSlow) {
                        $script:subSlow = $true
                        Write-Host "[ytdl] YouTube is limiting caption downloads; captions now wait 10 s each (videos are not slowed). -SubLangs en-orig avoids the stricter limit on translated captions." -ForegroundColor Yellow
                    }
                } else {
                    $script:paceWas429 = ($line -match $limit429Pattern)
                    $script:paceSim = ($line -match 'simulated by YTDL_TEST_BOTCHECK')
                    $runState.Abort = 'pace'; $runState.Running = $false
                    & $killTree $PID
                }
            }
            # 1.25.0: a new video starting counts against the hourly budget
            if ($line -match '^\[youtube\] ([\w-]{11}): Downloading webpage' -and $Matches[1] -ne $script:budgetLastId) {
                $script:budgetLastId = $Matches[1]
                if (-not $runState.Abort) { Step-Budget }
            }
            # 1.25.0: "Video unavailable" again and again while signed in can mean the account is flagged
            if (($Browser -or $Cookies) -and $line -match '^ERROR.*Video unavailable' -and ++$script:unavailN -eq 3) {
                Write-Host "[ytdl] 3 videos were 'unavailable' while signed in. If they play in a browser, YouTube may be limiting this account: try the same command without -Browser/-Cookies." -ForegroundColor Yellow
            }

            # Rotated cookies: everything after this would run signed-out and get skipped, so stop
            # now (same effect as Ctrl+C; partial files are kept) and let the main loop restart.
            if ($Browser -and $CookieRestarts -gt 0 -and -not $runState.Abort -and
                $line -match 'cookies are no longer valid') {
                $runState.Abort = 'cookies'; $runState.Running = $false
                & $killTree $PID
            }

            # Fragment 404 loop: the stream URLs have expired or the fragmented format is being
            # withdrawn. Retrying the same URL can't help; a fresh yt-dlp run gets new URLs and
            # resumes the .part. The count resets per video, so one bad video can't trigger it.
            if ($line -match '^\[youtube\] [\w-]{11}: Downloading webpage') { $script:frag404 = 0 }
            if ($line -match 'HTTP Error 404.*fragment|fragment.*HTTP Error 404') {
                $script:frag404++
                if ($FragmentRestarts -gt 0 -and $script:fragCount -lt $FragmentRestarts -and
                    $script:frag404 -ge 3 -and -not $runState.Abort) {
                    $runState.Abort = 'fragments'; $runState.Running = $false
                    & $killTree $PID
                }
            }

            # 1.12.0: YouTube refusing the parallel pieces: 3 refusals (each piece retries up to 10 times
            # otherwise) restart the run with one piece at a time.
            if ($script:fragOn -and -not $runState.Abort -and $line -match 'HTTP Error 403.*fragment|fragment \d+ not found') {
                $script:frag403++
                if ($script:frag403 -ge 3) { $runState.Abort = 'nofrag'; $runState.Running = $false; & $killTree $PID }
            }

            if ($line -match '^ERROR') {
                $script:consecErrors++
                if ($MaxErrors -gt 0 -and $script:consecErrors -ge $MaxErrors -and -not $runState.Abort) {
                    $runState.Abort = 'errorloop'; $runState.Running = $false
                    & $killTree $PID
                }
            } elseif ($line -match $okPattern) {
                $script:consecErrors = 0
            }
        }
    } finally {
        $passCode = $LASTEXITCODE
        $runState.Running = $false
        $ErrorActionPreference = $eap
        Complete-Current   # account for the last video of the pass
    }
    return $passCode
}

# ---- background size probe (S3) -----------------------------------------------------------
# Above 480p, file size per minute varies a lot (4K vs 1080p), so runtime-based estimates can be
# far off. A background runspace looks up each pending video's exact size, in download order,
# while downloads run; Get-X uses a size as soon as it's known. That is -Precise accuracy without
# its up-front wait. Its yt-dlp children are killed with everything else on stop/restart.
$probeSync = [hashtable]::Synchronized(@{ Done = $false; Probed = 0; Failed = 0 })
$prober = $null; $proberHandle = $null
if (-not $NoProbe -and -not $Precise -and -not $lowRes -and $eta.Queue -and $eta.Pending.Count -ge 2) {
    $probeIds = @($eta.Queue.Keys | Where-Object { $eta.Pending.Contains($_) })
    $probeArgs = @('--ignore-errors', '--no-warnings', '--sleep-requests', [string](Get-PaceReq), '-f', $fmt,
                   '--print', '%(id)s %(filesize,filesize_approx)s') + $authArgs + (Get-ClientArgs) + (Get-HelperArgs)
    $prober = [powershell]::Create()
    [void]$prober.AddScript({
        param($ps, $sizes, $ids, $exe, $pargs, $gap)
        # 1.6.0: 10 videos per yt-dlp call. One call per video re-read the browser cookies and
        # restarted yt-dlp every time; a real 234-video run's probe only finished as the run ended.
        $todo = @($ids | Where-Object { -not $sizes.ContainsKey($_) })
        for ($b = 0; $b -lt $todo.Count -and -not $ps.Done; $b += 10) {
            $batch = @($todo[$b..([math]::Min($b + 10, $todo.Count) - 1)])
            $out = & $exe @pargs @($batch | ForEach-Object { "https://www.youtube.com/watch?v=$_" }) 2>$null
            $found = @{}
            foreach ($l in $out) { $q = "$l".Trim() -split ' '; if ($q.Count -ge 2 -and $q[0] -match '^[\w-]{11}$' -and $q[1] -match '^\d+$') { $sizes[$q[0]] = [double]$q[1] / 1MB; $found[$q[0]] = $true } }
            $ps.Probed += $found.Count; $ps.Failed += ($batch.Count - $found.Count)
            for ($i = 0; $i -lt $gap -and -not $ps.Done; $i++) { Start-Sleep -Seconds 1 }
        }
    }).AddArgument($probeSync).AddArgument($eta.Size).AddArgument($probeIds).AddArgument($ytdlp).AddArgument($probeArgs).AddArgument(0)   # no extra gap: --sleep-requests already paces each probe; a 5 s gap made 6 probes take 3.5 min, too late to help
    $proberHandle = $prober.BeginInvoke()
    Write-LogOnly "[ytdl-event] background size probe started for $($probeIds.Count) video(s)"
}

# ---- Main loop ----------------------------------------------------------------------------
# Clear any stale stop signal. Workers leave it to the coordinator: one worker clearing it
# could hide a -Stop from the others.
if ($Worker -eq 0) { Clear-StopFiles }
# ---- parallel pieces (1.12.0) -----------------------------------------------------------------
# yt-dlp fetches each YouTube file as 10 MiB range requests, one at a time (requests over ~10 MiB
# get throttled to ~100 KiB/s). Fetching 3 of those pieces at once moved one 142 MiB stream at
# 15.8 MiB/s against 10.1 (5 runs each, 12.2 s vs 17.1 s). The format helper turns formats of known
# size into such pieces when YTDL_FRAGMENTS=1 (others keep yt-dlp's method), and -N sets how many run
# at once. Default: on only when this run downloads one video at a time; with several workers the
# connection is already full. If YouTube refuses pieces (HTTP 403, seen once in 10 signed-out
# tests), the run restarts with one piece at a time.
# 1.13.0: also with 2 workers. 2-worker runs without pieces got 4.3-9.0 MiB/s per stream (mean 7.2,
# 3 real runs) against 14.8 for one worker with pieces; two streams don't fill the connection.
$fragN = if ($limitBytes -gt 0 -or $Section -or $Live) { 0 } elseif ($Fragments -ge 0) { $Fragments } elseif ($Worker -eq 0 -or $WorkerCount -le 2) { 3 } else { 0 }
function Set-FragMode([bool]$on) {
    $script:fragOn = $on
    if ($on) { $env:YTDL_FRAGMENTS = '1' } else { Remove-Item Env:YTDL_FRAGMENTS -ErrorAction SilentlyContinue }
}
Set-FragMode ($fragN -ge 2 -and $formatsPlugin)
function Get-FragArgs { if ($script:fragOn) { @('-N', [string]$fragN) } else { @() } }

Write-Host "ytdl $YtdlVersion | Downloading to: $Out | pacing $(Get-PaceLabel)$(if ($limitBytes -gt 0 -and $Worker -eq 0) { " | at most $LimitRate/s in total" }) | $(if ($fastClient) { 'fast extraction' } else { 'default clients' })$(if ($thumbPlugin) { ' | thumbnail check' })$(if ($fragOn) { " | $fragN pieces at once" })" -ForegroundColor Cyan
Write-Host "To stop: press Ctrl+C here, or run 'ytdl -Stop' in another terminal. To pause: press P (P again resumes), or ytdl -Pause / -Resume." -ForegroundColor DarkGray
Write-Host "[ytdl] $(Get-PaceStatus)" -ForegroundColor DarkGray   # 1.25.0
$script:barState = { Get-RunBarState }; Update-Bar -Force   # 1.17.0

$totalPasses = 1 + [math]::Max(0, $Retries)
$passArgs    = $ytArgs
$staleFile   = $false
$stopReason  = $null
$code        = 1
$cookieCount = 0        # restarts used for rotated cookies
$fragCount   = 0        # restarts used for fragment 404 loops
$restartNow  = $false   # next loop iteration is a restart (cookies/fragments), not a retry pass
$restartWhy  = ''
$restartWait = 5
$paceWas429  = $false
$failInfo    = @{}      # 1.16.0: video id -> last error message
$curVid      = $null
function Set-PaceLevel([int]$lvl) {
    $script:paceLevel = $lvl; $runState.Level = $lvl
    # Overhead depends on the pauses: start this level's estimate from its own prior and history.
    $script:netKey = "s$(Get-PaceSleep)r$(Get-PaceReq)-p$workersN"
    $eta.OvN = 0.0; $eta.OvSum = 0.0; $eta.FirstOv = $null
    $h = $savedRates["ov-$script:netKey"]
    if ($h -and $h.N -gt 0) { $w = [math]::Min(1.0, $capOvN / [double]$h.N); $eta.OvN = $h.N * $w; $eta.OvSum = $h.Sum * $w }
}

try {
    for ($pass = 1; $pass -le $totalPasses; $pass++) {
        if ($restartNow) {
            $restartNow = $false
            Write-Host "`n=== Restarting $restartWhy (waiting $restartWait s) ===" -ForegroundColor Cyan
            if (-not (Wait-OrStop $restartWait)) { $stopReason = 'Stopped by ytdl -Stop.'; break }
            $restartWait = 5
        } elseif ($pass -gt 1) {
            # Auth failures get a short wait: fresh cookies fix them, and waiting longer gains nothing.
            # 1.18.0: the first retry waits 15 s unless -RetryDelay was given. In benchmark E4 a signed-out
            # round's 2 failed videos cost a flat 60 s wait (58 s slower than the clean rounds), and most
            # failures are passing network errors; bot checks are handled by pacing, not by this wait.
            $wait = if ($authHit) { [math]::Min($RetryDelay, 15) }
                    elseif ($pass -eq 2 -and -not $PSBoundParameters.ContainsKey('RetryDelay')) { [math]::Min($RetryDelay, 15) }
                    else { $RetryDelay }
            Write-Host "`n=== Retry pass $($pass - 1) of $Retries (waiting $wait s) ===" -ForegroundColor Cyan
            if (-not (Wait-OrStop $wait)) { $stopReason = 'Stopped by ytdl -Stop.'; break }
        }

        if ($breakerOn -and (Get-BreakerLeft (Read-GlobalPace)) -gt 0) {   # 1.25.0: opened by another run during the wait
            $stopReason = Get-BreakerText (Read-GlobalPace); $breakerStop = $true; break
        }
        $before = Get-ArchiveCount
        $code   = Invoke-Pass ($passArgs + (Get-PaceArgs) + (Get-ClientArgs) + (Get-HelperArgs) + (Get-FragArgs))
        $added  = (Get-ArchiveCount) - $before

        if ($code -eq 101 -and $breakFilter -and -not $runState.Abort) {
            Write-Host "[ytdl] Reached videos uploaded before $($afterDate.ToString('yyyy-MM-dd')) (-After); stopping there." -ForegroundColor DarkGray
            $code = 0
        }
        if ($code -eq 0 -and -not $runState.Abort) { break }

        if ($thumbFail -and -not $runState.Abort) {
            $thumbPlugin = $false; $formatsPlugin = $false; Set-FragMode $false
            Write-Host "`nyt-dlp couldn't load ytdl's helper plugins (needs a 2025+ yt-dlp); continuing without them (thumbnails are still embedded, just slower)." -ForegroundColor Yellow
            $restartWhy = 'without the helper plugins'; $restartWait = 1; $restartNow = $true; $pass--; continue
        }

        if ($runState.Abort -eq 'nofrag') {
            Set-FragMode $false
            Write-Host "`nYouTube refused the parallel pieces (HTTP 403); continuing with one piece at a time for this run. Partial download is kept." -ForegroundColor Yellow
            $restartWhy = 'with one piece at a time'; $restartWait = 2; $restartNow = $true; $pass--; continue
        }
        if ($runState.Abort -eq 'client') {
            $script:fastClient = $false; Save-ClientFallback
            Write-Host "`nThis video isn't available to the fast extraction client (embedding disabled, age-restricted or missing formats); switching to yt-dlp's default clients for this folder (remembered 7 days)." -ForegroundColor Yellow
            $restartWhy = "with yt-dlp's default clients"; $restartNow = $true; $pass--; continue
        }
        if ($runState.Abort -eq 'pace') {
            # 1.25.0 (AIMD): a 429 moves up 2 levels, a bot check 1. The breaker opens on a 429 (over the
            # budget: a short wait can't fix it), at the slowest level, or on the 2nd trip in 10 min on this PC.
            $top = $paceLevels.Count - 1; $wasTop = $paceLevel -ge $top
            $what = if ($paceWas429) { 'YouTube is rate-limiting' } else { 'YouTube asked to confirm this is not a bot' }
            if ($autoPace) { Set-PaceLevel ([math]::Min($top, $paceLevel + $(if ($paceWas429) { 2 } else { 1 }))); Save-PaceLevel }
            $cleanVids = 0
            Write-LogOnly "[ytdl-event] limit: $(if ($paceWas429) { '429' } else { 'bot' }) at level $paceLevel"
            if ($paceIdent -eq 'Out' -and -not $paceWas429 -and -not $botAdvised) {
                $botAdvised = $true
                Write-Host "`n[ytdl] Signed-out bot checks are about this connection's reputation, which pacing alone may not fix. Signing in usually helps: add -Browser firefox (or chrome, edge)." -ForegroundColor Yellow
            }
            if ($breakerOn -and -not $paceSim) {
                $recent = Add-PaceEvent $(if ($paceWas429) { '429' } else { 'bot' }) $paceLevel
                if ($paceWas429 -or $wasTop -or $recent -ge 2) {
                    Open-Breaker $(if ($paceWas429) { '429' } elseif ($wasTop) { 'max' } else { 'bot' })
                    Write-Host "`n$what; stopped yt-dlp. Partial download is kept." -ForegroundColor Yellow
                    $stopReason = Get-BreakerText (Read-GlobalPace); $breakerStop = $true; break
                }
            } elseif (($wasTop -or -not $autoPace) -and ++$maxTrips -ge 5) {
                $stopReason = "$what at the slowest pacing, 5 times (-IgnoreCooldown). Wait an hour or more before trying again."; break
            }
            Write-Host "`n$what; stopped yt-dlp and slowing down to pacing $(Get-PaceLabel). Partial download is kept." -ForegroundColor Yellow
            Write-Host "[ytdl] $(Get-PaceStatus)" -ForegroundColor DarkGray
            $restartWhy  = "at pacing $(Get-PaceLabel)"
            $restartWait = if ($wasTop -or -not $autoPace) { 60 } elseif ($paceWas429) { 30 * $paceLevel } else { 10 }
            $restartNow  = $true; $pass--; continue
        }
        if ($runState.Abort -eq 'breaker') {
            Write-Host "`nAnother download on this PC hit a YouTube limit; stopping this one too. Partial download is kept." -ForegroundColor Yellow
            $stopReason = Get-BreakerText (Read-GlobalPace); $breakerStop = $true; break
        }
        if ($runState.Abort -eq 'budget') {
            if ($budgetWait -gt 0) {
                Write-Host ("`n[ytdl] Hourly budget reached on this PC: {0} videos started in the last hour (limit {1} {2}). Waiting {3:N0} min, then continuing." -f $budgetUsed, $budgetMax, $(if ($paceIdent -eq 'In') { 'signed in' } else { 'signed out' }), ($budgetWait / 60)) -ForegroundColor Yellow
                $restartWhy = 'after the hourly budget wait'; $restartWait = $budgetWait; $budgetWait = 0
            } else {
                Set-PaceLevel ($paceLevel + 1); Save-PaceLevel
                Write-Host "`n[ytdl] $budgetUsed of $budgetMax videos used this hour on this PC; slowing down to pacing $(Get-PaceLabel) to stay under it." -ForegroundColor Yellow
                Write-Host "[ytdl] $(Get-PaceStatus)" -ForegroundColor DarkGray
                $restartWhy = "at pacing $(Get-PaceLabel)"; $restartWait = 2
            }
            $restartNow = $true; $pass--; continue
        }
        if ($runState.Abort -eq 'decay') {
            Set-PaceLevel ($paceLevel - 1); Save-PaceLevel; $cleanVids = 0
            Write-Host "`n[ytdl] $decayVideos videos in a row without a bot check; speeding up to pacing $(Get-PaceLabel)." -ForegroundColor DarkGray
            Write-Host "[ytdl] $(Get-PaceStatus)" -ForegroundColor DarkGray
            $restartWhy = "at pacing $(Get-PaceLabel)"; $restartWait = 1; $restartNow = $true; $pass--; continue
        }
        if ($runState.Abort -eq 'pacesync') {
            Set-PaceLevel ([math]::Min([int]$runState.NewLevel, $paceLevels.Count - 1))
            Write-Host "`nAnother download in this folder slowed down after a bot check; following it to pacing $(Get-PaceLabel)." -ForegroundColor Yellow
            $restartWhy = "at pacing $(Get-PaceLabel)"; $restartNow = $true; $pass--; continue
        }

        if ($runState.Abort -eq 'fragments') {
            $fragCount++
            Write-Host "`nRepeated HTTP 404 on stream fragments (expired or withdrawn stream URLs); stopped yt-dlp to restart with fresh URLs. Partial download is kept." -ForegroundColor Yellow
            if ($fragCount -ge $FragmentRestarts) { Write-Host "This is the last fragment restart ($FragmentRestarts); after this, yt-dlp's own retries decide, and the video is retried in later passes if it still fails." -ForegroundColor DarkYellow }
            $restartWhy = "with fresh stream URLs ($fragCount of $FragmentRestarts)"
            $restartNow = $true
            $pass--              # a fragment restart doesn't use up a retry pass
            continue
        }

        if ($runState.Abort -eq 'cookies') {
            $cookieCount++
            if ($cookieCount -le $CookieRestarts) {
                Write-Host "`nYouTube rotated the $Browser session cookies; stopped yt-dlp to restart before videos get skipped." -ForegroundColor Yellow
                $restartWhy = "with fresh $Browser cookies ($cookieCount of $CookieRestarts)"
                # 1.7.0: 5 -> 2 s. The browser already holds the rotated cookies; the old wait was 5 of
                # the 12-22 s each restart cost a worker in a real run (3 rotations per 28 min).
                $restartWait = 2
                $restartNow = $true
                $pass--          # a cookie restart doesn't use up a retry pass
                continue
            }
            Write-Host "`nCookies rotated $CookieRestarts times; no more restarts. Close YouTube tabs in $Browser, or wait a while, then re-run." -ForegroundColor Yellow
            $stopReason = "Cookie restart limit ($CookieRestarts) reached."
            break
        }

        switch ($runState.Abort) {
            'stop' {
                $stopReason = 'Stopped by ytdl -Stop.'
            }
            'disk' {
                $stopReason = ('Disk almost full: under {0} GB free on {1}. Free some space, then re-run to resume.' -f $MinFreeGB, $drive)
            }
            'stall' {
                Write-Host "`nNo output from yt-dlp for $StallMinutes min; killed the stuck pass." -ForegroundColor Yellow
            }
            'errorloop' {
                Write-Host "`n$MaxErrors errors in a row with no successful download; stopped this pass." -ForegroundColor Yellow
                if (-not $authHit) { $stopReason = "Error loop ($MaxErrors consecutive errors). Check the errors above." }
            }
        }
        if ($stopReason) { break }

        Write-Host "`nPass $pass finished with errors (exit code $code); $added new video(s) completed this pass." -ForegroundColor Yellow

        if ($authHit) {
            if ($Browser) {
                # Each pass is a new yt-dlp process, which re-reads cookies from the browser,
                # picking up the session the browser rotated to.
                Write-Host "YouTube rejected the session cookies (rotated/expired). Next pass re-reads fresh cookies from $Browser." -ForegroundColor Yellow
                Write-Host "Tip: keep YouTube tabs closed in $Browser while ytdl runs; browsing YouTube there rotates the session." -ForegroundColor DarkYellow
            } elseif ($Cookies -and -not $staleFile) {
                # A cookies.txt can't refresh itself. Drop it so the retry runs signed-out
                # (public videos often still work) instead of failing on stale auth again.
                $staleFile = $true
                $idx = [array]::IndexOf($passArgs, '--cookies')
                $passArgs = @($passArgs[0..($idx - 1)]) + @($passArgs[($idx + 2)..($passArgs.Count - 1)])
                Write-Host "The cookies file is stale. Retrying without it. To fix permanently, re-export cookies (see ytdl-NOTES.md) or use -Browser firefox." -ForegroundColor Yellow
            } else {
                Write-Host "YouTube wants a signed-in session. Re-run with -Browser firefox (signed in to YouTube)." -ForegroundColor Yellow
            }
            continue   # auth problems are transient: don't apply the no-progress stop
        }

        if ($runState.Abort -eq 'stall') { continue }   # hangs are transient: retry without the no-progress stop

        # A retry pass that completes nothing new, with no auth errors, means the remaining
        # failures are persistent (private/removed/blocked), so further passes would just repeat them.
        # 1.22.1: a rate limit seen at the slowest pacing level (pacing can't step down further) is not
        # permanent, but YouTube keeps it for up to an hour, so more passes now would only repeat it.
        if ($pass -gt 1 -and $added -eq 0) {
            if ($rateHit) {
                Write-Host "No progress on this retry: YouTube is still rate-limiting this account (it says for up to an hour). Stopping retries; re-run the same command later to get the rest." -ForegroundColor Yellow
            } else {
                Write-Host "No progress on this retry; remaining errors look permanent. Stopping retries." -ForegroundColor Yellow
            }
            break
        }
    }
} finally {
    # Runs on normal exit and on Ctrl+C: stop the watchdog, make sure yt-dlp isn't left running.
    if ($code -eq 0 -and -not $runState.Abort) { $script:barFinal = $true }   # finished: show 100%
    Close-Bar   # 1.17.0: the final bar stays; the summary prints below it
    $runState.Done = $true
    $probeSync.Done = $true
    if ($bgScan) { try { $bgScan.Stop(); $bgScan.Dispose() } catch { }; $bgScan = $null }
    Save-Rate
    & $killTree $PID
    try { [void]$watchdog.EndInvoke($watchdogHandle) } catch { }   # 1.16.1: exits within ~0.1 s once Done is set
    $watchdog.Dispose()
    if ($prober) {
        & $killTree $PID                                             # any probe still running
        try { $prober.Stop() } catch { }; try { $prober.Dispose() } catch { }
        Write-LogOnly "[ytdl-event] size probe: $($probeSync.Probed) found, $($probeSync.Failed) failed"
    }
    if ($Worker -eq 0) { Clear-StopFiles; Stop-PoServer }   # 1.22.0: Stop-PoServer
}

if ($pass -gt $totalPasses) { $pass = $totalPasses }
# 1.16.0: videos that hit an error and still aren't in the archive
$failed = @()
if ($failInfo.Count) {
    Update-ArchiveSet
    foreach ($id in @($failInfo.Keys)) {
        if (-not (Test-Archived $id -NoRefresh)) { $failed += New-FailItem $id ([string]$queueTitle[$id]) $failInfo[$id] }
    }
}
if ($Worker -gt 0) { foreach ($f in $failed) { Write-Host "[ytdl-fail] $($f.Id)`t$(([string]$f.Title) -replace "`t", ' ')`t$($f.Reason)" } }
elseif (-not $Estimate) { Save-FailedList $Url $failed; Show-FailedList $failed }
$finalMsg = if ($breakerStop) { "$stopReason Completed videos are kept; re-run the same command after that to resume." }
            elseif ($stopReason) { "$stopReason Completed videos are kept; re-run the same command to resume." } elseif ($code -eq 0) { 'Done.' }
            elseif ($failed.Count) { "Finished with errors after $pass pass(es); the failed videos are listed above." }
            else { "Finished with errors after $pass pass(es). Check the messages above for the videos that failed; re-running the command retries only those." }

$finalColor = if ($stopReason) { 'Yellow' } elseif ($code -eq 0) { 'Green' } else { 'Yellow' }
Write-Host "`n$finalMsg" -ForegroundColor $finalColor
if ($Worker -eq 0) { Send-RunToast $code $failed.Count $stopReason }   # 1.18.0
Release-Lock
if ($stopReason) { Unregister-Run; Restore-Console; exit $(if ($breakerStop) { 75 } else { 2 }) }
$qc = Invoke-QueueDrain; if ($code -eq 0 -and $qc) { $code = $qc }   # 1.20.0
if ($Worker -eq 0) { Unregister-Run }
Restore-Console
exit $code