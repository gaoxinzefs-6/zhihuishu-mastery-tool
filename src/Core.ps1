$Work = if ($env:ZHIHUISHU_WORK) { $env:ZHIHUISHU_WORK } elseif ($PSScriptRoot) { Join-Path (Split-Path -Parent $PSScriptRoot) 'work' } else { Join-Path (Get-Location) 'work' }
if (-not (Test-Path $Work)) { New-Item -ItemType Directory -Force $Work | Out-Null }
$CoreScript = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'Core.ps1' } else { Join-Path $env:ZHIHUISHU_SRC 'Core.ps1' }
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Native {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, int d, IntPtr e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
"@ -ErrorAction SilentlyContinue
[void][Native]::SetProcessDPIAware()

$script:EdgePid = (Get-Process msedge -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle } | Select-Object -First 1).Id

function Set-EdgePid([int]$pidValue) { $script:EdgePid = $pidValue }

function Get-Win {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $c = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $script:EdgePid)
    $w = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $c)
    if (-not $w) { throw "edge window not found" }
    return $w
}

function Get-Tabs {
    $win = Get-Win
    $tc = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::TabItem)
    return $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tc)
}

function Click-Point([int]$px, [int]$py) {
    [void][Native]::SetCursorPos($px, $py)
    Start-Sleep -Milliseconds 120
    [Native]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [Native]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 200
}

function Move-Point([int]$px, [int]$py) {
    [void][Native]::SetCursorPos($px, $py)
    Start-Sleep -Milliseconds 200
}

function Click-El($el) {
    try { $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep -Milliseconds 300; return 'invoke' } catch {}
    try { $el.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); Start-Sleep -Milliseconds 300; return 'select' } catch {}
    [void][Native]::SetForegroundWindow((Get-Win).Current.NativeWindowHandle)
    try {
        $pt = $el.GetClickablePoint()
        Click-Point ([int]$pt.X) ([int]$pt.Y)
    } catch {
        $r = $el.Current.BoundingRectangle
        if ($r.Width -le 0) { throw 'no clickable point' }
        Click-Point ([int]($r.X + $r.Width / 2)) ([int]($r.Y + $r.Height / 2))
    }
    return 'mouse'
}

function Get-Docs {
    $win = Get-Win
    $dc = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Document)
    return $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $dc)
}

function Get-PageText([int]$index = 0) {
    $docs = Get-Docs
    if ($index -ge $docs.Count) { return '' }
    $tp = $docs[$index].GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
    return $tp.DocumentRange.GetText(-1)
}

function Find-All([string]$name) {
    $win = Get-Win
    $c = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $name)
    return $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $c)
}

function Get-Items {
    $win = Get-Win
    $lc = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem)
    return $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $lc)
}

function Save-Shot([string]$path) {
    $win = Get-Win
    $r = $win.Current.BoundingRectangle
    $bmp = New-Object System.Drawing.Bitmap([int]$r.Width, [int]$r.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen([int]$r.X, [int]$r.Y, 0, 0, $bmp.Size)
    $dir = Split-Path $path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    return $path
}

function Get-PixelColor([int]$screenX, [int]$screenY) {
    $win = Get-Win
    $r = $win.Current.BoundingRectangle
    $bmp = New-Object System.Drawing.Bitmap(1, 1)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($screenX, $screenY, 0, 0, (New-Object System.Drawing.Size(1, 1)))
    $c = $bmp.GetPixel(0, 0)
    $g.Dispose(); $bmp.Dispose()
    return ,$c
}

function Send-Text([string]$text) {
    [void][Native]::SetForegroundWindow((Get-Win).Current.NativeWindowHandle)
    Start-Sleep -Milliseconds 150
    [System.Windows.Forms.SendKeys]::SendWait($text)
}

function Scroll-Down([int]$notches = 3) {
    $win = Get-Win
    $r = $win.Current.BoundingRectangle
    [void][Native]::SetForegroundWindow($win.Current.NativeWindowHandle)
    [void][Native]::SetCursorPos([int]($r.X + 1200), [int]($r.Y + 700))
    Start-Sleep -Milliseconds 100
    for ($i = 0; $i -lt $notches; $i++) { [Native]::mouse_event(0x0800, 0, 0, -120, [IntPtr]::Zero); Start-Sleep -Milliseconds 60 }
    Start-Sleep -Milliseconds 400
}


function Get-TooltipTitle {
    $win = Get-Win
    $c = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text)
    $all = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $c)
    $anchor = $null
    for ($i = 0; $i -lt $all.Count; $i++) {
        if ($all[$i].Current.Name -like '掌握度*') { $anchor = $all[$i]; break }
    }
    if (-not $anchor) { return '' }
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $node = $walker.GetParent($anchor)
    for ($k = 0; $k -lt 3 -and $node; $k++) {
        $names = @()
        $kids = $node.FindAll([System.Windows.Automation.TreeScope]::Descendants, $c)
        for ($i = 0; $i -lt $kids.Count; $i++) {
            $n = $kids[$i].Current.Name
            if ($n -and $n -notlike '掌握度*' -and $n -ne '提升掌握度') { $names += $n }
        }
        if ($names.Count -gt 0) { return $names[0] }
        $node = $walker.GetParent($node)
    }
    return ''
}
function Get-TipInfo {
    $btn = Find-All '提升掌握度'
    if ($btn.Count -eq 0) { return $null }
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $node = $walker.GetParent($btn[0])
    for ($k = 0; $k -lt 3 -and $node; $k++) {
        $c = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text)
        $kids = $node.FindAll([System.Windows.Automation.TreeScope]::Descendants, $c)
        $title = ''
        $pct = -1
        for ($i = 0; $i -lt $kids.Count; $i++) {
            $n = $kids[$i].Current.Name
            if ($n -match '(\d+)\s*%') { $pct = [int]$Matches[1] }
            elseif ($n -and $n -ne '提升掌握度' -and $title -eq '') { $title = $n }
        }
        if ($title -ne '' -or $pct -ge 0) { return [pscustomobject]@{ Title = $title; Pct = $pct; Btn = $btn[0] } }
        $node = $walker.GetParent($node)
    }
    return $null
}
function Get-TipInfo {
    $btn = Find-All '提升掌握度'
    if ($btn.Count -eq 0) { return $null }
    $b = $btn[0].Current.BoundingRectangle
    $win = Get-Win
    $c = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text)
    $kids = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $c)
    $title = ''
    $pct = -1
    $bestY = -999999
    for ($i = 0; $i -lt $kids.Count; $i++) {
        $n = $kids[$i].Current.Name
        $r = $kids[$i].Current.BoundingRectangle
        if ($r.X -lt ($b.X - 460) -or $r.X -gt ($b.X + $b.Width)) { continue }
        if ($r.Y -lt ($b.Y - 130) -or $r.Y -gt ($b.Y + $b.Height)) { continue }
        if ($n -match '(\d+)\s*%') { $pct = [int]$Matches[1]; continue }
        if ($n -and $n -ne '提升掌握度' -and $r.Y -gt $bestY) { $title = $n; $bestY = $r.Y }
    }
    return [pscustomobject]@{ Title = $title; Pct = $pct; Btn = $btn[0] }
}

function Wait-ScrollStable {
    $prev = -1
    $same = 0
    for ($i = 0; $i -lt 16; $i++) {
        $items = Get-Items
        $y = -1
        for ($j = 0; $j -lt $items.Count; $j++) {
            $r = $items[$j].Current.BoundingRectangle
            if ($r.Width -gt 150 -and $r.Width -lt 200) { $y = [int]$r.Y; break }
        }
        if ($y -eq $prev) { $same++ } else { $same = 0 }
        if ($same -ge 2) { return $true }
        $prev = $y
        Start-Sleep -Milliseconds 250
    }
    return $false
}



