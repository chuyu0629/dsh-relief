Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
if (-not $Root) { $Root = (Get-Location).Path }
$Log = Join-Path $Root "dsh-repair.log"
$Repair = Join-Path $Root "dsh-repair.ps1"
$Preview = ($args -contains "-Preview")
$Test = ($args -contains "-Test")
if ($Test) {
  $Log = Join-Path $Root "_diag\fake-repair.log"
  $Repair = Join-Path $Root "_diag\fake-repair.ps1"
}

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="DSH 修复" Width="420" Height="252" WindowStyle="None" AllowsTransparency="True" Background="Transparent" WindowStartupLocation="CenterScreen" Topmost="True" FontFamily="Microsoft YaHei UI" SnapsToDevicePixels="True" Opacity="0">
  <Border x:Name="Card" CornerRadius="22" BorderThickness="1" BorderBrush="#2A2A2E" RenderTransformOrigin="0.5,0.5">
    <Border.RenderTransform><ScaleTransform x:Name="WinScale" ScaleX="0.95" ScaleY="0.95"/></Border.RenderTransform>
    <Border.Background>
      <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
        <GradientStop Color="#1F1F23" Offset="0"/>
        <GradientStop Color="#131316" Offset="1"/>
      </LinearGradientBrush>
    </Border.Background>
    <Border.Effect><DropShadowEffect BlurRadius="46" ShadowDepth="0" Opacity="0.6" Color="#000000"/></Border.Effect>
    <Grid Margin="24,18,24,20">
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <Grid x:Name="Bar" Height="22" Background="Transparent">
        <TextBlock Text="DSH 修复" Foreground="#9C9CA3" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center"/>
        <Button x:Name="CloseBtn" Content="✕" Width="22" Height="22" Padding="0" HorizontalAlignment="Right" VerticalAlignment="Center" Background="Transparent" BorderThickness="0" Foreground="#5A5A61" FontSize="11" Cursor="Hand" Focusable="False"/>
      </Grid>
      <TextBlock x:Name="Step" Grid.Row="1" Text="准备就绪" Foreground="#FFFFFF" FontSize="23" FontWeight="SemiBold" Margin="0,12,0,0"/>
      <Grid Grid.Row="2" Height="5" Margin="0,18,0,0">
        <Border CornerRadius="2.5" Background="#2A2A2F"/>
        <Border x:Name="Track" CornerRadius="2.5" ClipToBounds="True">
          <Border x:Name="Fill" HorizontalAlignment="Left" Width="0" CornerRadius="2.5">
            <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,0"><GradientStop Color="#0A84FF" Offset="0"/><GradientStop Color="#64D2FF" Offset="1"/></LinearGradientBrush></Border.Background>
          </Border>
        </Border>
      </Grid>
      <TextBlock x:Name="Detail" Grid.Row="3" Text="点「开始修复」后 DSH 会重启一次，对话会中断" Foreground="#6E6E76" FontSize="11.5" Margin="0,11,0,0" TextTrimming="CharacterEllipsis" VerticalAlignment="Top" TextWrapping="Wrap"/>
      <Button x:Name="StartBtn" Grid.Row="4" Content="开始修复" Height="44" Margin="0,12,0,0" Foreground="#FFFFFF" FontSize="14" FontWeight="SemiBold" Cursor="Hand" BorderThickness="0" Focusable="False">
        <Button.Template>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" CornerRadius="22" Background="#0A84FF"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="#3D9BFF"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Background" Value="#0069D9"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Button.Template>
      </Button>
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
$lblDet   = $win.FindName("Detail")
$fill     = $win.FindName("Fill")
$track    = $win.FindName("Track")
$scale    = $win.FindName("WinScale")

$dragHandler = [System.Windows.Input.MouseButtonEventHandler]{
  param($s, $e)
  if ($e.ChangedButton -ne [System.Windows.Input.MouseButton]::Left) { return }
  try { $win.DragMove() } catch { }
}
$barArea.AddHandler([System.Windows.UIElement]::PreviewMouseLeftButtonDownEvent, $dragHandler, $true)

$btnClose.Add_Click({ $win.Close() })
$btnClose.Add_MouseEnter({ $btnClose.Foreground = "#FFFFFF" })
$btnClose.Add_MouseLeave({ $btnClose.Foreground = "#5A5A61" })

function Set-Progress($pct) {
  $w = 372.0
  try { if ($track.ActualWidth -gt 60) { $w = [double]$track.ActualWidth } } catch { }
  $target = [math]::Round($w * $pct / 100)
  $ease = New-Object System.Windows.Media.Animation.CubicEase
  $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
  $a1 = New-Object System.Windows.Media.Animation.DoubleAnimation([double]$target, [TimeSpan]::FromMilliseconds(420))
  $a1.EasingFunction = $ease
  $fill.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty, $a1)
}

function Set-Color($el, $hex) {
  try { $el.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($hex) } catch { }
}

$win.Add_KeyDown({ if ($_.Key -eq "Escape") { $win.Close() } elseif ($_.Key -eq "Return") { Start-Repair } })

function Start-Repair {
  if ($script:timer) { return }
  $script:done = $false
  $script:creep = 0
  $btnStart.Visibility = "Collapsed"
  $lblStep.Text = "正在修复"
  Set-Color $lblStep "#FFFFFF"
  $lblDet.Text = "正在关闭 DSH..."
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
        if ($says.Count -gt 0) { $last = ($says[-1] -replace "^.*SAY\s+", "").Trim(); if ($last) { $lblStep.Text = $last } }
        $pct = 8
        if ($tail -match "SAY 1/6") { $pct = 15 }
        if ($tail -match "SAY 2/6") { $pct = 25 }
        if ($tail -match "SAY 3/6") { $pct = 35 }
        if ($tail -match "SAY 4/6") { $pct = 45 }
        if ($tail -match "SAY 5/6") { $pct = 60 }
        if ($tail -match "rescue1") { $pct = 72 }
        if ($tail -match "rescue2") { $pct = 85 }
        if ($tail -match "start-cookie|start-nogpu|start-cache") { $pct = 70 }
        if ($tail -match "start1 ok|start2 ok|start-target ok|rescue1 result ok|rescue2 result ok") { $pct = 100 }
        if (-not $script:creep) { $script:creep = 0 }
        if ($script:creep -lt $pct) { $script:creep = $pct }
        if ($pct -ge 60 -and $pct -lt 100) { $script:creep = [Math]::Min(93, $script:creep + 1); $pct = $script:creep }
        Set-Progress $pct
        if ($script:testRun) { try { Add-Content -Path (Join-Path (Join-Path $Root "_diag") "ui-state.log") -Value ((Get-Date).ToString("HH:mm:ss") + " pct=" + $pct + " step=" + $lblStep.Text) } catch { } }
        $d = @($all | Where-Object { $_ -match "data ok|rollback point|PKG restored|orphan|crash|原因" } | Select-Object -Last 1)
        if ($d.Count -gt 0) { $lblDet.Text = ($d -join "   |   ") }
      }
      if ($script:proc -and $script:proc.HasExited -and -not $script:done) {
        $script:done = $true
        Set-Progress 100
        $fill.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#30D158")
        $lblStep.Text = "已修复"
        Set-Color $lblStep "#30D158"
        $lblDet.Text = "DSH 已启动 · 窗口 4 秒后自动关闭"
        $script:until = (Get-Date).AddSeconds(4)
      }
      if ($script:done -and $script:until -and (Get-Date) -gt $script:until) {
        $script:until = $null
        try { $script:timer.Stop() } catch { }
        $fade = New-Object System.Windows.Media.Animation.DoubleAnimation([double]0, [TimeSpan]::FromMilliseconds(300))
        $fade.Add_Completed({ $win.Close() })
        $win.BeginAnimation([System.Windows.Window]::OpacityProperty, $fade)
      }
    } catch { }
  })
  $script:timer.Start()
}

$win.Add_Loaded({
  try {
    $fin = New-Object System.Windows.Media.Animation.DoubleAnimation([double]1, [TimeSpan]::FromMilliseconds(240))
    $fin.EasingFunction = (New-Object System.Windows.Media.Animation.CubicEase)
    $win.BeginAnimation([System.Windows.Window]::OpacityProperty, $fin)
    $sin = New-Object System.Windows.Media.Animation.DoubleAnimation([double]1, [TimeSpan]::FromMilliseconds(340))
    $sin.EasingFunction = (New-Object System.Windows.Media.Animation.CubicEase)
    $scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $sin)
    $scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $sin)
    if ($Preview) {
      $lblStep.Text = "4/6 保存急救回滚点..."
      $lblDet.Text  = "data ok sessions=30   |   rollback point prescue-fake"
      Set-Progress 45
      return
    }
    if ($Test) {
      $script:testRun = $true
      $lblStep.Text = "准备就绪"
      $lblDet.Text = "测试模式：点按钮跑假修复"
      $script:t2 = New-Object System.Windows.Threading.DispatcherTimer
      $script:t2.Interval = [TimeSpan]::FromMilliseconds(900)
      $script:t2.Add_Tick({
        try {
          $script:t2.Stop()
          $pt = $btnStart.TranslatePoint((New-Object System.Windows.Point (($btnStart.ActualWidth / 2), ($btnStart.ActualHeight / 2))), $win)
          $hr = [System.Windows.Media.VisualTreeHelper]::HitTest($win, $pt)
          $node = $hr.VisualHit
          $isBtn = $false
          while ($node) { if ($node -is [System.Windows.Controls.Button]) { $isBtn = $true; break }; $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node) }
          Add-Content -Path (Join-Path (Join-Path $Root "_diag") "ui-hit.log") -Value ("hitBtn=" + $isBtn + " pt=" + $pt.X + "," + $pt.Y + " vis=" + $hr.VisualHit.GetType().Name)
          $ra = New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent, $btnStart)
          $btnStart.RaiseEvent($ra)
        } catch { Add-Content -Path (Join-Path (Join-Path $Root "_diag") "ui-err.log") -Value ((Get-Date).ToString("HH:mm:ss") + " | hook | " + $_.Exception.Message) }
      })
      $script:t2.Start()
    }
  } catch { try { Add-Content -Path (Join-Path (Join-Path $Root "_diag") "ui-err.log") -Value ((Get-Date).ToString("HH:mm:ss") + " | " + $_.Exception.GetType().Name + " | " + $_.Exception.Message + " | line " + $_.InvocationInfo.ScriptLineNumber) } catch { } }
})

$btnStart.Add_Click({ Start-Repair })

[void]$win.ShowDialog()

if ($script:timer) { $script:timer.Stop() }
