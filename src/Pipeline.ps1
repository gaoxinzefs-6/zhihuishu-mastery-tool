param(
    [Parameter(Mandatory=$true)][ValidateSet('pull','pull2','pullgray','push2','push3','push','scan','state','dump','analyze','pullname')][string]$Action,
    [string]$Answers = ''
)
$Work = if ($env:ZHIHUISHU_WORK) { $env:ZHIHUISHU_WORK } elseif ($PSScriptRoot) { Join-Path (Split-Path -Parent $PSScriptRoot) 'work' } else { Join-Path (Get-Location) 'work' }
if (-not (Test-Path $Work)) { New-Item -ItemType Directory -Force $Work | Out-Null }
$CoreScript = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'Core.ps1' } else { Join-Path $env:ZHIHUISHU_SRC 'Core.ps1' }
. ([scriptblock]::Create((Get-Content -Raw $CoreScript)))

function Get-Status($p) {
    if ($p.R -lt 0) { return 'hidden' }
    if ($p.G -gt $p.R -and $p.G -gt $p.B -and $p.G -gt 150) { return 'green' }
    if ([Math]::Abs($p.R - $p.G) -lt 12 -and [Math]::Abs($p.G - $p.B) -lt 12) { return 'gray' }
    if ($p.R -gt 200 -and $p.G -gt 150 -and $p.B -lt 150) { return 'yellow' }
    return 'other'
}

function Find-Prefix([string]$prefix) {
    $win = Get-Win
    $c = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text)
    $all = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $c)
    $res = @()
    for ($i = 0; $i -lt $all.Count; $i++) { if ($all[$i].Current.Name -like "$prefix*") { $res += $all[$i].Current.Name } }
    return $res
}

function Get-Kps {
    $items = Get-Items
    $res = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $items.Count; $i++) {
        $it = $items[$i]
        $r = $it.Current.BoundingRectangle
        if ($r.Width -lt 120 -or $r.Width -gt 220 -or $r.Height -lt 120 -or $r.Height -gt 220) { continue }
        $n = $it.Current.Name
        if (-not $n -or $n -match '%|个$|总数') { continue }
        $win = Get-Win
        $wr = $win.Current.BoundingRectangle
        $visible = $r.Y -gt ($wr.Y + 170) -and ($r.Y + $r.Height) -lt ($wr.Y + $wr.Height - 40) -and ($r.X + $r.Width * 0.5) -gt $wr.X -and ($r.X + $r.Width * 0.5) -lt ($wr.X + $wr.Width)
        if (-not $visible) {
            [void]$res.Add([pscustomobject]@{ Name = $n; X = [int]$r.X; Y = [int]$r.Y; W = [int]$r.Width; H = [int]$r.Height; R = -1; G = -1; B = -1 })
            continue
        }
        $c1 = Get-PixelColor ([int]($r.X + 7)) ([int]($r.Y + $r.Height * 0.5))
        $c2 = Get-PixelColor ([int]($r.X + $r.Width - 7)) ([int]($r.Y + $r.Height * 0.5))
        $pick = $c1
        if ($c1.R -lt 70 -and $c2.R -ge 70) { $pick = $c2 }
        if ($c2.R -lt 70 -and $c1.R -ge 70) { $pick = $c1 }
        [void]$res.Add([pscustomobject]@{ Name = $n; X = [int]$r.X; Y = [int]$r.Y; W = [int]$r.Width; H = [int]$r.Height; R = $pick.R; G = $pick.G; B = $pick.B })
    }
    return $res
}

function Open-Kp([string]$name) {
    $items = Get-Items
    $target = $null
    for ($i = 0; $i -lt $items.Count; $i++) {
        $r = $items[$i].Current.BoundingRectangle
        if ($items[$i].Current.Name -eq $name -and $r.Width -gt 120 -and $r.Width -lt 220) { $target = $items[$i]; break }
    }
    if (-not $target) { return 'ITEM NOT FOUND' }
    for ($attempt = 0; $attempt -lt 4; $attempt++) {
        try { $target.GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern).ScrollIntoView(); Start-Sleep -Milliseconds 800 } catch { }
        $r = $target.Current.BoundingRectangle
        Move-Point ([int]($r.X + 60)) ([int]($r.Y + 60))
        Start-Sleep -Milliseconds 350
        Move-Point ([int]($r.X + 95)) ([int]($r.Y + 95))
        Start-Sleep -Milliseconds 800
        $b = Find-All '提升掌握度'
        if ($b.Count -eq 0) { continue }
        $title = Get-TooltipTitle
        if ($title -ne $name) { continue }
        Click-El $b[0] | Out-Null
        return 'OPENED'
    }
    return 'MISMATCH'
}

function Back-Mastery {
    for ($i = 0; $i -lt 4; $i++) {
        $t = Get-PageText 0
        if ($t -match '掌握度热力图') { break }
        Send-Text '%{LEFT}'
        Start-Sleep -Milliseconds 1500
    }
    $t = Get-PageText 0
    if ($t -match '掌握度热力图') {
        $b = Find-All '刷新'
        if ($b.Count -gt 0) { Click-El $b[0] | Out-Null; Start-Sleep -Milliseconds 4000 }
        return 'AT MASTERY'
    }
    return 'NOT MASTERY'
}

function Get-ExamText {
    for ($i = 0; $i -lt 8; $i++) {
        $t0 = Get-PageText 0
        $h = ''
        foreach ($ln in ($t0 -split "`r?`n")) { if ($ln -match '^\d+、') { $h = $ln; break } }
        if ($h -match '^1、') { break }
        $p = Find-All '上一题'
        if ($p.Count -eq 0) { break }
        Click-El $p[0] | Out-Null
        Start-Sleep -Milliseconds 600
    }
    $seen = @()
    $all = New-Object System.Collections.ArrayList
    for ($page = 0; $page -lt 12; $page++) {
        $t = Get-PageText 0
        $lines = ($t -split "`r?`n") | Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^\uFFFC$' }
        $out = New-Object System.Collections.ArrayList
        $started = $false
        foreach ($l in $lines) {
            if ($l -match '^\d+、') { $started = $true; [void]$out.Add($l); continue }
            if ($started) {
                if ($l -match '^上一题$' -or $l -match '^下一题$' -or $l -match '^答题卡$') { break }
                [void]$out.Add($l)
            }
        }
        $txt = ($out -join "`n").Trim()
        if ($seen -contains $txt) { break }
        $seen += $txt
        [void]$all.Add($txt)
        $n = Find-All '下一题'
        if ($n.Count -eq 0) { break }
        Click-El $n[0] | Out-Null
        Start-Sleep -Milliseconds 650
    }
    return ($all -join "`n`n")
}

switch ($Action) {
    'scan' {
        $kps = Get-Kps
        $g = ($kps | Where-Object { (Get-Status $_) -eq 'green' }).Count
        $gr = ($kps | Where-Object { (Get-Status $_) -eq 'gray' }).Count
        "TOTAL=$($kps.Count) GREEN=$g GRAY=$gr"
    }
    'state' {
        $t = Get-PageText 0
        if ($t -match '掌握度热力图') { 'MASTERY' } elseif ($t -match '答题卡') { 'EXAM' } elseif ($t -match '总题数') { 'RESULT' } else { 'UNKNOWN' }
    }
    'pullseq' {
        $win = Get-Win
        [void][Native]::SetForegroundWindow($win.Current.NativeWindowHandle)
        Start-Sleep -Milliseconds 300
        $items = Get-Items
        $cand = @()
        for ($i = 0; $i -lt $items.Count; $i++) {
            $r = $items[$i].Current.BoundingRectangle
            if ($r.Width -gt 150 -and $r.Width -lt 200 -and $r.Height -gt 150 -and $r.Height -lt 200) {
                $n = $items[$i].Current.Name
                if ($n -and $n -notmatch '%|个$|总数') { $cand += $n }
            }
        }
        $idx = 0
        if (Test-Path "$Work\seq.txt") { $idx = [int](Get-Content "$Work\seq.txt" -Raw) }
        if ($idx -ge $cand.Count) { $idx = 0 }
        $name = $cand[$idx]
        $el = $null
        $items2 = Get-Items
        for ($i = 0; $i -lt $items2.Count; $i++) {
            $rr = $items2[$i].Current.BoundingRectangle
            if ($items2[$i].Current.Name -eq $name -and $rr.Width -gt 150 -and $rr.Width -lt 200) { $el = $items2[$i]; break }
        }
        if (-not $el) { 'ELEMENT NOT FOUND'; break }
        try { $el.GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern).ScrollIntoView(); Start-Sleep -Milliseconds 1300 } catch { }
        [void](Wait-ScrollStable)
        $info = $null
        for ($try2 = 0; $try2 -lt 3; $try2++) {
            $items3 = Get-Items
            $el2 = $null
            for ($i = 0; $i -lt $items3.Count; $i++) {
                $rr = $items3[$i].Current.BoundingRectangle
                if ($items3[$i].Current.Name -eq $name -and $rr.Width -gt 150 -and $rr.Width -lt 200) { $el2 = $items3[$i]; break }
            }
            if (-not $el2) { break }
            $rr = $el2.Current.BoundingRectangle
            Move-Point 200 300
            Start-Sleep -Milliseconds 200
            Move-Point ([int]($rr.X + $rr.Width / 2)) ([int]($rr.Y + $rr.Height / 2))
            Start-Sleep -Milliseconds 1100
            $info = Get-TipInfo
            if ($info) { break }
        }
        "POINT: $name (idx=$idx)"
        if (-not $info) { 'NO TOOLTIP'; Set-Content "$Work\seq.txt" -Value ($idx + 1) -Encoding UTF8; break }
        Click-El $info.Btn | Out-Null
        $ok = $false
        for ($i = 0; $i -lt 12; $i++) { Start-Sleep -Milliseconds 700; if ((Get-PageText 0) -match '答题卡') { $ok = $true; break } }
        Set-Content "$Work\current.txt" -Value $name -Encoding UTF8
        Set-Content "$Work\seq.txt" -Value ($idx + 1) -Encoding UTF8
        if (-not $ok) { 'EXAM NOT LOADED'; break }
        $lines = (Get-PageText 0) -split "`r?`n" | Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^\uFFFC$' }
        $ti = -1
        for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^测试题目$') { $ti = $i; break } }
        if ($ti -gt 0) { "EXAMTITLE: " + $lines[$ti - 1] }
        Get-ExamText
    }
    'pull' {
        $name = $null
        for ($try = 0; $try -lt 12; $try++) {
            $kps = Get-Kps
            $k = $kps | Where-Object { (Get-Status $_) -eq 'gray' } | Select-Object -First 1
            if ($k) { $name = $k.Name; break }
            Scroll-Down 4
            Start-Sleep -Milliseconds 600
        }
        if (-not $name) { 'NONE LEFT'; break }
        $o = Open-Kp $name
        "POINT: $name ($o)"
        $ok = $false
        for ($i = 0; $i -lt 12; $i++) {
            Start-Sleep -Milliseconds 700
            $t = Get-PageText 0
            if ($t -match '答题卡') { $ok = $true; break }
        }
        if (-not $ok) { 'EXAM NOT LOADED'; break }
        $lines = (Get-PageText 0) -split "`r?`n" | Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^\uFFFC$' }
        $ti = -1
        for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^测试题目$') { $ti = $i; break } }
        if ($ti -gt 0) { "EXAMTITLE: " + $lines[$ti - 1] }
        Get-ExamText
    }
    'pull2' {
        $win0 = Get-Win
        [void][Native]::SetForegroundWindow($win0.Current.NativeWindowHandle)
        Start-Sleep -Milliseconds 400
        $items = Get-Items
        $cand = @()
        for ($i = 0; $i -lt $items.Count; $i++) {
            $r = $items[$i].Current.BoundingRectangle
            if ($r.Width -gt 150 -and $r.Width -lt 200 -and $r.Height -gt 150 -and $r.Height -lt 200) {
                $n = $items[$i].Current.Name
                if ($n -and $n -notmatch '%|个$|总数') { $cand += [pscustomobject]@{ El = $items[$i]; Name = $n } }
            }
        }
        $start = 0
        if (Test-Path "$Work\cursor.txt") { $start = [int](Get-Content "$Work\cursor.txt" -Raw) }
        if ($start -ge $cand.Count) { $start = 0 }
        $found = $false
        $limit = [Math]::Min($cand.Count, 25)
        for ($k = 0; $k -lt $limit; $k++) {
            $idx = ($start + $k) % $cand.Count
            $c = $cand[$idx]
            try { $c.El.GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern).ScrollIntoView(); Start-Sleep -Milliseconds 300 } catch { }
            $r = $c.El.Current.BoundingRectangle
            if ($r.Y -lt 200 -or $r.Y -gt 1400) { continue }
            Click-Point ([int]($r.X + ($r.Width / 2))) ([int]($r.Y + ($r.Height / 2)))
            Start-Sleep -Milliseconds 500
            $tt = Find-All '提升掌握度'
            if ($tt.Count -eq 0) { continue }
            $pct = $null
            $ptxts = Find-Prefix '掌握度'
            foreach ($pt in $ptxts) { if ($pt -match '(\d+)%') { $pct = [int]$Matches[1]; break } }
            $title = Get-TooltipTitle
            if ($title -ne $c.Name -or $null -eq $pct -or $pct -ne 0) { continue }
            Click-El $tt[0] | Out-Null
            $ok = $false
            for ($i = 0; $i -lt 12; $i++) { Start-Sleep -Milliseconds 700; if ((Get-PageText 0) -match '答题卡') { $ok = $true; break } }
            if (-not $ok) { "POINT: $($c.Name) (OPEN FAILED)"; break }
            $lines = (Get-PageText 0) -split "`r?`n" | Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^\uFFFC$' }
            $ti = -1
            for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^测试题目$') { $ti = $i; break } }
            "POINT: $($c.Name)"
            if ($ti -gt 0) { "EXAMTITLE: " + $lines[$ti - 1] }
            Set-Content "$Work\cursor.txt" -Value $idx -Encoding UTF8
            $found = $true
            Get-ExamText
            break
        }
        if (-not $found) { 'NONE LEFT (all have mastery>0)' }
    }
    'dump' { Get-ExamText }
    'pullname' {
        $o = Open-Kp $Answers
        "POINT: $Answers ($o)"
        $ok = $false
        for ($i = 0; $i -lt 12; $i++) {
            Start-Sleep -Milliseconds 700
            $t = Get-PageText 0
            if ($t -match '答题卡') { $ok = $true; break }
        }
        if (-not $ok) { 'EXAM NOT LOADED'; break }
        Get-ExamText
    }
    'push3' {
        function Q-Head {
            $t = Get-PageText 0
            foreach ($ln in ($t -split "`r?`n")) { if ($ln -match '^\d+、') { return $ln } }
            return ''
        }
        for ($i = 0; $i -lt 8; $i++) {
            if ((Q-Head) -match '^1、') { break }
            $p = Find-All '上一题'
            if ($p.Count -eq 0) { break }
            Click-El $p[0] | Out-Null
            Start-Sleep -Milliseconds 600
        }
        $tokens = @()
        foreach ($tk in ($Answers -split '\|')) { if ($tk.Trim()) { $tokens += $tk.Trim().ToUpper() } }
        $idx = 0
        foreach ($tk in $tokens) {
            $head = Q-Head
            $win = Get-Win
            $clicked = @()
            if ($tk -eq 'T' -or $tk -eq 'F' -or $tk -eq 'TRUE' -or $tk -eq 'FALSE') {
                $label = if ($tk -like 'T*') { '对' } else { '错' }
                $radios = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::RadioButton)))
                for ($j = 0; $j -lt $radios.Count; $j++) {
                    if ($radios[$j].Current.Name -eq $label) { Click-El $radios[$j] | Out-Null; $clicked += $label; break }
                }
            } elseif ($tk.Length -gt 1) {
                $ck = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::CheckBox)))
                foreach ($c in $tk.ToCharArray()) {
                    for ($j = 0; $j -lt $ck.Count; $j++) {
                        if ($ck[$j].Current.Name -like "$c.*") { Click-El $ck[$j] | Out-Null; $clicked += "$c"; break }
                    }
                }
            } else {
                $radios = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::RadioButton)))
                for ($j = 0; $j -lt $radios.Count; $j++) {
                    if ($radios[$j].Current.Name -like "$tk.*" -and -not $radios[$j].Current.IsOffscreen) { Click-El $radios[$j] | Out-Null; $clicked += $tk; break }
                }
            }
            "Q$($idx+1) [$head] -> $tk : clicked $($clicked -join ',')"
            $idx++
            $n = Find-All '下一题'
            if ($n.Count -gt 0 -and $idx -lt $tokens.Count) {
                Click-El $n[0] | Out-Null
                Start-Sleep -Milliseconds 700
                if ((Q-Head) -eq $head) { Click-El $n[0] | Out-Null; Start-Sleep -Milliseconds 700 }
            }
        }
        Start-Sleep -Milliseconds 400
        $s = Find-All '提交'
        if ($s.Count -gt 0) { Click-El $s[0] | Out-Null; 'SUBMITTED' } else { 'NO SUBMIT' }
        Start-Sleep -Milliseconds 2200
        $t = Get-PageText 0
        if ($t -match '答题卡' -or $t -match '未作答') {
            foreach ($lbl in @('确定', '继续提交', '提交')) {
                $b = Find-All $lbl
                if ($b.Count -gt 0) { Click-El $b[0] | Out-Null; 'CONFIRM ' + $lbl; Start-Sleep -Milliseconds 1800; break }
            }
            $t = Get-PageText 0
        }
        if ($t -match '总题数') {
            $nums = @()
            foreach ($m in [regex]::Matches($t, '(?m)^(\d+)%$|^(\d+)$')) {
                if ($m.Groups[1].Success) { $nums += ($m.Groups[1].Value + '%') } else { $nums += $m.Groups[2].Value }
            }
            'RESULT: ' + ($nums -join ',')
            if ($nums[0] -match '^(\d+)%' -and [int]$Matches[1] -eq 100 -and (Test-Path "$Work\current.txt")) { $nm = (Get-Content "$Work\current.txt" -Raw).Trim(); $exist = @(); if (Test-Path "$Work\green.txt") { $exist = Get-Content "$Work\green.txt" -Encoding UTF8 }; if ($exist -notcontains $nm) { Add-Content "$Work\green.txt" -Value $nm -Encoding UTF8 } }
        } else { 'RESULT UNKNOWN' }
        Back-Mastery
    }
    'push2' {
        $letters = New-Object System.Collections.ArrayList
        foreach ($chr in "$Answers".ToCharArray()) { if ("$chr" -match '[A-Da-d]') { [void]$letters.Add("$chr".ToUpper()) } }
        function Q-Head {
            $t = Get-PageText 0
            foreach ($ln in ($t -split "`r?`n")) { if ($ln -match '^\d+、') { return $ln } }
            return ''
        }
        for ($i = 0; $i -lt 8; $i++) {
            if ((Q-Head) -match '^1、') { break }
            $p = Find-All '上一题'
            if ($p.Count -eq 0) { break }
            Click-El $p[0] | Out-Null
            Start-Sleep -Milliseconds 600
        }
        $idx = 0
        foreach ($ch in $letters) {
            $head = Q-Head
            $win = Get-Win
            $radios = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::RadioButton)))
            $target = $null
            for ($j = 0; $j -lt $radios.Count; $j++) {
                if ($radios[$j].Current.Name -like "$ch.*" -and -not $radios[$j].Current.IsOffscreen) { $target = $radios[$j]; break }
            }
            if (-not $target) { "Q$($idx+1) [$head] -> $ch MISS"; break }
            Click-El $target | Out-Null
            Start-Sleep -Milliseconds 250
            $sel = $false
            try { $sel = $target.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected } catch { }
            if (-not $sel) {
                $pt = $target.GetClickablePoint()
                Click-Point ([int]$pt.X) ([int]$pt.Y)
                Start-Sleep -Milliseconds 300
                try { $sel = $target.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected } catch { }
            }
            "Q$($idx+1) [$head] -> $ch : $($target.Current.Name) sel=$sel"
            $idx++
            $n = Find-All '下一题'
            if ($n.Count -gt 0 -and $idx -lt $letters.Count) { Click-El $n[0] | Out-Null; Start-Sleep -Milliseconds 700 }
        }
        Start-Sleep -Milliseconds 400
        $s = Find-All '提交'
        if ($s.Count -gt 0) { Click-El $s[0] | Out-Null; 'SUBMITTED' } else { 'NO SUBMIT' }
        Start-Sleep -Milliseconds 2200
        $t = Get-PageText 0
        if ($t -match '总题数') {
            $nums = @()
            foreach ($m in [regex]::Matches($t, '(?m)^(\d+)%$|^(\d+)$')) {
                if ($m.Groups[1].Success) { $nums += ($m.Groups[1].Value + '%') } else { $nums += $m.Groups[2].Value }
            }
            'RESULT: ' + ($nums -join ',')
            if ($nums[0] -match '^(\d+)%' -and [int]$Matches[1] -eq 100 -and (Test-Path "$Work\current.txt")) { $nm = (Get-Content "$Work\current.txt" -Raw).Trim(); $exist = @(); if (Test-Path "$Work\green.txt") { $exist = Get-Content "$Work\green.txt" -Encoding UTF8 }; if ($exist -notcontains $nm) { Add-Content "$Work\green.txt" -Value $nm -Encoding UTF8 } }
        } else { 'RESULT UNKNOWN' }
        Back-Mastery
    }
    'push' {
        $letters = New-Object System.Collections.ArrayList
        foreach ($chr in "$Answers".ToCharArray()) { if ("$chr" -match '[A-Da-d]') { [void]$letters.Add("$chr".ToUpper()) } }
        for ($i = 0; $i -lt 8; $i++) {
            $t = Get-PageText 0
            if ($t -match '(?m)^1、') { break }
            $p = Find-All '上一题'
            if ($p.Count -eq 0) { break }
            Click-El $p[0] | Out-Null
            Start-Sleep -Milliseconds 500
        }
        $idx = 0
        foreach ($ch in $letters) {
            $win = Get-Win
            $radios = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::RadioButton)))
            $target = $null
            for ($j = 0; $j -lt $radios.Count; $j++) {
                if ($radios[$j].Current.Name -like "$ch.*" -and -not $radios[$j].Current.IsOffscreen) { $target = $radios[$j]; break }
            }
            if ($target) { Click-El $target | Out-Null; "Q$($idx+1) -> $ch OK" } else { "Q$($idx+1) -> $ch MISS" }
            $idx++
            $n = Find-All '下一题'
            if ($n.Count -gt 0 -and $idx -lt $letters.Count) { Click-El $n[0] | Out-Null; Start-Sleep -Milliseconds 500 }
        }
        Start-Sleep -Milliseconds 300
        $s = Find-All '提交'
        if ($s.Count -gt 0) { Click-El $s[0] | Out-Null; 'SUBMITTED' } else { 'NO SUBMIT' }
        Start-Sleep -Milliseconds 2000
        $t = Get-PageText 0
        if ($t -match '总题数') {
            $nums = @()
            foreach ($m in [regex]::Matches($t, '(?m)^(\d+)%$|^(\d+)$')) {
                if ($m.Groups[1].Success) { $nums += ($m.Groups[1].Value + '%') } else { $nums += $m.Groups[2].Value }
            }
            'RESULT: ' + ($nums -join ',')
            if ($nums[0] -match '^(\d+)%' -and [int]$Matches[1] -eq 100 -and (Test-Path "$Work\current.txt")) { $nm = (Get-Content "$Work\current.txt" -Raw).Trim(); $exist = @(); if (Test-Path "$Work\green.txt") { $exist = Get-Content "$Work\green.txt" -Encoding UTF8 }; if ($exist -notcontains $nm) { Add-Content "$Work\green.txt" -Value $nm -Encoding UTF8 } }
        } else { 'RESULT UNKNOWN' }
        Back-Mastery
    }
    'analyze' {
        $letters = New-Object System.Collections.ArrayList
        foreach ($chr in "$Answers".ToCharArray()) { if ("$chr" -match '[A-Da-d]') { [void]$letters.Add("$chr".ToUpper()) } }
        for ($i = 0; $i -lt 8; $i++) {
            $t = Get-PageText 0
            if ($t -match '(?m)^1、') { break }
            $p = Find-All '上一题'
            if ($p.Count -eq 0) { break }
            Click-El $p[0] | Out-Null
            Start-Sleep -Milliseconds 500
        }
        $idx = 0
        foreach ($ch in $letters) {
            $win = Get-Win
            $radios = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::RadioButton)))
            for ($j = 0; $j -lt $radios.Count; $j++) {
                if ($radios[$j].Current.Name -like "$ch.*" -and -not $radios[$j].Current.IsOffscreen) { Click-El $radios[$j] | Out-Null; break }
            }
            $idx++
            $n = Find-All '下一题'
            if ($n.Count -gt 0 -and $idx -lt $letters.Count) { Click-El $n[0] | Out-Null; Start-Sleep -Milliseconds 500 }
        }
        Start-Sleep -Milliseconds 300
        $s = Find-All '提交'
        if ($s.Count -gt 0) { Click-El $s[0] | Out-Null }
        Start-Sleep -Milliseconds 2500
        $b = Find-All '查看作答记录与解析'
        if ($b.Count -gt 0) { Click-El $b[0] | Out-Null; 'ANALYSIS OPENED'; Start-Sleep -Milliseconds 2500; (Get-PageText 0) } else { 'NO ANALYSIS BUTTON' }
    }
}















