param([switch]$Scroll, [switch]$Next, [string]$Name = '')
$Work = if ($env:ZHIHUISHU_WORK) { $env:ZHIHUISHU_WORK } elseif ($PSScriptRoot) { Join-Path (Split-Path -Parent $PSScriptRoot) 'work' } else { Join-Path (Get-Location) 'work' }
if (-not (Test-Path $Work)) { New-Item -ItemType Directory -Force $Work | Out-Null }
$CoreScript = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'Core.ps1' } else { Join-Path $env:ZHIHUISHU_SRC 'Core.ps1' }
. ([scriptblock]::Create((Get-Content -Raw $CoreScript)))

function Is-Green($r) {
    $c = Get-PixelColor ([int]($r.X + 7)) ([int]($r.Y + $r.Height / 2))
    return ($c.G -gt ($c.R + 20) -and $c.G -gt ($c.B + 20))
}

$win = Get-Win
[void][Native]::SetForegroundWindow($win.Current.NativeWindowHandle)
$tabs = Get-Tabs
for ($ti = 0; $ti -lt $tabs.Count; $ti++) {
    $tn = $tabs[$ti].Current.Name
    if ($tn -match '智慧树' -and $tn -notmatch '学生首页') {
        try { $tabs[$ti].GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); Start-Sleep -Milliseconds 400 } catch { }
        break
    }
}
Move-Point 150 250
Start-Sleep -Milliseconds 300

if ($Scroll) { Scroll-Down 3; Start-Sleep -Milliseconds 1200; 'SCROLLED'; exit }

$items = Get-Items
$cand = @()
foreach ($it in $items) {
    $r = $it.Current.BoundingRectangle
    if ($r.Width -lt 150 -or $r.Width -gt 200 -or $r.Height -lt 150 -or $r.Height -gt 200) { continue }
    $n = $it.Current.Name
    if (-not $n -or $n -match '%|个$|总数') { continue }
    $cand += [pscustomobject]@{ El = $it; Name = $n }
}

function Open-ByName([string]$nm) {
    $el = $null
    foreach ($c in $cand) { if ($c.Name -eq $nm) { $el = $c.El; break } }
    if (-not $el) { return 'ELEMENT NOT FOUND' }
    try { $el.GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern).ScrollIntoView(); Start-Sleep -Milliseconds 900 } catch { }
    [void](Wait-ScrollStable)
    $r = $el.Current.BoundingRectangle
    $wr = (Get-Win).Current.BoundingRectangle
    if (($r.Y + $r.Height) -gt ($wr.Y + $wr.Height - 260)) {
        Scroll-Down 2
        Start-Sleep -Milliseconds 1200
        $r = $el.Current.BoundingRectangle
    }
    if (Is-Green $r) { return 'GREEN' }
    Move-Point 200 300
    Start-Sleep -Milliseconds 250
    Click-Point ([int]($r.X + $r.Width / 2)) ([int]($r.Y + $r.Height / 2))
    Start-Sleep -Milliseconds 1100
    $btn = Find-All '提升掌握度'
    if ($btn.Count -eq 0) {
        $r2 = $el.Current.BoundingRectangle
        Click-Point ([int]($r2.X + 30)) ([int]($r2.Y + 30))
        Start-Sleep -Milliseconds 1200
        $btn = Find-All '提升掌握度'
    }
    if ($btn.Count -eq 0) { return 'NO TOOLTIP' }
    Click-El $btn[0] | Out-Null
    for ($i = 0; $i -lt 10; $i++) { Start-Sleep -Milliseconds 600; if ((Get-PageText 0) -match '答题卡') { return 'OPENED' } }
    return 'EXAM NOT LOADED'
}

if ($Next) {
    $idx = 0
    if (Test-Path "$Work\seq.txt") { $idx = [int](Get-Content "$Work\seq.txt" -Raw) }
    if ($idx -ge $cand.Count) { $idx = 0 }
    for ($i = $idx; $i -lt $cand.Count; $i++) {
        $nm = $cand[$i].Name
        $res = Open-ByName $nm
        if ($res -eq 'GREEN') { Set-Content "$Work\seq.txt" -Value ($i + 1) -Encoding UTF8; continue }
        "POINT: $nm (idx=$i, $res)"
        Set-Content "$Work\seq.txt" -Value ($i + 1) -Encoding UTF8
        if ($res -ne 'OPENED') { exit }
        Set-Content "$Work\current.txt" -Value $nm -Encoding UTF8
        break
    }
} elseif ($Name) {
    $res = Open-ByName $Name
    "POINT: $Name ($res)"
    if ($res -ne 'OPENED') { exit }
    Set-Content "$Work\current.txt" -Value $Name -Encoding UTF8
}

# dump pages
$seen = @()
for ($page = 0; $page -lt 10; $page++) {
    $t = Get-PageText 0
    $ls = $t -split "`r?`n" | Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^\uFFFC$' }
    $out = @()
    $started = $false
    foreach ($l in $ls) {
        if ($l -match '^\d+、') { $started = $true; $out += $l; continue }
        if ($started) {
            if ($l -match '^上一题$' -or $l -match '^下一题$' -or $l -match '^答题卡$') { break }
            $out += $l
        }
    }
    $txt = ($out -join "`n").Trim()
    if ($seen -contains $txt) { break }
    $seen += $txt
    $txt
    '---'
    $n = Find-All '下一题'
    if ($n.Count -eq 0) { break }
    Click-El $n[0] | Out-Null
    Start-Sleep -Milliseconds 600
}




