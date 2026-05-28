<#
.SYNOPSIS
  Claude Code 양방향 상호작용 위젯 (PowerShell + WPF)
.DESCRIPTION
  Claude Code hook에 연결되어 이벤트별로 데스크톱 위젯을 띄운다.
    -Event Stop         작업 완료 시: 캐릭터 + 다음 지시 입력창. 입력하면 Claude가 이어서 작업.
    -Event Notification 입력/권한 대기 알림(토스트). 정보 전용.
    -Event PreToolUse   위험 명령 실행 전: 허용/거부/일반확인 위젯.
  결정용 출력은 stdout에 순수 JSON으로만 내보낸다. 오류 시 출력 없이 exit 0(Claude를 막지 않음).
#>
param(
    [Parameter(Mandatory)]
    [ValidateSet('Stop', 'Notification', 'PreToolUse')]
    [string]$Event
)

# WPF에는 STA 스레드 필요. 후크는 powershell.exe(5.1)로 호출 → STA 기본.
$ErrorActionPreference = 'Stop'

try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml | Out-Null

    # ----- stdout을 UTF-8로 쓰는 헬퍼 -----
    # Windows PowerShell 5.1의 [Console]::Out은 OEM 코드페이지를 쓰므로
    # Claude Code(UTF-8)로 한글이 깨진다. 표준출력에 UTF-8 바이트를 직접 쓴다.
    function Write-StdoutUtf8([string]$s) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($s + "`n")
        $stream = [Console]::OpenStandardOutput()
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
    }

    # ----- stdin (hook JSON) 읽기 (UTF-8 바이트로 직접 디코드) -----
    $stdin = [Console]::OpenStandardInput()
    $ms = New-Object System.IO.MemoryStream
    $stdin.CopyTo($ms)
    $raw = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
    # 일부 호출자가 stdin에 UTF-8 BOM(U+FEFF)을 붙이면 JSON 파싱이 실패하므로 선행 BOM 제거
    if ($raw.Length -gt 0 -and $raw[0] -eq [char]0xFEFF) { $raw = $raw.Substring(1) }
    $data = $null
    if ($raw -and $raw.Trim()) {
        try { $data = $raw | ConvertFrom-Json } catch { $data = $null }
    }

    # ----- 설정 로드 (config.psd1) -----
    $cfgPath = Join-Path $PSScriptRoot 'config.psd1'
    $cfg = @{}
    if (Test-Path -LiteralPath $cfgPath) {
        try { $cfg = Import-PowerShellDataFile -Path $cfgPath } catch { $cfg = @{} }
    }
    $assetsDir = Join-Path $PSScriptRoot 'assets'

    $sound = $true
    if ($cfg.ContainsKey('Sound')) { $sound = [bool]$cfg.Sound }
    $autoClose = if ($cfg.NotificationAutoCloseSeconds) { [double]$cfg.NotificationAutoCloseSeconds } else { 8 }
    $previewMax = if ($cfg.PreviewMaxChars) { [int]$cfg.PreviewMaxChars } else { 2000 }
    $danger = if ($cfg.DangerPattern) { [string]$cfg.DangerPattern } else {
        '(^|\s)(rm|del|rmdir|rd)\s|Remove-Item|-Recurse|\bformat\b|\bmkfs|dd\s+if=|git\s+push\b.*--force|--force\b|>\s*/dev/|chmod\s+-R|takeown|\bshutdown\b'
    }

    # ----- allowlist 확인 -----
    # settings.json의 permissions.allow와 매칭되는 명령이면 위젯을 띄우지 않는다.
    # Claude Code가 이미 조용히 통과시킬(혹은 서브에이전트가 상속받아 통과시킬) 명령엔
    # 위젯이 끼어들지 않게 해서 "터미널이 실제로 물어볼 때만 위젯도 뜬다"를 맞춘다.
    # settings 파싱이 실패하면 안전하게 $false(=위젯 정상 표시)로 떨어진다.
    function Test-CommandAllowed {
        param([string]$ToolName, [string]$Target)
        if (-not $ToolName -or -not $Target) { return $false }
        try {
            # 후보 settings 파일: 사용자(~/.claude) + 프로젝트(.claude)
            $files = @(Join-Path $env:USERPROFILE '.claude\settings.json')
            $projDir = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR }
            elseif ($data -and $data.cwd) { [string]$data.cwd }
            else { $null }
            if ($projDir) {
                $files += (Join-Path $projDir '.claude\settings.json')
                $files += (Join-Path $projDir '.claude\settings.local.json')
            }

            $rules = @()
            foreach ($f in $files) {
                if (Test-Path -LiteralPath $f) {
                    try {
                        $j = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
                        if ($j.permissions -and $j.permissions.allow) { $rules += $j.permissions.allow }
                    }
                    catch {}
                }
            }

            $t = $Target.Trim()
            foreach ($rule in $rules) {
                # 규칙 형식: "ToolName"  또는  "ToolName(pattern)"
                $m = [regex]::Match([string]$rule, '^\s*([A-Za-z0-9_]+)\s*(?:\((.*)\)\s*)?$')
                if (-not $m.Success) { continue }
                if ($m.Groups[1].Value -ne $ToolName) { continue }
                $pat = $m.Groups[2].Value
                # 패턴이 없거나 '*' 면 도구 전체 허용
                if (-not $m.Groups[2].Success -or $pat -eq '' -or $pat -eq '*') { return $true }
                # glob('*') → 정규식. 그 외 문자는 리터럴로 이스케이프.
                $rx = '^' + ([regex]::Escape($pat) -replace '\\\*', '.*') + '$'
                if ($t -match $rx) { return $true }
            }
        }
        catch { return $false }
        return $false
    }
    # ----- 테마 팔레트 (라이트/다크) -----
    # Mode: 'auto'(시스템 따름) | 'light' | 'dark'
    $mode = if ($cfg.Mode) { [string]$cfg.Mode } else { 'auto' }
    if ($mode -eq 'auto') {
        $isLight = $true
        try {
            $reg = Get-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop
            $isLight = ([int]$reg.AppsUseLightTheme -ne 0)
        }
        catch { $isLight = $true }
    }
    else { $isLight = ($mode -ne 'dark') }

    if ($isLight) {
        $bg = '#FFFFFF'      # 카드 배경
        $fg = '#1B1B1F'      # 본문 (대비 ~16:1)
        $fgMute = '#5B5B66'  # 보조 텍스트 (white 대비 ~5.7:1, AA 통과)
        $subtle = '#14000000'# 미리보기/코드 박스 배경
        $stroke = '#1F000000'# 카드 1px 테두리
        $btnSub = '#12000000'# 보조 버튼 배경
        $accent = if ($cfg.Accent) { [string]$cfg.Accent } else { '#6C4DD6' }  # white 대비 ~5.7:1
        $onAccent = 'White'
        $dngBg = '#C62828'   # 위험 강조 (white 대비 ~5.7:1)
        $warnText = '#B23A00'# 경고 제목 (white 대비 ~4.7:1)
    }
    else {
        $bg = '#2A2A2E'
        $fg = '#F2F2F5'
        $fgMute = '#B7B7C0'
        $subtle = '#1FFFFFFF'
        $stroke = '#26FFFFFF'
        $btnSub = '#24FFFFFF'
        $accent = if ($cfg.AccentDark) { [string]$cfg.AccentDark } else { '#B9A4FF' }  # 어두운 글자와 대비 ~8:1
        $onAccent = '#1A1130'
        $dngBg = '#FF8A8A'
        $warnText = '#FFB36B'
    }

    # =================================================================
    #  헬퍼
    # =================================================================
    function ConvertFrom-Xaml([string]$xaml) {
        $reader = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader $xaml)
        return [Windows.Markup.XamlReader]::Load($reader)
    }

    function Get-VectorCharacterXaml([string]$evt) {
        # 이벤트별 표정/색
        switch ($evt) {
            'Stop' {
                $acc = '#4CAF50'; $badge = [char]0x2713  # ✓
                $mouth = '<Path Stroke="#3A2E22" StrokeThickness="3" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Data="M48,76 Q60,90 72,76"/>'
                $extra = ''
            }
            'Notification' {
                $acc = '#2196F3'; $badge = '!'
                $mouth = '<Ellipse Canvas.Left="55" Canvas.Top="76" Width="10" Height="11" Fill="#3A2E22"/>'
                # 반짝이는 별
                $extra = '<Path Canvas.Left="96" Canvas.Top="20" Data="M6,0 L7.5,4.5 L12,6 L7.5,7.5 L6,12 L4.5,7.5 L0,6 L4.5,4.5 Z" Fill="#FFD54F"/>'
            }
            'PreToolUse' {
                $acc = '#FF8F00'; $badge = '!'
                $mouth = '<Path Stroke="#3A2E22" StrokeThickness="3" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Data="M48,82 Q54,75 60,82 Q66,89 72,82"/>'
                # 땀방울
                $extra = '<Path Canvas.Left="86" Canvas.Top="48" Data="M5,0 C9,6 10,9 5,12 C0,9 1,6 5,0 Z" Fill="#5AB8FF"/>'
            }
            default { $acc = $accent; $badge = ''; $mouth = ''; $extra = '' }
        }

        return @"
<Viewbox xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Stretch="Uniform">
  <Canvas Width="120" Height="120">
    <!-- 귀 -->
    <Polygon Points="30,40 42,12 58,36" Fill="#FFF3E0" Stroke="#E6CBA0" StrokeThickness="2"/>
    <Polygon Points="90,40 78,12 62,36" Fill="#FFF3E0" Stroke="#E6CBA0" StrokeThickness="2"/>
    <Polygon Points="36,34 43,20 50,33" Fill="#FFC1C1"/>
    <Polygon Points="84,34 77,20 70,33" Fill="#FFC1C1"/>
    <!-- 얼굴 -->
    <Ellipse Canvas.Left="20" Canvas.Top="30" Width="80" Height="74" Fill="#FFF3E0" Stroke="#E6CBA0" StrokeThickness="2"/>
    <!-- 볼터치 -->
    <Ellipse Canvas.Left="30" Canvas.Top="68" Width="16" Height="10" Fill="#FFB3B3" Opacity="0.85"/>
    <Ellipse Canvas.Left="74" Canvas.Top="68" Width="16" Height="10" Fill="#FFB3B3" Opacity="0.85"/>
    <!-- 눈 -->
    <Ellipse Canvas.Left="43" Canvas.Top="54" Width="10" Height="12" Fill="#3A2E22"/>
    <Ellipse Canvas.Left="67" Canvas.Top="54" Width="10" Height="12" Fill="#3A2E22"/>
    <Ellipse Canvas.Left="45" Canvas.Top="56" Width="3.5" Height="3.5" Fill="White"/>
    <Ellipse Canvas.Left="69" Canvas.Top="56" Width="3.5" Height="3.5" Fill="White"/>
    <!-- 입 (이벤트별) -->
    $mouth
    $extra
    <!-- 뱃지 -->
    <Border Canvas.Left="80" Canvas.Top="78" Width="30" Height="30" CornerRadius="15" Background="$acc" BorderBrush="White" BorderThickness="2.5">
      <TextBlock Text="$badge" FontSize="16" FontWeight="Bold" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
  </Canvas>
</Viewbox>
"@
    }

    function New-CharacterElement([string]$evt) {
        $png = Join-Path $assetsDir ("{0}.png" -f $evt.ToLower())
        if (Test-Path -LiteralPath $png) {
            try {
                $img = New-Object System.Windows.Controls.Image
                $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
                $bmp.BeginInit()
                $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                $bmp.UriSource = [Uri]$png
                $bmp.EndInit()
                $img.Source = $bmp
                $img.Stretch = [System.Windows.Media.Stretch]::Uniform
                return $img
            }
            catch { }
        }
        return (ConvertFrom-Xaml (Get-VectorCharacterXaml $evt))
    }

    function Get-LastAssistantText([string]$path) {
        if (-not $path -or -not (Test-Path -LiteralPath $path)) { return '' }
        try {
            # 트랜스크립트는 UTF-8. Get-Content 기본(ANSI)으로 읽으면 한글이 깨지므로 UTF-8로 명시.
            $lines = [System.IO.File]::ReadAllLines($path, (New-Object System.Text.UTF8Encoding $false))
            for ($i = $lines.Count - 1; $i -ge 0; $i--) {
                $line = $lines[$i]
                if (-not $line) { continue }
                $obj = $null
                try { $obj = $line | ConvertFrom-Json } catch { continue }
                if ($obj.type -eq 'assistant' -and $obj.message -and $obj.message.content) {
                    $texts = @()
                    foreach ($block in $obj.message.content) {
                        if ($block.type -eq 'text' -and $block.text) { $texts += [string]$block.text }
                    }
                    if ($texts.Count -gt 0) { return ($texts -join "`n").Trim() }
                }
            }
        }
        catch { }
        return ''
    }

    function Play-Cue {
        if ($sound) { try { [System.Media.SystemSounds]::Asterisk.Play() } catch { } }
    }

    function Get-WindowResources {
        return @"
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Foreground" Value="$fg"/>
      <Setter Property="Background" Value="$btnSub"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Padding" Value="12,0"/>
      <Setter Property="SnapsToDevicePixels" Value="True"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" CornerRadius="4" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.88"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.72"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="$accent"/>
      <Setter Property="Foreground" Value="$onAccent"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style x:Key="DangerOutline" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="$dngBg"/>
      <Setter Property="BorderBrush" Value="$dngBg"/>
      <Setter Property="BorderThickness" Value="1"/>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Foreground" Value="$fg"/>
      <Setter Property="CaretBrush" Value="$fg"/>
      <Setter Property="Background" Value="$subtle"/>
      <Setter Property="BorderBrush" Value="$stroke"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="8"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border CornerRadius="4" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
              <ScrollViewer x:Name="PART_ContentHost" Margin="0" Padding="{TemplateBinding Padding}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter Property="BorderBrush" Value="$accent"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
"@
    }

    function Start-Entrance($win) {
        # Windows "애니메이션 표시" 설정(=prefers-reduced-motion)을 존중. 끄면 즉시 표시.
        $animate = $true
        if ($cfg.ContainsKey('Animate')) { $animate = [bool]$cfg.Animate }
        else { try { $animate = [System.Windows.SystemParameters]::ClientAreaAnimation } catch { $animate = $true } }
        if (-not $animate) { $win.Opacity = 1; return }
        $tt = New-Object System.Windows.Media.TranslateTransform
        $win.Content.RenderTransform = $tt
        $dur = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(280))
        $ease = New-Object System.Windows.Media.Animation.CubicEase
        $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
        $fade = New-Object System.Windows.Media.Animation.DoubleAnimation (0, 1, $dur); $fade.EasingFunction = $ease
        $slide = New-Object System.Windows.Media.Animation.DoubleAnimation (28, 0, $dur); $slide.EasingFunction = $ease
        $win.BeginAnimation([System.Windows.Window]::OpacityProperty, $fade)
        $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $slide)
    }

    function Set-CommonWindowBehavior($win, $focusElement) {
        $win.Add_MouseLeftButtonDown({ try { $win.DragMove() } catch { } })
        $win.Add_Loaded({
                $wa = [System.Windows.SystemParameters]::WorkArea
                # 카드 Margin(28)이 화면 모서리와의 여백 역할을 하므로 창은 작업영역에 딱 붙인다.
                $win.Left = $wa.Right - $win.ActualWidth
                $win.Top = $wa.Bottom - $win.ActualHeight
                Start-Entrance $win
                if ($focusElement) { $focusElement.Focus() | Out-Null }
            }.GetNewClosure())
        $win.Topmost = $true
    }

    $res = Get-WindowResources

    # =================================================================
    #  이벤트 분기
    # =================================================================
    switch ($Event) {

        # --------------------------------------------------- Stop
        'Stop' {
            # 매번 위젯 표시(stop_hook_active여도 띄움). 우리 위젯은 사용자가 실제로
            # 입력했을 때만 block하고, 빈 입력/종료 시엔 block하지 않아(= 자연 정지)
            # 무한 루프가 생기지 않는다. Claude Code의 연속 block 상한이 최후 안전망.

            $previewText = Get-LastAssistantText ($data.transcript_path)
            if ($previewMax -gt 0 -and $previewText.Length -gt $previewMax) {
                $previewText = $previewText.Substring(0, $previewMax) + ' …'
            }

            $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" Opacity="0"
        ShowInTaskbar="True" SizeToContent="WidthAndHeight" Title="Claude" FontFamily="Segoe UI Variable, Segoe UI">
$res
  <Border CornerRadius="8" Background="$bg" BorderBrush="$stroke" BorderThickness="1" Padding="16" Margin="28">
    <Border.Effect><DropShadowEffect BlurRadius="40" ShadowDepth="6" Direction="270" Opacity="0.2"/></Border.Effect>
    <Grid Width="600">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <StackPanel Grid.Row="0" Orientation="Horizontal">
        <ContentControl x:Name="CharSlot" Width="84" Height="84" VerticalAlignment="Center"/>
        <StackPanel Margin="12,0,0,0" VerticalAlignment="Center">
          <TextBlock Text="작업을 마쳤어요" FontSize="20" FontWeight="SemiBold" Foreground="$fg"/>
          <TextBlock Text="이어서 지시하거나 종료할 수 있어요" FontSize="12" Foreground="$fgMute" Margin="0,2,0,0"/>
        </StackPanel>
      </StackPanel>
      <Border x:Name="PreviewBox" Grid.Row="1" CornerRadius="4" Background="$subtle" Margin="0,12,0,0" Padding="12" MaxHeight="280">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <TextBlock x:Name="Preview" TextWrapping="Wrap" Foreground="$fgMute" FontSize="14" LineHeight="20"/>
        </ScrollViewer>
      </Border>
      <TextBox x:Name="Input" Grid.Row="2" Margin="0,12,0,0" MinHeight="72" MaxHeight="200"
               TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto"/>
      <TextBlock Grid.Row="3" Text="Ctrl+Enter 이어가기 · Esc 종료" FontSize="12" Foreground="$fgMute" Margin="2,8,0,0"/>
      <StackPanel Grid.Row="4" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
        <Button x:Name="BtnStop" Content="종료" MinWidth="72" Height="32" Margin="0,0,8,0"/>
        <Button x:Name="BtnGo" Content="이어가기" MinWidth="96" Height="32" Style="{StaticResource Primary}"/>
      </StackPanel>
    </Grid>
  </Border>
</Window>
"@
            $win = ConvertFrom-Xaml $xaml
            $win.FindName('CharSlot').Content = New-CharacterElement 'Stop'
            $previewBox = $win.FindName('PreviewBox')
            if ($previewText) { $win.FindName('Preview').Text = $previewText }
            else { $previewBox.Visibility = [System.Windows.Visibility]::Collapsed }
            $inputBox = $win.FindName('Input')

            $script:go = $false
            $win.FindName('BtnGo').Add_Click({ $script:go = $true; $win.Close() })
            $win.FindName('BtnStop').Add_Click({ $script:go = $false; $win.Close() })
            $inputBox.Add_PreviewKeyDown({
                    param($s, $e)
                    if ($e.Key -eq [System.Windows.Input.Key]::Return -and
                        ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
                        $script:go = $true; $e.Handled = $true; $win.Close()
                    }
                    elseif ($e.Key -eq [System.Windows.Input.Key]::Escape) {
                        $script:go = $false; $e.Handled = $true; $win.Close()
                    }
                })

            Set-CommonWindowBehavior $win $inputBox
            Play-Cue
            $null = $win.ShowDialog()

            $text = ([string]$inputBox.Text).Trim()
            if ($script:go -and $text) {
                $out = [ordered]@{ decision = 'block'; reason = $text }
                Write-StdoutUtf8 ($out | ConvertTo-Json -Compress)
            }
            exit 0
        }

        # --------------------------------------------------- Notification
        'Notification' {
            $msg = if ($data -and $data.message) { [string]$data.message } else { 'Claude가 기다리고 있어요.' }
            $ntype = if ($data) { [string]$data.notification_type } else { '' }
            $title = switch ($ntype) {
                'permission_prompt' { '권한이 필요해요' }
                'idle_prompt' { '입력을 기다려요' }
                default { 'Claude 알림' }
            }

            $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" Opacity="0"
        ShowInTaskbar="False" SizeToContent="WidthAndHeight" Title="Claude" FontFamily="Segoe UI Variable, Segoe UI">
$res
  <Border CornerRadius="8" Background="$bg" BorderBrush="$stroke" BorderThickness="1" Padding="16" Margin="28">
    <Border.Effect><DropShadowEffect BlurRadius="40" ShadowDepth="6" Direction="270" Opacity="0.2"/></Border.Effect>
    <StackPanel Orientation="Horizontal" Width="316">
      <ContentControl x:Name="CharSlot" Width="56" Height="56" VerticalAlignment="Center"/>
      <StackPanel Margin="12,0,0,0" Width="248" VerticalAlignment="Center">
        <TextBlock Text="$title" FontSize="16" FontWeight="SemiBold" Foreground="$fg"/>
        <TextBlock x:Name="Msg" TextWrapping="Wrap" Foreground="$fgMute" FontSize="14" LineHeight="20" Margin="0,4,0,0"/>
        <TextBlock Text="클릭하면 닫혀요" FontSize="12" Foreground="$fgMute" Margin="0,6,0,0"/>
      </StackPanel>
    </StackPanel>
  </Border>
</Window>
"@
            $win = ConvertFrom-Xaml $xaml
            $win.FindName('CharSlot').Content = New-CharacterElement 'Notification'
            $win.FindName('Msg').Text = $msg
            $win.Add_MouseLeftButtonUp({ $win.Close() })

            $timer = New-Object System.Windows.Threading.DispatcherTimer
            $timer.Interval = [TimeSpan]::FromSeconds($autoClose)
            $timer.Add_Tick({ $timer.Stop(); $win.Close() })

            $win.Add_MouseLeftButtonDown({ try { $win.DragMove() } catch { } })
            $win.Add_Loaded({
                    $wa = [System.Windows.SystemParameters]::WorkArea
                    $win.Left = $wa.Right - $win.ActualWidth
                    $win.Top = $wa.Bottom - $win.ActualHeight
                    Start-Entrance $win
                    $timer.Start()
                }.GetNewClosure())
            $win.Topmost = $true
            Play-Cue
            $null = $win.ShowDialog()
            exit 0
        }

        # --------------------------------------------------- PreToolUse
        'PreToolUse' {
            # 권한 모드 게이트: auto / bypassPermissions / dontAsk 에선 위젯을 띄우지 않는다.
            #   (auto·bypass = "알아서 진행", dontAsk = 비대화형 자동거부 → 위젯 확인이 무의미/방해.
            #    plan/default/acceptEdits 등에선 띄움)
            #   $data.permission_mode: default | plan | auto | acceptEdits | bypassPermissions | dontAsk
            #   permission_mode 가 없으면(구버전/수동 테스트) 빈 문자열 → skip 안 함(기존대로 표시)
            $pm = if ($data) { [string]$data.permission_mode } else { '' }
            if ($pm -in @('auto', 'bypassPermissions', 'dontAsk')) { exit 0 }
            #   ▶ 다른 조합 예:
            #       default 모드에서만 띄우기:  if ($pm -and $pm -ne 'default') { exit 0 }

            $cmd = ''
            if ($data -and $data.tool_input) {
                if ($data.tool_input.command) { $cmd = [string]$data.tool_input.command }
                elseif ($data.tool_input.file_path) { $cmd = [string]$data.tool_input.file_path }
            }
            $toolName = if ($data) { [string]$data.tool_name } else { 'Bash' }

            # 이미 allowlist로 통과될 명령이면 위젯 안 띄움 (메인/서브에이전트 공통)
            if (Test-CommandAllowed $toolName $cmd) { exit 0 }

            # 위험 패턴이 아니면 위젯 안 띄우고 정상 권한 흐름
            if (-not $cmd -or ($cmd -notmatch $danger)) { exit 0 }

            $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" Opacity="0"
        ShowInTaskbar="True" SizeToContent="WidthAndHeight" Title="Claude" FontFamily="Segoe UI Variable, Segoe UI">
$res
  <Border CornerRadius="8" Background="$bg" BorderBrush="$stroke" BorderThickness="1" Padding="16" Margin="28">
    <Border.Effect><DropShadowEffect BlurRadius="40" ShadowDepth="6" Direction="270" Opacity="0.2"/></Border.Effect>
    <Grid Width="600">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <StackPanel Grid.Row="0" Orientation="Horizontal">
        <ContentControl x:Name="CharSlot" Width="64" Height="64" VerticalAlignment="Center"/>
        <StackPanel Margin="12,0,0,0" VerticalAlignment="Center">
          <TextBlock Text="실행 전 확인이 필요해요" FontSize="20" FontWeight="SemiBold" Foreground="$warnText"/>
          <TextBlock Text="$toolName · 되돌릴 수 없는 작업일 수 있어요" FontSize="12" Foreground="$fgMute" Margin="0,2,0,0"/>
        </StackPanel>
      </StackPanel>
      <Border Grid.Row="1" CornerRadius="4" Background="$subtle" Margin="0,12,0,0" Padding="12" MaxHeight="152">
        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto">
          <TextBlock x:Name="Cmd" TextWrapping="Wrap" Foreground="$fg" FontFamily="Cascadia Mono, Consolas" FontSize="13"/>
        </ScrollViewer>
      </Border>
      <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
        <Button x:Name="BtnAllow" Content="허용" MinWidth="72" Height="32" Margin="0,0,8,0" Style="{StaticResource DangerOutline}"/>
        <Button x:Name="BtnAsk" Content="직접 확인" MinWidth="84" Height="32" Margin="0,0,8,0"/>
        <Button x:Name="BtnDeny" Content="차단" MinWidth="80" Height="32" Style="{StaticResource Primary}"/>
      </StackPanel>
    </Grid>
  </Border>
</Window>
"@
            $win = ConvertFrom-Xaml $xaml
            $win.FindName('CharSlot').Content = New-CharacterElement 'PreToolUse'
            $win.FindName('Cmd').Text = $cmd

            $script:decision = 'ask'   # 창 닫힘/Esc 기본값 = 일반 권한 흐름
            $btnDeny = $win.FindName('BtnDeny')
            $win.FindName('BtnAllow').Add_Click({ $script:decision = 'allow'; $win.Close() })
            $btnDeny.Add_Click({ $script:decision = 'deny'; $win.Close() })
            $win.FindName('BtnAsk').Add_Click({ $script:decision = 'ask'; $win.Close() })
            $win.Add_PreviewKeyDown({
                    param($s, $e)
                    if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $script:decision = 'ask'; $win.Close() }
                })

            # 기본 포커스 = 안전한 '차단'(위험한 '허용'에 두지 않음)
            Set-CommonWindowBehavior $win $btnDeny
            Play-Cue
            $null = $win.ShowDialog()

            if ($script:decision -eq 'allow' -or $script:decision -eq 'deny') {
                $hso = [ordered]@{
                    hookEventName            = 'PreToolUse'
                    permissionDecision       = $script:decision
                    permissionDecisionReason = if ($script:decision -eq 'deny') { '위젯에서 사용자가 거부했습니다.' } else { '위젯에서 사용자가 허용했습니다.' }
                }
                $out = [ordered]@{ hookSpecificOutput = $hso }
                Write-StdoutUtf8 ($out | ConvertTo-Json -Compress -Depth 5)
            }
            # 'ask' → 출력 없음 → 기본 권한 프롬프트
            exit 0
        }
    }
}
catch {
    # 어떤 오류도 Claude를 막지 않도록: 출력 없이 정상 종료
    try { [Console]::Error.WriteLine("claude-widget error: $($_.Exception.Message)") } catch { }
    exit 0
}
