<#
  Builds the test corpus for TidyTag 2's golden test in %TEMP%\tidytag-corpus:
    files\         copies of at most 3 files per audio extension from the given sources,
                   plus one "rich" copy per extension with every field written by 1.2's tagset
    expected.jsonl what 1.2's tagdump --json reads from them
  The sources are only read. Run from the repo root after building bin\tagdump.exe and
  bin\tagset.exe:
    powershell -File tools\make-corpus.ps1 -Source C:\some\folder, D:\other\file.flac
  Then: $env:TIDYTAG_CORPUS = "$env:TEMP\tidytag-corpus"; cargo test -p tidytag-core --test golden
#>
param(
  [Parameter(Mandatory = $true)][string[]]$Source,
  [string]$Target = (Join-Path $env:TEMP 'tidytag-corpus'),
  [int]$PerExt = 3
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$tagdump = Join-Path $repo 'bin\tagdump.exe'
$tagset = Join-Path $repo 'bin\tagset.exe'
foreach ($t in $tagdump, $tagset) { if (-not (Test-Path $t)) { throw "Missing $t - build the Pascal tools first" } }

# never write into the user's music
$full = [IO.Path]::GetFullPath($Target)
$music = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE 'Music'))
if ($full.StartsWith($music, 'OrdinalIgnoreCase') -or $full -match '^[Dd]:') { throw "Refusing target $full" }

$exts = '.mp3', '.flac', '.ogg', '.oga', '.opus', '.m4a', '.m4b', '.mp4', '.wav', '.aif', '.aiff',
        '.aifc', '.ape', '.wv', '.mpc', '.ofr', '.wma', '.asf'
$files = Join-Path $full 'files'
if (Test-Path $full) { Remove-Item -Recurse -Force $full }
New-Item -ItemType Directory -Force $files | Out-Null

$count = @{}
foreach ($src in $Source) {
  $items = if (Test-Path $src -PathType Leaf) { Get-Item -LiteralPath $src }
           else { Get-ChildItem -LiteralPath $src -Recurse -File -ErrorAction SilentlyContinue }
  foreach ($f in $items) {
    $e = $f.Extension.ToLower()
    if ($exts -notcontains $e) { continue }
    if ($count[$e] -ge $PerExt) { continue }
    $count[$e] = 1 + $count[$e]
    # ASCII names: 1.2's console tools take ANSI command lines
    Copy-Item -LiteralPath $f.FullName (Join-Path $files ("{0}-{1}{2}" -f $e.TrimStart('.'), $count[$e], $e))
  }
  if ($count.Count -eq $exts.Count -and ($count.Values | Where-Object { $_ -lt $PerExt }).Count -eq 0) { break }
}

# one rich copy per extension: every field, non-ASCII text (within the ANSI code page),
# long lyrics, flags and ReplayGain values
$lyrics = ('Linje med æøå og ÆØÅ — ' * 230).Substring(0, 5000)
foreach ($e in $count.Keys) {
  $src = Join-Path $files ("{0}-1{1}" -f $e.TrimStart('.'), $e)
  $dst = Join-Path $files ("rich-{0}{1}" -f $e.TrimStart('.'), $e)
  Copy-Item -LiteralPath $src $dst
  $out = & $tagset $dst 'title=Ægir — Øl' 'artist=Kim Larsen' 'album=Midt om natten' 'year=1983' `
    'track=2/12' 'disc=1/2' 'genre=Rock' 'comment=En kommentar' 'albumartist=Kim Larsen & Bellami' `
    'composer=Kim Larsen' 'bpm=120' "lyrics=$lyrics" 'conductor=Dirigent' 'lyricist=Tekst' `
    'origartist=Oprindelig' 'remixer=Remix' 'label=Medley' 'catalog=CAT-1' 'isrc=DKABC8300001' `
    'copyright=© 1983' 'encodedby=TidyTag' 'url=https://example.org' 'grouping=Gruppe' `
    'subtitle=Undertitel' 'mood=Glad' 'key=Am' 'sorttitle=Aegir' 'sortartist=Larsen, Kim' `
    'sortalbumartist=Larsen, Kim' 'sortalbum=Midt' 'sortcomposer=Larsen' 'compilation=1' `
    'replaygain_track_gain=-6.52 dB' 'replaygain_track_peak=0.988553' `
    'replaygain_album_gain=-7.10 dB' 'replaygain_album_peak=1.000000'
  if ($LASTEXITCODE -ne 0) { Write-Warning "tagset failed on $dst : $out"; Remove-Item $dst }
}

$expected = Join-Path $full 'expected.jsonl'
$json = & $tagdump --json $files -r
[IO.File]::WriteAllLines($expected, [string[]]$json, (New-Object Text.UTF8Encoding $false))
"{0} files, {1} records -> {2}" -f (Get-ChildItem $files -File).Count, $json.Count, $expected
$count.GetEnumerator() | Sort-Object Name | ForEach-Object { "  {0}: {1}" -f $_.Name, $_.Value }
