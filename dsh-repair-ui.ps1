Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$ErrorActionPreference = "Stop"
trap { try { ("ERR " + $_.Exception.ToString() + " @line " + $_.InvocationInfo.ScriptLineNumber + ": " + $_.InvocationInfo.Line.Trim()) | Out-File -FilePath "D:\111111\_diag\ui-err2.log" -Append -Encoding UTF8 } catch { }; exit 1 }
$Root = $PSScriptRoot
if (-not $Root) { $Root = "D:\111111" }
$Log = Join-Path $Root "dsh-repair.log"
$Repair = Join-Path $Root "dsh-repair.ps1"
$Preview = ($args -contains "-Preview")
$Test = ($args -contains "-Test")
if ($Test) {
  $Log = Join-Path $Root "_diag\fake-repair.log"
  $Repair = Join-Path $Root "_diag\fake-repair.ps1"
}

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="DSH 修复" Width="560" Height="300" WindowStyle="None" AllowsTransparency="True" Background="Transparent" WindowStartupLocation="CenterScreen" Topmost="True" FontFamily="Segoe UI" UseLayoutRounding="True" SnapsToDevicePixels="True" Opacity="0">
  <Border x:Name="Card" CornerRadius="16" BorderThickness="1" Background="#0C0D10" BorderBrush="#1A1D23" RenderTransformOrigin="0.5,0.5">
    <Border.RenderTransform><ScaleTransform x:Name="WinScale" ScaleX="0.985" ScaleY="0.985"/></Border.RenderTransform>
    <Border.Effect><DropShadowEffect BlurRadius="48" ShadowDepth="0" Opacity="0.6" Color="#000000"/></Border.Effect>
    <Grid Margin="30,24,30,24">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <Grid x:Name="Bar" Height="18" Background="Transparent">
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="DSH RELIEF" Foreground="#5C626B" FontSize="9.5" FontWeight="SemiBold" VerticalAlignment="Center"/>
          <TextBlock x:Name="VerChip" Text="v3.0.1" Foreground="#3B4047" FontSize="9.5" Margin="10,1,0,0" VerticalAlignment="Center"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
          <Ellipse x:Name="Dot" Width="5" Height="5" Fill="#5C626B" Margin="0,0,7,0" VerticalAlignment="Center"/>
          <TextBlock x:Name="Status" Text="待命" Foreground="#7C828B" FontSize="10" VerticalAlignment="Center"/>
          <Button x:Name="CloseBtn" Content="&#x2715;" Width="18" Height="18" Padding="0" Margin="10,0,0,0" Background="Transparent" BorderThickness="0" Foreground="#4A4F57" FontSize="9" Cursor="Hand" Focusable="False" VerticalAlignment="Center">
            <Button.Template>
              <ControlTemplate TargetType="Button">
                <Border CornerRadius="5" Background="Transparent">
                  <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
              </ControlTemplate>
            </Button.Template>
          </Button>
        </StackPanel>
      </Grid>

      <StackPanel Grid.Row="1" Margin="0,28,0,0">
        <TextBlock x:Name="PctBig" Text="0" Foreground="#F3F4F6" FontSize="40" FontFamily="Segoe UI Light" FontWeight="Light"/>
        <TextBlock x:Name="Step" Text="准备就绪" Foreground="#A6ACB5" FontSize="13.5" Margin="0,12,0,0" TextWrapping="Wrap" LineHeight="19"/>
        <TextBlock x:Name="Meta" Text="尚未开始" Foreground="#4A4F57" FontSize="10" Margin="0,6,0,0"/>
      </StackPanel>

      <Grid Grid.Row="2" Height="1.5" Margin="0,22,0,0">
        <Border CornerRadius="1" Background="#16181D"/>
        <Border x:Name="Track" CornerRadius="1" ClipToBounds="True" Background="Transparent">
          <Border x:Name="Fill" HorizontalAlignment="Left" Width="0" CornerRadius="1" Background="#DCDFE4"/>
        </Border>
        <Border x:Name="ShimHold" CornerRadius="1" ClipToBounds="True" Background="Transparent">
          <Border x:Name="Shim" Width="120" Height="1.5" HorizontalAlignment="Left" Opacity="0.10" IsHitTestVisible="False" Background="#FFFFFF">
            <Border.RenderTransform><TranslateTransform x:Name="ShimT" X="-140"/></Border.RenderTransform>
          </Border>
        </Border>
      </Grid>

      <TextBlock x:Name="Detail" Grid.Row="3" Text="点「开始修复」后 DSH 会重启一次，此处对话会中断" Foreground="#565C66" FontFamily="Cascadia Mono, Consolas" FontSize="10.5" Margin="0,18,0,0" TextTrimming="CharacterEllipsis" TextWrapping="NoWrap"/>

      <Grid Grid.Row="4" Margin="0,20,0,0">
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock x:Name="ChipA" Text="备份 —" Foreground="#4A4F57" FontSize="9.5"/>
          <TextBlock Text="·" Foreground="#2E3238" FontSize="9.5" Margin="7,0,7,0"/>
          <TextBlock x:Name="ChipB" Text="缓存 —" Foreground="#4A4F57" FontSize="9.5"/>
          <TextBlock Text="·" Foreground="#2E3238" FontSize="9.5" Margin="7,0,7,0"/>
          <TextBlock x:Name="ChipC" Text="插件 —" Foreground="#4A4F57" FontSize="9.5"/>
        </StackPanel>
        <Button x:Name="StartBtn" Content="开始修复" HorizontalAlignment="Right" Padding="18,7,18,8" Background="#0A0B0D" Foreground="#C3C8CF" FontSize="11.5" Cursor="Hand" Focusable="False">
          <Button.Template>
            <ControlTemplate TargetType="Button">
              <Border x:Name="bd" CornerRadius="8" BorderThickness="1" BorderBrush="#262A31" Background="#0A0B0D">
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <ControlTemplate.Triggers>
                <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="BorderBrush" Value="#3D434C"/><Setter Property="Foreground" Value="#EDEFF2"/></Trigger>
                <Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Background" Value="#14161A"/></Trigger>
              </ControlTemplate.Triggers>
            </ControlTemplate>
          </Button.Template>
        </Button>
      </Grid>
    </Grid>
  </Border>
</Window>
"@


$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$win = [Windows.Markup.XamlReader]::Load($reader)
$barArea  = $win.FindName("Bar")
$btnClose = $win.FindName("CloseBtn")
$btnStart = $win.FindName("StartBtn")
$lblStep  = $win.FindName("Step")
$lblMeta  = $win.FindName("Meta")
$lblSta   = $win.FindName("Status")
$dotStat  = $win.FindName("Dot")
$lblDet   = $win.FindName("Detail")
$fill     = $win.FindName("Fill")
$track    = $win.FindName("Track")
$scale    = $win.FindName("WinScale")
$ringFg   = $win.FindName("RingFg")
$pctBig   = $win.FindName("PctBig")
$pctTxt   = $win.FindName("PctTxt")
$shimT    = $win.FindName("ShimT")
$chipA    = $win.FindName("ChipA")
$chipB    = $win.FindName("ChipB")
$chipC    = $win.FindName("ChipC")
$script:lastStep = ""
$script:cntNow = ""
$script:twFull = ""
$script:twI = 0

$script:shimAnim = New-Object System.Windows.Media.Animation.DoubleAnimation([double]-100, [double]420, [TimeSpan]::FromMilliseconds(2600))
$script:shimAnim.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
$shimT.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $script:shimAnim)
$db = New-Object System.Windows.Media.Animation.DoubleAnimation([double]0.4, [double]1, [TimeSpan]::FromMilliseconds(1500))
$db.AutoReverse = $true
$db.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
$dotStat.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $db)

function Set-Status([string]$text, [string]$hex) {
  try { $lblSta.Text = $text; $lblSta.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($hex) } catch { }
  try { $dotStat.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString($hex) } catch { }
}

function Set-Chip($el, [string]$text) {
  try { if ($text -and $text -ne $el.Text) { $el.Text = $text } } catch { }
}

function Set-Arc([double]$pct) { }

function Set-Big([int]$pct) {
  if ([string]$pct -eq $script:cntNow) { return }
  $script:cntNow = [string]$pct
  try {
    $pctBig.Text = [string]$pct
    $ty = New-Object System.Windows.Media.TranslateTransform(0, 7)
    $pctBig.RenderTransform = $ty
    $ease = New-Object System.Windows.Media.Animation.CubicEase
    $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
    $a1 = New-Object System.Windows.Media.Animation.DoubleAnimation([double]9, [double]0, [TimeSpan]::FromMilliseconds(480))
    $a1.EasingFunction = $ease
    $ty.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $a1)
    $a2 = New-Object System.Windows.Media.Animation.DoubleAnimation([double]0.15, [double]1, [TimeSpan]::FromMilliseconds(480))
    $pctBig.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $a2)
  } catch { }
}

$script:twTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:twTimer.Interval = [TimeSpan]::FromMilliseconds(24)
$script:twTimer.Add_Tick({
  try {
    if ($script:twI -lt $script:twFull.Length) {
      $n = [Math]::Min($script:twI + 2, $script:twFull.Length)
      $lblDet.Text = $script:twFull.Substring(0, $n)
      $script:twI = $n
    }
  } catch { }
})
$script:twTimer.Start()

function Set-Detail([string]$t) {
  if ($t -eq $script:twFull) { return }
  $script:twFull = $t
  $script:twI = 0
  try { $lblDet.Text = "" } catch { }
}

function Set-Progress($pct) {
  $w = 300.0
  try { if ($track.ActualWidth -gt 40) { $w = [double]$track.ActualWidth } } catch { }
  $target = [math]::Round($w * $pct / 100)
  $ease = New-Object System.Windows.Media.Animation.CubicEase
  $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
  $a1 = New-Object System.Windows.Media.Animation.DoubleAnimation([double]$target, [TimeSpan]::FromMilliseconds(460))
  $a1.EasingFunction = $ease
  $fill.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty, $a1)
  Set-Arc $pct
  Set-Big ([int]$pct)
  try { $pctTxt.Text = ([string]$pct + "%") } catch { }
}

$dragHandler = [System.Windows.Input.MouseButtonEventHandler]{
  param($s, $e)
  if ($e.ChangedButton -ne [System.Windows.Input.MouseButton]::Left) { return }
  $src = $e.OriginalSource
  while ($src -ne $null -and -not [object]::ReferenceEquals($src, $barArea)) {
    if ($src -is [System.Windows.Controls.Button]) { return }
    try { $src = [System.Windows.Media.VisualTreeHelper]::GetParent($src) } catch { break }
  }
  try { $win.DragMove() } catch { }
}
$barArea.AddHandler([System.Windows.UIElement]::PreviewMouseLeftButtonDownEvent, $dragHandler, $true)
$btnClose.Add_Click({ $win.Close() })
$win.Add_KeyDown({ if ($_.Key -eq "Escape") { $win.Close() } elseif ($_.Key -eq "Return") { Start-Repair } })

function Start-Repair {
  if ($script:timer) { return }
  $script:done = $false
  $script:creep = 0
  $script:sayPct = 0
  $btnStart.IsEnabled = $false
  $btnStart.Content = "修复中…"
  $btnStart.Opacity = 0.45
  Set-Status "修复中" "#8F97F2"
  $lblStep.Text = "正在诊断"
  Set-Detail "正在关闭 DSH 并读取日志"
  $script:proc = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-WindowStyle","Hidden","-File", $Repair) -WindowStyle Hidden -PassThru
  $script:timer = New-Object System.Windows.Threading.DispatcherTimer
  $script:timer.Interval = [TimeSpan]::FromMilliseconds(700)
  $script:timer.Add_Tick({
    try {
      if (Test-Path $Log) {
        $all = @(Get-Content $Log)
        $ri = -1
        for ($i = $all.Count - 1; $i -ge 0; $i--) { if ($all[$i] -match "==== repair start ====") { $ri = $i; break } }
        if ($ri -ge 0) { $all = @($all[$ri..($all.Count - 1)]) }
        $tail = @($all | Select-Object -Last 60)
        $says = @($tail | Where-Object { $_ -match "SAY " })
        if ($says.Count -gt 0) {
          $last = ($says[-1] -replace "^.*SAY\s+", "").Trim()
          if ($last) {
            $mm = [regex]::Match($last, "^(\d{1,2})/(\d{1,2})\s*(.*)$")
            if ($mm.Success) {
              $cur = [int]$mm.Groups[1].Value
              $tot = [int]$mm.Groups[2].Value
              if ($tot -gt 10) {
                $lblMeta.Text = "第 " + $cur.ToString("00") + " 类 / 共 " + $tot + " 类"
                $script:sayPct = [math]::Round(6 + 90 * ($cur / $tot))
              } else {
                $lblMeta.Text = "阶段 " + $cur + " / " + $tot
              }
              $t3 = $mm.Groups[3].Value
              if ($t3 -ne $script:lastStep) {
                $script:lastStep = $t3
                $lblStep.Text = $t3
                $fa = New-Object System.Windows.Media.Animation.DoubleAnimation([double]0.4, [double]1, [TimeSpan]::FromMilliseconds(420))
                $lblStep.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fa)
              }
            } else { $lblStep.Text = $last }
          }
        }
        $pct = 6
        if ($tail -match "SAY 1/6") { $pct = 15 }
        if ($tail -match "SAY 2/6") { $pct = 25 }
        if ($tail -match "SAY 3/6") { $pct = 35 }
        if ($tail -match "SAY 4/6") { $pct = 45 }
        if ($tail -match "SAY 5/6") { $pct = 60 }
        if ($tail -match "rescue1") { $pct = 72 }
        if ($tail -match "rescue2") { $pct = 85 }
        if ($tail -match "start-cookie|start-nogpu|start-cache") { $pct = 70 }
        if ($tail -match "start1 ok|start2 ok|start-target ok|rescue1 result ok|rescue2 result ok") { $pct = 100 }
        if ($script:sayPct -and $pct -lt 100 -and $script:sayPct -gt $pct) { $pct = $script:sayPct }
        if (-not $script:creep) { $script:creep = 0 }
        if ($script:creep -lt $pct) { $script:creep = $pct }
        if ($pct -ge 60 -and $pct -lt 100) { $script:creep = [Math]::Min(93, $script:creep + 1); $pct = $script:creep }
        Set-Progress $pct
        if ($script:testRun) { try { Add-Content -Path (Join-Path "D:\111111\_diag" "ui-state.log") -Value ((Get-Date).ToString("HH:mm:ss") + " pct=" + $pct + " step=" + $lblStep.Text) } catch { } }
        $dm = @($all | Where-Object { $_ -match "sessions=(\d+)" } | Select-Object -Last 1)
        if ($dm.Count -gt 0) { $null = $dm[0] -match "sessions=(\d+)"; Set-Chip $chipA ("备份 " + $matches[1] + " 会话") }
        $cm = @($all | Where-Object { $_ -match "cache cleared[^\d]*([\d\.]+MB)" } | Select-Object -Last 1)
        if ($cm.Count -gt 0) { $null = $cm[0] -match "([\d\.]+MB)"; Set-Chip $chipB ("缓存 " + $matches[1]) }
        $pm = @($all | Where-Object { $_ -match "PKG|bundles=(\d+)" } | Select-Object -Last 1)
        if ($pm.Count -gt 0 -and $pm[0] -match "bundles=(\d+)") { Set-Chip $chipC ("插件 " + $matches[1]) }
        $d = @($all | Where-Object { $_ -match "data ok|rollback point|PKG restored|orphan|crash|原因|证据|动作|校验" } | Select-Object -Last 1)
        if ($d.Count -gt 0) { Set-Detail ($d -join "   |   ") }
      }
      if ($script:proc -and $script:proc.HasExited -and -not $script:done) {
        $script:done = $true
        Set-Progress 100
        Set-Status "完成" "#30D158"
        try { $ringFg.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#47D07F") } catch { }
        $lblStep.Text = "已修复"
        $lblMeta.Text = "DSH 已启动 · star 一下：dsh-relief"
        $btnStart.Content = "已修复"
        $btnStart.Opacity = 0.6
        Set-Detail "修好了就给个 star：https://github.com/chuyu0629/dsh-relief"
        $script:until = (Get-Date).AddSeconds(7)
      }
      if ($script:done -and $script:until -and (Get-Date) -gt $script:until) {
        $script:until = $null
        try { $script:timer.Stop() } catch { }
        $fade = New-Object System.Windows.Media.Animation.DoubleAnimation([double]0, [TimeSpan]::FromMilliseconds(320))
        $fade.Add_Completed({ $win.Close() })
        $win.BeginAnimation([System.Windows.Window]::OpacityProperty, $fade)
      }
    } catch { }
  })
  $script:timer.Start()
}

$win.Add_Loaded({
  try {
    $fin = New-Object System.Windows.Media.Animation.DoubleAnimation([double]1, [TimeSpan]::FromMilliseconds(280))
    $fin.EasingFunction = (New-Object System.Windows.Media.Animation.CubicEase)
    $win.BeginAnimation([System.Windows.Window]::OpacityProperty, $fin)
    $sin = New-Object System.Windows.Media.Animation.DoubleAnimation([double]1, [TimeSpan]::FromMilliseconds(400))
    $sin.EasingFunction = (New-Object System.Windows.Media.Animation.CubicEase)
    $scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $sin)
    $scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $sin)
    Set-Arc 0
    if ($Preview) {
      $lblStep.Text = "保存急救回滚点"
      $lblMeta.Text = "阶段 4 / 6"
      Set-Detail "data ok sessions=30   |   rollback point prescue-fake"
      Set-Chip $chipA "备份 30 会话"
      Set-Chip $chipB "缓存 14.1MB"
      Set-Chip $chipC "插件 24"
      Set-Progress 45
      return
    }
    if ($Test) {
      $script:testRun = $true
      $script:t2 = New-Object System.Windows.Threading.DispatcherTimer
      $script:t2.Interval = [TimeSpan]::FromMilliseconds(900)
      $script:t2.Add_Tick({
        try {
          $script:t2.Stop()
          $ra = New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent, $btnStart)
          $btnStart.RaiseEvent($ra)
        } catch { }
      })
      $script:t2.Start()
    }
  } catch { try { Add-Content -Path (Join-Path "D:\111111\_diag" "ui-err.log") -Value ((Get-Date).ToString("HH:mm:ss") + " | " + $_.Exception.Message) } catch { } }
})

$btnStart.Add_Click({ Start-Repair })

[void]$win.ShowDialog()

if ($script:timer) { $script:timer.Stop() }
