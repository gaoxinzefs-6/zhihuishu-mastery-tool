#requires -Version 5.1
<#
.SYNOPSIS
    智慧树 / 知到 知识点掌握度自动提升 - 命令行入口

.DESCRIPTION
    两种用法：
      1) 人机协作：next 打开下一个灰色知识点并打印题目，submit 提交答案
      2) 机器调用：所有动作都支持 -Json，输出单行 JSON，便于 harness / agent 解析

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\run.ps1 -Action status

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\run.ps1 -Action next -Json

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\run.ps1 -Action submit -Answers "B|B|A|B|B" -Json
#>
param(
    [ValidateSet('status', 'scan', 'list', 'next', 'submit', 'back', 'dump', 'open', 'node', 'help')]
    [string]$Action = 'status',

    # 每题答案，用 | 分隔；判断题用 T/F；多选写成连写字母，例如 B|T|AC|D|A
    [string]$Answers = '',

    # -Action open 时指定知识点名称
    [string]$Name = '',

    # 输出单行 JSON（供 agent / 脚本解析）
    [switch]$Json,

    # next 找哪一类知识点：missing 灰色 / weak 黄色 / any
    [ValidateSet('missing', 'weak', 'any')]
    [string]$Target = 'missing'
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

$apiActions = @('status', 'scan', 'list', 'next', 'submit', 'back')
if ($apiActions -contains $Action) {
    $a = @{ Action = $Action }
    if ($Answers) { $a['Answers'] = $Answers }
    if ($Json) { $a['Json'] = $true }
    if ($Target) { $a['Target'] = $Target }
    Invoke-Tool 'Api.ps1' $a
    exit $LASTEXITCODE
}

switch ($Action) {
    'dump' { Invoke-Tool 'Exam.ps1' @{ Action = 'dumpall' } }
    'open' {
        if (-not $Name) { throw '请用 -Name 指定知识点名称' }
        Invoke-Tool 'Mastery.ps1' @{ Name = $Name }
    }
    'node' { Invoke-Tool 'UiTree.ps1' @{ Action = 'tree'; MaxDepth = 5; MaxNodes = 200 } }
    'help' { Get-Help $PSCommandPath -Detailed }
}


