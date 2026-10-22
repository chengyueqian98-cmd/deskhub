# Windows 上一条命令出安装包：测试 → 检查英文 → 发布单文件 exe → 打绿色版 zip → 打安装包。
# 用法（在 windows 目录）：powershell -ExecutionPolicy Bypass -File scripts\build.ps1 [-Version 0.5.1]
param([string]$Version = "")
$ErrorActionPreference = "Stop"
$env:PYTHONIOENCODING = "utf-8"
Set-Location (Split-Path $PSScriptRoot -Parent)
if (-not $Version) { $Version = ([xml](Get-Content DeskHub/DeskHub.csproj)).Project.PropertyGroup.Version | Select-Object -First 1 }
Write-Host "== DeskHub $Version =="

dotnet run --project DeskHub.Tests -c Release
if ($LASTEXITCODE) { throw "测试没通过" }
python scripts/gen-strings.py --check
if ($LASTEXITCODE) { throw "英文对照表不全" }

if (Test-Path out) { Remove-Item out -Recurse -Force }
dotnet publish DeskHub/DeskHub.csproj -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true `
  -p:DebugType=none -p:Version=$Version -o out/DeskHub
if ($LASTEXITCODE) { throw "发布失败" }

Compress-Archive -Path out/DeskHub/DeskHub.exe -DestinationPath "out/DeskHub-Windows-$Version-portable.zip" -Force

$iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $iscc)) { choco install innosetup -y --no-progress | Out-Null }
& $iscc "/DAppVersion=$Version" installer/DeskHub.iss
if ($LASTEXITCODE) { throw "安装包打包失败" }
Get-ChildItem out -File | Format-Table Name, Length
