<#
  What TidyTag 1.2's rename engine makes of the corpus, for TidyTag 2's rename cross-check
  (core\tests\golden_rename.rs). For every file in %TEMP%\tidytag-corpus\files (made by
  make-corpus.ps1), 1.2's bin\renamedump.exe writes its lines; they go to rename.jsonl as
  {"file": <name>, ...case}.
    powershell -File tools\make-rename-corpus.ps1
#>
param([string]$Corpus = (Join-Path $env:TEMP 'tidytag-corpus'))
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$dump = Join-Path $repo 'bin\renamedump.exe'
if (-not (Test-Path $dump)) { throw "Missing $dump - build the Pascal tools first" }
$full = [IO.Path]::GetFullPath($Corpus)
$out = Join-Path $full 'rename.jsonl'
$lines = New-Object Collections.Generic.List[string]
[Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
foreach ($f in Get-ChildItem (Join-Path $full 'files') -File) {
  foreach ($l in (& $dump $f.FullName)) {
    $name = $f.Name.Replace('\', '\\').Replace('"', '\"')
    $lines.Add('{ "file" : "' + $name + '", ' + $l.TrimStart().Substring(1).TrimStart())
  }
}
[IO.File]::WriteAllLines($out, $lines, (New-Object Text.UTF8Encoding $false))
"$($lines.Count) lines -> $out"
