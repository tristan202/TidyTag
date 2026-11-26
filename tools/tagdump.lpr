program TagDump;

{ Console test tool: prints what the tag readers find.
  Usage: tagdump [--json] <folder-or-file> [-r]   (-r = include subfolders)
  --json prints one JSON record per file (with picture data read), the format TidyTag 2's
  Rust tagdump writes too, so the two can be compared. }

{$mode objfpc}{$H+}

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  Classes, SysUtils, Math, fpjson, AudioTypes, AudioTags, TagUtils;

const
  { Same keys and order as TTagField, shared with TidyTag 2. }
  FieldKeys: array[TTagField] of string = ('title', 'artist', 'album', 'year', 'track', 'disc',
    'genre', 'comment', 'albumArtist', 'composer', 'bpm', 'lyrics', 'conductor', 'lyricist',
    'origArtist', 'remixer', 'publisher', 'catalogNo', 'isrc', 'copyright', 'encodedBy', 'url',
    'grouping', 'subtitle', 'mood', 'initialKey', 'sortTitle', 'sortArtist', 'sortAlbumArtist',
    'sortAlbum', 'sortComposer', 'compilation', 'podcast', 'rgTrackGain', 'rgTrackPeak',
    'rgAlbumGain', 'rgAlbumPeak');

var
  Json: Boolean = False;

procedure DumpJson(const FileName: string);
var
  Info: TAudioInfo;
  F: TTagField;
  O, Fields, P: TJSONObject;
  Pics: TJSONArray;
  I: Integer;
begin
  Info := ReadAudioInfo(FileName, True);
  O := TJSONObject.Create;
  try
    O.Add('file', FileName);
    O.Add('fileSize', Info.FileSize);
    O.Add('supported', Info.Supported);
    O.Add('error', Info.Error);
    O.Add('codec', Info.Codec);
    O.Add('tagTypes', Info.TagTypes);
    O.Add('hasCover', Info.HasCover);
    O.Add('durationMs', Int64(Round(Info.Duration * 1000)));
    O.Add('bitrate', Info.Bitrate);
    O.Add('sampleRate', Info.SampleRate);
    O.Add('channels', Info.Channels);
    O.Add('bitDepth', Info.BitDepth);
    Fields := TJSONObject.Create;
    for F := Low(TTagField) to High(TTagField) do
      if Info.Fields[F] <> '' then Fields.Add(FieldKeys[F], Info.Fields[F]);
    O.Add('fields', Fields);
    Pics := TJSONArray.Create;
    for I := 0 to High(Info.Pictures) do
    begin
      P := TJSONObject.Create;
      P.Add('type', Info.Pictures[I].PicType);
      P.Add('mime', Info.Pictures[I].MimeType);
      P.Add('description', Info.Pictures[I].Description);
      P.Add('size', Length(Info.Pictures[I].Data));
      Pics.Add(P);
    end;
    O.Add('pictures', Pics);
    WriteLn(O.AsJSON);
  finally
    O.Free;
    Info.Free;
  end;
end;

procedure Dump(const FileName: string);
var
  Info: TAudioInfo;
  F: TTagField;
begin
  if Json then begin DumpJson(FileName); Exit; end;
  Info := ReadAudioInfo(FileName);
  try
    WriteLn('== ', FileName);
    if Info.Error <> '' then WriteLn('   FEJL: ', Info.Error);
    if not Info.Supported then WriteLn('   (format ikke understøttet endnu)');
    WriteLn(Format('   %s | %s | %d kbit/s | %d Hz | %d kanaler | %d bit | tags: %s | cover: %s',
      [Info.Codec, FormatDuration(Info.Duration), Info.Bitrate, Info.SampleRate,
       Info.Channels, Info.BitDepth, Info.TagTypes, BoolToStr(Info.HasCover, 'ja', 'nej')]));
    for F := Low(TTagField) to High(TTagField) do
      if Info.Fields[F] <> '' then
        WriteLn('   ', TagFieldCaptions[F], ': ', Info.Fields[F]);
  finally
    Info.Free;
  end;
end;

procedure Walk(const Dir: string; Recursive: Boolean);
var
  SR: TSearchRec;
  Files, Dirs: TStringList;
  I: Integer;
begin
  Files := TStringList.Create;
  Dirs := TStringList.Create;
  try
    if FindFirst(IncludeTrailingPathDelimiter(Dir) + '*', faAnyFile, SR) = 0 then
    begin
      repeat
        if (SR.Name = '.') or (SR.Name = '..') then Continue;
        if SR.Attr and faDirectory <> 0 then
          Dirs.Add(IncludeTrailingPathDelimiter(Dir) + SR.Name)
        else if IsAudioFile(SR.Name) then
          Files.Add(IncludeTrailingPathDelimiter(Dir) + SR.Name);
      until FindNext(SR) <> 0;
      FindClose(SR);
    end;
    Files.Sort;
    for I := 0 to Files.Count - 1 do Dump(Files[I]);
    if Recursive then
      for I := 0 to Dirs.Count - 1 do Walk(Dirs[I], True);
  finally
    Files.Free;
    Dirs.Free;
  end;
end;

var
  Target: string;
  Recursive: Boolean = False;
  I: Integer;
begin
  // Make RTL file APIs and string conversions use UTF-8, like an LCL program does.
  SetMultiByteConversionCodePage(CP_UTF8);
  SetMultiByteFileSystemCodePage(CP_UTF8);
  {$IFDEF WINDOWS}SetConsoleOutputCP(CP_UTF8);{$ENDIF}
  SetTextCodePage(Output, CP_UTF8);
  Target := '';
  for I := 1 to ParamCount do
    if ParamStr(I) = '--json' then Json := True
    else if ParamStr(I) = '-r' then Recursive := True
    else Target := UTF8Encode(UnicodeString(ParamStr(I)));
  if Target = '' then
  begin
    WriteLn('Brug: tagdump [--json] <mappe-eller-fil> [-r]');
    Halt(1);
  end;
  if DirectoryExists(Target) then
    Walk(Target, Recursive)
  else
    Dump(Target);
end.
