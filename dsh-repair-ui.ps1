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
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="DSH 修复" Width="470" Height="356" WindowStyle="None" AllowsTransparency="True" Background="Transparent" WindowStartupLocation="CenterScreen" Topmost="True" FontFamily="Segoe UI" UseLayoutRounding="True" SnapsToDevicePixels="True" Opacity="0">
  <Border x:Name="Card" CornerRadius="18" BorderThickness="1" RenderTransformOrigin="0.5,0.5">
    <Border.RenderTransform><ScaleTransform x:Name="WinScale" ScaleX="0.97" ScaleY="0.97"/></Border.RenderTransform>
    <Border.BorderBrush>
      <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
        <GradientStop Color="#2AFFFFFF" Offset="0"/>
        <GradientStop Color="#0AFFFFFF" Offset="0.3"/>
        <GradientStop Color="#05FFFFFF" Offset="1"/>
      </LinearGradientBrush>
    </Border.BorderBrush>
    <Border.Background>
      <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
        <GradientStop Color="#111318" Offset="0"/>
        <GradientStop Color="#0A0B0E" Offset="0.55"/>
        <GradientStop Color="#07080A" Offset="1"/>
      </LinearGradientBrush>
    </Border.Background>
    <Border.Effect><DropShadowEffect BlurRadius="60" ShadowDepth="0" Opacity="0.72" Color="#000000"/></Border.Effect>
    <Grid>
      <Ellipse Width="300" Height="300" HorizontalAlignment="Left" VerticalAlignment="Bottom" Margin="-160,0,0,-180" IsHitTestVisible="False" Opacity="0.7">
        <Ellipse.Fill><RadialGradientBrush><GradientStop Color="#3A5E6AD2" Offset="0"/><GradientStop Color="#005E6AD2" Offset="1"/></RadialGradientBrush></Ellipse.Fill>
      </Ellipse>
      <Ellipse Width="260" Height="260" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,-140,-110,0" IsHitTestVisible="False">
        <Ellipse.Fill><RadialGradientBrush><GradientStop Color="#14FFFFFF" Offset="0"/><GradientStop Color="#00FFFFFF" Offset="1"/></RadialGradientBrush></Ellipse.Fill>
      </Ellipse>
      <Grid Margin="26,18,26,20">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Grid x:Name="Bar" Height="18" Background="Transparent">
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
            <TextBlock Text="DEEPSEEK HARNESS" Foreground="#454A53" FontSize="9.5" VerticalAlignment="Center"/>
            <Border CornerRadius="4" Background="#1AFFFFFF" Padding="5,1,5,2" Margin="8,0,0,0" VerticalAlignment="Center">
              <TextBlock x:Name="VerChip" Text="RELIEF v3" Foreground="#7A808A" FontSize="8.5"/>
            </Border>
          </StackPanel>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
            <Border CornerRadius="9" Background="#08FFFFFF" Padding="8,2,8,3" BorderThickness="1" BorderBrush="#14FFFFFF">
              <StackPanel Orientation="Horizontal">
                <Ellipse x:Name="Dot" Width="5" Height="5" Fill="#5E6AD2" VerticalAlignment="Center" Margin="0,0,6,0"/>
                <TextBlock x:Name="Status" Text="待命" Foreground="#8A9099" FontSize="9.5"/>
              </StackPanel>
            </Border>
            <Button x:Name="CloseBtn" Content="&#x2715;" Width="20" Height="20" Padding="0" Margin="8,0,0,0" Background="Transparent" BorderThickness="0" Foreground="#6E737C" FontSize="10" Cursor="Hand" Focusable="False" VerticalAlignment="Center">
              <Button.Template>
                <ControlTemplate TargetType="Button">
                  <Border x:Name="cb" CornerRadius="5" Background="Transparent">
                    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <ControlTemplate.Triggers>
                    <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="cb" Property="Background" Value="#0FFFFFFF"/></Trigger>
                  </ControlTemplate.Triggers>
                </ControlTemplate>
              </Button.Template>
            </Button>
          </StackPanel>
        </Grid>

        <Grid Grid.Row="1" Margin="0,20,0,0">
          <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <StackPanel Grid.Column="0" VerticalAlignment="Center" Margin="0,0,16,0">
            <TextBlock Text="CURRENT STEP" Foreground="#454B55" FontSize="9" Margin="0,0,0,8"/>
            <TextBlock x:Name="Step" Text="准备就绪" Foreground="#F1F2F4" FontSize="21.5" FontWeight="SemiBold" TextWrapping="Wrap" LineHeight="28"/>
            <TextBlock x:Name="Meta" Text="尚未开始" Foreground="#5C626B" FontSize="10" Margin="0,9,0,0"/>
          </StackPanel>
          <Grid Grid.Column="1" Width="78" Height="78" VerticalAlignment="Center">
            <Ellipse Width="78" Height="78" Stroke="#12FFFFFF" StrokeThickness="1.6"/>
            <Ellipse x:Name="RingFg" Width="78" Height="78" StrokeThickness="1.8" StrokeStartLineCap="Round" StrokeEndLineCap="Round">
              <Ellipse.Stroke><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#8F97F2" Offset="0"/><GradientStop Color="#DFE2FF" Offset="1"/></LinearGradientBrush></Ellipse.Stroke>
              <Ellipse.RenderTransform><RotateTransform Angle="-90" CenterX="39" CenterY="39"/></Ellipse.RenderTransform>
            </Ellipse>
            <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
              <TextBlock x:Name="PctBig" Text="0" FontSize="21" FontWeight="SemiBold" Foreground="#F1F2F4" HorizontalAlignment="Center"/>
              <TextBlock Text="%" FontSize="8.5" Foreground="#5A6068" HorizontalAlignment="Center" Margin="0,-2,0,0"/>
            </StackPanel>
          </Grid>
        </Grid>

        <Grid Grid.Row="2" Margin="0,18,0,0">
          <Grid.ColumnDefinitions><ColumnDefinition/></Grid.ColumnDefinitions>
          <Grid Grid.Column="0" Height="2" VerticalAlignment="Center">
            <Border CornerRadius="1" Background="#0FFFFFFF"/>
            <Border x:Name="Track" CornerRadius="1" ClipToBounds="True">
              <Border x:Name="Fill" HorizontalAlignment="Left" Width="0" CornerRadius="1">
                <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,0"><GradientStop Color="#5E6AD2" Offset="0"/><GradientStop Color="#B6BCFF" Offset="1"/></LinearGradientBrush></Border.Background>
              </Border>
            </Border>
            <Border x:Name="ShimHold" CornerRadius="1" ClipToBounds="True">
              <Border x:Name="Shim" Width="90" Height="2" HorizontalAlignment="Left" Opacity="0.2" IsHitTestVisible="False">
                <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,0"><GradientStop Color="#00FFFFFF" Offset="0"/><GradientStop Color="#99FFFFFF" Offset="0.5"/><GradientStop Color="#00FFFFFF" Offset="1"/></LinearGradientBrush></Border.Background>
                <Border.RenderTransform><TranslateTransform x:Name="ShimT" X="-100"/></Border.RenderTransform>
              </Border>
            </Border>
          </Grid>
        </Grid>

        <Border Grid.Row="3" Height="1" Background="#0DFFFFFF" Margin="0,16,0,0"/>

        <Border Grid.Row="4" Margin="0,14,0,0" CornerRadius="8" Background="#06FFFFFF" BorderThickness="1" BorderBrush="#0BFFFFFF" Padding="11,9,11,9" VerticalAlignment="Top" MinHeight="42"><Grid VerticalAlignment="Top">
          <Grid.ColumnDefinitions><ColumnDefinition Width="2"/><ColumnDefinition/></Grid.ColumnDefinitions>
          <Border Grid.Column="0" Width="2" CornerRadius="1" Background="#5E6AD2" Opacity="0.7" VerticalAlignment="Stretch" Margin="0,1,0,1"/>
          <StackPanel Grid.Column="1" Margin="12,0,0,0">
            <TextBlock Text="LIVE LOG" Foreground="#3F444D" FontSize="8.5" Margin="0,0,0,6"/>
            <TextBlock x:Name="Detail" Text="点「开始修复」后 DSH 会重启一次，此处对话会中断" Foreground="#78808C" FontFamily="Cascadia Mono, Consolas" FontSize="10.5" TextWrapping="Wrap" LineHeight="16"/>
          </StackPanel>
        </Grid></Border>

        <StackPanel Grid.Row="5" Orientation="Horizontal" Margin="0,14,0,0">
          <Border CornerRadius="6" Background="#0DFFFFFF" BorderThickness="1" BorderBrush="#12FFFFFF" Padding="7,2,7,3" Margin="0,0,6,0">
            <TextBlock x:Name="ChipA" Text="备份 —" Foreground="#6B7280" FontSize="9"/>
          </Border>
          <Border CornerRadius="6" Background="#0DFFFFFF" BorderThickness="1" BorderBrush="#12FFFFFF" Padding="7,2,7,3" Margin="0,0,6,0">
            <TextBlock x:Name="ChipB" Text="缓存 —" Foreground="#6B7280" FontSize="9"/>
          </Border>
          <Border CornerRadius="6" Background="#0DFFFFFF" BorderThickness="1" BorderBrush="#12FFFFFF" Padding="7,2,7,3">
            <TextBlock x:Name="ChipC" Text="插件 —" Foreground="#6B7280" FontSize="9"/>
          </Border>
        </StackPanel>

        <Button x:Name="StartBtn" Grid.Row="6" Content="开始修复" Height="42" Margin="0,14,0,0" Foreground="#EBECF2" FontSize="12.5" FontWeight="SemiBold" Cursor="Hand" Focusable="False">
          <Button.Template>
            <ControlTemplate TargetType="Button">
              <Border x:Name="bd" CornerRadius="10" BorderThickness="1" BorderBrush="#8E96FF">
                <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="0,1"><GradientStop Color="#7A85F0" Offset="0"/><GradientStop Color="#5A66D6" Offset="1"/></LinearGradientBrush></Border.Background>
                <Grid>
                  <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  <Border CornerRadius="10" BorderThickness="1,1,1,0" BorderBrush="#33FFFFFF" IsHitTestVisible="False"/>
                </Grid>
              </Border>
              <ControlTemplate.Triggers>
                <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="BorderBrush" Value="#6A8F97F2"/></Trigger>
                <Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Background" Value="#0DFFFFFF"/></Trigger>
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

function Set-Arc([double]$pct) {
  try {
    $c = 239.4
    $th = 1.8
    $v = [Math]::Max(0.0, [Math]::Min(100.0, $pct))
    $arcLen = $c * ($v / 100.0)
    $d = New-Object System.Windows.Media.DoubleCollection
    if ($arcLen -le 0.01) { $null = $d.Add([double]0.0001); $null = $d.Add([double]($c / $th)) }
    else { $null = $d.Add([double]($arcLen / $th)); $null = $d.Add([double](($c - $arcLen) / $th)) }
    $ringFg.StrokeDashArray = $d
  } catch { }
}

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
