#requires -Version 5.1
<# DSH 安全启动守卫：启动前校验配置 -> 坏了先用 golden 快照回滚 -> 再启动。用法: dsh-safe-start.ps1 [-CheckOnly] #>
param([switch]$CheckOnly)
$ErrorActionPreference = 'Continue'
$Root   = $PSScriptRoot
if (-not $Root) { $Root = (Get-Location).Path }

function Find-DshHome {
  try {
    $pr = Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pr -and $pr.Path) {
      $dir = Split-Path -Parent $pr.Path
      if (Test-Path (Join-Path $dir 'DeepSeek Harness.exe')) { return $dir }
    }
  } catch { }
  foreach ($p in @($env:DSH_APP, (Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness'), (Join-Path $env:ProgramFiles 'DeepSeek Harness'), (Join-Path ${env:ProgramFiles(x86)} 'DeepSeek Harness'), 'C:\Program Files\DeepSeek Harness', 'C:\Program Files (x86)\DeepSeek Harness')) {
    if (Test-Path (Join-Path $p 'DeepSeek Harness.exe')) { return $p }
  }
  try {
    foreach ($k in @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue)) {
      $it = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
      if ($it -and $it.DisplayName -match 'DeepSeek Harness' -and $it.InstallLocation) {
        $loc = $it.InstallLocation.TrimEnd('\')
        if (Test-Path (Join-Path $loc 'DeepSeek Harness.exe')) { return $loc }
      }
    }
  } catch { }
  return $null
}
$DshHome = Find-DshHome
$Node = Join-Path $Root 'node.exe'
if (-not (Test-Path $Node)) { $cand = Get-ChildItem (Join-Path $DshHome 'resources') -Filter 'node.exe' -Recurse -Depth 6 -File -ErrorAction SilentlyContinue | Select-Object -First 1; if ($cand) { $Node = $cand.FullName } }
if (-not (Test-Path $Node)) { $g = Get-Command node.exe -ErrorAction SilentlyContinue; if ($g) { $Node = $g.Source } }
$Check  = Join-Path $Root 'yaml-check.js'
$PatchV = Join-Path $Root 'rea-validate.js'
$Log    = Join-Path $Root 'dsh-safe-start.log'
$Golden = Join-Path $Root 'dsh-golden'
$Exe    = Join-Path $DshHome 'DeepSeek Harness.exe'
$HomeDir = Join-Path $env:USERPROFILE '.dsh'
$PatchRoot = Join-Path $HomeDir 'cordis.patch.yml'
$PatchProf = Join-Path $HomeDir 'profiles\desktop\cordis.patch.yml'
$Cred      = Join-Path $HomeDir '.credentials.yaml'
if (-not (Test-Path $Golden)) { New-Item -ItemType Directory -Path $Golden -Force | Out-Null }

function Note($m) { try { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m" | Out-File -FilePath $Log -Append -Encoding utf8 } catch { } }
function NodeRc($js, $file) {
  if (-not (Test-Path $Node)) { return -1 }
  if (-not (Test-Path $js)) { return -1 }
  try { $null = & $Node $js $file 2>&1 } catch { return -1 }
  if ($null -eq $LASTEXITCODE) { return -1 }
  return [int]$LASTEXITCODE
}
function Test-Patch($f) {
  if (-not (Test-Path $f)) { return 'missing' }
  $rc = NodeRc $PatchV $f
  if ($rc -eq -1) { return 'unknown' }
  if ($rc -eq 0) { return 'ok' }
  return 'bad'
}
function Test-Yaml($f) {
  if (-not (Test-Path $f)) { return 'missing' }
  $rc = NodeRc $Check $f
  if ($rc -eq -1) { return 'unknown' }
  if ($rc -eq 0) { return 'ok' }
  return 'bad'
}
function GoldenPath($f, $tag) { Join-Path $Golden ($tag + '-' + (Split-Path $f -Leaf)) }

function Save-Golden($f, $isPatch, $tag) {
  try {
    $g = GoldenPath $f $tag
    $cur = Get-Content -Path $f -Raw -ErrorAction SilentlyContinue
    $old = Get-Content -Path $g -Raw -ErrorAction SilentlyContinue
    if ($cur -ne $old) { Copy-Item $f $g -Force; Note ('GOLDEN saved ' + (Split-Path $f -Leaf)) }
  } catch { }
}

function Restore-Best($f, $isPatch, $tag) {
  $g = GoldenPath $f $tag
  if (Test-Path $g) {
    if ($isPatch) { if ((Test-Patch $g) -eq 'ok') { return $g } } else { if ((Test-Yaml $g) -eq 'ok') { return $g } }
  }
  $dir  = Split-Path $f -Parent
  $leaf = Split-Path $f -Leaf
  $cand = Get-ChildItem -Path $dir -Filter ("$leaf.bak-*") -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
  foreach ($c in $cand) {
    if ($isPatch) { if ((Test-Patch $c.FullName) -eq 'ok') { return $c.FullName } }
    else { if ((Test-Yaml $c.FullName) -eq 'ok') { return $c.FullName } }
  }
  return $null
}

$repaired = @()
$dead     = @()
$warn     = @()

# --- profile package.json 校验与回滚 ---
$Pkg = Join-Path $HomeDir 'profiles\desktop\package.json'
if (Test-Path $Pkg) {
  $pkgOk = $false
  if (Test-Path $Node) {
    $chk = Join-Path $Root 'dsh-jsoncheck.cjs'
    if (Test-Path $chk) {
      & $Node $chk $Pkg | Out-Null
      if ($LASTEXITCODE -eq 0) { $pkgOk = $true }
    }
  }
  if ($pkgOk) { Save-Golden $Pkg $false 'pkg' }
  else {
    $gp = GoldenPath $Pkg 'pkg'
    if (Test-Path $gp) {
      Copy-Item $Pkg ($Pkg + '.bak-' + (Get-Date -Format 'yyyyMMddHHmmss') + '-broken') -Force -ErrorAction SilentlyContinue
      Copy-Item $gp $Pkg -Force
      $repaired += 'profile package.json 损坏，已用 golden 恢复'
      Note 'PKG restored from golden'
    } else { $dead += 'profile package.json 损坏且无 golden 备份' }
  }
}
# --- 配置预检：剥 BOM + 校验所有 profile 的 package.json / cordis*.yml ---
$Pre = Join-Path $Root '_diag\preflight.js'
if ((Test-Path $Pre) -and (Test-Path $Node)) {
  $preOut = ((& $Node $Pre 2>&1) -join ' / ').Trim()
  Note ('PREFLIGHT ' + $preOut)
  if ($preOut -match 'bomFixed=[1-9]') { $repaired += ('BOM 已修正: ' + ($preOut -replace '\s+', ' ')) }
  if ($preOut -match '^FAIL') { $dead += ('配置文件损坏: ' + $preOut) }
}

# --- 启动前数据快照（12 小时节流，保留 3 代） ---
$Bk = Join-Path $Root 'dsh-backup.cjs'
if ((Test-Path $Bk) -and (Test-Path $Node)) {
  try { $null = & $Node $Bk 2>&1; Note 'SNAPSHOT ok' } catch { Note ('SNAPSHOT fail ' + $_.Exception.Message) }
}

foreach ($p in @([pscustomobject]@{f=$PatchRoot;n='root 补丁';t='root'}, [pscustomobject]@{f=$PatchProf;n='profile 补丁';t='profile'})) {
  $st = Test-Patch $p.f
  if ($st -eq 'ok') { Save-Golden $p.f $true $p.t; continue }
  if ($st -eq 'missing') { continue }
  if ($st -eq 'unknown') { $warn += ($p.n + ' 校验器没跑起来，本次跳过校验（文件未改动）'); Note ('SKIP ' + $p.n + ' validator unavailable'); continue }
  $bk = Restore-Best $p.f $true $p.t
  if ($bk) {
    Copy-Item $bk $p.f -Force
    $repaired += ($p.n + ' 已回滚到 ' + (Split-Path $bk -Leaf))
    Note ('REPAIR ' + $p.n + ' <- ' + $bk)
  } else {
    $dead += ($p.n + ' 损坏且无可用备份（已保留原文件，未做修改）')
    Note ('KEEP ' + $p.n + ' unrepairable, left untouched')
  }
}

if ((Test-Yaml $Cred) -eq 'ok') { Save-Golden $Cred $false 'cred' }
elseif ((Test-Yaml $Cred) -eq 'bad') {
  $bk = Restore-Best $Cred $false 'cred' 'cred'
  if ($bk) { Copy-Item $bk $Cred -Force; $repaired += '凭据文件已回滚'; Note ('REPAIR credentials <- ' + $bk) }
  else { $dead += '凭据文件损坏且无可用备份' }
}

$stRoot = Test-Patch $PatchRoot
$stProf = Test-Patch $PatchProf
$stCred = Test-Yaml $Cred
# --- 记忆文件守卫（mnemon runtime） ---
$MemDir = Join-Path $env:USERPROFILE '.mnemon\runtime'
$memFix = @()
if (Test-Path $MemDir) {
  foreach ($n in @('MEMORY.md','USER.md','memories.json')) {
    $f = Join-Path $MemDir $n
    $g = Join-Path $Golden ('mnemon-' + $n)
    $sz = if (Test-Path $f) { (Get-Item $f).Length } else { -1 }
    $gs = if (Test-Path $g) { (Get-Item $g).Length } else { -1 }
    if ($sz -le 0) {
      if ($gs -gt 0) { Copy-Item $g $f -Force; $memFix += ('记忆 ' + $n + ' 空，已从快照还原'); Note ('MEMFIX restore ' + $n) }
    } elseif ($sz -ne $gs) { Copy-Item $f $g -Force }
  }
}
Note ('CHECK done warn=' + $warn.Count + ' root=' + $stRoot + ' profile=' + $stProf + ' cred=' + $stCred + ' memfix=' + $memFix.Count + ' repaired=' + $repaired.Count + ' dead=' + $dead.Count)

if ($CheckOnly) {
  Write-Host ('配置检查: root=' + $stRoot + ' profile=' + $stProf + ' cred=' + $stCred)
  if ($repaired.Count -gt 0) { Write-Host ('已修复: ' + ($repaired -join ' | ')) }
  if ($dead.Count -gt 0) { Write-Host ('无法修复: ' + ($dead -join ', ')) }
  if ($memFix.Count -gt 0) { Write-Host ('记忆修复: ' + ($memFix -join '; ')) }
  exit 0
}

# 只有在"必须人工处理"时才弹窗；自动修好的安静启动，不打扰
if ($dead.Count -gt 0) {
  try {
    Add-Type -AssemblyName System.Windows.Forms
    $nl = [Environment]::NewLine
    $text = '启动检查发现配置损坏，自动修复没成功，需要你处理：' + $nl + $nl + ($dead -join $nl)
    [void][System.Windows.Forms.MessageBox]::Show($text, 'DSH 启动检查', 'OK', 'Warning')
  } catch { }
}

$BunExe = Join-Path $Root 'bun\bun.exe'
if (Test-Path $BunExe) { $env:OUR_FREE_MODEL_BUN = $BunExe }
$LaunchArgs = $env:DSH_LAUNCH_ARGS
if (Test-Path $Exe) {
  if ($LaunchArgs) { Start-Process -FilePath $Exe -ArgumentList $LaunchArgs; Note ('LAUNCH ' + $Exe + ' ' + $LaunchArgs) }
  else { Start-Process -FilePath $Exe; Note ('LAUNCH ' + $Exe) }
}
else { try { Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.MessageBox]::Show('找不到主程序：' + $Exe, 'DSH 安全启动', 'OK', 'Error') } catch { }; exit 3 }
