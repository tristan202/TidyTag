unit ExportImport;

{ Exporting the file list (CSV for Excel, tab-separated text, HTML, XML) and importing
  tag values back from CSV or XLSX. Rows are matched to files by the "Sti" (full path)
  column, else by "Filnavn" when that name is unique. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, AudioTypes, BatchWrite;

resourcestring
  rsCsvTilExcelSemikolon = 'CSV til Excel (semikolon)';
  rsCsvKomma = 'CSV (komma)';
  rsTekstTabulator = 'Tekst (tabulator)';
  rsAendres = 'Ændres';
  rsUaendret = 'Uændret';
  rsIngenFilPasser = 'Ingen fil passer';
  rsFlereFilerPasser = 'Flere filer passer';
  rsFiltypenKanIkkeGemmes = 'Filtypen kan ikke gemmes';
  rsGemt = 'Gemt';
  rsFejl = 'Fejl';
  rsFilnavn = 'Filnavn';
  rsSti = 'Sti';
  rsMappe = 'Mappe';
  rsVarighed = 'Varighed';
  rsBitrate = 'Bitrate';
  rsSamplerate = 'Samplerate';
  rsCodec = 'Codec';
  rsStoerrelseByte = 'Størrelse (byte)';
  rsCover = 'Cover';
  rsJa = 'Ja';
  rsNej = 'Nej';
  rsRegnearketHarIntetFoersteArk = 'Regnearket har intet første ark (xl/worksheets/sheet1.xml)';
  rsDetGamleXlsFormatUnderstoettes = 'Det gamle .xls-format understøttes ikke. Gem regnearket som .xlsx eller .csv.';
  rsFilenHarIngenDataraekker = 'Filen har ingen datarækker.';
  rsDerManglerEnKolonneSti = 'Der mangler en kolonne "Sti" eller "Filnavn" til at finde filerne.';
  rsIngenKolonneoverskrifterSvarerTilTag = 'Ingen kolonneoverskrifter svarer til tag-felter (fx "Titel", "Kunstner", "Album").';
  rsFelter = 'Felter: ';
  rsFilerFindesViaSti = '.  Filer findes via "Sti".';
  rsFilerFindesViaFilnavn = '.  Filer findes via "Filnavn".';


type
  TExportKind = (ekFileName, ekPath, ekFolder, ekField, ekDuration, ekBitrate, ekSampleRate,
    ekCodec, ekSize, ekCover, ekTagTypes);

  TExportColumn = record
    Caption: string;   // header in CSV/TXT/HTML (Danish, also accepted on import)
    Key: string;       // ASCII name: XML element and alternative import header
    Kind: TExportKind;
    Field: TTagField;
  end;
  TExportColumns = array of TExportColumn;

  TExportFormat = (efCsvSemicolon, efCsvComma, efTxt, efHtml, efXml);

  TTable = array of TStringArray;

  TImportStatus = (isChange, isUnchanged, isNoMatch, isAmbiguous, isNotWritable, isSaved, isFailed);

  TImportRow = record
    RowNo: Integer;          // 1-based row in the sheet (header = row 1)
    Info: TAudioInfo;        // matched file, nil if none
    Values: TFieldValues;
    Fields: TTagFieldSet;    // fields that change
    Status: TImportStatus;
    Detail: string;
  end;
  TImportRows = array of TImportRow;

const
  ExportFormatNames: array[TExportFormat] of string = (rsCsvTilExcelSemikolon,
    rsCsvKomma, rsTekstTabulator, 'HTML-tabel', 'XML');
  ExportFormatExt: array[TExportFormat] of string = ('csv', 'csv', 'txt', 'html', 'xml');
  ImportStatusText: array[TImportStatus] of string = (rsAendres, rsUaendret, rsIngenFilPasser,
    rsFlereFilerPasser, rsFiltypenKanIkkeGemmes, rsGemt, rsFejl);
  FieldKeys: array[TTagField] of string = ('title', 'artist', 'album', 'year', 'track', 'disc',
    'genre', 'comment', 'albumartist', 'composer', 'bpm', 'lyrics', 'conductor', 'lyricist',
    'origartist', 'remixer', 'label', 'catalog', 'isrc', 'copyright', 'encodedby', 'url',
    'grouping', 'subtitle', 'mood', 'key', 'sorttitle', 'sortartist', 'sortalbumartist',
    'sortalbum', 'sortcomposer');

function AllExportColumns: TExportColumns;
function ExportCellText(Info: TAudioInfo; const C: TExportColumn): string;
procedure ExportFiles(const FileName: string; const Items: TAudioInfoArray;
  const Cols: TExportColumns; Fmt: TExportFormat);
{ CSV text with auto-detected separator (; , or tab), quotes and line breaks in cells. }
function ParseCsv(const Text: string): TTable;
function ReadXlsx(const FileName: string): TTable;
{ CSV/TXT/XLSX by extension. }
function ReadTableFile(const FileName: string): TTable;
{ Matches the rows to Items and works out which fields change. EmptyClears: an empty
  cell clears the field (otherwise empty cells are ignored). }
function PlanImport(const Table: TTable; const Items: TAudioInfoArray; EmptyClears: Boolean;
  out HeaderInfo: string): TImportRows;

implementation

uses
  zipper, DOM, XMLRead, TagUtils, TagWriter;

function LowerUTF8(const S: string): string;
begin
  Result := UTF8Encode(WideLowerCase(UTF8Decode(S)));
end;

function IsValidUTF8(const S: string): Boolean;
var
  I, N, K: Integer;
  B: Byte;
begin
  I := 1;
  while I <= Length(S) do
  begin
    B := Ord(S[I]);
    if B < $80 then N := 0
    else if B and $E0 = $C0 then N := 1
    else if B and $F0 = $E0 then N := 2
    else if B and $F8 = $F0 then N := 3
    else Exit(False);
    if I + N > Length(S) then Exit(False);
    for K := 1 to N do
      if Ord(S[I + K]) and $C0 <> $80 then Exit(False);
    Inc(I, N + 1);
  end;
  Result := True;
end;

{ Older Excel saves CSV in the Windows code page (1252 in Denmark). }
function Cp1252ToUTF8(const S: string): string;
var
  R: RawByteString;
begin
  R := S;
  SetCodePage(R, 1252, False);
  Result := UTF8Encode(UnicodeString(R));
end;

function Col(const ACaption, AKey: string; AKind: TExportKind; AField: TTagField = tfTitle): TExportColumn;
begin
  Result.Caption := ACaption;
  Result.Key := AKey;
  Result.Kind := AKind;
  Result.Field := AField;
end;

function AllExportColumns: TExportColumns;
var
  F: TTagField;
  N: Integer;
begin
  Result := nil;
  SetLength(Result, 3 + Ord(High(TTagField)) + 1 + 7);
  N := 0;
  Result[N] := Col(rsFilnavn, 'filename', ekFileName); Inc(N);
  Result[N] := Col(rsSti, 'path', ekPath); Inc(N);
  Result[N] := Col(rsMappe, 'folder', ekFolder); Inc(N);
  for F := Low(TTagField) to High(TTagField) do
  begin
    Result[N] := Col(TagFieldCaptions[F], FieldKeys[F], ekField, F);
    Inc(N);
  end;
  Result[N] := Col(rsVarighed, 'duration', ekDuration); Inc(N);
  Result[N] := Col(rsBitrate, 'bitrate', ekBitrate); Inc(N);
  Result[N] := Col(rsSamplerate, 'samplerate', ekSampleRate); Inc(N);
  Result[N] := Col(rsCodec, 'codec', ekCodec); Inc(N);
  Result[N] := Col(rsStoerrelseByte, 'size', ekSize); Inc(N);
  Result[N] := Col(rsCover, 'cover', ekCover); Inc(N);
  Result[N] := Col('Tag-typer', 'tagtypes', ekTagTypes); Inc(N);
  SetLength(Result, N);
end;

function ExportCellText(Info: TAudioInfo; const C: TExportColumn): string;
begin
  case C.Kind of
    ekFileName: Result := ExtractFileName(Info.FileName);
    ekPath: Result := Info.FileName;
    ekFolder: Result := ExtractFileDir(Info.FileName);
    ekField: Result := Info.Fields[C.Field];
    ekDuration: Result := FormatDuration(Info.Duration);
    ekBitrate: if Info.Bitrate > 0 then Result := IntToStr(Info.Bitrate) else Result := '';
    ekSampleRate: if Info.SampleRate > 0 then Result := IntToStr(Info.SampleRate) else Result := '';
    ekCodec: Result := Info.Codec;
    ekSize: Result := IntToStr(Info.FileSize);
    ekCover: if Info.HasCover then Result := rsJa else Result := rsNej;
    ekTagTypes: Result := Info.TagTypes;
  else
    Result := '';
  end;
end;

{ ---------- export ---------- }

function CsvQuote(const S: string; Sep: Char): string;
begin
  if (Pos(Sep, S) > 0) or (Pos('"', S) > 0) or (Pos(#10, S) > 0) or (Pos(#13, S) > 0) or
    ((S <> '') and ((S[1] = ' ') or (S[Length(S)] = ' '))) then
    Result := '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := S;
end;

function XmlEscape(const S: string): string;
begin
  Result := StringReplace(S, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

{ Excel opens UTF-8 CSV correctly only with a byte order mark. }
procedure SaveText(const FileName, Text: string; Bom: Boolean);
var
  S: TFileStream;
  B: TBytes;
begin
  S := TFileStream.Create(FileName, fmCreate);
  try
    if Bom then
    begin
      S.WriteByte($EF); S.WriteByte($BB); S.WriteByte($BF);
    end;
    B := UTF8Bytes(Text);
    WriteBytes(S, B);
  finally
    S.Free;
  end;
end;

procedure ExportFiles(const FileName: string; const Items: TAudioInfoArray;
  const Cols: TExportColumns; Fmt: TExportFormat);
var
  SB: TStringBuilder;
  I, J: Integer;
  Sep: Char;
  Cell: string;
begin
  SB := TStringBuilder.Create;
  try
    case Fmt of
      efCsvSemicolon, efCsvComma, efTxt:
        begin
          case Fmt of
            efCsvSemicolon: Sep := ';';
            efCsvComma: Sep := ',';
          else
            Sep := #9;
          end;
          for J := 0 to High(Cols) do
          begin
            if J > 0 then SB.Append(Sep);
            SB.Append(CsvQuote(Cols[J].Caption, Sep));
          end;
          SB.Append(#13#10);
          for I := 0 to High(Items) do
          begin
            for J := 0 to High(Cols) do
            begin
              if J > 0 then SB.Append(Sep);
              Cell := ExportCellText(Items[I], Cols[J]);
              if Fmt = efTxt then
                Cell := StringReplace(StringReplace(Cell, #13#10, ' / ', [rfReplaceAll]), #9, ' ', [rfReplaceAll]);
              SB.Append(CsvQuote(Cell, Sep));
            end;
            SB.Append(#13#10);
          end;
          SaveText(FileName, SB.ToString, True);
        end;
      efHtml:
        begin
          SB.Append('<!DOCTYPE html>'#13#10'<html lang="da"><head><meta charset="utf-8">');
          SB.Append('<title>Musikfiler</title><style>body{font-family:Segoe UI,Arial,sans-serif;font-size:13px}');
          SB.Append('table{border-collapse:collapse}th,td{border:1px solid #ccc;padding:3px 6px;vertical-align:top}');
          SB.Append('th{background:#eee;text-align:left}tr:nth-child(even){background:#fafafa}</style></head><body>'#13#10);
          SB.Append(Format('<h1>Musikfiler (%d)</h1>'#13#10'<table>'#13#10'<tr>', [Length(Items)]));
          for J := 0 to High(Cols) do SB.Append('<th>' + XmlEscape(Cols[J].Caption) + '</th>');
          SB.Append('</tr>'#13#10);
          for I := 0 to High(Items) do
          begin
            SB.Append('<tr>');
            for J := 0 to High(Cols) do
              SB.Append('<td>' + StringReplace(XmlEscape(ExportCellText(Items[I], Cols[J])),
                #13#10, '<br>', [rfReplaceAll]) + '</td>');
            SB.Append('</tr>'#13#10);
          end;
          SB.Append('</table>'#13#10'</body></html>'#13#10);
          SaveText(FileName, SB.ToString, False);
        end;
      efXml:
        begin
          SB.Append('<?xml version="1.0" encoding="UTF-8"?>'#13#10'<files>'#13#10);
          for I := 0 to High(Items) do
          begin
            SB.Append('  <file>'#13#10);
            for J := 0 to High(Cols) do
            begin
              Cell := ExportCellText(Items[I], Cols[J]);
              if Cell <> '' then
                SB.Append(Format('    <%s>%s</%s>'#13#10, [Cols[J].Key, XmlEscape(Cell), Cols[J].Key]));
            end;
            SB.Append('  </file>'#13#10);
          end;
          SB.Append('</files>'#13#10);
          SaveText(FileName, SB.ToString, False);
        end;
    end;
  finally
    SB.Free;
  end;
end;

{ ---------- import: reading tables ---------- }

function DetectSeparator(const Text: string): Char;
var
  I, Semi, Comma, Tab: Integer;
  InQ: Boolean;
begin
  Semi := 0; Comma := 0; Tab := 0;
  InQ := False;
  for I := 1 to Length(Text) do
  begin
    case Text[I] of
      '"': InQ := not InQ;
      ';': if not InQ then Inc(Semi);
      ',': if not InQ then Inc(Comma);
      #9: if not InQ then Inc(Tab);
      #10: if not InQ then Break; // header line decides
    end;
  end;
  if (Tab >= Semi) and (Tab >= Comma) and (Tab > 0) then Result := #9
  else if Semi >= Comma then Result := ';'
  else Result := ',';
end;

function ParseCsv(const Text: string): TTable;
var
  T: string;
  Sep: Char;
  I, N: Integer;
  Cell: string;
  Row: TStringArray;
  InQ: Boolean;

  procedure EndCell;
  begin
    SetLength(Row, Length(Row) + 1);
    Row[High(Row)] := Cell;
    Cell := '';
  end;

  procedure EndRow;
  begin
    EndCell;
    // skip completely empty lines
    if not ((Length(Row) = 1) and (Row[0] = '')) then
    begin
      N := Length(Result);
      SetLength(Result, N + 1);
      Result[N] := Row;
    end;
    Row := nil;
  end;

begin
  Result := nil;
  T := Text;
  if Copy(T, 1, 3) = #$EF#$BB#$BF then Delete(T, 1, 3);
  Sep := DetectSeparator(T);
  Row := nil;
  Cell := '';
  InQ := False;
  I := 1;
  while I <= Length(T) do
  begin
    if InQ then
    begin
      if T[I] = '"' then
      begin
        if (I < Length(T)) and (T[I + 1] = '"') then
        begin
          Cell := Cell + '"';
          Inc(I);
        end
        else
          InQ := False;
      end
      else
        Cell := Cell + T[I];
    end
    else
      case T[I] of
        '"': InQ := True;
        #13: ;
        #10: EndRow;
      else
        if T[I] = Sep then EndCell else Cell := Cell + T[I];
      end;
    Inc(I);
  end;
  if (Cell <> '') or (Length(Row) > 0) then EndRow;
  // quoted line breaks come back as LF; store them as CRLF like the tags
  for I := 0 to High(Result) do
    for N := 0 to High(Result[I]) do
      Result[I][N] := StringReplace(StringReplace(Result[I][N], #13#10, #10, [rfReplaceAll]),
        #10, #13#10, [rfReplaceAll]);
end;

{ All text below a node, e.g. the runs of a rich-text shared string. }
function NodeText(N: TDOMNode): string;
var
  C: TDOMNode;
begin
  Result := '';
  if N = nil then Exit;
  if (N.NodeName = 't') then Exit(UTF8Encode(N.TextContent));
  C := N.FirstChild;
  while C <> nil do
  begin
    if C.NodeName <> 'rPh' then Result := Result + NodeText(C); // skip phonetic runs
    C := C.NextSibling;
  end;
end;

function ColumnIndex(const Ref: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Length(Ref) do
    if Ref[I] in ['A'..'Z'] then Result := Result * 26 + Ord(Ref[I]) - Ord('A') + 1
    else Break;
  Dec(Result);
end;

function UnzipEntry(Zip: TUnZipper; const Name: string; Dest: TStream): Boolean;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Add(Name);
    try
      Zip.UnZipFiles(L);
    except
      Exit(False);
    end;
  finally
    L.Free;
  end;
  Result := Dest.Size > 0;
end;

type
  { Collects unzipped entries in memory instead of on disk. }
  TMemUnzip = class
    Data: TMemoryStream;
    procedure CreateStream(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
    procedure DoneStream(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
  end;

procedure TMemUnzip.CreateStream(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
begin
  Data.Clear;
  AStream := Data;
end;

procedure TMemUnzip.DoneStream(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
begin
  AStream := nil; // owned by Data
end;

function ReadZipXml(const FileName, Entry: string): TXMLDocument;
var
  Zip: TUnZipper;
  Mem: TMemUnzip;
begin
  Result := nil;
  Zip := TUnZipper.Create;
  Mem := TMemUnzip.Create;
  Mem.Data := TMemoryStream.Create;
  try
    Zip.FileName := FileName;
    Zip.OnCreateStream := @Mem.CreateStream;
    Zip.OnDoneStream := @Mem.DoneStream;
    if not UnzipEntry(Zip, Entry, Mem.Data) then Exit;
    Mem.Data.Position := 0;
    ReadXMLFile(Result, Mem.Data);
  finally
    Mem.Data.Free;
    Mem.Free;
    Zip.Free;
  end;
end;

function ReadXlsx(const FileName: string): TTable;
var
  Shared: TStringList;
  Doc: TXMLDocument;
  Rows, Cells: TDOMNodeList;
  RowNode, CellNode, V: TDOMNode;
  I, J, ColNo, N: Integer;
  CellType, Value: string;
  Row: TStringArray;
begin
  Result := nil;
  Shared := TStringList.Create;
  try
    Doc := ReadZipXml(FileName, 'xl/sharedStrings.xml');
    if Doc <> nil then
    try
      Rows := Doc.GetElementsByTagName('si');
      for I := 0 to Rows.Count - 1 do Shared.Add(NodeText(Rows[I]));
    finally
      Doc.Free;
    end;
    Doc := ReadZipXml(FileName, 'xl/worksheets/sheet1.xml');
    if Doc = nil then raise Exception.Create(rsRegnearketHarIntetFoersteArk);
    try
      Rows := Doc.GetElementsByTagName('row');
      for I := 0 to Rows.Count - 1 do
      begin
        RowNode := Rows[I];
        Row := nil;
        Cells := TDOMElement(RowNode).GetElementsByTagName('c');
        for J := 0 to Cells.Count - 1 do
        begin
          CellNode := Cells[J];
          ColNo := ColumnIndex(UTF8Encode(TDOMElement(CellNode).GetAttribute('r')));
          if ColNo < 0 then ColNo := Length(Row);
          CellType := UTF8Encode(TDOMElement(CellNode).GetAttribute('t'));
          Value := '';
          if CellType = 'inlineStr' then
            Value := NodeText(TDOMElement(CellNode).FindNode('is'))
          else
          begin
            V := TDOMElement(CellNode).FindNode('v');
            if V <> nil then Value := UTF8Encode(V.TextContent);
            if (CellType = 's') and (StrToIntDef(Value, -1) >= 0) and (StrToInt(Value) < Shared.Count) then
              Value := Shared[StrToInt(Value)];
          end;
          if ColNo >= Length(Row) then
          begin
            N := Length(Row);
            SetLength(Row, ColNo + 1);
            while N < ColNo do begin Row[N] := ''; Inc(N); end;
          end;
          Row[ColNo] := StringReplace(StringReplace(Value, #13#10, #10, [rfReplaceAll]), #10, #13#10, [rfReplaceAll]);
        end;
        N := Length(Result);
        SetLength(Result, N + 1);
        Result[N] := Row;
      end;
    finally
      Doc.Free;
    end;
  finally
    Shared.Free;
  end;
end;

function ReadTableFile(const FileName: string): TTable;
var
  S: TFileStream;
  B: TBytes;
  Text: string;
begin
  case LowerCase(ExtractFileExt(FileName)) of
    '.xlsx', '.xlsm': Exit(ReadXlsx(FileName));
    '.xls': raise Exception.Create(rsDetGamleXlsFormatUnderstoettes);
  end;
  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    B := ReadStreamBytes(S, S.Size);
  finally
    S.Free;
  end;
  SetLength(Text, Length(B));
  if Length(B) > 0 then Move(B[0], Text[1], Length(B));
  if (Length(Text) >= 3) and (Copy(Text, 1, 3) = #$EF#$BB#$BF) then
    Delete(Text, 1, 3)
  else if not IsValidUTF8(Text) then
    Text := Cp1252ToUTF8(Text); // an ANSI CSV saved by older Excel
  Result := ParseCsv(Text);
end;

{ ---------- import: matching ---------- }

type
  THeaderKind = (hkIgnore, hkPath, hkFileName, hkField);

function NormalizeHeader(const S: string): string;
begin
  Result := LowerUTF8(Trim(S));
  Result := StringReplace(Result, ' ', '', [rfReplaceAll]);
  Result := StringReplace(Result, '.', '', [rfReplaceAll]);
  Result := StringReplace(Result, '_', '', [rfReplaceAll]);
  Result := StringReplace(Result, '-', '', [rfReplaceAll]);
end;

procedure MapHeader(const H: string; out Kind: THeaderKind; out Field: TTagField);
const
  // English names other programs (and Tag&Rename) use
  Aliases: array[0..19, 0..1] of string = (('track#', 'track'), ('tracknumber', 'track'),
    ('disc#', 'disc'), ('discnumber', 'disc'), ('albumartist', 'albumartist'),
    ('band', 'albumartist'), ('date', 'year'), ('publisher', 'label'), ('catalog#', 'catalog'),
    ('catalognumber', 'catalog'), ('initialkey', 'key'), ('origartist', 'origartist'),
    ('originalartist', 'origartist'), ('encoded by', 'encodedby'), ('remixedby', 'remixer'),
    ('lyric', 'lyrics'), ('unsyncedlyrics', 'lyrics'), ('website', 'url'), ('tempo', 'bpm'),
    ('content group', 'grouping'));
var
  N, A: string;
  F: TTagField;
  I: Integer;
begin
  Kind := hkIgnore;
  Field := tfTitle;
  N := NormalizeHeader(H);
  if (N = 'sti') or (N = 'path') or (N = 'filepath') or (N = 'fuldsti') then begin Kind := hkPath; Exit; end;
  if (N = 'filnavn') or (N = 'filename') or (N = 'file') or (N = 'fil') then begin Kind := hkFileName; Exit; end;
  for I := Low(Aliases) to High(Aliases) do
    if NormalizeHeader(Aliases[I, 0]) = N then N := Aliases[I, 1];
  for F := Low(TTagField) to High(TTagField) do
    if (NormalizeHeader(TagFieldCaptions[F]) = N) or (FieldKeys[F] = N) then
    begin
      Kind := hkField;
      Field := F;
      Exit;
    end;
end;

function PlanImport(const Table: TTable; const Items: TAudioInfoArray; EmptyClears: Boolean;
  out HeaderInfo: string): TImportRows;
var
  Kinds: array of THeaderKind;
  ColFields: array of TTagField;
  PathCol, NameCol, I, J, K, Found, Hits: Integer;
  Value: string;
  Used: TTagFieldSet;
  F: TTagField;
begin
  Result := nil;
  HeaderInfo := '';
  if Length(Table) < 2 then
  begin
    HeaderInfo := rsFilenHarIngenDataraekker;
    Exit;
  end;
  SetLength(Kinds, Length(Table[0]));
  SetLength(ColFields, Length(Table[0]));
  PathCol := -1;
  NameCol := -1;
  Used := [];
  for J := 0 to High(Table[0]) do
  begin
    MapHeader(Table[0][J], Kinds[J], ColFields[J]);
    case Kinds[J] of
      hkPath: if PathCol < 0 then PathCol := J;
      hkFileName: if NameCol < 0 then NameCol := J;
      hkField: Include(Used, ColFields[J]);
    end;
  end;
  if (PathCol < 0) and (NameCol < 0) then
  begin
    HeaderInfo := rsDerManglerEnKolonneSti;
    Exit;
  end;
  if Used = [] then
  begin
    HeaderInfo := rsIngenKolonneoverskrifterSvarerTilTag;
    Exit;
  end;
  HeaderInfo := rsFelter;
  for F in Used do HeaderInfo := HeaderInfo + TagFieldCaptions[F] + ', ';
  SetLength(HeaderInfo, Length(HeaderInfo) - 2);
  if PathCol >= 0 then HeaderInfo := HeaderInfo + rsFilerFindesViaSti
  else HeaderInfo := HeaderInfo + rsFilerFindesViaFilnavn;

  SetLength(Result, Length(Table) - 1);
  for I := 1 to High(Table) do
    with Result[I - 1] do
    begin
      RowNo := I + 1;
      Info := nil;
      Fields := [];
      Detail := '';
      for F := Low(TTagField) to High(TTagField) do Values[F] := '';
      // find the file
      Found := -1;
      Hits := 0;
      if (PathCol >= 0) and (PathCol < Length(Table[I])) and (Trim(Table[I][PathCol]) <> '') then
      begin
        for K := 0 to High(Items) do
          if SameFileName(Items[K].FileName, Trim(Table[I][PathCol])) then
          begin
            Found := K;
            Hits := 1;
            Break;
          end;
      end
      else if (NameCol >= 0) and (NameCol < Length(Table[I])) then
        for K := 0 to High(Items) do
          if SameFileName(ExtractFileName(Items[K].FileName), Trim(Table[I][NameCol])) then
          begin
            Found := K;
            Inc(Hits);
          end;
      if Hits = 0 then
      begin
        Status := isNoMatch;
        if (PathCol >= 0) and (PathCol < Length(Table[I])) then Detail := Table[I][PathCol]
        else if (NameCol >= 0) and (NameCol < Length(Table[I])) then Detail := Table[I][NameCol];
        Continue;
      end;
      if Hits > 1 then
      begin
        Status := isAmbiguous;
        Detail := Table[I][NameCol];
        Continue;
      end;
      Info := Items[Found];
      // collect changed fields
      Values := FieldValuesOf(Info);
      for J := 0 to High(Table[0]) do
      begin
        if Kinds[J] <> hkField then Continue;
        if J < Length(Table[I]) then Value := Trim(Table[I][J]) else Value := '';
        if (Value = '') and not EmptyClears then Continue;
        if Value <> Info.Fields[ColFields[J]] then
        begin
          Values[ColFields[J]] := Value;
          Include(Result[I - 1].Fields, ColFields[J]);
        end;
      end;
      if Result[I - 1].Fields = [] then Status := isUnchanged
      else if not CanWriteTags(Info.FileName) then Status := isNotWritable
      else Status := isChange;
    end;
end;

end.
