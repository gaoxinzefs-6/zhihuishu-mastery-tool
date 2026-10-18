param(
    [Parameter(Mandatory=$true)][string]$Action,
    [int]$EdgePid = (Get-Process msedge -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle } | Select-Object -First 1).Id,
    [int]$DocIndex = 0,
    [int]$MaxDepth = 4,
    [string]$OutFile = "",
    [int]$MaxNodes = 400
)
$Work = if ($env:ZHIHUISHU_WORK) { $env:ZHIHUISHU_WORK } elseif ($PSScriptRoot) { Join-Path (Split-Path -Parent $PSScriptRoot) 'work' } else { Join-Path (Get-Location) 'work' }
if (-not (Test-Path $Work)) { New-Item -ItemType Directory -Force $Work | Out-Null }
$CoreScript = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'Core.ps1' } else { Join-Path $env:ZHIHUISHU_SRC 'Core.ps1' }

Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes

function Get-EdgeWindow {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $EdgePid)
    $win = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
    if (-not $win) { throw "Edge window not found for pid $EdgePid" }
    return $win
}

function Get-Doc([int]$index) {
    $win = Get-EdgeWindow
    $docCond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Document)
    $docs = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $docCond)
    if ($index -ge $docs.Count) { throw "doc index $index out of range ($($docs.Count))" }
    return $docs[$index]
}

switch ($Action) {
    "text" {
        $doc = Get-Doc $DocIndex
        $tp = $doc.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
        $txt = $tp.DocumentRange.GetText(-1)
        if ($OutFile) { [System.IO.File]::WriteAllText($OutFile, $txt, [System.Text.Encoding]::UTF8) }
        $txt
    }
    "tree" {
        $doc = Get-Doc $DocIndex
        $sb = New-Object System.Text.StringBuilder
        $script:count = 0
        function Walk($el, $depth) {
            if ($script:count -ge $MaxNodes) { return }
            $script:count++
            $name = $el.Current.Name
            $ct = $el.Current.ControlType.ProgrammaticName -replace 'ControlType\.',''
            $r = $el.Current.BoundingRectangle
            if ($name -or $ct -notin @('Pane','Group','Custom')) {
                $line = ("  " * $depth) + "[$ct] '" + ($name -replace "`r?`n",' / ') + "' rect=$([int]$r.X),$([int]$r.Y),$([int]$r.Width)x$([int]$r.Height)"
                [void]$sb.AppendLine($line)
            }
            if ($depth -ge $MaxDepth) { return }
            $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
            $child = $walker.GetFirstChild($el)
            while ($child -and $script:count -lt $MaxNodes) {
                Walk $child ($depth + 1)
                $child = $walker.GetNextSibling($child)
            }
        }
        Walk $doc 0
        $res = $sb.ToString()
        if ($OutFile) { [System.IO.File]::WriteAllText($OutFile, $res, [System.Text.Encoding]::UTF8) }
        $res
    }
}



