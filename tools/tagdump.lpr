program TagDump;

{ Console test tool: prints what the tag readers find.
  Usage: tagdump <folder-or-file> [-r]   (-r = include subfolders) }

{$mode objfpc}{$H+}

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  Classes, SysUtils, AudioTypes, AudioTags, TagUtils;

procedure Dump(const FileName: string);
var
  Info: TAudioInfo;
  F: TTagField;
begin
  Info := ReadAudioInfo(FileName);
  try
    WriteLn('== ', FileName);
    if Info.Error <> '' then WriteLn('   FEJL: ', Info.Error);
    if not Info.Supported then WriteLn('   (format ikke understøttet endnu)');
    WriteLn(Format('   %s | %s | %d kbit/s | %d Hz | %d kanaler | tags: %s | cover: %s',
      [Info.Codec, FormatDuration(Info.Duration), Info.Bitrate, Info.SampleRate,
       Info.Channels, Info.TagTypes, BoolToStr(Info.HasCover, 'ja', 'nej')]));
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
begin
  // Make RTL file APIs and string conversions use UTF-8, like an LCL program does.
  SetMultiByteConversionCodePage(CP_UTF8);
  SetMultiByteFileSystemCodePage(CP_UTF8);
  {$IFDEF WINDOWS}SetConsoleOutputCP(CP_UTF8);{$ENDIF}
  SetTextCodePage(Output, CP_UTF8);
  if ParamCount < 1 then
  begin
    WriteLn('Brug: tagdump <mappe-eller-fil> [-r]');
    Halt(1);
  end;
  Target := UTF8Encode(UnicodeString(ParamStr(1)));
  if DirectoryExists(Target) then
    Walk(Target, (ParamCount > 1) and (ParamStr(2) = '-r'))
  else
    Dump(Target);
end.
