unit AudioTypes;

{ Format-independent result of reading one audio file. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  TTagField = (tfTitle, tfArtist, tfAlbum, tfYear, tfTrack, tfDisc, tfGenre,
    tfComment, tfAlbumArtist, tfComposer, tfBpm,
    // further fields (editor tabs "Flere felter", "Sortering", "Sangtekst")
    tfLyrics, tfConductor, tfLyricist, tfOrigArtist, tfRemixer, tfPublisher, tfCatalogNo,
    tfIsrc, tfCopyright, tfEncodedBy, tfUrl, tfGrouping, tfSubtitle, tfMood, tfInitialKey,
    tfSortTitle, tfSortArtist, tfSortAlbumArtist, tfSortAlbum, tfSortComposer);

  TTagPicture = record
    PicType: Byte;       // ID3/FLAC picture type, 3 = front cover
    MimeType: string;    // 'image/jpeg' or 'image/png'
    Description: string;
    Data: TBytes;
  end;
  TTagPictures = array of TTagPicture;

  TAudioInfo = class
  public
    FileName: string;
    FileSize: Int64;
    Fields: array[TTagField] of string;
    TagTypes: string;    // e.g. 'ID3v2.3, ID3v1'
    Codec: string;       // e.g. 'MP3', 'FLAC', 'AAC'
    HasCover: Boolean;
    Duration: Double;    // seconds
    Bitrate: Integer;    // kbit/s
    SampleRate: Integer; // Hz
    Channels: Integer;
    Supported: Boolean;  // False = listed, but tags are not read yet
    Error: string;
    { Set before reading to keep picture data (the file list only needs HasCover). }
    WantPictures: Boolean;
    Pictures: TTagPictures;
    { Ticked in the file list; batch functions work on ticked files. }
    Checked: Boolean;
    { Hidden from the list by "Skjul valgte filer" until "Vis alle". }
    Hidden: Boolean;
    { Empty values never erase an existing field. }
    procedure SetField(F: TTagField; const V: string; Overwrite: Boolean = True);
    { Adds a further value ('A; B'), used for repeated Vorbis comments. }
    procedure AppendField(F: TTagField; const V: string);
    procedure AddTagType(const T: string);
    procedure AddPicture(APicType: Byte; const AMime, ADescription: string; const AData: TBytes);
  end;
  TAudioInfoArray = array of TAudioInfo;

const
  TagFieldCaptions: array[TTagField] of string = ('Titel', 'Kunstner', 'Album',
    'År', 'Spor', 'Disc', 'Genre', 'Kommentar', 'Albumkunstner', 'Komponist', 'BPM',
    'Sangtekst', 'Dirigent', 'Tekstforfatter', 'Oprindelig kunstner', 'Remixet af',
    'Pladeselskab', 'Katalognr.', 'ISRC', 'Copyright', 'Kodet af', 'URL', 'Gruppering',
    'Undertitel', 'Stemning', 'Toneart', 'Sortér titel', 'Sortér kunstner',
    'Sortér albumkunstner', 'Sortér album', 'Sortér komponist');
  PicTypeFrontCover = 3;

{ 'image/png' / 'image/jpeg' from the data signature; Fallback if unknown. }
function DetectImageMime(const Data: TBytes; const Fallback: string = 'image/jpeg'): string;
{ Pixel size from PNG/JPEG headers; False if it cannot be determined. }
function ImageDimensions(const Data: TBytes; out W, H: Integer): Boolean;
function PictureTypeName(T: Byte): string;

implementation

procedure TAudioInfo.SetField(F: TTagField; const V: string; Overwrite: Boolean);
var
  T: string;
begin
  T := Trim(V);
  if T = '' then Exit;
  if Overwrite or (Fields[F] = '') then
    Fields[F] := T;
end;

procedure TAudioInfo.AppendField(F: TTagField; const V: string);
var
  T: string;
begin
  T := Trim(V);
  if T = '' then Exit;
  if Fields[F] = '' then
    Fields[F] := T
  else
    Fields[F] := Fields[F] + '; ' + T;
end;

procedure TAudioInfo.AddTagType(const T: string);
begin
  if TagTypes = '' then
    TagTypes := T
  else
    TagTypes := TagTypes + ', ' + T;
end;

procedure TAudioInfo.AddPicture(APicType: Byte; const AMime, ADescription: string; const AData: TBytes);
var
  N: Integer;
begin
  if Length(AData) = 0 then Exit;
  HasCover := True;
  if not WantPictures then Exit;
  N := Length(Pictures);
  SetLength(Pictures, N + 1);
  Pictures[N].PicType := APicType;
  if (AMime = '') or (Pos('/', AMime) = 0) then
    Pictures[N].MimeType := DetectImageMime(AData)
  else
    Pictures[N].MimeType := LowerCase(AMime);
  Pictures[N].Description := ADescription;
  Pictures[N].Data := AData;
end;

function DetectImageMime(const Data: TBytes; const Fallback: string): string;
begin
  if (Length(Data) >= 8) and (Data[0] = $89) and (Data[1] = Ord('P')) and
    (Data[2] = Ord('N')) and (Data[3] = Ord('G')) then
    Result := 'image/png'
  else if (Length(Data) >= 3) and (Data[0] = $FF) and (Data[1] = $D8) then
    Result := 'image/jpeg'
  else if (Length(Data) >= 6) and (Data[0] = Ord('G')) and (Data[1] = Ord('I')) and (Data[2] = Ord('F')) then
    Result := 'image/gif'
  else if (Length(Data) >= 2) and (Data[0] = Ord('B')) and (Data[1] = Ord('M')) then
    Result := 'image/bmp'
  else
    Result := Fallback;
end;

function ImageDimensions(const Data: TBytes; out W, H: Integer): Boolean;
var
  P, SegLen: SizeInt;
  M: Byte;
begin
  W := 0;
  H := 0;
  Result := False;
  if DetectImageMime(Data, '') = 'image/png' then
  begin
    if Length(Data) < 24 then Exit;
    W := (Data[16] shl 24) or (Data[17] shl 16) or (Data[18] shl 8) or Data[19];
    H := (Data[20] shl 24) or (Data[21] shl 16) or (Data[22] shl 8) or Data[23];
    Exit(True);
  end;
  if DetectImageMime(Data, '') <> 'image/jpeg' then Exit;
  P := 2;
  while P + 9 < Length(Data) do
  begin
    if Data[P] <> $FF then Exit;
    M := Data[P + 1];
    if M = $FF then begin Inc(P); Continue; end; // fill byte
    if (M = $D8) or ((M >= $D0) and (M <= $D7)) or (M = $01) then begin Inc(P, 2); Continue; end;
    SegLen := (Data[P + 2] shl 8) or Data[P + 3];
    // SOF0..SOF15 except DHT (C4), JPG (C8), DAC (CC)
    if (M >= $C0) and (M <= $CF) and not (M in [$C4, $C8, $CC]) then
    begin
      H := (Data[P + 5] shl 8) or Data[P + 6];
      W := (Data[P + 7] shl 8) or Data[P + 8];
      Exit(True);
    end;
    Inc(P, 2 + SegLen);
  end;
end;

function PictureTypeName(T: Byte): string;
begin
  case T of
    0: Result := 'Andet';
    1, 2: Result := 'Fil-ikon';
    3: Result := 'Forside';
    4: Result := 'Bagside';
    5: Result := 'Indlægsseddel';
    6: Result := 'Medie (CD)';
    7: Result := 'Solist';
    8: Result := 'Kunstner';
    9: Result := 'Dirigent';
    10: Result := 'Orkester';
    11: Result := 'Komponist';
    12: Result := 'Tekstforfatter';
    13: Result := 'Optagested';
    14, 15: Result := 'Under optagelse';
    18: Result := 'Illustration';
    19: Result := 'Kunstnerlogo';
    20: Result := 'Udgiverlogo';
  else
    Result := 'Billede';
  end;
end;

end.
