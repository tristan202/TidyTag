program RenameTest;

{ Unit tests for RenameCore and FileNameTags.
  The rename/undo test works in a fresh folder below the given test folder:
    renametest <test-folder> }

{$mode objfpc}{$H+}

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  Classes, SysUtils, AudioTypes, RenameCore, FileNameTags, TrackCore;

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

function MakeInfo(const FileName, Artist, Title, Album, Track: string): TAudioInfo;
begin
  Result := TAudioInfo.Create;
  Result.FileName := FileName;
  Result.Fields[tfArtist] := Artist;
  Result.Fields[tfTitle] := Title;
  Result.Fields[tfAlbum] := Album;
  Result.Fields[tfTrack] := Track;
  Result.Fields[tfYear] := '1999';
  Result.Bitrate := 320;
  Result.Duration := 185;
end;

procedure TestCase;
begin
  WriteLn('-- versaler');
  Eq(ApplyCase('hELLO wORLD (live at øresund)', cmTitle), 'Hello World (Live At Øresund)', 'Hvert ord');
  Eq(ApplyCase('don''t stop-me now', cmTitle), 'Don''t Stop-Me Now', 'Hvert ord med apostrof');
  Eq(ApplyCase('  01 æBLE OG PÆRE', cmSentence), '  01 Æble og pære', 'Første bogstav');
  Eq(ApplyCase('Ærø Å', cmLower), 'ærø å', 'Små');
  Eq(ApplyCase('ærø å', cmUpper), 'ÆRØ Å', 'Store');
end;

procedure TestExpand;
var
  Info: TAudioInfo;
  Opt: TRenameOptions;
  Missing: string;
begin
  WriteLn('-- maske');
  Opt.CaseMode := cmNone;
  Opt.SpacesToUnderscores := False;
  Opt.PadTrack := True;
  Info := MakeInfo('C:\Musik\gammel.mp3', 'AC/DC', 'What? "Now": <Live>*', 'Album', '7/12');
  try
    Eq(ExpandRenameMask('%6 - %1 - %2', Info, 1, 2, Opt, Missing), 'C:\Musik\07 - AC-DC - What ''Now'' - (Live).mp3', 'ulovlige tegn');
    Eq(ExpandRenameMask('%1\%4 - %3\%6 %2', Info, 1, 2, Opt, Missing),
      'C:\Musik\AC-DC\1999 - Album\07 What ''Now'' - (Live).mp3', 'undermapper');
    Eq(ExpandRenameMask('D:\Ny\%1 - %3', Info, 1, 2, Opt, Missing), 'D:\Ny\AC-DC - Album.mp3', 'absolut sti');
    Eq(ExpandRenameMask('%8 %7 [%0kbps] %t', Info, 3, 2, Opt, Missing), 'C:\Musik\03 gammel [320kbps] 3.05.mp3', 'filnummer/filnavn/bitrate/tid');
    Eq(ExpandRenameMask('%1 - %cp', Info, 1, 2, Opt, Missing), '', 'mangler komponist giver tomt');
    Eq(Missing, 'Komponist', 'mangler-tekst');
    Eq(ExpandRenameMask('%3. ', Info, 1, 2, Opt, Missing), 'C:\Musik\Album.mp3', 'afsluttende punktum fjernes');
    Opt.SpacesToUnderscores := True;
    Opt.CaseMode := cmUpper;
    Eq(ExpandRenameMask('%1 - %3', Info, 1, 2, Opt, Missing), 'C:\Musik\AC-DC_-_ALBUM.mp3', 'store + understreg');
    Opt.PadTrack := False;
    Opt.CaseMode := cmNone;
    Opt.SpacesToUnderscores := False;
    Eq(ExpandRenameMask('%6 %2x', Info, 1, 2, Opt, Missing), 'C:\Musik\7-12 What ''Now'' - (Live)x.mp3', 'spor uden udfyldning');
  finally
    Info.Free;
  end;
end;

procedure TestMatch;
var
  M: TFileNameMatch;
begin
  WriteLn('-- tags fra filnavn');
  M := MatchFileName('%6 - %1 - %2', 'C:\x\01 - Kim Larsen - Om lidt bli''r her stille.mp3', False, cmNone);
  Check(M.Ok, 'match 1');
  Eq(M.Values[tfTrack], '01', 'spor');
  Eq(M.Values[tfArtist], 'Kim Larsen', 'kunstner');
  Eq(M.Values[tfTitle], 'Om lidt bli''r her stille', 'titel');

  M := MatchFileName('%1 - %2', 'C:\x\A - B - C.flac', False, cmNone);
  Eq(M.Values[tfArtist], 'A', 'doven kunstner');
  Eq(M.Values[tfTitle], 'B - C', 'resten til titel');

  M := MatchFileName('%6%2', 'C:\x\12Titel med tal 7.mp3', False, cmNone);
  Eq(M.Values[tfTrack], '12', 'grådigt spor uden skilletegn');
  Eq(M.Values[tfTitle], 'Titel med tal 7', 'titel efter spor');

  M := MatchFileName('%1\%4 - %3\%6. %2', 'D:\Musik\Gasolin''\1975 - Gas 5\03. Kvinde_min.mp3', True, cmNone);
  Check(M.Ok, 'match med mapper');
  Eq(M.Values[tfArtist], 'Gasolin''', 'kunstner fra mappe');
  Eq(M.Values[tfYear], '1975', 'år fra mappe');
  Eq(M.Values[tfAlbum], 'Gas 5', 'album fra mappe');
  Eq(M.Values[tfTitle], 'Kvinde min', 'understreg -> mellemrum');

  M := MatchFileName('%d - %2', 'C:\x\Noget - Titel.mp3', False, cmTitle);
  Eq(M.Values[tfTitle], 'Titel', '%d springer over');
  Check(not (tfArtist in M.Used), '%d udfylder intet');

  M := MatchFileName('%6 - %2', 'C:\x\Ingen bindestreg.mp3', False, cmNone);
  Check(not M.Ok, 'ingen match når skilletegn mangler');

  M := MatchFileName('%6 - %2', 'C:\x\AB - Titel.mp3', False, cmNone);
  Check(not M.Ok, 'spor skal være tal');

  M := MatchFileName('%1 - %2', 'C:\x\ÆBLE - grød.mp3', False, cmTitle);
  Eq(M.Values[tfArtist], 'Æble', 'versaler på værdier');
end;

procedure TestTracks;
var
  Items: array of TAudioInfo;
  R: TStringArray;
  N, T, I: Integer;
begin
  WriteLn('-- spornumre');
  Check(ParseTrack(' 7/12', N, T) and (N = 7) and (T = 12), 'parse 7/12');
  Check(ParseTrack('03', N, T) and (N = 3) and (T = 0), 'parse 03');
  Check(not ParseTrack('A1', N, T), 'parse A1 fejler');
  Eq(FormatTrack(7, 12, nfPlain), '7', 'format 7');
  Eq(FormatTrack(7, 12, nfTwoDigits), '07', 'format 07');
  Eq(FormatTrack(7, 12, nfThreeDigits), '007', 'format 007');
  Eq(FormatTrack(7, 12, nfPlainTotal), '7/12', 'format 7/12');
  Eq(FormatTrack(7, 9, nfTwoDigitsTotal), '07/09', 'format 07/09');
  Eq(FormatTrack(7, 0, nfTwoDigitsTotal), '07', 'format uden total');

  SetLength(Items, 5);
  Items[0] := MakeInfo('C:\a=b\1.mp3', 'x', 'x', 'x', '3');
  Items[1] := MakeInfo('C:\a=b\2.mp3', 'x', 'x', 'x', '1/10');
  Items[2] := MakeInfo('C:\a=b\3.mp3', 'x', 'x', 'x', '');
  Items[3] := MakeInfo('C:\cd2\1.mp3', 'x', 'x', 'x', '12');
  Items[4] := MakeInfo('C:\cd2\2.mp3', 'x', 'x', 'x', 'B2');
  R := PlanTrackNumbers(Items, tmFormat, nfTwoDigitsTotal, 1, True);
  Eq(R[0], '03/03', 'formatér: total = filer i mappen');
  Eq(R[1], '01/10', 'formatér: eksisterende total bevares');
  Eq(R[2], '', 'formatér: tomt forbliver tomt');
  Eq(R[3], '12/02', 'formatér: anden mappe');
  Eq(R[4], 'B2', 'formatér: ikke-tal bevares');
  R := PlanTrackNumbers(Items, tmNumber, nfTwoDigits, 1, True);
  Eq(R[0] + ' ' + R[1] + ' ' + R[2] + ' ' + R[3] + ' ' + R[4], '01 02 03 01 02', 'nummerér pr. mappe');
  R := PlanTrackNumbers(Items, tmNumber, nfPlainTotal, 5, False);
  Eq(R[0] + ' ' + R[4], '5/9 9/9', 'nummerér fortløbende fra 5');
  for I := 0 to High(Items) do Items[I].Free;
end;

procedure TestFolderPlan;
var
  Items: array of TAudioInfo;
  Plan: TRenamePlan;
  Opt: TRenameOptions;
  V: TMaskValues;
  I: Integer;
begin
  WriteLn('-- mappe-omdøbning (plan)');
  SetLength(Items, 5);
  Items[0] := MakeInfo('C:\Musik\x\1.mp3', 'Gasolin''', 'A', 'Gas 5', '1');
  Items[1] := MakeInfo('C:\Musik\x\2.mp3', 'Gasolin''', 'B', 'Gas 5', '2');
  Items[2] := MakeInfo('C:\Musik\komp\1.mp3', 'Kunstner A', 'A', 'Hits', '1');
  Items[3] := MakeInfo('C:\Musik\komp\2.mp3', 'Kunstner B', 'B', 'Hits', '2');
  Items[4] := MakeInfo('C:\Musik\komp2\1.mp3', 'Kunstner C', 'A', 'Hits 2', '1');
  Items[2].Fields[tfAlbumArtist] := 'Diverse';
  Items[3].Fields[tfAlbumArtist] := 'Diverse';
  V := CommonFolderValues(Items, 'C:\Musik\komp');
  Eq(V.Fields[tfArtist], 'Diverse', 'kunstner falder tilbage til albumkunstner');
  Check(tfTitle in V.Different, 'titel er forskellig');
  Opt.CaseMode := cmNone;
  Opt.SpacesToUnderscores := False;
  Opt.PadTrack := True;
  Plan := PlanFolderRename(Items, '%1 - %4 - %3', Opt);
  Check(Length(Plan) = 3, '3 mapper');
  // Sorted by folder: komp, komp2, x
  Eq(Plan[0].NewName, 'C:\Musik\Diverse - 1999 - Hits', 'kompilation');
  Eq(Plan[1].NewName, 'C:\Musik\Kunstner C - 1999 - Hits 2', 'én fil');
  Eq(Plan[2].NewName, 'C:\Musik\Gasolin'' - 1999 - Gas 5', 'almindeligt album');
  Plan := PlanFolderRename(Items, '%2', Opt);
  Check(Plan[0].Status = rsMissing, 'titel forskellig -> mangler');
  Eq(Plan[0].Detail, 'Titel (forskellige)', 'forklaring');
  Plan := PlanFolderRename(Items, '%1\%3', Opt);
  Eq(Plan[2].NewName, 'C:\Musik\Gasolin''\Gas 5', 'undermappe');
  Plan := PlanFolderRename(Items, '%f', Opt);
  Check(Plan[0].Status = rsUnchanged, '%f = uændret');
  for I := 0 to High(Items) do Items[I].Free;

  SetLength(Items, 2);
  Items[0] := MakeInfo('C:\Musik\A\1.mp3', 'K', 'T', 'Alb', '1');
  Items[1] := MakeInfo('C:\Musik\A\B\1.mp3', 'K', 'T', 'Alb2', '1');
  Plan := PlanFolderRename(Items, '%3', Opt);
  Check(Plan[0].Status = rsInvalid, 'ydre mappe springes over');
  Check(Plan[1].Status = rsOk, 'indre mappe ok');
  for I := 0 to High(Items) do Items[I].Free;
end;

procedure TouchFile(const Name: string);
var
  S: TFileStream;
begin
  ForceDirectories(ExtractFileDir(Name));
  S := TFileStream.Create(Name, fmCreate);
  S.Free;
end;

procedure TestRenameAndUndo(const Base: string);
var
  Dir: string;
  Items: array of TAudioInfo;
  Plan: TRenamePlan;
  Log: TRenameLog;
  Opt: TRenameOptions;
  Errors: TStringList;
  I: Integer;
begin
  WriteLn('-- omdøb og fortryd på disk');
  Dir := IncludeTrailingPathDelimiter(Base) + 'rename-' + FormatDateTime('hhnnsszzz', Now) + '\';
  TouchFile(Dir + 'a.mp3');
  TouchFile(Dir + 'b.mp3');
  TouchFile(Dir + 'c.mp3');
  TouchFile(Dir + 'd.mp3');
  TouchFile(Dir + 'Blokeret - Titel.mp3');
  SetLength(Items, 4);
  Items[0] := MakeInfo(Dir + 'a.mp3', 'Kunstner', 'Første', 'Album', '1');
  Items[1] := MakeInfo(Dir + 'b.mp3', 'Kunstner', 'Første', 'Album', '2'); // same name as a -> duplicate
  Items[2] := MakeInfo(Dir + 'c.mp3', 'Blokeret', 'Titel', 'Album', '3');  // target already exists
  Items[3] := MakeInfo(Dir + 'd.mp3', '', 'Uden kunstner', 'Album', '4'); // missing field
  Opt.CaseMode := cmNone;
  Opt.SpacesToUnderscores := False;
  Opt.PadTrack := True;
  Plan := PlanRename(Items, '%1 - %2', Opt);
  Check(Plan[0].Status = rsOk, 'a omdøbes');
  Check(Plan[1].Status = rsDuplicate, 'b er dublet');
  Check(Plan[2].Status = rsExists, 'c findes allerede');
  Check(Plan[3].Status = rsMissing, 'd mangler kunstner');

  Plan := PlanRename(Items, '%1\%3\%6 - %2', Opt);
  Check(CountStatus(Plan, rsOk) = 3, '3 klar til omdøbning i undermapper');
  Log := ExecuteRename(Plan);
  Check(Length(Log) = 3, '3 omdøbt');
  Check(FileExists(Dir + 'Kunstner\Album\01 - Første.mp3'), 'ny fil findes');
  Check(not FileExists(Dir + 'a.mp3'), 'gammel fil væk');
  Check(Items[0].FileName = Dir + 'Kunstner\Album\01 - Første.mp3', 'Info.FileName opdateret');

  Errors := TStringList.Create;
  try
    I := UndoRename(Log, Errors);
    Check(I = 3, 'fortryd 3 filer');
    Check(Errors.Count = 0, 'ingen fortryd-fejl ' + Errors.Text);
  finally
    Errors.Free;
  end;
  Check(FileExists(Dir + 'a.mp3') and FileExists(Dir + 'b.mp3') and FileExists(Dir + 'c.mp3'), 'originaler tilbage');
  Check(not DirectoryExists(Dir + 'Kunstner'), 'tomme mapper fjernet');

  // Folder rename + undo on disk
  Items[0].FileName := Dir + 'a.mp3';
  TouchFile(Dir + 'album\x.mp3');
  Items[1].FileName := Dir + 'album\x.mp3';
  Items[1].Fields[tfArtist] := 'Mappekunstner';
  Items[1].Fields[tfAlbum] := 'Mappealbum';
  Plan := PlanFolderRename([Items[1]], '%1\%3', Opt);
  Check(Plan[0].Status = rsOk, 'mappe klar');
  Log := ExecuteRename(Plan);
  Check((Length(Log) = 1) and FileExists(Dir + 'Mappekunstner\Mappealbum\x.mp3'), 'mappe omdøbt og flyttet');
  Eq(MapRenamedPath(Dir + 'album\x.mp3', Log, False), Dir + 'Mappekunstner\Mappealbum\x.mp3', 'sti følger mappen');
  Errors := TStringList.Create;
  try
    Check(UndoRename(Log, Errors) = 1, 'mappe fortrudt');
  finally
    Errors.Free;
  end;
  Check(FileExists(Dir + 'album\x.mp3') and not DirectoryExists(Dir + 'Mappekunstner'), 'mappe tilbage, tom mappe fjernet');
  Eq(MapRenamedPath(Dir + 'Mappekunstner\Mappealbum\x.mp3', Log, True), Dir + 'album\x.mp3', 'sti tilbage');

  // Case-only rename must work on a case-insensitive file system.
  Items[0].FileName := Dir + 'a.mp3';
  Plan := PlanRename([Items[0]], '%7', Opt);
  Check(Plan[0].Status = rsUnchanged, 'samme navn = uændret');
  Opt.CaseMode := cmUpper;
  Plan := PlanRename([Items[0]], '%7', Opt);
  Check(Plan[0].Status = rsOk, 'kun versaler ændret er ok');
  Log := ExecuteRename(Plan);
  Check((Length(Log) = 1) and (ExtractFileName(Items[0].FileName) = 'A.mp3'), 'omdøbt til A.mp3');

  for I := 0 to High(Items) do Items[I].Free;
end;

begin
  SetMultiByteConversionCodePage(CP_UTF8);
  SetMultiByteFileSystemCodePage(CP_UTF8);
  {$IFDEF WINDOWS}SetConsoleOutputCP(CP_UTF8);{$ENDIF}
  SetTextCodePage(Output, CP_UTF8);
  TestCase;
  TestExpand;
  TestMatch;
  TestTracks;
  TestFolderPlan;
  if ParamCount >= 1 then
    TestRenameAndUndo(UTF8Encode(UnicodeString(ParamStr(1))));
  WriteLn;
  if Failures = 0 then WriteLn('ALLE TESTS OK') else WriteLn(Failures, ' FEJL');
  ExitCode := Ord(Failures > 0);
end.
