unit AsfReader;

{ WMA/ASF: audio properties from the File and Stream Properties objects, tags from the
  Content Description (title, author, copyright, description), the Extended Content
  Description (WM/* attributes) and the Metadata (Library) objects inside the Header
  Extension, where large values such as big WM/Picture items live. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, AudioTypes;

const
  GuidHeader = '75B22630-668E-11CF-A6D9-00AA0062CE6C';
  GuidFileProps = '8CABDCA1-A947-11CF-8EE4-00C00C205365';
  GuidStreamProps = 'B7DC0791-A9B7-11CF-8EE6-00C00C205365';
  GuidAudioMedia = 'F8699E40-5B4D-11CF-A8FD-00805F5C442B';
  GuidContentDesc = '75B22633-668E-11CF-A6D9-00AA0062CE6C';
  GuidExtContentDesc = 'D2D0A440-E307-11D2-97F0-00A0C95EA850';
  GuidHeaderExt = '5FBF03B5-A92E-11CF-8EE3-00C00C205365';
  GuidHeaderExtReserved = 'ABD3D211-A9BA-11CF-8EE6-00C00C205365';
  GuidMetadata = 'C5F8CBEA-5BAF-4877-8467-AA8C44FA4CCA';
  GuidMetadataLibrary = '44231C94-9498-49D1-A141-1D134E457054';
  GuidPadding = '1806D474-CADF-4509-A4BA-9AABCB96AAE8';

  AsfString = 0;
  AsfBytes = 1;
  AsfBool = 2;
  AsfDword = 3;
  AsfQword = 4;
  AsfWord = 5;

  { Extended attribute per field; '' = stored in the Content Description object. }
  WmNames: array[TTagField] of string = ('', '', 'WM/AlbumTitle', 'WM/Year',
    'WM/TrackNumber', 'WM/PartOfSet', 'WM/Genre', '', 'WM/AlbumArtist', 'WM/Composer',
    'WM/BeatsPerMinute', 'WM/Lyrics', 'WM/Conductor', 'WM/Writer', 'WM/OriginalArtist',
    'WM/ModifiedBy', 'WM/Publisher', 'WM/CatalogNo', 'WM/ISRC', '', 'WM/EncodedBy',
    'WM/AuthorURL', 'WM/ContentGroupDescription', 'WM/SubTitle', 'WM/Mood',
    'WM/InitialKey', 'WM/TitleSortOrder', 'WM/ArtistSortOrder', 'WM/AlbumArtistSortOrder',
    'WM/AlbumSortOrder', 'WM/ComposerSortOrder', 'WM/IsCompilation', '');

function GuidBytes(const G: string): TBytes;
function IsGuid(const B: TBytes; P: SizeInt; const G: string): Boolean;
{ UTF-16LE with a terminating zero character. }
function Utf16z(const S: string): TBytes;
{ Attribute names written by TagKlon (and their old variants), compared case-insensitively. }
function IsManagedAttr(const Name: string): Boolean;
procedure ReadAsf(S: TStream; Info: TAudioInfo);

implementation

uses
  TagUtils;

resourcestring
  rsIkkeEnWmaAsfFil = 'Ikke en WMA/ASF-fil';
  rsUgyldigAsfHeader = 'Ugyldig ASF-header';


function GuidBytes(const G: string): TBytes;
var
  Hex: string;
  I: Integer;
  Raw: array[0..15] of Byte;
begin
  Hex := StringReplace(G, '-', '', [rfReplaceAll]);
  for I := 0 to 15 do Raw[I] := StrToInt('$' + Copy(Hex, I * 2 + 1, 2));
  SetLength(Result, 16);
  // Data1 (4 bytes), Data2 and Data3 (2 bytes each) are little-endian
  Result[0] := Raw[3]; Result[1] := Raw[2]; Result[2] := Raw[1]; Result[3] := Raw[0];
  Result[4] := Raw[5]; Result[5] := Raw[4];
  Result[6] := Raw[7]; Result[7] := Raw[6];
  for I := 8 to 15 do Result[I] := Raw[I];
end;

function IsGuid(const B: TBytes; P: SizeInt; const G: string): Boolean;
var
  R: TBytes;
begin
  R := GuidBytes(G);
  Result := (P + 16 <= Length(B)) and CompareMem(@B[P], @R[0], 16);
end;

function Utf16z(const S: string): TBytes;
var
  W: UnicodeString;
begin
  W := UTF8Decode(S);
  SetLength(Result, (Length(W) + 1) * 2);
  if Length(W) > 0 then Move(W[1], Result[0], Length(W) * 2);
  Result[High(Result) - 1] := 0;
  Result[High(Result)] := 0;
end;

function IsManagedAttr(const Name: string): Boolean;
var
  F: TTagField;
begin
  for F := Low(TTagField) to High(TTagField) do
    if (WmNames[F] <> '') and SameText(Name, WmNames[F]) then Exit(True);
  Result := SameText(Name, 'WM/Track') or SameText(Name, 'TotalTracks') or
    SameText(Name, 'WM/Picture') or SameText(Name, 'WM/UserWebURL');
end;

{ Text without the trailing zero character(s). }
function Utf16Text(const B: TBytes; P, Len: SizeInt): string;
begin
  while (Len >= 2) and (B[P + Len - 2] = 0) and (B[P + Len - 1] = 0) do Dec(Len, 2);
  Result := UTF16ToUTF8(B, P, Len, False);
end;

function ValueText(const B: TBytes; P, Len: SizeInt; DataType: Word): string;
begin
  case DataType of
    AsfString: Result := Utf16Text(B, P, Len);
    AsfBool: if Len >= 2 then Result := BoolToStr(B[P] <> 0, 'True', 'False') else Result := '';
    AsfDword: if Len >= 4 then Result := IntToStr(LE32(B, P)) else Result := '';
    AsfQword: if Len >= 8 then Result := IntToStr(LE64(B, P)) else Result := '';
    AsfWord: if Len >= 2 then Result := IntToStr(LE16(B, P)) else Result := '';
  else
    Result := '';
  end;
end;

{ Ends after the zero character of a UTF-16 string starting at P. }
function SkipUtf16z(const B: TBytes; P: SizeInt): SizeInt;
begin
  while (P + 1 < Length(B)) and not ((B[P] = 0) and (B[P + 1] = 0)) do Inc(P, 2);
  Result := P + 2;
end;

type
  TTrackParts = record
    Number, Total: string;
    ZeroBased: Integer;
  end;

procedure AddPictureBlob(const B: TBytes; P, Len: SizeInt; Info: TAudioInfo);
var
  PicType: Byte;
  DataLen: Cardinal;
  MimeEnd, DescEnd: SizeInt;
begin
  if Len < 9 then Exit;
  PicType := B[P];
  DataLen := LE32(B, P + 1);
  MimeEnd := SkipUtf16z(B, P + 5);
  DescEnd := SkipUtf16z(B, MimeEnd);
  if DescEnd + Int64(DataLen) > P + Len then Exit;
  Info.HasCover := True;
  Info.AddPicture(PicType, Utf16Text(B, P + 5, MimeEnd - P - 5),
    Utf16Text(B, MimeEnd, DescEnd - MimeEnd), Copy(B, DescEnd, DataLen));
end;

procedure HandleAttr(const Name: string; const B: TBytes; P, Len: SizeInt; DataType: Word;
  Info: TAudioInfo; var Track: TTrackParts);
var
  F: TTagField;
  V: string;
begin
  if SameText(Name, 'WM/Picture') then
  begin
    if DataType = AsfBytes then AddPictureBlob(B, P, Len, Info);
    Exit;
  end;
  V := ValueText(B, P, Len, DataType);
  if V = '' then Exit;
  if SameText(Name, 'WM/TrackNumber') then begin Track.Number := Trim(V); Exit; end;
  if SameText(Name, 'TotalTracks') then begin Track.Total := Trim(V); Exit; end;
  if SameText(Name, 'WM/Track') then begin Track.ZeroBased := StrToIntDef(Trim(V), -1); Exit; end;
  if SameText(Name, 'WM/UserWebURL') then begin Info.SetField(tfUrl, V, False); Exit; end;
  for F := Low(TTagField) to High(TTagField) do
    if (WmNames[F] <> '') and SameText(Name, WmNames[F]) then
    begin
      if F = tfCompilation then Info.SetField(F, FlagValue(V))
      else if F = tfLyrics then Info.SetField(F, V, False)
      else Info.AppendField(F, CleanTagText(V));
      Exit;
    end;
end;

procedure ReadContentDesc(const B: TBytes; P, Limit: SizeInt; Info: TAudioInfo);
var
  Lens: array[0..4] of Word;
  I: Integer;
  Q: SizeInt;
  Texts: array[0..4] of string;
begin
  if P + 10 > Limit then Exit;
  for I := 0 to 4 do Lens[I] := LE16(B, P + I * 2);
  Q := P + 10;
  for I := 0 to 4 do
  begin
    if Q + Lens[I] > Limit then Exit;
    Texts[I] := CleanTagText(Utf16Text(B, Q, Lens[I]));
    Inc(Q, Lens[I]);
  end;
  Info.SetField(tfTitle, Texts[0]);
  Info.SetField(tfArtist, Texts[1]);
  Info.SetField(tfCopyright, Texts[2]);
  Info.SetField(tfComment, Texts[3]);
end;

procedure ReadExtContentDesc(const B: TBytes; P, Limit: SizeInt; Info: TAudioInfo;
  var Track: TTrackParts);
var
  Count, I: Integer;
  NameLen, DataType, ValLen: Word;
  Name: string;
begin
  if P + 2 > Limit then Exit;
  Count := LE16(B, P);
  Inc(P, 2);
  for I := 1 to Count do
  begin
    if P + 2 > Limit then Exit;
    NameLen := LE16(B, P);
    if P + 6 + NameLen > Limit then Exit;
    Name := Utf16Text(B, P + 2, NameLen);
    DataType := LE16(B, P + 2 + NameLen);
    ValLen := LE16(B, P + 4 + NameLen);
    P := P + 6 + NameLen;
    if P + ValLen > Limit then Exit;
    HandleAttr(Name, B, P, ValLen, DataType, Info, Track);
    Inc(P, ValLen);
  end;
end;

{ Metadata and Metadata Library objects share their record layout. }
procedure ReadMetadataRecords(const B: TBytes; P, Limit: SizeInt; Info: TAudioInfo;
  var Track: TTrackParts);
var
  Count, I: Integer;
  NameLen, DataType: Word;
  DataLen: Cardinal;
  Name: string;
begin
  if P + 2 > Limit then Exit;
  Count := LE16(B, P);
  Inc(P, 2);
  for I := 1 to Count do
  begin
    if P + 12 > Limit then Exit;
    NameLen := LE16(B, P + 4);
    DataType := LE16(B, P + 6);
    DataLen := LE32(B, P + 8);
    if P + 12 + NameLen + Int64(DataLen) > Limit then Exit;
    // only file-wide values (stream 0)
    if LE16(B, P + 2) = 0 then
    begin
      Name := Utf16Text(B, P + 12, NameLen);
      HandleAttr(Name, B, P + 12 + NameLen, DataLen, DataType, Info, Track);
    end;
    P := P + 12 + NameLen + DataLen;
  end;
end;

procedure ReadAsf(S: TStream; Info: TAudioInfo);
var
  B: TBytes;
  HeaderSize, Size, P, Q, ExtEnd: Int64;
  Track: TTrackParts;
  Duration, Preroll: QWord;
  Codec: Word;
  AnyTag: Boolean;
begin
  Info.Supported := True;
  S.Position := 0;
  B := ReadStreamBytes(S, 30);
  if (Length(B) < 30) or not IsGuid(B, 0, GuidHeader) then
    raise Exception.Create(rsIkkeEnWmaAsfFil);
  HeaderSize := LE64(B, 16);
  if (HeaderSize < 30) or (HeaderSize > S.Size) or (HeaderSize > 256 * 1024 * 1024) then
    raise Exception.Create(rsUgyldigAsfHeader);
  S.Position := 0;
  B := ReadStreamBytes(S, HeaderSize);
  Info.Codec := 'WMA';
  Track.Number := '';
  Track.Total := '';
  Track.ZeroBased := -1;
  AnyTag := False;
  P := 30;
  while P + 24 <= HeaderSize do
  begin
    Size := LE64(B, P + 16);
    if (Size < 24) or (P + Size > HeaderSize) then Break;
    if IsGuid(B, P, GuidFileProps) and (Size >= 24 + 80) then
    begin
      Duration := LE64(B, P + 24 + 40);
      Preroll := LE64(B, P + 24 + 56);
      Info.Duration := Duration / 1e7 - Preroll / 1000;
      if Info.Duration < 0 then Info.Duration := 0;
    end
    else if IsGuid(B, P, GuidStreamProps) and IsGuid(B, P + 24, GuidAudioMedia) and
      (Size >= 24 + 54 + 16) then
    begin
      Q := P + 24 + 54;
      Codec := LE16(B, Q);
      Info.Channels := LE16(B, Q + 2);
      Info.SampleRate := LE32(B, Q + 4);
      Info.Bitrate := Round(LE32(B, Q + 8) * 8 / 1000);
      case Codec of
        $0160: Info.Codec := 'WMA v1';
        $0161: Info.Codec := 'WMA';
        $0162: Info.Codec := 'WMA Pro';
        $0163: Info.Codec := 'WMA Lossless';
        $000A: Info.Codec := 'WMA Voice';
        $0055: Info.Codec := 'MP3 (ASF)';
      end;
    end
    else if IsGuid(B, P, GuidContentDesc) then
    begin
      ReadContentDesc(B, P + 24, P + Size, Info);
      AnyTag := True;
    end
    else if IsGuid(B, P, GuidExtContentDesc) then
    begin
      ReadExtContentDesc(B, P + 24, P + Size, Info, Track);
      AnyTag := True;
    end
    else if IsGuid(B, P, GuidHeaderExt) and (Size >= 46) then
    begin
      Q := P + 46;
      ExtEnd := P + Size;
      while Q + 24 <= ExtEnd do
      begin
        Size := LE64(B, Q + 16);
        if (Size < 24) or (Q + Size > ExtEnd) then Break;
        if IsGuid(B, Q, GuidMetadataLibrary) or IsGuid(B, Q, GuidMetadata) then
          ReadMetadataRecords(B, Q + 24, Q + Size, Info, Track);
        Inc(Q, Size);
      end;
      Size := ExtEnd - P;
    end;
    Inc(P, Size);
  end;
  if AnyTag then Info.AddTagType('ASF');
  if (Track.Number = '') and (Track.ZeroBased >= 0) then
    Track.Number := IntToStr(Track.ZeroBased + 1);
  if Track.Number <> '' then
    if Track.Total <> '' then
      Info.SetField(tfTrack, Track.Number + '/' + Track.Total)
    else
      Info.SetField(tfTrack, Track.Number);
end;

end.
