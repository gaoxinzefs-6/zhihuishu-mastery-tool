#requires -Version 5.1
<#
.SYNOPSIS
    智慧树 / 知到 知识点掌握度自动提升 - 命令行入口

.DESCRIPTION
    Windows 桌面自动化：通过 UI Automation 操作 Edge 浏览器中的
    「智慧树 · 掌握度」页面，自动打开灰色知识点、抓取题目、填入答案并提交。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\run.ps1 -Action status

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\run.ps1 -Action next

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\run.ps1 -Action submit -Answers "B|B|A|B|B"
#>
param(
    [ValidateSet('status', 'next', 'submit', 'dump', 'open', 'node', 'help')]
    [string]$Action = 'status',

    # 每题答案，用 | 分隔；判断题用 T/F；多选写成连写字母，例如 B|T|AC|D|A
    [string]$Answers = '',

    # -Action open 时指定知识点名称
    [string]$Name = ''
)

$ErrorActionPreference = 'Stop'

$src = Join-Path $PSScriptRoot 'src'
$work = Join-Path $PSScriptRoot 'work'
if (-not (Test-Path $work)) { New-Item -ItemType Directory -Force $work | Out-Null }

$env:ZHIHUISHU_SRC = $src
$env:ZHIHUISHU_WORK = $work

function Invoke-Tool {
    param([string]$File, [hashtable]$ArgSet)
    $path = Join-Path $src $File
    if (-not (Test-Path $path)) { throw "找不到脚本: $path" }
    $sb = [scriptblock]::Create((Get-Content -Raw $path))
    & $sb @ArgSet
}

switch ($Action) {
    'status' { Invoke-Tool 'Exam.ps1' @{ Action = 'status' } }
    'dump' { Invoke-Tool 'Exam.ps1' @{ Action = 'dumpall' } }
    'next' { Invoke-Tool 'Mastery.ps1' @{ Next = $true } }
    'open' {
        if (-not $Name) { throw '请用 -Name 指定知识点名称' }
        Invoke-Tool 'Mastery.ps1' @{ Name = $Name }
    }
    'submit' {
        if (-not $Answers) { throw '请用 -Answers 传入答案，例如 "B|B|A|B|B"' }
        Invoke-Tool 'Pipeline.ps1' @{ Action = 'push3'; Answers = $Answers }
    }
    'node' { Invoke-Tool 'UiTree.ps1' @{ Action = 'tree'; MaxDepth = 5; MaxNodes = 200 } }
    'help' { Get-Help $PSCommandPath -Detailed }
}
