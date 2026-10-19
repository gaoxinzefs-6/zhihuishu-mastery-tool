# PageLib.ps1 — 页面级能力库（掌握度页 + 答题页）
# 依赖 Core.ps1 提供的底层函数；本文件只定义函数，不执行动作。

$GreenColor = @{ R = 140; G = 229; B = 162 }   # #8CE5A2 掌握较好
$GrayColor  = @{ R = 204; G = 204; B = 204 }   # #CCCCCC 遗漏点

function Get-PageState {
    $t = Get-PageText 0
    if ($t -match '掌握度热力图') { return 'mastery' }
    if ($t -match '答题卡') { return 'exam' }
    if ($t -match '总题数') { return 'result' }
    return 'unknown'
}

function Get-KpColor {
    param($rect)
    $c1 = Get-PixelColor ([int]($rect.X + 7)) ([int]($rect.Y + $rect.Height / 2))
    $c2 = Get-PixelColor ([int]($rect.X + $rect.Width - 7)) ([int]($rect.Y + $rect.Height / 2))
    $c = $c1
    if ($c1.R -lt 70 -and $c2.R -ge 70) { $c = $c2 }
    if ($c2.R -lt 70 -and $c1.R -ge 70) { $c = $c1 }
    return $c
}

function Get-KpStatus {
    param($c)
    if ($c.G -gt ($c.R + 20) -and $c.G -gt ($c.B + 20)) { return 'mastered' }   # 绿
    if ([Math]::Abs($c.R - 204) -lt 16 -and [Math]::Abs($c.G - 204) -lt 16 -and [Math]::Abs($c.B - 204) -lt 16) { return 'missing' }
    if ($c.R -gt 200 -and $c.G -gt 150 -and $c.B -lt 170) { return 'weak' }      # 黄
    return 'other'
}

function Get-KpList {
    $win = Get-Win
    $wr = $win.Current.BoundingRectangle
    $items = Get-Items
    $res = New-Object System.Collections.ArrayList
    foreach ($it in $items) {
        $r = $it.Current.BoundingRectangle
        if ($r.Width -lt 150 -or $r.Width -gt 200 -or $r.Height -lt 150 -or $r.Height -gt 200) { continue }
        $n = $it.Current.Name
        if (-not $n -or $n -match '%|个$|总数') { continue }
        $visible = $r.Y -gt ($wr.Y + 170) -and ($r.Y + $r.Height) -lt ($wr.Y + $wr.Height - 40)
        if (-not $visible) {
            $res.Add([pscustomobject]@{ name = $n; status = 'hidden'; x = [int]$r.X; y = [int]$r.Y }) | Out-Null
            continue
        }
        $c = Get-KpColor $r
        $res.Add([pscustomobject]@{ name = $n; status = (Get-KpStatus $c); x = [int]$r.X; y = [int]$r.Y }) | Out-Null
    }
    return $res
}

function Get-KpSummary {
    $list = Get-KpList
    [pscustomobject]@{
        total    = $list.Count
        mastered = ($list | Where-Object { $_.status -eq 'mastered' }).Count
        missing  = ($list | Where-Object { $_.status -eq 'missing' }).Count
        weak     = ($list | Where-Object { $_.status -eq 'weak' }).Count
        hidden   = ($list | Where-Object { $_.status -eq 'hidden' }).Count
    }
}

function Open-PointByName {
    param([string]$Name)

    $items = Get-Items
    $el = $null
    foreach ($it in $items) {
        $r = $it.Current.BoundingRectangle
        if ($it.Current.Name -eq $Name -and $r.Width -gt 150 -and $r.Width -lt 200) { $el = $it; break }
    }
    if (-not $el) { return 'ELEMENT NOT FOUND' }

    try { $el.GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern).ScrollIntoView() } catch { }
    Start-Sleep -Milliseconds 900
    [void](Wait-ScrollStable)

    $r = $el.Current.BoundingRectangle
    $wr = (Get-Win).Current.BoundingRectangle
    if (($r.Y + $r.Height) -gt ($wr.Y + $wr.Height - 260)) {
        Scroll-Down 2
        Start-Sleep -Milliseconds 1200
        $r = $el.Current.BoundingRectangle
    }

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
    for ($i = 0; $i -lt 12; $i++) {
        Start-Sleep -Milliseconds 600
        if ((Get-PageText 0) -match '答题卡') { return 'OK' }
    }
    return 'EXAM NOT LOADED'
}

function Get-NextMissingPoint {
    param([string]$DoneFile, [string]$Status = 'missing')

    $done = @()
    if ($DoneFile -and (Test-Path $DoneFile)) { $done = Get-Content $DoneFile -Encoding UTF8 }

    Send-Text '^{HOME}'
    Start-Sleep -Milliseconds 800

    for ($try = 0; $try -lt 12; $try++) {
        [void](Wait-ScrollStable)
        $list = Get-KpList
        $k = $list | Where-Object { $_.status -eq $Status -and ($done -notcontains $_.name) } | Select-Object -First 1
        if ($k) { return $k.name }
        Scroll-Down 3
        Start-Sleep -Milliseconds 1200
    }
    return $null
}

function Get-CurrentQuestions {
    # 回到第 1 题
    for ($i = 0; $i -lt 8; $i++) {
        $t0 = Get-PageText 0
        if ($t0 -match '(?m)^1、') { break }
        $p = Find-All '上一题'
        if ($p.Count -eq 0) { break }
        Click-El $p[0] | Out-Null
        Start-Sleep -Milliseconds 500
    }

    $questions = New-Object System.Collections.ArrayList
    $seen = @()

    for ($page = 0; $page -lt 10; $page++) {
        $t = Get-PageText 0
        $lines = $t -split "`r?`n" | Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^\uFFFC$' }

        $num = $null; $stemLines = @(); $opts = @(); $curKey = $null; $curText = @()
        $inStem = $false
        foreach ($l in $lines) {
            if ($l -match '^(\d+)、') {
                $num = [int]$Matches[1]
                $rest = $l -replace '^\d+、', ''
                if ($rest.Trim()) { $stemLines += $rest.Trim() }
                $inStem = $true
                continue
            }
            if ($l -match '^([A-E])\.$') {
                if ($curKey) { $opts += [pscustomobject]@{ key = $curKey; text = ($curText -join ' ') } }
                $curKey = $Matches[1]; $curText = @()
                $inStem = $false
                continue
            }
            if ($l -eq '对' -or $l -eq '错') {
                if ($curKey) { $opts += [pscustomobject]@{ key = $curKey; text = ($curText -join ' ') } }
                $opts += [pscustomobject]@{ key = $l; text = $l }
                $curKey = $null; $curText = @()
                continue
            }
            if ($l -match '^(上一题|下一题|答题卡|客观题|单选题|多选题|判断题)$') {
                if ($l -eq '下一题') {
                    if ($curKey) { $opts += [pscustomobject]@{ key = $curKey; text = ($curText -join ' ') }; $curKey = $null }
                    break
                }
                continue
            }
            if ($curKey) { $curText += $l }
            elseif ($inStem) { $stemLines += $l }
        }
        if ($curKey) { $opts += [pscustomobject]@{ key = $curKey; text = ($curText -join ' ') }; $curKey = $null }

        $stem = ($stemLines -join ' ').Trim()
        if (-not $stem) { break }
        if ($seen -contains $stem) { break }
        $seen += $stem

        $type = 'single'
        if ($stem -match '哪些|多选') { $type = 'multi' }
        elseif ($opts.Count -gt 0 -and ($opts[0].key -eq '对' -or $opts[0].key -eq '错')) { $type = 'judge' }

        $questions.Add([pscustomobject]@{
            index   = $num
            type    = $type
            stem    = $stem
            options = $opts
        }) | Out-Null

        $n = Find-All '下一题'
        if ($n.Count -eq 0) { break }
        Click-El $n[0] | Out-Null
        Start-Sleep -Milliseconds 650
    }

    return $questions
}

function Send-Answers {
    param([string[]]$Tokens)

    for ($i = 0; $i -lt 8; $i++) {
        if ((Get-PageText 0) -match '(?m)^1、') { break }
        $p = Find-All '上一题'
        if ($p.Count -eq 0) { break }
        Click-El $p[0] | Out-Null
        Start-Sleep -Milliseconds 500
    }

    $i = 0
    foreach ($tk in $Tokens) {
        $win = Get-Win
        $clicked = @()
        if ($tk -in @('T', 'F', 'TRUE', 'FALSE')) {
            $label = if ($tk -like 'T*') { '对' } else { '错' }
            $radios = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants,
                (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::RadioButton)))
            foreach ($r in $radios) { if ($r.Current.Name -eq $label) { Click-El $r | Out-Null; $clicked += $label; break } }
        } elseif ($tk.Length -gt 1) {
            $cks = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants,
                (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::CheckBox)))
            foreach ($ch in $tk.ToCharArray()) {
                foreach ($c in $cks) { if ($c.Current.Name -like "$ch.*") { Click-El $c | Out-Null; $clicked += "$ch"; break } }
            }
        } else {
            $radios = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants,
                (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::RadioButton)))
            foreach ($r in $radios) { if ($r.Current.Name -like "$tk.*" -and -not $r.Current.IsOffscreen) { Click-El $r | Out-Null; $clicked += $tk; break } }
        }
        $i++
        $n = Find-All '下一题'
        if ($n.Count -gt 0 -and $i -lt $Tokens.Count) {
            Click-El $n[0] | Out-Null
            Start-Sleep -Milliseconds 600
        }
    }

    Start-Sleep -Milliseconds 400
    $s = Find-All '提交'
    if ($s.Count -eq 0) { return $null }
    Click-El $s[0] | Out-Null
    Start-Sleep -Milliseconds 2200

    $t = Get-PageText 0
    if ($t -match '答题卡') {
        foreach ($lbl in @('确定', '继续提交')) {
            $b = Find-All $lbl
            if ($b.Count -gt 0) { Click-El $b[0] | Out-Null; Start-Sleep -Milliseconds 1800; break }
        }
        $t = Get-PageText 0
    }
    if ($t -notmatch '总题数') { return $null }

    $score = $null; $total = $null; $correct = $null
    $nums = [regex]::Matches($t, '(?m)^(\d+)%$') | ForEach-Object { [int]$_.Groups[1].Value }
    if ($nums.Count -gt 0) { $score = $nums[0] }
    if ($t -match '(?s)总题数\s*(\d+)') { $total = [int]$Matches[1] }
    if ($t -match '(?s)已答对\s*(\d+)') { $correct = [int]$Matches[1] }

    return [pscustomobject]@{ score = $score; correct = $correct; total = $total }
}



