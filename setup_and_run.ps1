# =============================================================
#  追剧记录 App —— 补齐平台目录 + 拉依赖 + 生成 drift 代码 + 静态检查
#  前置：已运行 install_toolchain.ps1，且重开过终端（flutter 在 PATH 里）
#  用法：PowerShell 中  Set-ExecutionPolicy -Scope Process Bypass
#                       .\setup_and_run.ps1
#  可重复运行，已完成的步骤会跳过。
# =============================================================

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Definition
$proj = Join-Path $root 'tracker'

function Say($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Ok($msg)  { Write-Host "  [OK] $msg" -ForegroundColor Green }

# ---------- 0. 环境检查 ----------
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Host '未找到 flutter 命令。请先运行 install_toolchain.ps1，然后重开终端。' -ForegroundColor Red
    exit 1
}
Say 'Flutter 版本'
flutter --version

# Windows 桌面端默认可能未开启
flutter config --enable-windows-desktop 2>&1 | Out-Null

# ---------- 1. 补齐平台目录 ----------
# 仓库里只提交了 lib/ 与 pubspec.yaml，android/ windows/ 等由本机 flutter 模板生成。
if (Test-Path (Join-Path $proj 'android')) {
    Write-Host '  [跳过] 平台目录已存在' -ForegroundColor DarkGray
} else {
    Say '生成 android / windows 平台脚手架'
    $tmp = Join-Path $env:TEMP 'tracker_scaffold'
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }

    flutter create --project-name tracker --org com.haku --platforms=android,windows $tmp
    if ($LASTEXITCODE -ne 0) { throw 'flutter create 失败，请检查上面的报错' }

    foreach ($d in @('android', 'windows')) {
        Copy-Item (Join-Path $tmp $d) (Join-Path $proj $d) -Recurse -Force
    }
    foreach ($f in @('.metadata', 'analysis_options.yaml', '.gitignore')) {
        $src = Join-Path $tmp $f
        if (Test-Path $src) { Copy-Item $src (Join-Path $proj $f) -Force }
    }
    Remove-Item $tmp -Recurse -Force
    Ok '平台脚手架已就位'
}

Set-Location $proj

# ---------- 2. 依赖 ----------
Say 'flutter pub get'
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'pub get 失败，多为网络或镜像问题' }

# ---------- 3. 生成 drift 代码 ----------
Say '生成 database.g.dart'
if (Get-Command dart -ErrorAction SilentlyContinue) {
    dart run build_runner build --delete-conflicting-outputs
} else {
    flutter pub run build_runner build --delete-conflicting-outputs
}
if ($LASTEXITCODE -ne 0) { throw 'drift 代码生成失败' }

$generated = Join-Path $proj 'lib\data\db\database.g.dart'
if (-not (Test-Path $generated)) { throw "未生成 $generated" }
Ok 'database.g.dart 已生成'

# ---------- 4. 静态检查 ----------
Say 'flutter analyze'
flutter analyze

# ---------- 完成 ----------
Write-Host @"

------------------------------------------------------------
环境已就绪。运行方式：

  桌面（需 VS 2022 / "使用 C++ 的桌面开发" 工作负载）：
    cd $proj
    flutter run -d windows

  手机（开 USB 调试并授权）：
    flutter run

  只编译 APK 不安装：
    flutter build apk --debug
------------------------------------------------------------
"@ -ForegroundColor Yellow
