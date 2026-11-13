<#
  Build DSH一键修复.exe  (launcher that embeds the scripts)
  Usage: powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
  Output: dist\DshRelief.exe
#>
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
if (-not $Root) { $Root = (Get-Location).Path }
$Out = Join-Path $Root 'dist'
if (-not (Test-Path $Out)) { New-Item -ItemType Directory -Path $Out -Force | Out-Null }

$Csc = $null
foreach ($c in @(
  (Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
  (Join-Path $env:windir 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)) { if (Test-Path $c) { $Csc = $c; break } }
if (-not $Csc) { throw 'csc.exe not found (.NET Framework 4.x is required, ships with Windows)' }

$Resources = @(
  'dsh-repair.ps1',
  'dsh-repair-ui.ps1',
  'dsh-safe-start.ps1',
  'dsh-rescue.cjs',
  'dsh-backup.cjs',
  'dsh-restore.cjs',
  'dsh-orphans.cjs',
  'dsh-check.cjs',
  'dsh-jsoncheck.cjs',
  'dsh-diagnose.cjs',
  'dsh-repair-ops.cjs',
  'dsh-repair-knowledge.json'
)
$exe = Join-Path $Out 'DshRelief.exe'
$cscArgs = @('/nologo', '/target:winexe', '/optimize+', ('/out:' + $exe), '/r:System.Windows.Forms.dll', (Join-Path $Root 'Launcher.cs'))
foreach ($r in $Resources) {
  $p = Join-Path $Root $r
  if (-not (Test-Path $p)) { throw ('missing file: ' + $r) }
  $cscArgs += ('/resource:' + $p + ',DshRelief.' + $r)
}
& $Csc @cscArgs
if ($LASTEXITCODE -ne 0) { throw ('compile failed, exit ' + $LASTEXITCODE) }
Write-Host ('OK -> ' + $exe + '  ' + (Get-Item $exe).Length + ' bytes')
