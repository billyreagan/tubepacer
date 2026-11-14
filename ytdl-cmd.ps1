# ytdl launcher shim for Command Prompt (1.20.1). ytdl.cmd runs this instead of ytdl.ps1 directly.
# Why: pwsh -File binds arguments itself before ytdl sees them, and reads any argument that starts with "-"
# and contains ":" (e.g. -YtdlpArgs "--proxy http://host:8080") as "-Name:value", splitting it and losing
# the ":". So this script takes the raw command line Windows passed, splits it with Windows' own rules
# (the ones CommandLineToArgvW uses), and binds it to ytdl.ps1's real parameters: a value after an option
# that takes one is always taken word for word. Then it runs ytdl.ps1 in this same process.
$ytdl = Join-Path $PSScriptRoot 'ytdl.ps1'

function Split-CommandLine([string]$s) {
    # Windows argv rules: spaces/tabs separate outside quotes; 2n backslashes + quote -> n backslashes and the
    # quote toggles quoting; 2n+1 backslashes + quote -> n backslashes and a literal quote; other backslashes
    # are literal; inside quotes, "" is a literal quote.
    $out = New-Object System.Collections.Generic.List[string]
    $sb = New-Object System.Text.StringBuilder; $inQ = $false; $have = $false; $i = 0
    while ($i -lt $s.Length) {
        $c = $s[$i]
        if ($c -eq '\') {
            $n = 0; while ($i -lt $s.Length -and $s[$i] -eq '\') { $n++; $i++ }
            if ($i -lt $s.Length -and $s[$i] -eq '"') {
                [void]$sb.Append('\', [int][math]::Floor($n / 2)); $have = $true
                if ($n % 2 -eq 1) { [void]$sb.Append('"'); $i++ }
            } else { [void]$sb.Append('\', $n); $have = $true }
            continue
        }
        if ($c -eq '"') {
            if ($inQ -and $i + 1 -lt $s.Length -and $s[$i + 1] -eq '"') { [void]$sb.Append('"'); $i += 2; continue }
            $inQ = -not $inQ; $have = $true; $i++; continue
        }
        if (-not $inQ -and ($c -eq ' ' -or $c -eq "`t")) {
            if ($have) { $out.Add($sb.ToString()); [void]$sb.Clear(); $have = $false }
            $i++; continue
        }
        [void]$sb.Append($c); $have = $true; $i++
    }
    if ($have) { $out.Add($sb.ToString()) }
    , $out.ToArray()
}

# Everything after this script's own path on the command line
$all = Split-CommandLine ([Environment]::CommandLine)
$me = [IO.Path]::GetFullPath($PSCommandPath)
$start = -1
for ($k = 0; $k -lt $all.Count; $k++) { try { if ([IO.Path]::GetFullPath($all[$k]) -ieq $me) { $start = $k + 1; break } } catch { } }
$toks = @(if ($start -ge 0) { $all | Select-Object -Skip $start } else { $args | ForEach-Object { "$_" } })   # @(): one token stays a list

# Bind to ytdl.ps1's parameters (names, aliases, unique prefixes, as PowerShell would)
$params = (Get-Command $ytdl).Parameters
$names = @{}
foreach ($p in $params.Values) {
    if ($p.Name -in [System.Management.Automation.PSCmdlet]::CommonParameters) { continue }
    $names[$p.Name.ToLowerInvariant()] = $p.Name; foreach ($al in $p.Aliases) { $names[$al.ToLowerInvariant()] = $p.Name }
}
function Resolve-Param([string]$n) {
    $n = $n.ToLowerInvariant()
    if ($names.ContainsKey($n)) { return $names[$n] }
    $hits = @($names.Keys | Where-Object { $_.StartsWith($n) } | ForEach-Object { $names[$_] } | Select-Object -Unique)
    if ($hits.Count -eq 1) { return $hits[0] }
    if ($hits.Count -gt 1) { Write-Host "ytdl: -$n is ambiguous ($(($hits | ForEach-Object { "-$_" }) -join ', '))." -ForegroundColor Red; exit 1 }
    $null
}
$bind = @{}; $pos = @()
for ($i = 0; $i -lt $toks.Count; $i++) {
    $t = $toks[$i]
    if ($t -match '^-([A-Za-z]\w*)(?::(.*))?$') {
        $pn = Resolve-Param $Matches[1]
        if ($pn) {
            $hasColon = $null -ne $Matches[2] -and $t.Contains(':'); $cv = $Matches[2]
            if ($params[$pn].ParameterType -eq [System.Management.Automation.SwitchParameter]) {
                $bind[$pn] = if ($hasColon) { $cv -notmatch '^(\$?false|0)$' } else { $true }
            } elseif ($hasColon) { $bind[$pn] = $cv }
            elseif ($i + 1 -lt $toks.Count) { $i++; $bind[$pn] = $toks[$i] }
            else { Write-Host "ytdl: -$pn needs a value." -ForegroundColor Red; exit 1 }
            continue
        }
        Write-Host "ytdl: unknown option $t (ytdl -? lists them)." -ForegroundColor Red; exit 1
    }
    $pos += $t
}
if ($pos.Count) { $bind['Url'] = $pos[0] }
if ($pos.Count -gt 1) { Write-Host "ytdl: only one link per run; ignoring: $(($pos | Select-Object -Skip 1) -join ' ')" -ForegroundColor Yellow }
$global:LASTEXITCODE = 0
& $ytdl @bind
exit $LASTEXITCODE
