$ErrorActionPreference = 'Stop'

$Project = 'D:\project\AlistClientN'
$OutDir  = 'F:\apk'
$Abi     = 'arm64-v8a'
$Flutter = 'D:\flutter\bin\flutter.bat'

# 1) 编译（用 & 而不是 Start-Process：会等结束，且能拿到退出码）
Push-Location $Project
try {
    & $Flutter build apk --target-platform android-arm64 --release --split-per-abi
    $code = $LASTEXITCODE
} finally {
    Pop-Location
}
if ($code -ne 0) { throw "flutter build 失败，退出码 $code" }

# 2) 定位产物
$src = Join-Path $Project "build\app\outputs\flutter-apk\app-$Abi-release.apk"
if (-not (Test-Path -LiteralPath $src)) { throw "找不到 APK 产物：$src" }

# 3) 版本后缀：优先取 pubspec 的 version，取不到就用时间戳
$ver = ''
$pubspec = Join-Path $Project 'pubspec.yaml'
if (Test-Path -LiteralPath $pubspec) {
    $m = Select-String -LiteralPath $pubspec -Pattern '^\s*version:\s*(\S+)' | Select-Object -First 1
    if ($m) { $ver = '-v' + ($m.Matches[0].Groups[1].Value -replace '\+', '_') }
}
if (-not $ver) { $ver = '-' + (Get-Date -Format 'yyyyMMdd-HHmm') }

# 4) 拷到 F:\apk
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$dst = Join-Path $OutDir ("AlistClientN$ver-$Abi.apk")
Copy-Item -LiteralPath $src -Destination $dst -Force

$size = [math]::Round((Get-Item -LiteralPath $dst).Length / 1MB, 2)
Write-Host "[OK] $dst  ($size MB)" -ForegroundColor Green
