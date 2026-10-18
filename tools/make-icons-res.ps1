# Rebuilds res\icons.res (the toolbar icons) from res\icons.rc and the PNG files in res\icons.
# The program links the precompiled .res, because FPC 3.2.2 passes .rc files to windres
# without quotes, which fails when the project path contains spaces.
#   powershell -ExecutionPolicy Bypass -File tools\make-icons-res.ps1
param([string]$FpcBin = 'C:\lazarus\fpc\3.2.2\bin\x86_64-win64')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
# windres itself cannot cope with spaces either, so work in a temporary folder without any
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('tidytag-res-' + [Guid]::NewGuid().ToString('N'))
if ($tmp -match ' ') { $tmp = "C:\Temp\tidytag-res-$([Guid]::NewGuid().ToString('N'))" }
New-Item -ItemType Directory "$tmp\res" | Out-Null
try {
  Copy-Item "$root\res\icons.rc" "$tmp\res\"
  Copy-Item "$root\res\icons" "$tmp\res\icons" -Recurse
  Push-Location $tmp
  try {
    # the preprocessor FPC itself gives windres (gcc cannot find it on its own)
    & "$FpcBin\windres.exe" "--preprocessor=$FpcBin\cpp.exe" -D FPC -i res/icons.rc -o res/icons.res -O res
    if ($LASTEXITCODE -ne 0) { throw 'windres failed' }
  } finally {
    Pop-Location
  }
  Copy-Item "$tmp\res\icons.res" "$root\res\icons.res" -Force
  Write-Host ("res\icons.res: {0:N0} bytes" -f (Get-Item "$root\res\icons.res").Length)
} finally {
  Remove-Item -Recurse -Force $tmp
}
