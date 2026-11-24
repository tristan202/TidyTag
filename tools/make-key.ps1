# Creates the signing key for TidyTag Companion releases. Run it yourself, once:
#   powershell -ExecutionPolicy Bypass -File tools\make-key.ps1
# It asks for a password and writes %USERPROFILE%\.tidytag\release.jks and release.properties
# (outside the repository), which tools\make-release.ps1 then uses. Back both up: without this
# key and password, updates to an installed app (or one on Google Play) cannot be published.
$ErrorActionPreference = 'Stop'
$dir = "$env:USERPROFILE\.tidytag"
$jks = "$dir\release.jks"
$props = "$dir\release.properties"
if ((Test-Path $jks) -or (Test-Path $props)) {
  throw "$jks or $props exists already. Nothing changed (an existing key is never replaced)."
}
# any JDK's keytool will do: the build-tools JDK, JAVA_HOME, Android Studio's, or one on PATH
$keytool = @("$env:LOCALAPPDATA\TidyTagBuildTools\jdk17\bin\keytool.exe",
  "$env:USERPROFILE\AppData\Local\TidyTagBuildTools\jdk17\bin\keytool.exe",
  "$env:JAVA_HOME\bin\keytool.exe",
  "$env:ProgramFiles\Android\Android Studio\jbr\bin\keytool.exe") |
  Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $keytool) { $keytool = (Get-Command keytool -ErrorAction SilentlyContinue).Source }
if (-not $keytool) { throw 'keytool not found (it comes with Java). Nothing changed.' }
Write-Host "Using $keytool"

function Read-Plain([string]$prompt) {
  $s = Read-Host $prompt -AsSecureString
  [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
}
$pw = Read-Plain 'Password for the key (at least 8 characters)'
if ($pw.Length -lt 8) { throw 'The password is too short.' }
# release.properties is plain ASCII: no letters like æøå
if ($pw -match '[^\x21-\x7E]') { throw 'Use only letters a-z, digits and signs (no spaces or æøå).' }
if ((Read-Plain 'Same password again') -ne $pw) { throw 'The passwords differ. Nothing changed.' }
$name = Read-Host 'Your name as the publisher (shown in the certificate)'
if (-not $name) { $name = 'TidyTag' }

New-Item -ItemType Directory -Force $dir | Out-Null
# the password goes to keytool through the environment, never on the command line
$env:TIDYTAG_KEY_PW = $pw
try {
  & $keytool -genkeypair -keystore $jks -storetype PKCS12 -alias tidytag -keyalg RSA -keysize 4096 `
    -validity 10000 -dname "CN=$($name -replace '[,=+<>#;\\"]', ' '), O=TidyTag Companion" `
    -storepass:env TIDYTAG_KEY_PW -keypass:env TIDYTAG_KEY_PW
  if ($LASTEXITCODE -ne 0) { throw 'keytool failed. Nothing usable was written.' }
} finally {
  Remove-Item Env:TIDYTAG_KEY_PW
}

@"
keystore=$($jks -replace '\\', '/')
storePassword=$pw
keyAlias=tidytag
keyPassword=$pw
"@ | Set-Content -Encoding ascii $props
# only you can read the password file
icacls $props /inheritance:r /grant:r "${env:USERNAME}:F" | Out-Null

Write-Host ''
Write-Host "Key created: $jks"
Write-Host "Settings:    $props"
Write-Host 'Back up both files (and the password) somewhere safe, e.g. a USB stick or a password manager.'
Write-Host 'tools\make-release.ps1 now signs TidyTag-Companion-<version>.apk with this key.'
