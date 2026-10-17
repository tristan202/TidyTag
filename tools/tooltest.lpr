program ToolTest;

{ Tests for the tag tools: artist name tools, the album artist rule and ID3v1/ID3v2
  synchronisation. The sync test works on a COPY of an MP3 file:
    tooltest <test-folder> <file.mp3> }

{$mode objfpc}{$H+}

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  Classes, SysUtils, AudioTypes, AudioTags, TagWriter, FieldTools, ID3Sync, ID3Writer,
  TagRemove, Mp3Reader;

var
  Failures: Integer = 0;

procedure Check(Cond: Boolean; const What: string);
begin
  if Cond then
    WriteLn('ok   ', What)
  else
  begin
    WriteLn('FEJL ', What);
    Inc(Failures);
  end;
end;

procedure Eq(const Got, Expected, What: string);
begin
  Check(Got = Expected, Format('%s: "%s"%s', [What, Got,
    BoolToStr(Got = Expected, '', ' (forventet "' + Expected + '")')]));
end;

procedure TestNames;
begin
  WriteLn('-- kunstner-værktøjer');
  Eq(ApplyNameTool('The Beatles', ntRemoveThe), 'Beatles', 'fjern The');
  Eq(ApplyNameTool('Theatre of Tragedy', ntRemoveThe), 'Theatre of Tragedy', 'The kun som helt ord');
  Eq(ApplyNameTool('The Beatles; The Who', ntTheToEnd), 'Beatles, The; Who, The', 'The bagud, flere kunstnere');
  Eq(ApplyNameTool('Beatles, The', ntTheToFront), 'The Beatles', 'The forrest');
  Eq(ApplyNameTool('Carl Nielsen', ntNameToSurnameFirst), 'Nielsen, Carl', 'efternavn først');
  Eq(ApplyNameTool('Johann Sebastian Bach', ntNameToSurnameFirst), 'Bach, Johann Sebastian', 'flere fornavne');
  Eq(ApplyNameTool('Madonna', ntNameToSurnameFirst), 'Madonna', 'ét navn uændret');
  Eq(ApplyNameTool('Nielsen, Carl', ntSurnameFirstToName), 'Carl Nielsen', 'fornavn først');
  Eq(ApplyNameTool('Nielsen, Carl', ntNameToSurnameFirst), 'Nielsen, Carl', 'allerede vendt');
end;

procedure TestAlbumArtistRule;
var
  Info: TAudioInfo;
begin
  WriteLn('-- albumkunstner-regel');
  Info := TAudioInfo.Create;
  try
    Info.Fields[tfArtist] := 'A';
    AlbumArtistRule := aaNone;
    ApplyAlbumArtistRule(Info);
    Eq(Info.Fields[tfAlbumArtist], '', 'ingen');
    AlbumArtistRule := aaIfEmpty;
    ApplyAlbumArtistRule(Info);
    Eq(Info.Fields[tfAlbumArtist], 'A', 'hvis tom');
    Info.Fields[tfArtist] := 'B';
    ApplyAlbumArtistRule(Info);
    Eq(Info.Fields[tfAlbumArtist], 'A', 'hvis tom - ikke overskrevet');
    AlbumArtistRule := aaAlways;
    ApplyAlbumArtistRule(Info);
    Eq(Info.Fields[tfAlbumArtist], 'B', 'altid');
  finally
    AlbumArtistRule := aaNone;
    Info.Free;
  end;
end;

procedure ReadV1V2(const FileName: string; V1, V2: TAudioInfo; out HasV1: Boolean);
var
  S: TFileStream;
  Size: Int64;
begin
  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    ReadID3v2(S, V2, Size);
    HasV1 := ReadID3v1(S, V1);
  finally
    S.Free;
  end;
end;

procedure TestSync(const Dir, Src: string);
var
  F: string;
  Info, V1, V2: TAudioInfo;
  HasV1: Boolean;
begin
  WriteLn('-- ID3-synkronisering');
  F := Dir + 'sync.mp3';
  if not CopyFile(PChar(Src), PChar(F), False) then
  begin
    Check(False, 'kopi af ' + Src);
    Exit;
  end;
  RemoveAllTags(F, False);
  // only ID3v2: title/artist/album
  Info := ReadAudioInfo(F, True);
  try
    Info.Fields[tfTitle] := 'Titel v2';
    Info.Fields[tfArtist] := 'Kunstner v2';
    Info.Fields[tfAlbum] := 'Album æøå';
    Info.Fields[tfTrack] := '3/10';
    WriteAudioTags(Info, False);
  finally
    Info.Free;
  end;
  Check(SyncID3(F, sdV2ToV1, seOverwrite, False), 'v2 -> v1 ændrer filen');
  V1 := TAudioInfo.Create; V2 := TAudioInfo.Create;
  try
    ReadV1V2(F, V1, V2, HasV1);
    Check(HasV1, 'ID3v1 oprettet');
    Eq(V1.Fields[tfTitle], 'Titel v2', 'v1 titel');
    Eq(V1.Fields[tfAlbum], 'Album æøå', 'v1 album (Latin-1)');
    Eq(V1.Fields[tfTrack], '3', 'v1 spor');
  finally
    V1.Free; V2.Free;
  end;
  Check(not SyncID3(F, sdV2ToV1, seSkip, False), 'v2 -> v1 springer over eksisterende v1');
  // change v1 only, then copy v1 -> v2 for blank fields only
  V1 := TAudioInfo.Create;
  try
    V1.Fields[tfTitle] := 'Titel v1';
    V1.Fields[tfArtist] := 'Kunstner v1';
    V1.Fields[tfComment] := 'Kommentar v1';
    WriteID3v1(F, V1, False);
  finally
    V1.Free;
  end;
  Check(SyncID3(F, sdV1ToV2, seBlankOnly, False), 'v1 -> v2 kun tomme felter');
  V1 := TAudioInfo.Create; V2 := TAudioInfo.Create;
  try
    ReadV1V2(F, V1, V2, HasV1);
    Eq(V2.Fields[tfTitle], 'Titel v2', 'v2 titel beholdt');
    Eq(V2.Fields[tfComment], 'Kommentar v1', 'v2 kommentar udfyldt fra v1');
    Eq(V1.Fields[tfArtist], 'Kunstner v1', 'v1 uændret af v1 -> v2');
  finally
    V1.Free; V2.Free;
  end;
  Check(SyncID3(F, sdV1ToV2, seOverwrite, False) or True, 'v1 -> v2 overskriv');
  V1 := TAudioInfo.Create; V2 := TAudioInfo.Create;
  try
    ReadV1V2(F, V1, V2, HasV1);
    Eq(V2.Fields[tfArtist], 'Kunstner v1', 'v2 kunstner overskrevet fra v1');
  finally
    V1.Free; V2.Free;
  end;
end;

begin
  SetMultiByteConversionCodePage(CP_UTF8);
  SetMultiByteFileSystemCodePage(CP_UTF8);
  {$IFDEF WINDOWS}SetConsoleOutputCP(CP_UTF8);{$ENDIF}
  SetTextCodePage(Output, CP_UTF8);
  TestNames;
  TestAlbumArtistRule;
  if ParamCount >= 2 then
  begin
    ForceDirectories(ParamStr(1));
    TestSync(IncludeTrailingPathDelimiter(UTF8Encode(UnicodeString(ParamStr(1)))),
      UTF8Encode(UnicodeString(ParamStr(2))));
  end;
  WriteLn;
  if Failures = 0 then WriteLn('ALLE TESTS OK') else WriteLn(Failures, ' FEJL');
  ExitCode := Ord(Failures > 0);
end.
