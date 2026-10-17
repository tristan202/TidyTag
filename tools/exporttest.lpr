program ExportTest;

{ Tests for ExportImport: CSV round trip, matching, XLSX reading, HTML/XML output.
    exporttest <test-folder> [<file.xlsx>] }

{$mode objfpc}{$H+}

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  Classes, SysUtils, DOM, XMLRead, AudioTypes, BatchWrite, ExportImport;

var
  Failures: Integer = 0;

procedure Check(Cond: Boolean; const What: string);
begin
  if Cond then WriteLn('ok   ', What)
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

function MakeInfo(const Path, Title, Artist: string): TAudioInfo;
begin
  Result := TAudioInfo.Create;
  Result.FileName := Path;
  Result.Fields[tfTitle] := Title;
  Result.Fields[tfArtist] := Artist;
  Result.Fields[tfAlbum] := 'Album';
  Result.Duration := 61;
  Result.Bitrate := 320;
end;

var
  Dir, CsvFile: string;
  Items: TAudioInfoArray;
  Cols: TExportColumns;
  T: TTable;
  Plan: TImportRows;
  Info, I: Integer;
  Hdr: string;
  Doc: TXMLDocument;
  Fmt: TExportFormat;
begin
  SetMultiByteConversionCodePage(CP_UTF8);
  SetMultiByteFileSystemCodePage(CP_UTF8);
  {$IFDEF WINDOWS}SetConsoleOutputCP(CP_UTF8);{$ENDIF}
  SetTextCodePage(Output, CP_UTF8);
  Dir := IncludeTrailingPathDelimiter(UTF8Encode(UnicodeString(ParamStr(1))));
  ForceDirectories(Dir);

  SetLength(Items, 3);
  Items[0] := MakeInfo('C:\Musik\a.mp3', 'Semi;kolon "citat"', 'Ærø Ålborg');
  Items[1] := MakeInfo('C:\Musik\b.flac', 'Linje 1' + #13#10 + 'Linje 2', '漢字');
  Items[2] := MakeInfo('C:\Andet\a.mp3', ' mellemrum foran', 'Komma, her');
  Items[0].Fields[tfLyrics] := 'Vers' + #13#10 + '"Omkvæd"';

  WriteLn('-- CSV');
  Cols := AllExportColumns;
  CsvFile := Dir + 'eksport.csv';
  ExportFiles(CsvFile, Items, Cols, efCsvSemicolon);
  T := ReadTableFile(CsvFile);
  Check(Length(T) = 4, 'header + 3 rækker');
  Eq(T[0][0], 'Filnavn', 'første overskrift');
  Eq(T[1][4], 'Ærø Ålborg', 'kunstner med æøå'); // columns: Filnavn, Sti, Mappe, Titel, Kunstner
  Eq(T[1][3], 'Semi;kolon "citat"', 'semikolon og citationstegn');
  Eq(T[2][3], 'Linje 1' + #13#10 + 'Linje 2', 'linjeskift i celle');
  Eq(T[2][4], '漢字', 'unicode');
  Eq(T[3][3], ' mellemrum foran', 'foranstillet mellemrum bevares');

  WriteLn('-- import (uændret, ændret, match)');
  Plan := PlanImport(T, Items, False, Hdr);
  Check(Length(Plan) = 3, '3 planrækker');
  Check((Plan[0].Status = isUnchanged) and (Plan[1].Status = isUnchanged), 'rundtur giver ingen ændringer');
  T[1][3] := 'Ny titel';
  T[3][4] := '';                       // empty cell: ignored by default
  Plan := PlanImport(T, Items, False, Hdr);
  Check(Plan[0].Info = Items[0], 'række 1 -> a.mp3 via sti');
  Check(tfTitle in Plan[0].Fields, 'titel ændres');
  Eq(Plan[0].Values[tfTitle], 'Ny titel', 'ny værdi');
  Check(not (tfArtist in Plan[2].Fields), 'tom celle ignoreres');
  Plan := PlanImport(T, Items, True, Hdr);
  Check(tfArtist in Plan[2].Fields, 'tom celle rydder når valgt');

  WriteLn('-- kun filnavn');
  SetLength(T, 3);
  T[0] := ['Filnavn', 'Track #', 'Album Artist'];
  T[1] := ['b.flac', '7/9', 'Diverse'];
  T[2] := ['a.mp3', '1', 'X'];
  Plan := PlanImport(T, Items, False, Hdr);
  Check(Plan[0].Info = Items[1], 'b.flac fundet via filnavn');
  Check((tfTrack in Plan[0].Fields) and (tfAlbumArtist in Plan[0].Fields), 'engelske overskrifter forstås');
  Check(Plan[1].Status = isAmbiguous, 'a.mp3 findes to steder');

  T[0] := ['Titel', 'Kunstner'];
  Plan := PlanImport(T, Items, False, Hdr);
  Check((Length(Plan) = 0) and (Pos('Sti', Hdr) > 0), 'mangler Sti/Filnavn -> forklaring');

  WriteLn('-- HTML / XML / TXT');
  for Fmt := Low(TExportFormat) to High(TExportFormat) do
  begin
    ExportFiles(Dir + 'eksport.' + IntToStr(Ord(Fmt)) + '.' + ExportFormatExt[Fmt], Items, Cols, Fmt);
    Check(FileExists(Dir + 'eksport.' + IntToStr(Ord(Fmt)) + '.' + ExportFormatExt[Fmt]), ExportFormatNames[Fmt]);
  end;
  ReadXMLFile(Doc, Dir + 'eksport.4.xml');
  try
    Check(Doc.GetElementsByTagName('file').Count = 3, 'XML er gyldig med 3 filer');
    Eq(UTF8Encode(Doc.GetElementsByTagName('title')[0].TextContent), 'Semi;kolon "citat"', 'XML-værdi');
  finally
    Doc.Free;
  end;
  T := ReadTableFile(Dir + 'eksport.2.txt');
  Eq(T[2][3], 'Linje 1 / Linje 2', 'TXT: linjeskift erstattet');

  if ParamCount >= 2 then
  begin
    WriteLn('-- XLSX');
    T := ReadTableFile(UTF8Encode(UnicodeString(ParamStr(2))));
    Check(Length(T) = 3, 'xlsx: 3 rækker');
    Eq(T[0][0], 'Sti', 'xlsx: delt streng');
    Eq(T[1][1], 'Titel æøå', 'xlsx: unicode');
    Eq(T[1][2], '7', 'xlsx: tal');
    Eq(T[2][1], 'Rich text', 'xlsx: rig tekst i flere dele');
    Eq(T[2][3], 'inline', 'xlsx: inline-streng i kolonne D (C er tom)');
    Eq(T[2][2], '', 'xlsx: tom celle');
  end;

  for Info := 0 to High(Items) do Items[Info].Free;
  I := Failures;
  WriteLn;
  if I = 0 then WriteLn('ALLE TESTS OK') else WriteLn(I, ' FEJL');
  ExitCode := Ord(I > 0);
end.
