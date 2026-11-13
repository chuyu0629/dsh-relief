# DSH 一键修复：停进程 -> 查数据 -> 补齐 -> 快照 -> 校验启动 -> 启动失败则逐级禁用插件急救
param([switch]$SelfTest, [switch]$DryRun, [switch]$Preflight, [switch]$SafeMode, [switch]$Undo, [switch]$Verify)
$ErrorActionPreference = 'Continue'
$Root = $PSScriptRoot
if (-not $Root) { try { $Root = Split-Path -Parent $MyInvocation.MyCommand.Definition } catch { } }
if (-not $Root) { $Root = 'D:\111111' }

function Find-DshHome {
  foreach ($p in @('C:\111111', 'D:\111111', 'C:\Program Files\DeepSeek Harness', 'D:\Program Files\DeepSeek Harness')) {
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
  return 'C:\111111'
}
$DshHome = Find-DshHome
$Node = $null
foreach ($nc in @((Join-Path $Root 'node24\node-v24.22.1-win-x64\node.exe'), (Join-Path $DshHome 'resources\runtime\primary-runtime\dependencies\node\bin\node.exe'), (Join-Path $Root 'node.exe'))) {
  if ((-not $Node) -and $nc -and (Test-Path $nc)) { $Node = $nc }
}
if (-not $Node) {
  try {
    $cand = Get-ChildItem (Join-Path $DshHome 'resources') -Filter 'node.exe' -Recurse -Depth 6 -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cand) { $Node = $cand.FullName }
  } catch { }
}
if (-not $Node) { $Node = 'node' }
$UserHome = $env:USERPROFILE
if (-not $UserHome) { $UserHome = $env:HOMEDRIVE + $env:HOMEPATH }
if (-not $UserHome) { $UserHome = 'C:\Users\Administrator' }
$HomeDir = Join-Path $UserHome '.dsh'
$ProfileDir = Join-Path $HomeDir 'profiles\desktop'
$log = Join-Path $Root 'dsh-repair.log'
$AppData = $env:APPDATA
if (-not $AppData) { $AppData = Join-Path $UserHome 'AppData\Roaming' }
$logsDir = Join-Path $AppData '@deepseek-ai\dsh-desktop\logs'
$Exe = Join-Path $DshHome 'DeepSeek Harness.exe'
$OpsCjs = Join-Path $Root 'dsh-repair-ops.cjs'
$KnowledgeFile = Join-Path $Root 'dsh-repair-knowledge.json'
$GoldenFile = Join-Path $Root 'dsh-golden\last-good-plugins.json'
$StateFile = Join-Path $HomeDir 'dsh-repair-state.json'

function Note($m) { try { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m" | Out-File -FilePath $log -Append -Encoding utf8 } catch { }; Write-Host $m }
function Say($m) { Note ("SAY " + $m); Write-Host $m }
function Get-AvNames {
  $names = @('huorong','HipsDaemon','HipsTray','HipsMain','360tray','360Safe','ZhuDongFangYu','QQPCTray','kxetray','MsMpEng')
  $hit = @()
  foreach ($n in $names) { if (@(Get-Process -Name $n -ErrorAction SilentlyContinue).Count -gt 0) { $hit += $n } }
  return $hit
}

function Show-AvWarn {
  $av = Get-AvNames
  if ($av.Count -gt 0) {
    Note ('av present: ' + ($av -join ','))
    Say ('   注意：检测到安全软件（' + ($av -join '、') + '）在运行，它可能拦下本工具的启动动作；如果下面显示没起来，先关掉它再试。')
  }
}

function Get-PortFromLog {
  $ports = @()
  try {
    $files = @(Get-ChildItem $logsDir -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-30) })
    foreach ($f in $files) {
      $t = ''
      try { $t = [System.IO.File]::ReadAllText($f.FullName) } catch { }
      foreach ($m in [regex]::Matches($t, 'EADDRINUSE[^\r\n]{0,120}')) {
        foreach ($pm in [regex]::Matches($m.Value, '(\d{2,5})')) {
          $v = [int]$pm.Groups[1].Value
          if ($v -ge 1024 -and $v -le 65535) { $ports += $v }
        }
      }
    }
  } catch { }
  return @($ports | Sort-Object -Unique)
}

function Show-PortConflict {
  $ps = Get-PortFromLog
  if ($ps.Count -eq 0) { return }
  Note ('EADDRINUSE ports: ' + ($ps -join ','))
  foreach ($p in $ps) {
    $owner = @()
    try { $owner = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue) } catch { }
    if ($owner.Count -gt 0) {
      foreach ($o in $owner) {
        $pn = ''
        try { $pn = (Get-Process -Id $o.OwningProcess -ErrorAction SilentlyContinue).ProcessName } catch { }
        Say ('   端口 ' + $p + ' 被 ' + $pn + '(pid ' + $o.OwningProcess + ') 占着，DSH 起不来；要关掉它告诉我一声。')
      }
    } else {
      Say ('   端口 ' + $p + ' 报过占用，但现在查不到监听者，像是上次残留的半死进程。')
    }
  }
}

function Show-ActivateIssues {
  $issues = @()
  try {
    $files = @(Get-ChildItem $logsDir -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-10) })
    foreach ($f in $files) {
      $t = ''
      try { $t = [System.IO.File]::ReadAllText($f.FullName) } catch { }
      foreach ($m in [regex]::Matches($t, '(did not activate|failed to activate|Cannot find module)[^\r\n]{0,160}')) { $issues += $m.Value }
    }
  } catch { }
  if ($issues.Count -eq 0) { return }
  $u = @($issues | Sort-Object -Unique | Select-Object -First 5)
  Note ('activate issues: ' + ($u -join ' | '))
  Say ('   起来了，但有 ' + $u.Count + ' 条插件加载问题，这些插件没生效：')
  foreach ($i in $u) { Say ('     - ' + $i) }
}

function Get-Diag {
  $sc = Join-Path $Root 'dsh-diagnose.cjs'
  if (-not (Test-Path $sc)) { return $null }
  $tmp = Join-Path $env:TEMP ('dshdiag-' + [guid]::NewGuid().ToString('N') + '.json')
  try {
    $null = (& $Node $sc '--minutes=180' ('--out=' + $tmp) 2>$null)
    if (-not (Test-Path $tmp)) { Note 'diag: no output file'; return $null }
    $raw = Get-Content -LiteralPath $tmp -Raw -Encoding UTF8
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    if (-not $raw) { return $null }
    return ($raw | ConvertFrom-Json)
  } catch { Note ('diag fail: ' + $_.Exception.Message); Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue; return $null }
}

function Show-Diag($d) {
  if (-not $d) { Say '   日志归类器没跑起来，按常规流程处理。'; return }
  Note ('diag classes: ' + ($d.classes -join ','))
  if ($d.classes.Count -eq 0) { Say '   日志里没有典型故障特征，按常规流程处理。'; return }
  Say ('   日志判定：' + ($d.classes -join ' / '))
  if ($d.failedPlugins.Count -gt 0) { Say ('   日志点名的插件：' + ($d.failedPlugins -join '、')) }
  if ($d.ports.Count -gt 0) { Say ('   被占端口：' + ($d.ports -join ',')) }
  if ($d.missingModules.Count -gt 0) { Say ('   缺失模块：' + (($d.missingModules | Select-Object -First 5) -join '、') + ' —— 这不是禁插件能解决的') }
  foreach ($k in @('auth431','cookiesBloat','gpuCrash','cacheDenied','v8Snapshot','breakpoint','serviceConflict','gnuWhoami','portReserved','corruptSession','diskFull','clockSkew','rendererOom','singleInstance','sandboxDenied','hostCrash','providerLoop','stuckKill','whiteScreen','slotConflict','peerIncompat')) {
    if ($d.classes -contains $k) { Say ('   ' + $k + '：' + $d.evidence.$k) }
    $nk = $k + '_note'
    if ($d.evidence.$nk) { Say ('     对策：' + $d.evidence.$nk) }
  }
}

function Stop-Dsh {
  for ($i = 0; $i -lt 3; $i++) {
    $ps = Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue
    if (-not $ps) { break }
    $ps | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800
  }
  Start-Sleep -Seconds 1
  if (@(Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue).Count -eq 0) { return $true }
  foreach ($p in @(Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue)) {
    try { $null = (& taskkill.exe /F /T /PID $p.Id 2>$null) } catch { }
  }
  Start-Sleep -Seconds 2
  if (@(Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue).Count -eq 0) { Note 'stop: killed via taskkill /T'; return $true }
  Note ('stop failed, still alive: ' + ((@(Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue) | ForEach-Object { $_.Id }) -join ','))
  return $false
}

function Test-HttpUp($port, $timeoutMs) {
  $c = $null
  try {
    $c = New-Object System.Net.Sockets.TcpClient
    $iar = $c.BeginConnect('127.0.0.1', $port, $null, $null)
    if (-not $iar.AsyncWaitHandle.WaitOne($timeoutMs)) { return $false }
    $c.EndConnect($iar)
    $s = $c.GetStream()
    $s.ReadTimeout = $timeoutMs
    $s.WriteTimeout = $timeoutMs
    $b = [System.Text.Encoding]::ASCII.GetBytes("GET / HTTP/1.0`r`nHost: 127.0.0.1`r`n`r`n")
    $s.Write($b, 0, $b.Length)
    $buf = New-Object byte[] 32
    $n = 0
    try { $n = $s.Read($buf, 0, 32) } catch { $n = 0 }
    if ($n -le 0) { return $false }
    return ([System.Text.Encoding]::ASCII.GetString($buf, 0, $n).StartsWith('HTTP/'))
  } catch { return $false }
  finally { if ($c) { try { $c.Close() } catch { } } }
}

function Get-DshListenPorts {
  $ids = @(Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
  if ($ids.Count -eq 0) { return @() }
  try {
    return @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $ids -contains $_.OwningProcess } | Select-Object -ExpandProperty LocalPort -Unique)
  } catch { return @() }
}

function Test-DshHttp($maxSec) {
  $sawPort = $false
  $deadline = (Get-Date).AddSeconds($maxSec)
  while ((Get-Date) -lt $deadline) {
    $ports = Get-DshListenPorts
    if ($ports.Count -gt 0) {
      $sawPort = $true
      foreach ($pp in $ports) { if (Test-HttpUp $pp 1200) { return $true } }
    }
    Start-Sleep -Milliseconds 700
  }
  if (-not $sawPort) { return $true }
  return $false
}

function Get-CrashHint {
  $best = $null
  try {
    $files = @(Get-ChildItem $logsDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'crash|fatal' } | Sort-Object LastWriteTime -Descending)
    if ($files.Count -gt 0) { $best = $files[0] }
  } catch { }
  if (-not $best) { return 'no crash log' }
  $lines = @()
  try { $lines = @(Get-Content $best.FullName -TotalCount 40 -ErrorAction SilentlyContinue) } catch { }
  $hit = @($lines | Where-Object { $_ -match 'Error|error|Cannot find module|did not activate|failed to activate|EADDRINUSE|Exception' } | Select-Object -First 2)
  if ($hit.Count -eq 0) { $hit = @($lines | Where-Object { $_.Trim() -ne '' } | Select-Object -First 2) }
  $msg = (($hit -join ' / ') -replace "\s+", ' ')
  if ($msg.Length -gt 200) { $msg = $msg.Substring(0, 200) }
  return ($best.Name + ' | ' + $msg)
}

function Test-DshUp($waitSec, $since) {
  $fnStart = Get-Date
  $deadline = $fnStart.AddSeconds($waitSec)
  $upAt = $null
  while ((Get-Date) -lt $deadline) {
    if (-not $upAt) {
      $fresh = @()
      try { $fresh = @(Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue | Where-Object { $_.StartTime -gt $fnStart.AddSeconds(-3) }) } catch { $fresh = @() }
      if ($fresh.Count -gt 0) { $upAt = Get-Date }
    }
    if ($upAt -and ((Get-Date) - $upAt).TotalSeconds -ge 8) { break }
    Start-Sleep -Milliseconds 700
  }
  $p = Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue
  if (-not $p) { return 'down' }
  if (Test-Path $logsDir) {
    if ($since) { $cut = ([datetime]$since).AddSeconds(-5) } else { $cut = (Get-Date).AddSeconds(-($waitSec + 25)) }
    $recent = @(Get-ChildItem $logsDir -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt $cut })
    if ($since -and $global:LogBase) { $recent = @($recent | Where-Object { $global:LogBase -notcontains $_.Name }) }
    foreach ($f in $recent) {
      if ($f.Name -match 'renderer') { return ('crash-ui:' + $f.Name) }
      if ($f.Name -match 'crash|fatal') { return ('crash:' + $f.Name) }
      $t = ''
      try { $t = [System.IO.File]::ReadAllText($f.FullName) } catch { }
      if ($t -match 'DesktopHostFatalError|FatalError|Cannot find module|EADDRINUSE|did not activate|failed to activate') { return ('fatal:' + $f.Name) }
    }
  }
  if (-not (Test-DshHttp 18)) { return 'down:http' }
  return 'ok'
}

function Save-Baseline {
  try {
    $pkg = Join-Path $ProfileDir 'package.json'
    if (-not (Test-Path $pkg)) { return }
    $j = Get-Content $pkg -Raw | ConvertFrom-Json
    $names = New-Object System.Collections.Generic.List[string]
    if ($j.dependencies) { foreach ($pr in $j.dependencies.PSObject.Properties) { $names.Add($pr.Name) } }
    if ($j.dsh -and $j.dsh.profile -and $j.dsh.profile.bundles) { foreach ($b in $j.dsh.profile.bundles) { $names.Add([string]$b) } }
    $keep = @($names | Where-Object { $_ -notmatch '^@deepseek-ai/' } | Sort-Object -Unique)
    $obj = [pscustomobject]@{ ts = (Get-Date).ToString('s'); packages = $keep }
    $dir = Join-Path $Root 'dsh-golden'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $json = ($obj | ConvertTo-Json -Depth 4)
    [System.IO.File]::WriteAllText((Join-Path $dir 'last-good-plugins.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
    Note ('baseline saved: ' + $keep.Count + ' plugins')
    Show-ActivateIssues
  } catch { Note ('baseline fail: ' + $_.Exception.Message) }
}

function Show-SelfCheck {
  try {
    $out = & $Node (Join-Path $Root 'dsh-check.cjs') (('--root=' + $Root))
    $o = ($out | Out-String).Trim() | ConvertFrom-Json
    if ($o.ok) { Say '   依赖与配置检查通过'; return }
    if ($o.deps.missing.Count) { Say ('   缺少依赖目录: ' + ($o.deps.missing -join ', ')) }
    if ($o.deps.broken.Count) { Say ('   依赖损坏: ' + ($o.deps.broken -join ', ')) }
    if ($o.bundles.missing.Count) { Say ('   配置里引用了但未安装: ' + ($o.bundles.missing -join ', ')) }
    if ($o.patch.missingPackage.Count) { Say ('   配置引用的插件不存在: ' + (($o.patch.missingPackage | ForEach-Object { $_.name }) -join ', ')) }
    if ($o.baseline.newPlugins.Count) { Say ('   相对上次正常启动新增: ' + ($o.baseline.newPlugins -join ', ')) }
  } catch { Say '   依赖与配置检查未能完成（跳过）' }
}

function Show-OrphanPlugins {
  try {
    $raw = & $Node (Join-Path $Root 'dsh-orphans.cjs') 2>$null
    if (-not $raw) { return }
    $list = @($raw | ConvertFrom-Json | ForEach-Object { if ($_ -is [string]) { $_ } elseif ($_.name) { [string]$_.name } else { [string]$_ } })
    $list = @($list | Where-Object { $_ -and $_.Trim() })
    if ($list.Count -gt 0) {
      Note ('orphan plugins: ' + ($list -join ', '))
      Say ('注意：这些插件文件还在但没在配置里（可能被回退掉了）：' + ($list -join '、') + '。要恢复告诉我一声。')
    }
  } catch { }
}

function Repair-AuthCache {
  $dir = Join-Path $AppData '@deepseek-ai\dsh-desktop'
  if (-not (Test-Path $dir)) { return $false }
  $leaf = 'dsh-desktop-bak-' + (Get-Date -Format 'yyyyMMddHHmmss')
  try {
    Rename-Item -Path $dir -NewName $leaf -ErrorAction Stop
    Note ('auth cache reset -> ' + $leaf)
    return $true
  } catch {
    Note ('auth cache reset fail: ' + $_.Exception.Message)
    return $false
  }
}

function Test-NearLog($pat) {
  $f = Join-Path $Root 'dsh-safe-start.log'
  if (-not (Test-Path $f)) { return $false }
  $tail = Get-Content $f -Tail 30 -ErrorAction SilentlyContinue
  return (($tail | Select-String -SimpleMatch $pat | Measure-Object).Count -gt 0)
}

function Start-Safe([string]$ExtraArgs = '') {
  if ($ExtraArgs) { $env:DSH_LAUNCH_ARGS = $ExtraArgs } else { Remove-Item Env:\DSH_LAUNCH_ARGS -ErrorAction SilentlyContinue }
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'dsh-safe-start.ps1') | Out-Null
}

function Save-RollbackPoint {
  $pre = Join-Path $Root ('dsh-backups\prescue-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
  New-Item -ItemType Directory -Force -Path $pre | Out-Null
  foreach ($rel in @('profiles\desktop\package.json', 'profiles\desktop\cordis.patch.yml', 'cordis.patch.yml')) {
    $src = Join-Path $HomeDir $rel
    if (Test-Path $src) { Copy-Item $src (Join-Path $pre (Split-Path $rel -Leaf)) -Force -ErrorAction SilentlyContinue }
  }
  return $pre
}

function Restore-RollbackPoint($pre) {
  foreach ($rel in @('profiles\desktop\package.json', 'profiles\desktop\cordis.patch.yml', 'cordis.patch.yml')) {
    $src = Join-Path $pre (Split-Path $rel -Leaf)
    if (Test-Path $src) { Copy-Item $src (Join-Path $HomeDir $rel) -Force -ErrorAction SilentlyContinue }
  }
}


function Clear-RenderCache($n) {
  $freed = 0.0
  $cnt = 0
  $names = @('GPUCache','Code Cache','Cache','DawnCache','DawnGraphiteCache','DawnWebGPUCache','ShaderCache','GrShaderCache','blob_storage')
  $lad = $env:LOCALAPPDATA
  $bases = @($ProfileDir)
  if ($AppData) { $bases += (Join-Path $AppData '@deepseek-ai\dsh-desktop') }
  if ($lad) { $bases += (Join-Path $lad '@deepseek-ai') }
  foreach ($base in $bases) {
    if (-not $base -or -not (Test-Path $base)) { continue }
    foreach ($nm in $names) {
      $t = Join-Path $base $nm
      if (-not (Test-Path $t)) { continue }
      $sz = 0.0
      try { $sz = [math]::Round((@(Get-ChildItem $t -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum + 0) / 1MB, 1) } catch { $sz = 0 }
      try { Remove-Item $t -Recurse -Force -ErrorAction Stop; $freed += $sz; $cnt++; Note ('cache cleared: ' + $t + ' (' + $sz + 'MB)') } catch { Note ('cache clear fail: ' + $t) }
    }
  }
  if ($cnt -gt 0) { Say ('   已清渲染缓存 ' + $cnt + ' 处 / ' + [math]::Round($freed, 1) + ' MB（下次启动自动重建）') } else { Say '   渲染缓存已是最简，无需清理' }
}

function Kill-StalePortOwners($n, $extraPorts) {
  $ports = @()
  try { $d = Get-Diag; if ($d -and $d.ports) { $ports += @($d.ports) } } catch { }
  if ($extraPorts) { $ports += @($extraPorts) }
  $ports = @($ports | Where-Object { $_ } | Sort-Object -Unique)
  if ($ports.Count -eq 0) { return }
  foreach ($p in $ports) {
    $num = 0
    if (-not [int]::TryParse([string]$p, [ref]$num)) { continue }
    if ($num -lt 1024) { continue }
    try {
      foreach ($c in @(Get-NetTCPConnection -State Listen -LocalPort $num -ErrorAction SilentlyContinue)) {
        $op = $c.OwningProcess
        $pr = Get-Process -Id $op -ErrorAction SilentlyContinue
        if (-not $pr) { continue }
        if ($pr.ProcessName -notmatch '^(DeepSeek|node|electron|dsh)') { Note ('port ' + $num + ' held by ' + $pr.ProcessName + ', skip') ; continue }
        $cl = ''
        try { $cl = [string](Get-CimInstance Win32_Process -Filter ('ProcessId=' + $op) -ErrorAction SilentlyContinue).CommandLine } catch { $cl = '' }
        if ($pr.ProcessName -in @('node','electron','dsh') -and $cl -and ($cl -notmatch 'dsh')) { Note ('port ' + $num + ' held by non-dsh ' + $pr.ProcessName + ', skip'); continue }
        try { Stop-Process -Id $op -Force -ErrorAction Stop; Note ('killed stale port owner pid=' + $op + ' ' + $pr.ProcessName + ' port=' + $num); Say ('   端口 ' + $num + ' 上的 DSH 残留进程已结束') }
        catch { Note ('kill stale port owner fail pid=' + $op) }
      }
    } catch { }
  }
}

function Restore-ConfigBackup {
  $n = 0
  foreach ($rel in @('profiles\desktop\package.json', 'profiles\desktop\cordis.patch.yml', 'cordis.patch.yml')) {
    $target = Join-Path $HomeDir $rel
    $leaf = Split-Path $target -Leaf
    $curBad = $false
    if (-not (Test-Path $target)) { $curBad = $true }
    elseif ($leaf -like '*.json') { try { $null = (Get-Content -LiteralPath $target -Raw | ConvertFrom-Json) } catch { $curBad = $true } }
    if (-not $curBad) { continue }
    $dir = Split-Path $target -Parent
    $baks = @(Get-ChildItem $dir -File -Filter ($leaf + '.bak-*') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    foreach ($b in $baks) {
      $bad = $false
      if ($leaf -like '*.json') { try { $null = (Get-Content -LiteralPath $b.FullName -Raw | ConvertFrom-Json) } catch { $bad = $true } }
      if ($bad) { continue }
      try { Copy-Item $b.FullName $target -Force -ErrorAction Stop; Note ('config from bak: ' + $b.Name + ' -> ' + $rel); $n++; break } catch { }
    }
  }
  if ($n -gt 0) { Say ('   配置已从备份恢复：' + $n + ' 个文件（原来那份已损坏）') }
  return $n
}

function Test-InstallFiles {
  $script:InstallMissing = @()
  foreach ($f in @('resources\app\lib\main.js', 'resources\runtime\cli\bin\dsh.cmd')) {
    if (-not (Test-Path (Join-Path $DshHome $f))) { $script:InstallMissing += $f }
  }
  if (-not (Test-Path $Exe)) { $script:InstallMissing += 'DeepSeek Harness.exe' }
  return ($script:InstallMissing.Count -eq 0)
}

# ---- 冷门崩溃定向修复：只动缓存与登录 cookie，不动插件配置和会话数据 ----
$script:LastClasses = ''

function Get-CookieStoreSize {
  $dir = Join-Path $AppData '@deepseek-ai\dsh-desktop'
  $sum = 0
  foreach ($rel in @('Network\Cookies', 'Network\Cookies-journal', 'Cookies', 'Cookies-journal')) {
    $p = Join-Path $dir $rel
    if (Test-Path $p) { try { $sum += (Get-Item -LiteralPath $p).Length } catch { } }
  }
  return $sum
}

function Repair-CookieStore {
  $dir = Join-Path $AppData '@deepseek-ai\dsh-desktop'
  if (-not (Test-Path $dir)) { Note 'cookie reset: no user data dir'; return $false }
  $bk = Join-Path $Root ('dsh-backups\cookies-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
  New-Item -ItemType Directory -Force -Path $bk | Out-Null
  $moved = 0
  foreach ($rel in @('Network\Cookies', 'Network\Cookies-journal', 'Cookies', 'Cookies-journal')) {
    $p = Join-Path $dir $rel
    if (Test-Path $p) {
      try { Move-Item -LiteralPath $p -Destination (Join-Path $bk (Split-Path $rel -Leaf)) -Force -ErrorAction Stop; $moved++ }
      catch { Note ('cookie move fail: ' + $_.Exception.Message) }
    }
  }
  Note ('cookie reset: moved=' + $moved + ' -> ' + $bk)
  return ($moved -gt 0)
}

function Rename-CacheDirs($n) {
  $ud = Join-Path $AppData '@deepseek-ai\dsh-desktop'
  $did = 0
  foreach ($d in @('GPUCache', 'Code Cache', 'Cache', 'DawnCache', 'DawnGraphiteCache', 'DawnWebGPUCache', 'ShaderCache', 'GrShaderCache', 'blob_storage')) {
    $p = Join-Path $ud $d
    if (-not (Test-Path $p)) { continue }
    try { Rename-Item -LiteralPath $p -NewName ($d + '-bak-' + (Get-Date -Format 'HHmmss')) -Force -ErrorAction Stop; $did++ }
    catch { Note ('cache rename fail: ' + $p + ' ' + $_.Exception.Message) }
  }
  Note ('round' + $n + ' cache renamed=' + $did)
  return $did
}

function Test-PortReserved($port) {
  if (-not $port) { return $false }
  try {
    $o = (& netsh.exe int ipv4 show excludedportrange protocol=tcp 2>$null) -join [string][char]10
    foreach ($m in [regex]::Matches($o, '(\d{2,5})\s+(\d{2,5})')) {
      $a = [int]$m.Groups[1].Value
      $b = [int]$m.Groups[2].Value
      if ($port -ge $a -and $port -le $b) { return $true }
    }
  } catch { }
  return $false
}

function Get-FreeGB {
  try { return [math]::Round((Get-PSDrive -Name 'C' -ErrorAction Stop).Free / 1GB, 1) } catch { return -1 }
}

function Add-StatsRecord($result, $round, $classes) {
  try {
    $p = Join-Path $Root 'dsh-repair-stats.jsonl'
    $o = [ordered]@{ at = (Get-Date).ToString('s'); round = $round; result = $result; classes = '' + $classes }
    ($o | ConvertTo-Json -Compress) | Add-Content -LiteralPath $p -Encoding UTF8
  } catch { }
}

function Invoke-Ops([string[]]$OpArgs) {
  try {
    if (-not (Test-Path $OpsCjs)) { return $null }
    $raw = @(& $Node $OpsCjs @OpArgs 2>$null)
    $txt = ($raw -join [Environment]::NewLine).Trim()
    if (-not $txt) { return $null }
    return ($txt | ConvertFrom-Json)
  } catch { Note ('ops fail: ' + $_.Exception.Message); return $null }
}

function Show-Preflight {
  $r = Invoke-Ops @('preflight', '--profile', $ProfileDir)
  if (-not $r) { Say '   预检没跑起来（组件缺失或输出异常）'; return }
  Note ('preflight fatal=' + $r.counts.fatal + ' warn=' + $r.counts.warn)
  $f = @($r.findings)
  if ($f.Count -eq 0) { Say '   预检：没发现问题'; return }
  foreach ($x in $f) { Say ('   [' + $x.level + '] ' + $x.id + ' ' + $x.message) }
}

function Get-DiffSuspects {
  if (-not (Test-Path $GoldenFile)) { Note 'diff: no golden'; return @() }
  $r = Invoke-Ops @('diff', '--profile', $ProfileDir, '--golden', $GoldenFile)
  if (-not $r) { return @() }
  $s = @($r.suspects)
  Note ('diff suspects=' + ($s -join ','))
  return $s
}

function Get-FrozenState([string]$name) {
  if (-not (Test-Path $StateFile)) { return $false }
  try { $s = Get-Content $StateFile -Raw | ConvertFrom-Json } catch { return $false }
  if (-not $s -or -not $s.plugins) { return $false }
  $p = $s.plugins.$name
  if (-not $p) { return $false }
  return [bool]$p.frozen
}

function Add-Failure([string]$name, [string]$msg) {
  $null = Invoke-Ops @('freeze', '--state', $StateFile, '--name', $name, '--error', $msg, '--limit', '3')
}

function Clear-Failure([string]$name) {
  $null = Invoke-Ops @('freeze', '--state', $StateFile, '--name', $name, '--mode', 'reset')
}

function Show-Knowledge([string[]]$classes) {
  if (-not $classes -or $classes.Count -eq 0) { return }
  $r = Invoke-Ops @('knowledge', '--file', $KnowledgeFile, '--classes', ($classes -join ','))
  if (-not $r -or -not $r.matched) { return }
  foreach ($e in @($r.matched)) {
    Say ('   [' + $e.id + '] ' + $e.title)
    Say ('     证据: ' + $e.evidence)
    if ($e.useless) { Say ('     已知无效: ' + (@($e.useless) -join '；')) }
  }
}

function Invoke-SurgicalRemove {
  $sus = @(Get-DiffSuspects)
  if ($sus.Count -eq 0) { Note 'surgical: no suspect'; return 'none' }
  $pick = @()
  foreach ($s in $sus) { if (-not (Get-FrozenState $s)) { $pick += $s } }
  if ($pick.Count -eq 0) { Say '   嫌疑插件都被冻结过（反复弄崩），不再试，建议手动卸载。'; return 'none' }
  $target = $pick[0]
  Say ('   比对上次正常启动：变化的是 ' + ($pick -join '、') + '；只摘 ' + $target + '（改前备份，-Undo 可回退）...')
  $r = Invoke-Ops @('comment', '--profile', $ProfileDir, '--name', $target)
  if (-not $r -or -not $r.ok) {
    $why = 'unknown'
    if ($r -and $r.patch -and $r.patch.message) { $why = $r.patch.message } elseif ($r -and $r.reason) { $why = $r.reason }
    Note ('surgical fail: ' + $why)
    Say ('   摘除失败（配置结构不常规：' + $why + '），没动它')
    return 'none'
  }
  Note ('surgical removed ' + $target)
  if (-not (Stop-Dsh)) { return 'alive' }
  Kill-StalePortOwners 0 @()
  $mark = Get-Date
  $global:LogBase = @(Get-ChildItem $logsDir -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
  Start-Safe
  $st = Test-DshUp 25 $mark
  Note ('start-surgical ' + $st)
  if ($st -eq 'ok') {
    Clear-Failure $target
    Say ('   摘掉 ' + $target + ' 后启动正常，插件配置已备份，想装回去用 -Undo')
    return 'ok'
  }
  Add-Failure $target (Get-CrashHint)
  return 'retry'
}

function Invoke-TargetedRepair($n, $d) {
  $cls = @()
  if ($d -and $d.classes) { $cls = @($d.classes) }
  $script:LastClasses = ($cls -join ',')
  try { Show-Knowledge $cls } catch { }
  if ($cls.Count -eq 0) { Note 'targeted: no class'; return 'none' }
  $free = Get-FreeGB
  if ($free -ge 0 -and $free -lt 2) {
    Say ('   C 盘只剩 ' + $free + ' GB，缓存和配置都写不下去，先腾空间。')
    return 'fatal'
  }
  if (($cls -contains 'breakpoint') -or ($cls -contains 'v8Snapshot')) {
    Say '   崩溃发生在窗口出现之前（V8 / 本体层），改配置和禁插件都无效。'
    return 'fatal'
  }
  if (($cls -contains 'cookiesBloat') -or ($cls -contains 'auth431')) {
    $kb = [math]::Round((Get-CookieStoreSize) / 1KB, 0)
    Say ('   登录 cookie 库 ' + $kb + ' KB（Cookie 头超过 16KB 就会被拒），只重置它，不动其它数据...')
    if (-not (Stop-Dsh)) { return 'alive' }
    if (Repair-CookieStore) {
      $mark = Get-Date
      $global:LogBase = @(Get-ChildItem $logsDir -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
      Start-Safe
      $st = Test-DshUp 25 $mark
      Note ('round' + $n + ' start-cookie ' + $st)
      if ($st -eq 'ok') { return 'ok' }
    }
  }
  if ($cls -contains 'gpuCrash') {
    Say '   GPU 进程崩了，改用软件渲染再启一次...'
    if (-not (Stop-Dsh)) { return 'alive' }
    $mark = Get-Date
    $global:LogBase = @(Get-ChildItem $logsDir -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    Start-Safe '--disable-gpu'
    $st = Test-DshUp 25 $mark
    Note ('round' + $n + ' start-nogpu ' + $st)
    if ($st -eq 'ok') { return 'ok' }
  }
  if ($cls -contains 'cacheDenied') {
    Say '   缓存目录被占或权限被拒，改名缓存目录后重启...'
    if (-not (Stop-Dsh)) { return 'alive' }
    Rename-CacheDirs $n | Out-Null
    $mark = Get-Date
    $global:LogBase = @(Get-ChildItem $logsDir -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    Start-Safe
    $st = Test-DshUp 25 $mark
    Note ('round' + $n + ' start-cache ' + $st)
    if ($st -eq 'ok') { return 'ok' }
  }
  if ($cls -contains 'portReserved') {
    foreach ($p in @($d.ports)) {
      if (Test-PortReserved $p) { Say ('   端口 ' + $p + ' 落在 Hyper-V / WSL2 / Docker 的保留段，需要换端口，脚本不改你的配置。') }
    }
  }
  if ($cls -contains 'serviceConflict') { Say ('   白屏原因是插件注册了已被占的服务名：' + $d.registeredService + '，禁掉那个插件能起。') }
  if ($cls -contains 'corruptSession') { Say '   会话日志损坏：侧栏可能空白但程序能起；这个脚本不动会话数据。' }
  if ($cls -contains 'gnuWhoami') { Say '   PATH 里 Git 的 whoami 抢在系统命令前，需要调 PATH 顺序，脚本不替你改系统环境。' }
  Note ('targeted done: ' + $script:LastClasses)
  return 'none'
}

function Invoke-Round($n) {
  if (-not (Stop-Dsh)) { Note ('round' + $n + ' abort: process alive'); return 'alive' }
  Kill-StalePortOwners $n @()
  Clear-RenderCache $n
  Say ('5/6 第 ' + $n + ' 轮：启动 DSH...')
  $mark = Get-Date
  $global:LogBase = @(Get-ChildItem $logsDir -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
  Start-Safe
  $st = Test-DshUp 25 $mark
  Note ('round' + $n + ' start1 ' + $st)
  if ($st -eq 'ok') { Note 'start1 ok'; return 'ok' }
  Show-PortConflict
  Show-AvWarn
  $d0 = Get-Diag
  Show-Diag $d0
  $tr = 'none'
  try { $tr = Invoke-TargetedRepair $n $d0 } catch { Note ('targeted fail: ' + $_.Exception.Message) }
  if ($tr -eq 'ok') { Note 'start-target ok'; return 'ok' }
  if ($tr -eq 'alive') { return 'alive' }
  if ($tr -eq 'fatal') { return 'fatal' }
  $done = 0
  while ($done -lt 2) {
    $done++
    $sg = 'none'
    try { $sg = Invoke-SurgicalRemove } catch { Note ('surgical err: ' + $_.Exception.Message) }
    if ($sg -eq 'ok') { Note 'start-target ok'; return 'ok' }
    if ($sg -eq 'alive') { return 'alive' }
    if ($sg -ne 'retry') { break }
  }
  if ($st -eq 'down:http') {
    Say '   进程起来了但界面连不上，像是登录凭证缓存失配，先重置它...'
    Stop-Dsh
    if (Repair-AuthCache) {
      $mark = Get-Date
      $global:LogBase = @(Get-ChildItem $logsDir -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
      Start-Safe
      $st = Test-DshUp 25 $mark
      Note ('round' + $n + ' start-auth ' + $st)
      if ($st -eq 'ok') { Note 'start-auth ok'; return 'ok' }
    }
  }
  Say ('   第 ' + $n + ' 轮首次失败（' + $st + '），原样重试一次...')
  Say ('   原因: ' + (Get-CrashHint))
  if (-not (Stop-Dsh)) { return 'alive' }
  $mark = Get-Date
  $global:LogBase = @(Get-ChildItem $logsDir -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
  Start-Safe
  $st = Test-DshUp 20 $mark
  Note ('round' + $n + ' start2 ' + $st)
  if ($st -eq 'ok') { Note 'start2 ok'; return 'ok' }
  Show-PortConflict
  for ($lv = 1; $lv -le 2; $lv++) {
    Say ('   第 ' + $n + ' 轮急救第 ' + $lv + ' 级：禁用可疑插件...')
    Say ('   原因: ' + (Get-CrashHint))
    $d2 = Get-Diag
    Show-Diag $d2
    if (-not (Stop-Dsh)) { return 'alive' }
    if ($lv -eq 1 -and $d2 -and $d2.failedPlugins.Count -gt 0) {
      Say ('   按日志点名禁用（不盲禁）：' + ($d2.failedPlugins -join '、'))
      $out = & $Node (Join-Path $Root 'dsh-rescue.cjs') ('--packages=' + ($d2.failedPlugins -join ','))
    } else {
      $out = & $Node (Join-Path $Root 'dsh-rescue.cjs') ('--level=' + $lv)
    }
    Note ('round' + $n + ' rescue' + $lv + ' ' + $out)
    Kill-StalePortOwners $n @()
    Clear-RenderCache $n
    $mark = Get-Date
    $global:LogBase = @(Get-ChildItem $logsDir -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    Start-Safe
    $st = Test-DshUp 25 $mark
    Note ('round' + $n + ' rescue' + $lv + ' result ' + $st)
    if ($st -eq 'ok') { Note ('rescue' + $lv + ' result ok'); return 'ok' }
  }
  return $st
}

if ($SelfTest) {
  Say 'SELFTEST 检查环境...'
  Say ('node   : ' + (Test-Path $Node))
  Say ('exe    : ' + (Test-Path $Exe))
  Say ('safestart: ' + (Test-Path (Join-Path $Root 'dsh-safe-start.ps1')))
  Say ('rescue : ' + (Test-Path (Join-Path $Root 'dsh-rescue.cjs')))
  $raw1 = @(& $Node (Join-Path $Root 'dsh-rescue.cjs') '--level=1' '--dry' 2>&1)
  $o = ($raw1 -join "`n").Trim()
  if (-not $o) { $o = 'no output' }
  Say ('level1 dry: ' + $o)
  $raw2 = @(& $Node (Join-Path $Root 'dsh-rescue.cjs') '--level=2' '--dry' 2>&1)
  $o2 = ($raw2 -join "`n").Trim()
  Say ('level2 dry count: ' + (([regex]::Matches($o2, '"name"')).Count))
  Say ('logsdir: ' + (Test-Path $logsDir))
  Say ('appdata: ' + (Test-Path (Join-Path $AppData '@deepseek-ai\dsh-desktop')))
  exit
}

if ($DryRun) {
  Note '==== dry run ===='
  Say '体检模式：只检查，不改动任何文件'
  $missD = @()
  foreach ($f in @('profiles\desktop\package.json', 'prompt-inject.md', 'storages')) { if (-not (Test-Path (Join-Path $HomeDir $f))) { $missD += $f } }
  $sc = 0
  $sd = Join-Path $HomeDir 'sessions'
  if (Test-Path $sd) { $sc = @(Get-ChildItem $sd -Recurse -File -ErrorAction SilentlyContinue).Count }
  $freeC = 0
  try { $freeC = [math]::Round((Get-PSDrive C -ErrorAction Stop).Free / 1GB, 1) } catch { }
  Say ('   数据: 会话 ' + $sc + ' 个，缺失项: ' + $(if ($missD.Count) { $missD -join ', ' } else { '无' }))
  Say ('   C 盘剩余: ' + $freeC + ' GB')
  Show-SelfCheck
  $raw1 = @(& $Node (Join-Path $Root 'dsh-rescue.cjs') '--level=1' '--dry' 2>&1)
  $o = ($raw1 -join "`n").Trim()
  Say ('   一级急救会禁用: ' + $o)
  $raw2 = @(& $Node (Join-Path $Root 'dsh-rescue.cjs') '--level=2' '--dry' 2>&1)
  $o2 = ($raw2 -join "`n").Trim()
  Say ('   二级急救会禁用: ' + (([regex]::Matches($o2, '"name"')).Count) + ' 个插件')
  $diag = Get-Diag
  Show-Diag $diag
  Say '体检结束，未改动任何文件'
  exit
}

if ($Preflight -or $SafeMode -or $Undo -or $Verify) {
  if ($Preflight) {
    Note '==== preflight ===='
    Say '预检模式：只读检查 profile，不改任何文件'
    Show-Preflight
    $sus = @(Get-DiffSuspects)
    if ($sus.Count -gt 0) { Say ('   与上次正常启动相比新增/变化: ' + ($sus -join '、')) } else { Say '   与上次正常启动相比没有变化' }
    exit
  }
  if ($Undo) {
    Note '==== undo ===='
    $u = Invoke-Ops @('undo', '--profile', $ProfileDir)
    if ($u -and $u.ok) { Say ('已回退最近一次改动：' + (@($u.restored) -join '、')); Say '重启 DSH 后生效。' }
    else { Say '没有可回退的改动记录（台账为空或备份已不在）。' }
    exit
  }
  if ($Verify) {
    Say '隔离复验：造临时 DSH_HOME 校验配置能否组合，不动真 profile'
    $v = Invoke-Ops @('verify', '--profile', $ProfileDir, '--dsh', (Join-Path $DshHome 'resources\runtime\cli\bin\dsh.cmd'))
    if ($v -and $v.ok) { Say '   配置组合正常（--dump-config 退出码 0）' }
    elseif ($v) { Say ('   配置组合失败，退出码 ' + $v.status); Say ('   ' + $v.tail) }
    else { Say '   复验没跑起来' }
    exit
  }
  if ($SafeMode) {
    Note '==== safemode ===='
    if (-not (Stop-Dsh)) { Say '进程杀不掉，先手动结束再试。'; exit }
    $s = Invoke-Ops @('safemode', '--profile', $ProfileDir)
    if (-not $s -or -not $s.ok) { Say '安全模式写入失败，配置未改。'; exit }
    if (-not $s.changed) { Say '已经只有官方插件了，不需要安全模式。'; exit }
    Say ('已摘出 ' + (@($s.removed).Count) + ' 个第三方插件，只留官方 ' + (@($s.kept).Count) + ' 个启动；原配置已备份，-Undo 可还原。')
    Show-Preflight
    Start-Safe
    $mark = Get-Date
    if ((Test-DshUp 30 $mark) -eq 'ok') { Say ('安全模式启动成功。被摘出的插件: ' + (@($s.removed) -join '、')) }
    else { Say '安全模式也没起来，问题不在第三方插件。' }
    exit
  }
}

# 单实例锁：两个入口同时点会互相 Stop-Dsh、各起一次，实测过会留下半截启动
if (-not $SelfTest -and -not $DryRun) {
  $script:RepairMutex = New-Object System.Threading.Mutex($false, 'Global\DshReliefRepair')
  $got = $false
  try { $got = $script:RepairMutex.WaitOne(0) }
  catch [System.Threading.AbandonedMutexException] { $got = $true }
  if (-not $got) {
    Say '已经有一次修复在跑（可能是另一个窗口或另一个入口），这次不再重复动作，等它跑完再点。'
    exit
  }
}
Note '==== repair start ===='
Show-AvWarn

Say '1/6 关闭 DSH...'
if (-not (Stop-Dsh)) { Say '进程杀不掉，已停手：这种情况禁插件、回滚都无效，得手动结束残留进程。'; Note 'abort: process still alive'; exit }

Say '2/6 检查数据完整性...'
$miss = @()
foreach ($f in @('profiles\desktop\package.json', 'prompt-inject.md', 'storages')) {
  if (-not (Test-Path (Join-Path $HomeDir $f))) { $miss += $f }
}
$sessCount = 0
$sessDir = Join-Path $HomeDir 'sessions'
if (Test-Path $sessDir) { $sessCount = @(Get-ChildItem $sessDir -Recurse -File -ErrorAction SilentlyContinue).Count }
if (($miss.Count -gt 0) -or ($sessCount -lt 5)) {
  Note ('RESET detected missing=' + ($miss -join ',') + ' sessions=' + $sessCount)
  Say '   数据疑似被重置，正在从快照补齐...'
  & $Node (Join-Path $Root 'dsh-restore.cjs')
} else {
  Note ('data ok sessions=' + $sessCount)
  Say '   数据正常'
}

Say '3/6 备份当前数据...'
& $Node (Join-Path $Root 'dsh-backup.cjs') '--force'

Say '4/6 保存急救回滚点...'
$pre = Save-RollbackPoint
Note ('rollback point ' + $pre)
  $all = @(Get-ChildItem (Join-Path $Root 'dsh-backups') -Directory -Filter 'prescue-*' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
  if ($all.Count -gt 10) { $all | Select-Object -Skip 10 | ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } }

Say '5/6 校验依赖与配置...'
Show-SelfCheck
$diag = Get-Diag
Show-Diag $diag
if ($diag) { $script:LastClasses = (@($diag.classes) -join ',') }
Say '5/6 本体与安装自检...'
if (-not (Test-InstallFiles)) {
  Note ('install broken, missing=' + ($script:InstallMissing -join ','))
  Say ('本体文件缺失：' + ($script:InstallMissing -join '、'))
  Say ('这不是配置问题，禁插件和回滚都无效，需要重装 DSH。数据目录 ' + $HomeDir + ' 重装时保留；本次已先备份到 dsh-backups。')
  exit
}
Say '   本体文件齐全'

$st = 'down'
$round = 0
while ($round -lt 2) {
  $round++
  if ($round -eq 2) {
    Say '6/6 第 1 轮无效：恢复配置、清掉残留后，重跑一整轮...'
    Note 'round2 prep: restore rollback point'
    Restore-RollbackPoint $pre
    Restore-ConfigBackup | Out-Null
  }
  $st = Invoke-Round $round
  if ($st -eq 'ok') {
    Save-Baseline
    Note ('==== repair done (round ' + $round + ') ====')
    Add-StatsRecord 'ok' $round $script:LastClasses
    if ((Test-NearLog 'PKG restored')) { Say '提示：配置文件曾损坏，已回退到上次正常版本；如果你刚装过新插件，需要重新装一次。' }
    Show-OrphanPlugins
    if ($round -eq 1) { Say '完成，DSH 已正常启动。' } else { Say '完成：第一轮没成，第二轮成了，DSH 已正常启动。' }
    exit
  }
  if ($st -eq 'alive') { Say '进程杀不掉，已停手：这种情况禁插件、回滚都无效，得手动结束残留进程。'; Note 'abort: process still alive'; exit }
  if ($st -eq 'fatal') { Say '这次崩溃属于改配置修不了的类型（见上面判定），已停手，数据没有动。'; Note ('abort: fatal ' + $script:LastClasses); Add-StatsRecord 'fatal' $round $script:LastClasses; exit }
}

Say '6/6 两轮都没成，恢复到修复前的配置...'
Note ('all rounds failed, restoring ' + $pre)
Stop-Dsh
Restore-RollbackPoint $pre
Start-Safe
Test-DshUp 20 | Out-Null
Note '==== repair finished with failure, config restored ===='
Add-StatsRecord 'fail' $round $script:LastClasses
Say ('自动修复没能解决，配置已恢复原样。原因: ' + (Get-CrashHint))
