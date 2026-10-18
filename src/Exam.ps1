param(
    [Parameter(Mandatory=$true)][ValidateSet('qtext','dumpall','answerall','gotoq','tofirst','pick','solve','next','prev','first','submit','close','status','shot')][string]$Action,
    [string]$Answers = '',
    [string]$Path = ''
)
$Work = if ($env:ZHIHUISHU_WORK) { $env:ZHIHUISHU_WORK } elseif ($PSScriptRoot) { Join-Path (Split-Path -Parent $PSScriptRoot) 'work' } else { Join-Path (Get-Location) 'work' }
if (-not (Test-Path $Work)) { New-Item -ItemType Directory -Force $Work | Out-Null }
$CoreScript = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'Core.ps1' } else { Join-Path $env:ZHIHUISHU_SRC 'Core.ps1' }
. ([scriptblock]::Create((Get-Content -Raw $CoreScript)))
if (-not $Path) { $Path = Join-Path $Work 'shots\exam.png' }

function Q-Text {
    $t = Get-PageText 0
    $lines = ($t -split "`r?`n") | Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^\uFFFC$' }
    $out = New-Object System.Collections.ArrayList
    $started = $false
    foreach ($l in $lines) {
        if ($l -match '^\d+、') { $started = $true }
        if ($started) {
            [void]$out.Add($l)
            if ($l -match '^[A-D]\.$') { }
        }
        if ($started -and $l -match '^下一题$') { break }
    }
    return ($out -join "`n")
}

switch ($Action) {
    'qtext' { Q-Text }
    'dumpall' {
        $seen = @()
        for ($i = 0; $i -lt 12; $i++) {
            $txt = Q-Text
            if ($seen -contains $txt) { break }
            $seen += $txt
            "###### PAGE $($i+1) ######"
            $txt
            $n = Find-All '下一题'
            if ($n.Count -eq 0) { break }
            Click-El $n[0] | Out-Null
            Start-Sleep -Milliseconds 700
        }
    }
    'first' {
        for ($i = 0; $i -lt 10; $i++) {
            $p = Find-All '上一题'
            if ($p.Count -eq 0) { break }
            if (-not $p[0].Current.IsEnabled) { break }
            Click-El $p[0] | Out-Null
            Start-Sleep -Milliseconds 400
        }
        'AT FIRST'
    }
    'answerall' {
        $ansList = New-Object System.Collections.ArrayList
        foreach ($chr in "$Answers".ToCharArray()) { if ("$chr" -match '[A-Da-d]') { [void]$ansList.Add("$chr".ToUpper()) } }
        $idx = 0
        foreach ($ch in $ansList) {
            $win = Get-Win
            $radios = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::RadioButton)))
            $target = $null
            for ($i = 0; $i -lt $radios.Count; $i++) {
                if ($radios[$i].Current.Name -like "$ch.*" -and -not $radios[$i].Current.IsOffscreen) { $target = $radios[$i]; break }
            }
            if ($target) {
                Click-El $target | Out-Null
                "Q$($idx+1) -> $ch : " + $target.Current.Name
            } else { "Q$($idx+1) -> $ch : NOT FOUND" }
            $idx++
            $n = Find-All '下一题'
            if ($n.Count -gt 0 -and $idx -lt $ansList.Count) { Click-El $n[0] | Out-Null; Start-Sleep -Milliseconds 500 }
        }
        "ANSWERED $idx"
    }
    'tofirst' {
        for ($i = 0; $i -lt 8; $i++) {
            $t = Q-Text
            if ($t -match '^1、') { return "AT Q1" }
            $p = Find-All '上一题'
            if ($p.Count -eq 0) { break }
            Click-El $p[0] | Out-Null
            Start-Sleep -Milliseconds 600
        }
        $t = Q-Text
        if ($t -match '^1、') { "AT Q1" } else { "NOT AT Q1: " + ($t -split "`n")[0] }
    }
    'gotoq' {
        $win = Get-Win
        $c = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, "$Answers")
        $els = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $c)
        $target = $null
        for ($i = 0; $i -lt $els.Count; $i++) {
            if ($els[$i].Current.ControlType -eq [System.Windows.Automation.ControlType]::Text -and $els[$i].Current.BoundingRectangle.X -gt 1800) { $target = $els[$i]; break }
        }
        if ($target) { $how = Click-El $target; "GOTO Q$($Answers) via $how" } else { "Q NUM NOT FOUND" }
    }
    'pick' {
        $picked = @()
        foreach ($ch in $Answers.ToCharArray()) {
            if ($ch -notmatch '[A-D]') { continue }
            $win = Get-Win
            $c = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, "$ch.")
            $radios = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::RadioButton)))
            $target = $null
            for ($i = 0; $i -lt $radios.Count; $i++) {
                if ($radios[$i].Current.Name -like "$ch.*" -and -not $radios[$i].Current.IsOffscreen) { $target = $radios[$i]; break }
            }
            if ($target) {
                $how = Click-El $target
                $picked += "$ch($how): " + $target.Current.Name
            } else { $picked += "${ch}: NOT FOUND" }
        }
        $picked -join "`n"
    }
    'solve' {
        # go to first question
        for ($i = 0; $i -lt 8; $i++) {
            $t = Q-Text
            if ($t -match '^1、') { break }
            $p = Find-All '上一题'
            if ($p.Count -eq 0) { break }
            Click-El $p[0] | Out-Null
            Start-Sleep -Milliseconds 500
        }
        $ansList = New-Object System.Collections.ArrayList
        foreach ($chr in "$Answers".ToCharArray()) { if ("$chr" -match '[A-Da-d]') { [void]$ansList.Add("$chr".ToUpper()) } }
        $idx = 0
        foreach ($ch in $ansList) {
            $head = (Q-Text -split "`n")[0]
            $win = Get-Win
            $radios = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::RadioButton)))
            $target = $null
            for ($i = 0; $i -lt $radios.Count; $i++) {
                if ($radios[$i].Current.Name -like "$ch.*" -and -not $radios[$i].Current.IsOffscreen) { $target = $radios[$i]; break }
            }
            if ($target) { Click-El $target | Out-Null; "Q$($idx+1) [$head] -> $ch OK" } else { "Q$($idx+1) [$head] -> $ch MISSING" }
            $idx++
            $n = Find-All '下一题'
            if ($n.Count -gt 0 -and $idx -lt $ansList.Count) { Click-El $n[0] | Out-Null; Start-Sleep -Milliseconds 450 }
        }
        Start-Sleep -Milliseconds 300
        $s = Find-All '提交'
        if ($s.Count -gt 0) { Click-El $s[0] | Out-Null; 'SUBMITTED' } else { 'NO SUBMIT' }
    }
    'next' { $b = Find-All '下一题'; if ($b.Count -eq 0) { 'NO NEXT' } else { Click-El $b[0] | Out-Null; 'NEXT OK' } }
    'prev' { $b = Find-All '上一题'; if ($b.Count -eq 0) { 'NO PREV' } else { Click-El $b[0] | Out-Null; 'PREV OK' } }
    'submit' {
        $b = Find-All '提交'
        if ($b.Count -eq 0) { 'NO SUBMIT' } else { $how = Click-El $b[0]; "SUBMIT via $how" }
    }
    'close' {
        $b = Find-All '关闭'
        if ($b.Count -gt 0) { Click-El $b[0] | Out-Null; 'CLOSED' } else { 'NO CLOSE BTN' }
    }
    'status' {
        $t = Get-PageText 0
        "LEN=" + $t.Length
        if ($t -match '答题卡') { 'MODE=exam' }
        elseif ($t -match '掌握度热力图') { 'MODE=mastery' }
        else { 'MODE=unknown' }
    }
    'shot' { Save-Shot $Path }
}







