unit ApeTag;

{ APEv2 tags (Monkey's Audio, WavPack, Musepack, OptimFROG): reading and writing.
  The tag sits at the end of the file, before an optional ID3v1 tag. Writing replaces it
  in place (the audio before it is never touched); unknown items are kept, pictures are
  stored as 'Cover Art (Front)' etc. (file name, zero byte, image data). An existing
  ID3v1 tag is kept and updated so both agree. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, AudioTypes;

type
  TApeLocation = record
    Found: Boolean;
    Start: Int64;     // first byte of the tag (header, or first item if there is no header)
    Size: Int64;      // whole tag incl. header and footer
    Version: Cardinal;
    HasID3v1: Boolean;
    AudioEnd: Int64;  // where the tag starts, or where it would go
  end;

function FindApeTag(S: TStream): TApeLocation;
{ Reads the APE tag (if any). Returns True when one was found. }
function ReadApeTag(S: TStream; Info: TAudioInfo): Boolean;
procedure WriteApeTags(const FileName: string; Info: TAudioInfo);

implementation

uses
  StrUtils, TagUtils, ID3Writer;

const
  FlagHasHeader = Cardinal(1) shl 31;
  FlagIsHeader = Cardinal(1) shl 29;
  ItemBinary = 1 shl 1;

  FieldKeys: array[TTagField] of string = ('Title', 'Artist', 'Album', 'Year', 'Track',
    'Disc', 'Genre', 'Comment', 'Album Artist', 'Composer', 'BPM', 'Lyrics', 'Conductor',
    'Lyricist', 'Original Artist', 'MixArtist', 'Label', 'CatalogNumber', 'ISRC',
    'Copyright', 'EncodedBy', 'Weblink', 'Grouping', 'Subtitle', 'Mood', 'Key',
    'TitleSort', 'ArtistSort', 'AlbumArtistSort', 'AlbumSort', 'ComposerSort',
    'Compilation', 'Podcast');

  PicNames: array[0..20] of string = ('Other', 'Png Icon', 'Icon', 'Front', 'Back',
    'Leaflet', 'Media', 'Lead Artist', 'Artist', 'Conductor', 'Band', 'Composer',
    'Lyricist', 'Recording Location', 'During Recording', 'During Performance',
    'Video Capture', 'Fish', 'Illustration', 'Band Logotype', 'Publisher Logotype');

{ Key -> field, case-insensitive, incl. common alternative spellings. }
function KeyField(const Key: string; out F: TTagField): Boolean;
var
  K: string;
  G: TTagField;
begin
  K := LowerCase(Key);
  for G := Low(TTagField) to High(TTagField) do
    if K = LowerCase(FieldKeys[G]) then
    begin
      F := G;
      Exit(True);
    end;
  Result := True;
  case K of
    'albumartist', 'album_artist': F := tfAlbumArtist;
    'date': F := tfYear;
    'tracknumber': F := tfTrack;
    'discnumber': F := tfDisc;
    'publisher', 'organization': F := tfPublisher;
    'catalog': F := tfCatalogNo;
    'unsyncedlyrics', 'unsynced lyrics': F := tfLyrics;
    'initialkey', 'initial key': F := tfInitialKey;
    'encoded by', 'encoder': F := tfEncodedBy;
    'url', 'related': F := tfUrl;
    'remixer': F := tfRemixer;
    'originalartist', 'origartist': F := tfOrigArtist;
  else
    Result := False;
  end;
end;

{ 'Cover Art (Front)' -> 3; -1 if the key is no picture. }
function PicKeyType(const Key: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  if not AnsiStartsText('Cover Art (', Key) then Exit;
  for I := 0 to High(PicNames) do
    if SameText(Key, 'Cover Art (' + PicNames[I] + ')') then Exit(I);
  Result := 0;
end;

function FindApeTag(S: TStream): TApeLocation;
var
  B: TBytes;
  FooterPos, Size: Int64;
  Flags: Cardinal;
begin
  Result.Found := False;
  Result.HasID3v1 := False;
  Result.Start := 0;
  Result.Size := 0;
  Result.Version := 0;
  FooterPos := S.Size - 32;
  if S.Size >= 128 then
  begin
    S.Position := S.Size - 128;
    B := ReadStreamBytes(S, 3);
    if BytesAre(B, 0, 'TAG') then
    begin
      Result.HasID3v1 := True;
      Dec(FooterPos, 128);
    end;
  end;
  Result.AudioEnd := FooterPos + 32;
  if FooterPos < 0 then Exit;
  S.Position := FooterPos;
  B := ReadStreamBytes(S, 32);
  if (Length(B) < 32) or not BytesAre(B, 0, 'APETAGEX') then Exit;
  Flags := LE32(B, 20);
  if Flags and FlagIsHeader <> 0 then Exit;
  Size := LE32(B, 12); // items + footer
  if Flags and FlagHasHeader <> 0 then Inc(Size, 32);
  if (Size < 32) or (Size > FooterPos + 32) then Exit;
  Result.Found := True;
  Result.Version := LE32(B, 8);
  Result.Size := Size;
  Result.Start := FooterPos + 32 - Size;
  Result.AudioEnd := Result.Start;
end;

type
  TApeItem = record
    Key: string;
    Flags: Cardinal;
    Value: TBytes;
  end;
  TApeItems = array of TApeItem;

function ParseItems(S: TStream; const Loc: TApeLocation): TApeItems;
var
  B: TBytes;
  P, Stop, Len, KeyEnd: Int64;
  N: Integer;
begin
  Result := nil;
  S.Position := Loc.Start;
  B := ReadStreamBytes(S, Loc.Size);
  P := 0;
  if BytesAre(B, 0, 'APETAGEX') then P := 32; // header
  Stop := Length(B) - 32;
  while P + 8 < Stop do
  begin
    Len := LE32(B, P);
    KeyEnd := P + 8;
    while (KeyEnd < Stop) and (B[KeyEnd] <> 0) do Inc(KeyEnd);
    if (KeyEnd >= Stop) or (KeyEnd + 1 + Len > Stop) then Break;
    N := Length(Result);
    SetLength(Result, N + 1);
    Result[N].Flags := LE32(B, P + 4);
    Result[N].Key := BytesToAscii(B, P + 8, KeyEnd - P - 8);
    Result[N].Value := Copy(B, KeyEnd + 1, Len);
    P := KeyEnd + 1 + Len;
  end;
end;

function ReadApeTag(S: TStream; Info: TAudioInfo): Boolean;
var
  Loc: TApeLocation;
  Items: TApeItems;
  It: TApeItem;
  F: TTagField;
  V, FileName: string;
  T, Z: Integer;
begin
  Loc := FindApeTag(S);
  Result := Loc.Found;
  if not Result then Exit;
  if Loc.Version >= 2000 then Info.AddTagType('APEv2') else Info.AddTagType('APEv1');
  Items := ParseItems(S, Loc);
  for It in Items do
  begin
    T := PicKeyType(It.Key);
    if (T >= 0) and (It.Flags and 6 = ItemBinary) then
    begin
      Z := 0;
      while (Z < Length(It.Value)) and (It.Value[Z] <> 0) do Inc(Z);
      if Z >= Length(It.Value) then Continue;
      FileName := RawUTF8(It.Value, 0, Z);
      // the stored name is a file name; 'cover.jpg' etc. carry no description
      if AnsiStartsText('cover.', FileName) then FileName := '';
      Info.HasCover := True;
      Info.AddPicture(T, '', FileName, Copy(It.Value, Z + 1, MaxInt));
    end
    else if (It.Flags and 6 = 0) and KeyField(It.Key, F) then
    begin
      V := StringReplace(RawUTF8(It.Value, 0, Length(It.Value)), #0, '; ', [rfReplaceAll]);
      if F in [tfCompilation, tfPodcast] then
        Info.SetField(F, FlagValue(V))
      else if F = tfLyrics then
        Info.SetField(F, V, Info.Fields[F] = '')
      else
        Info.AppendField(F, CleanTagText(V));
    end;
  end;
end;

procedure AddItem(Dest: TStream; const Key: string; Flags: Cardinal; const Value: TBytes;
  var Count: Integer);
begin
  WriteLE32(Dest, Length(Value));
  WriteLE32(Dest, Flags);
  WriteAscii(Dest, Key);
  Dest.WriteByte(0);
  WriteBytes(Dest, Value);
  Inc(Count);
end;

procedure WriteHeaderFooter(Dest: TStream; ItemsSize, Count: Integer; IsHeader: Boolean);
var
  Flags: Cardinal;
begin
  WriteAscii(Dest, 'APETAGEX');
  WriteLE32(Dest, 2000);
  WriteLE32(Dest, ItemsSize + 32);
  WriteLE32(Dest, Count);
  Flags := FlagHasHeader;
  if IsHeader then Flags := Flags or FlagIsHeader;
  WriteLE32(Dest, Flags);
  WriteZeros(Dest, 8);
end;

procedure WriteApeTags(const FileName: string; Info: TAudioInfo);
var
  S: TFileStream;
  Loc: TApeLocation;
  Old: TApeItems;
  It: TApeItem;
  Items: TBytesStream;
  Tag, V1, Data: TBytes;
  F: TTagField;
  Count, I: Integer;
  Used: array[0..20] of Boolean;
  Name: string;
begin
  S := TFileStream.Create(FileName, fmOpenReadWrite or fmShareExclusive);
  try
    Loc := FindApeTag(S);
    if Loc.Found then Old := ParseItems(S, Loc) else Old := nil;
    V1 := nil;
    if Loc.HasID3v1 then
    begin
      S.Position := S.Size - 128;
      V1 := ReadStreamBytes(S, 128);
    end;

    Count := 0;
    Items := TBytesStream.Create;
    try
      // unknown items first, in their old order
      for It in Old do
        if (PicKeyType(It.Key) < 0) and not ((It.Flags and 6 = 0) and KeyField(It.Key, F)) then
          AddItem(Items, It.Key, It.Flags and $7, It.Value, Count);
      for F := Low(TTagField) to High(TTagField) do
        if F in [tfCompilation, tfPodcast] then
        begin
          if IsTrueFlag(Info.Fields[F]) then AddItem(Items, FieldKeys[F], 0, UTF8Bytes('1'), Count);
        end
        else if Info.Fields[F] <> '' then
          AddItem(Items, FieldKeys[F], 0, UTF8Bytes(Info.Fields[F]), Count);
      FillChar(Used, SizeOf(Used), 0);
      for I := 0 to High(Info.Pictures) do
      begin
        if Info.Pictures[I].PicType > 20 then Continue;
        if Used[Info.Pictures[I].PicType] then Continue; // one picture per type
        Used[Info.Pictures[I].PicType] := True;
        Name := Info.Pictures[I].Description;
        if Name = '' then
          if Info.Pictures[I].MimeType = 'image/png' then Name := 'cover.png' else Name := 'cover.jpg';
        Data := UTF8Bytes(Name);
        SetLength(Data, Length(Data) + 1);
        Data[High(Data)] := 0;
        Data := Concat(Data, Info.Pictures[I].Data);
        AddItem(Items, 'Cover Art (' + PicNames[Info.Pictures[I].PicType] + ')', ItemBinary,
          Data, Count);
      end;
      Tag := StreamBytes(Items);
    finally
      Items.Free;
    end;

    S.Size := Loc.AudioEnd;
    S.Position := Loc.AudioEnd;
    if Count > 0 then
    begin
      WriteHeaderFooter(S, Length(Tag), Count, True);
      WriteBytes(S, Tag);
      WriteHeaderFooter(S, Length(Tag), Count, False);
    end;
    WriteBytes(S, V1);
  finally
    S.Free;
  end;
  if Loc.HasID3v1 then UpdateID3v1(FileName, Info);
end;

end.
