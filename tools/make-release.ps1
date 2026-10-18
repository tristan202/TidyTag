# Builds a TidyTag release: optimized exe, Inno Setup installer and a portable zip in release\.
# The version comes from TidyTag.lpi (Project Options > Version Info, ProductVersion).
#   powershell -ExecutionPolicy Bypass -File tools\make-release.ps1
param(
  [string]$Lazbuild = 'C:\lazarus\lazbuild.exe',
  [string]$Iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

[xml]$lpi = Get-Content "$root\TidyTag.lpi"
$vi = $lpi.CONFIG.ProjectOptions.VersionInfo
$version = $vi.StringTable.ProductVersion
if (-not $version) { throw 'No ProductVersion in TidyTag.lpi' }
$nums = @([int]$vi.MajorVersionNr.Value, [int]$vi.MinorVersionNr.Value, [int]$vi.RevisionNr.Value)
if (($nums -join '.') -ne $version) {
  throw "TidyTag.lpi: ProductVersion $version does not match the version numbers $($nums -join '.')"
}
Write-Host "TidyTag $version"

if (Get-Process TidyTag -ErrorAction SilentlyContinue) { throw 'Close TidyTag first (the exe is rebuilt).' }

Write-Host '== Release build'
& $Lazbuild --build-mode=Release TidyTag.lpi | Select-String -Pattern 'Error|Fatal|Linking'
if ($LASTEXITCODE -ne 0) { throw 'lazbuild failed' }
$exe = Get-Item "$root\bin\TidyTag.exe"
if ($exe.VersionInfo.ProductVersion -ne $version) { throw "bin\TidyTag.exe reports version $($exe.VersionInfo.ProductVersion)" }

$out = "$root\release"
New-Item -ItemType Directory -Force $out | Out-Null

Write-Host '== Installer'
if (-not (Test-Path $Iscc)) { throw "Inno Setup not found: $Iscc" }
& $Iscc /Q "/DAppVersion=$version" "$root\installer\tidytag.iss"
if ($LASTEXITCODE -ne 0) { throw 'ISCC failed' }

Write-Host '== Portable zip'
$stage = "$out\TidyTag-$version-portable"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory "$stage\languages" | Out-Null
Copy-Item $exe.FullName $stage
Copy-Item "$root\languages\*.po" "$stage\languages"
Copy-Item "$root\LICENSE" "$stage\LICENSE.txt"
Copy-Item "$root\README.md" $stage
$zip = "$out\TidyTag-$version-portable.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path "$stage\*" -DestinationPath $zip
Remove-Item -Recurse -Force $stage

Write-Host '== Files (SHA-256 for the release notes)'
foreach ($f in "$out\TidyTag-$version-setup.exe", $zip) {
  $h = (Get-FileHash $f -Algorithm SHA256).Hash.ToLower()
  '{0}  {1:N0} KB  {2}' -f (Split-Path -Leaf $f), ((Get-Item $f).Length / 1KB), $h
}
