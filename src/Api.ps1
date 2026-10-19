# Api.ps1 — 面向 Agent 的机器可读 CLI
# 所有动作都可以加 -Json，输出单行 JSON，便于被 harness / 其他 agent 直接解析。
# 退出码：0 成功；2 页面状态不对；3 没有灰色知识点；4 打开知识点失败；5 提交失败。

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('status', 'scan', 'list', 'next', 'submit', 'back')]
    [string]$Action,

    [string]$Answers = '',

    [switch]$Json
)

$Work = if ($env:ZHIHUISHU_WORK) { $env:ZHIHUISHU_WORK } elseif ($PSScriptRoot) { Join-Path (Split-Path -Parent $PSScriptRoot) 'work' } else { Join-Path (Get-Location) 'work' }
if (-not (Test-Path $Work)) { New-Item -ItemType Directory -Force $Work | Out-Null }
$CoreScript = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'Core.ps1' } else { Join-Path $env:ZHIHUISHU_SRC 'Core.ps1' }

. ([scriptblock]::Create((Get-Content -Raw $CoreScript)))
. ([scriptblock]::Create((Get-Content -Raw (Join-Path (Split-Path $CoreScript) 'PageLib.ps1'))))

function Out-Result {
    param($Obj, [int]$Code = 0)
    if ($Json) {
        $Obj | ConvertTo-Json -Depth 8 -Compress
    } else {
        $Obj | Format-List
    }
    exit $Code
}

function Test-MasteryPage {
    if ((Get-PageState) -ne 'mastery') {
        Out-Result @{ ok = $false; error = 'NOT_ON_MASTERY_PAGE'; state = (Get-PageState) } 2
    }
}

try {
    switch ($Action) {
        'status' {
            Out-Result @{
                ok     = $true
                state  = (Get-PageState)
                window = (Get-Win).Current.Name
                pid    = $script:EdgePid
            }
        }

        'scan' {
            Test-MasteryPage
            $s = Get-KpSummary
            $s | Add-Member -NotePropertyName ok -NotePropertyValue $true
            Out-Result $s
        }

        'list' {
            Test-MasteryPage
            Out-Result @{ ok = $true; points = @(Get-KpList) }
        }

        'next' {
            Test-MasteryPage
            $name = Get-NextMissingPoint -DoneFile (Join-Path $Work 'green.txt')
            if (-not $name) { Out-Result @{ ok = $false; error = 'NO_MISSING_POINT' } 3 }

            $open = Open-PointByName $name
            if ($open -ne 'OK') { Out-Result @{ ok = $false; error = $open; point = $name } 4 }

            Set-Content (Join-Path $Work 'current.txt') -Value $name -Encoding UTF8
            $qs = Get-CurrentQuestions
            Out-Result @{ ok = $true; point = $name; questions = @($qs) }
        }

        'submit' {
            if (-not $Answers) { Out-Result @{ ok = $false; error = 'MISSING_ANSWERS' } 5 }
            $tokens = @()
            foreach ($tk in ($Answers -split '\|')) { if ($tk.Trim()) { $tokens += $tk.Trim().ToUpper() } }

            $r = Send-Answers -Tokens $tokens
            if (-not $r) { Out-Result @{ ok = $false; error = 'SUBMIT_FAILED' } 5 }

            $point = ''
            $cf = Join-Path $Work 'current.txt'
            if (Test-Path $cf) { $point = (Get-Content $cf -Raw).Trim() }

            if ($r.score -eq 100 -and $point) {
                $gf = Join-Path $Work 'green.txt'
                $done = @()
                if (Test-Path $gf) { $done = Get-Content $gf -Encoding UTF8 }
                if ($done -notcontains $point) { Add-Content $gf -Value $point -Encoding UTF8 }
            }

            Out-Result @{ ok = $true; point = $point; score = $r.score; correct = $r.correct; total = $r.total; state = (Get-PageState) }
        }

        'back' {
            for ($i = 0; $i -lt 5; $i++) {
                if ((Get-PageState) -eq 'mastery') { break }
                Send-Text '%{LEFT}'
                Start-Sleep -Milliseconds 1300
            }
            $b = Find-All '刷新'
            if ($b.Count -gt 0) { Click-El $b[0] | Out-Null; Start-Sleep -Milliseconds 4500 }
            Out-Result @{ ok = $true; state = (Get-PageState) }
        }
    }
}
catch {
    Out-Result @{ ok = $false; error = $_.Exception.Message } 1
}
