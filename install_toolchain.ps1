# =============================================================
#  追剧记录 App —— Flutter / Android 工具链一键安装
#  用法：右键“使用 PowerShell 运行”，或在 PowerShell 中执行
#        Set-ExecutionPolicy -Scope Process Bypass
#        .\install_toolchain.ps1
#  全程约 3-5 GB，取决于网络。可重复运行，已完成的步骤会跳过。
# =============================================================

$ErrorActionPreference = 'Stop'

# 任何致命错误都打印原因并暂停，避免双击运行时窗口一闪而过看不到报错。
trap {
    Write-Host "`n[致命错误] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "脚本异常终止。建议：在 PowerShell 里先执行  Set-ExecutionPolicy -Scope Process Bypass  再重跑本脚本。" -ForegroundColor Yellow
    Write-Host '按任意键退出...' -ForegroundColor DarkGray
    [void][System.Console]::ReadKey()
    exit 1
}

Write-Host '== 安装脚本已启动，请勿关闭窗口 ==' -ForegroundColor Cyan

$DEV      = 'D:\software\DEV'
$FLUTTER  = Join-Path $DEV 'flutter'
$JDK      = Join-Path $DEV 'jdk17'
$ANDROID  = Join-Path $DEV 'android-sdk'
$TMP      = Join-Path $DEV 'downloads'

$FLUTTER_VER = '3.47.4'
$FLUTTER_URL = "https://mirrors.cloud.tencent.com/flutter/flutter_infra_release/releases/stable/windows/flutter_windows_$FLUTTER_VER-stable.zip"
$JDK_URL     = 'https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse'
$CMDTOOLS    = 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip'

function Say($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Ok($msg)  { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Skip($msg){ Write-Host "  [跳过] $msg" -ForegroundColor DarkGray }

function Get-File($url, $out) {
    if (Test-Path $out) { Skip "已存在 $(Split-Path $out -Leaf)"; return }
    Say "下载 $(Split-Path $out -Leaf)"
    Write-Host "  $url" -ForegroundColor DarkGray
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -TimeoutSec 3600
        Ok "完成 $([math]::Round((Get-Item $out).Length/1MB)) MB"
    } catch {
        Write-Host "  [失败] $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  可手动下载后放到 $out ，再重新运行本脚本" -ForegroundColor Yellow
        throw
    }
}

New-Item -ItemType Directory -Force -Path $DEV, $TMP | Out-Null

# ---------- 1. Flutter SDK ----------
if (Test-Path (Join-Path $FLUTTER 'bin\flutter.bat')) {
    Skip "Flutter 已安装在 $FLUTTER"
} else {
    Say '1/5 安装 Flutter SDK'
    $zip = Join-Path $TMP 'flutter.zip'
    Get-File $FLUTTER_URL $zip
    Say '解压 Flutter（约 3 分钟）'
    Expand-Archive -Path $zip -DestinationPath $DEV -Force
    Remove-Item $zip -Force
    Ok 'Flutter 解压完成'
}

# ---------- 2. JDK 17 ----------
if (Test-Path (Join-Path $JDK 'bin\java.exe')) {
    Skip "JDK 已安装在 $JDK"
} else {
    Say '2/5 安装 JDK 17'
    $zip = Join-Path $TMP 'jdk17.zip'
    Get-File $JDK_URL $zip
    Expand-Archive -Path $zip -DestinationPath $TMP -Force
    $inner = Get-ChildItem -Path $TMP -Directory -Filter 'jdk-17*' | Select-Object -First 1
    if (-not $inner) { throw 'JDK 解压后未找到 jdk-17* 目录' }
    if (Test-Path $JDK) { Remove-Item $JDK -Recurse -Force }
    Move-Item $inner.FullName $JDK
    Remove-Item $zip -Force
    Ok 'JDK 17 安装完成'
}

# ---------- 3. Android SDK ----------
$cmdline = Join-Path $ANDROID 'cmdline-tools\latest\bin\sdkmanager.bat'
if (Test-Path $cmdline) {
    Skip 'Android cmdline-tools 已安装'
} else {
    Say '3/5 安装 Android cmdline-tools'
    $zip = Join-Path $TMP 'cmdtools.zip'
    Get-File $CMDTOOLS $zip
    $extract = Join-Path $TMP 'cmdtools'
    Expand-Archive -Path $zip -DestinationPath $extract -Force
    $dest = Join-Path $ANDROID 'cmdline-tools\latest'
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item (Join-Path $extract 'cmdline-tools\*') $dest -Recurse -Force
    Remove-Item $zip, $extract -Recurse -Force
    Ok 'cmdline-tools 安装完成'
}

# ---------- 4. Android 平台组件 ----------
Say '4/5 安装 Android 平台与构建工具（首次较慢）'
$env:JAVA_HOME = $JDK
$env:ANDROID_HOME = $ANDROID
$env:ANDROID_SDK_ROOT = $ANDROID

cmd /c "`"$cmdline`" --sdk_root=$ANDROID --licenses < nul" 2>&1 | Out-Null
# Flutter 3.47 要求 Android SDK 36（doctor 会检查），build-tools 下限是 28.0.3
& $cmdline --sdk_root=$ANDROID 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0'
if ($LASTEXITCODE -ne 0) { Write-Host '  [警告] sdkmanager 返回非零，可稍后手动重试' -ForegroundColor Yellow } else { Ok 'Android 组件安装完成' }

# ---------- 5. 环境变量 ----------
Say '5/5 配置环境变量（用户级，需重开终端生效）'
$pathsToAdd = @(
    (Join-Path $FLUTTER 'bin'),
    (Join-Path $ANDROID 'platform-tools')
)
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
foreach ($p in $pathsToAdd) {
    if ($userPath -notlike "*$p*") { $userPath = "$userPath;$p" }
}
[Environment]::SetEnvironmentVariable('Path', $userPath, 'User')
[Environment]::SetEnvironmentVariable('ANDROID_HOME', $ANDROID, 'User')
[Environment]::SetEnvironmentVariable('ANDROID_SDK_ROOT', $ANDROID, 'User')
[Environment]::SetEnvironmentVariable('JAVA_HOME', $JDK, 'User')
# Flutter 中国镜像，加速 pub get
[Environment]::SetEnvironmentVariable('PUB_HOSTED_URL', 'https://pub.flutter-io.cn', 'User')
[Environment]::SetEnvironmentVariable('FLUTTER_STORAGE_BASE_URL', 'https://storage.flutter-io.cn', 'User')
Ok '环境变量已写入'

# ---------- 完成 ----------
$env:Path = "$(Join-Path $FLUTTER 'bin');" + $env:Path
Say '安装完成，正在校验环境'
& (Join-Path $FLUTTER 'bin\flutter.bat') --version
Write-Host @"

------------------------------------------------------------
下一步：
  1. 重新打开一个 PowerShell / 终端
  2. cd D:\Users\haku\WorkBuddy\2026-09-10-21-52-45\tracker
  3. flutter pub get
  4. flutter run -d windows      （先在电脑上跑起来）
  5. 手机开 USB 调试后：flutter run
------------------------------------------------------------
"@ -ForegroundColor Yellow

Write-Host ''
Write-Host '按任意键退出...' -ForegroundColor DarkGray
[void][System.Console]::ReadKey()
