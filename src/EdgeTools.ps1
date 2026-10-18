param(
    [Parameter(Mandatory=$true)][ValidateSet('tabs','selecttab','shot','text','click','find','type','keys','info')][string]$Action,
    [int]$EdgePid = (Get-Process msedge -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle } | Select-Object -First 1).Id,
    [string]$Name = '',
    [string]$Match = '',
    [string]$Path = '',
    [string]$Keys = '',
    [int]$X = -1,
    [int]$Y = -1,
    [switch]$Ctrl
)
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
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string n);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
}
"@
[void][Native]::SetProcessDPIAware()

function Get-Win {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $c = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $EdgePid)
    $w = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $c)
    if (-not $w) { throw "window not found" }
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
    Start-Sleep -Milliseconds 150
}

function Click-El($el) {
    try {
        $ip = $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        $ip.Invoke(); Start-Sleep -Milliseconds 400; return 'invoke'
    } catch {}
    try {
        $p = $el.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
        $p.Select(); Start-Sleep -Milliseconds 400; return 'select'
    } catch {}
    try {
        $pt = $el.GetClickablePoint()
        [void][Native]::SetForegroundWindow((Get-Win).Current.NativeWindowHandle)
        Click-Point ([int]$pt.X) ([int]$pt.Y)
        return 'mouse'
    } catch { throw "cannot click element: $($_.Exception.Message)" }
}

switch ($Action) {
    'info' {
        $win = Get-Win
        $r = $win.Current.BoundingRectangle
        "TITLE=" + $win.Current.Name
        "RECT=$([int]$r.X),$([int]$r.Y) $([int]$r.Width)x$([int]$r.Height)"
        $tabs = Get-Tabs
        for ($i = 0; $i -lt $tabs.Count; $i++) {
            $t = $tabs[$i]
            $sel = $false
            try { $sel = $t.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected } catch {}
            "TAB$i sel=$sel name='" + $t.Current.Name + "'"
        }
    }
    'tabs' {
        $tabs = Get-Tabs
        for ($i = 0; $i -lt $tabs.Count; $i++) {
            $t = $tabs[$i]
            $sel = $false
            try { $sel = $t.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected } catch {}
            "TAB$i sel=$sel name='" + $t.Current.Name + "'"
        }
    }
    'selecttab' {
        $tabs = Get-Tabs
        if ($Match -match '^\d+$') {
            $idx = [int]$Match
            $r = Click-El $tabs[$idx]
            "SELECTED tab $idx via $r"
            break
        }
        for ($i = 0; $i -lt $tabs.Count; $i++) {
            if ($tabs[$i].Current.Name -like "*$Match*") {
                $r = Click-El $tabs[$i]
                "SELECTED tab $i via $r"
                break
            }
        }
    }
    'shot' {
        $win = Get-Win
        $r = $win.Current.BoundingRectangle
        $bmp = New-Object System.Drawing.Bitmap([int]$r.Width, [int]$r.Height)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen([int]$r.X, [int]$r.Y, 0, 0, $bmp.Size)
        $dir = Split-Path $Path -Parent
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
        $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $bmp.Dispose()
        "SAVED $Path"
    }
    'text' {
        $win = Get-Win
        $dc = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Document)
        $docs = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $dc)
        $out = @()
        for ($i = 0; $i -lt $docs.Count; $i++) {
            $t = ''
            try { $t = $docs[$i].GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern).DocumentRange.GetText(-1) } catch {}
            $out += "=== DOC$i name='$($docs[$i].Current.Name)' len=$($t.Length) ==="
            $out += $t
        }
        $out
    }
    'find' {
        $win = Get-Win
        $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $Name)
        $els = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
        "FOUND=" + $els.Count
        for ($i = 0; $i -lt $els.Count; $i++) {
            $e = $els[$i]
            $r = $e.Current.BoundingRectangle
            "$i [$($e.Current.ControlType.ProgrammaticName)] '$($e.Current.Name)' rect=$([int]$r.X),$([int]$r.Y) $([int]$r.Width)x$([int]$r.Height) offscreen=$($e.Current.IsOffscreen)"
        }
    }
    'click' {
        if ($X -ge 0 -and $Y -ge 0) {
            [void][Native]::SetForegroundWindow((Get-Win).Current.NativeWindowHandle)
            Click-Point $X $Y
            "CLICKED $X,$Y"
            break
        }
        $win = Get-Win
        $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $Name)
        $els = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
        if ($els.Count -eq 0) { throw "element not found: $Name" }
        $e = $null
        for ($i = 0; $i -lt $els.Count; $i++) { if (-not $els[$i].Current.IsOffscreen) { $e = $els[$i]; break } }
        if (-not $e) { $e = $els[0] }
        $how = Click-El $e
        "CLICKED '$Name' via $how"
    }
    'type' {
        [void][Native]::SetForegroundWindow((Get-Win).Current.NativeWindowHandle)
        Start-Sleep -Milliseconds 100
        if ($Ctrl) { [System.Windows.Forms.SendKeys]::SendWait('^a'); Start-Sleep -Milliseconds 100 }
        [System.Windows.Forms.SendKeys]::SendWait($Name)
        "TYPED"
    }
    'keys' {
        [void][Native]::SetForegroundWindow((Get-Win).Current.NativeWindowHandle)
        Start-Sleep -Milliseconds 100
        [System.Windows.Forms.SendKeys]::SendWait($Keys)
        "KEYS SENT"
    }
}




