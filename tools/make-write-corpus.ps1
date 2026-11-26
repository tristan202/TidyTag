<#
  What TidyTag 1.2 writes, for TidyTag 2's write cross-check (core\tests\golden_write.rs).
  For every file in %TEMP%\tidytag-corpus\files (made by make-corpus.ps1) a copy goes through
  tagtest's scenarios 0, 1 and 2 in order with 1.2's bin\tagset.exe --scenario N. After each
  step the copy is kept as written\<name>.s<N>, or tagset's error text as written\<name>.s<N>.err.
    powershell -File tools\make-write-corpus.ps1
#>
param([string]$Corpus = (Join-Path $env:TEMP 'tidytag-corpus'))
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$tagset = Join-Path $repo 'bin\tagset.exe'
if (-not (Test-Path $tagset)) { throw "Missing $tagset - build the Pascal tools first" }
$full = [IO.Path]::GetFullPath($Corpus)
$music = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE 'Music'))
if ($full.StartsWith($music, 'OrdinalIgnoreCase') -or $full -match '^[Dd]:') { throw "Refusing $full" }

$files = Join-Path $full 'files'
$out = Join-Path $full 'written'
if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force $out | Out-Null
$work = Join-Path $out '_work'
New-Item -ItemType Directory -Force $work | Out-Null

$n = 0
foreach ($f in Get-ChildItem $files -File) {
  $copy = Join-Path $work $f.Name
  Copy-Item -LiteralPath $f.FullName $copy
  foreach ($s in 0, 1, 2) {
    $msg = & $tagset --scenario $s $copy 2>&1 | Out-String
    $target = Join-Path $out ("{0}.s{1}" -f $f.Name, $s)
    if ($LASTEXITCODE -eq 0) { Copy-Item -LiteralPath $copy $target }
    else { [IO.File]::WriteAllText("$target.err", ($msg.Trim() -replace '^FEJL: ', ''), (New-Object Text.UTF8Encoding $false)) }
  }
  $n++
}
Remove-Item -Recurse -Force $work
$errs = (Get-ChildItem $out -Filter *.err).Count
"$n files, $errs errors -> $out"
