unit VorbisReader;

{ FLAC (metadata blocks) and Ogg Vorbis/Opus/FLAC, which share Vorbis comments. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, AudioTypes;

procedure ReadFlac(S: TStream; Info: TAudioInfo);
procedure ReadOgg(S: TStream; Info: TAudioInfo);
{ FLAC PICTURE block body (also used base64-encoded in Vorbis comments). }
procedure ParseFlacPicture(const B: TBytes; Info: TAudioInfo);

implementation

uses
  base64, TagUtils, Mp3Reader;

type
  TPacketArray = array of TBytes;

procedure ParseFlacPicture(const B: TBytes; Info: TAudioInfo);
var
  P: SizeInt;
  PicType, MimeLen, DescLen, DataLen: Cardinal;
  Mime, Desc: string;
begin
  PicType := BE32(B, 0);
  MimeLen := BE32(B, 4);
  P := 8;
  Mime := RawUTF8(B, P, MimeLen);
  Inc(P, MimeLen);
  DescLen := BE32(B, P);
  Inc(P, 4);
  Desc := RawUTF8(B, P, DescLen);
  Inc(P, Int64(DescLen) + 16); // width, height, depth, colours
  DataLen := BE32(B, P);
  Inc(P, 4);
  if P + Int64(DataLen) > Length(B) then Exit;
  Info.AddPicture(PicType and $FF, Mime, Desc, Copy(B, P, DataLen));
end;

procedure ParseBase64Picture(const Value: string; Info: TAudioInfo);
var
  Raw: string;
  B: TBytes;
begin
  if not Info.WantPictures then
  begin
    Info.HasCover := True;
    Exit;
  end;
  Raw := DecodeStringBase64(Value);
  SetLength(B, Length(Raw));
  if Length(Raw) > 0 then Move(Raw[1], B[0], Length(Raw));
  ParseFlacPicture(B, Info);
end;

{ Parses a Vorbis comment block (little-endian lengths) starting at P. }
procedure ParseVorbisComment(const B: TBytes; P: SizeInt; Info: TAudioInfo);
var
  VendorLen, Count, I, Len: Cardinal;
  Entry, Key, Value, TrackTotal, DiscTotal: string;
  Eq: Integer;
begin
  Info.AddTagType('Vorbis');
  TrackTotal := '';
  DiscTotal := '';
  VendorLen := LE32(B, P);
  Inc(P, 4 + Int64(VendorLen));
  Count := LE32(B, P);
  Inc(P, 4);
  for I := 1 to Count do
  begin
    if P + 4 > Length(B) then Break;
    Len := LE32(B, P);
    Inc(P, 4);
    if P + Int64(Len) > Length(B) then Break;
    Entry := RawUTF8(B, P, Len);
    Inc(P, Len);
    Eq := Pos('=', Entry);
    if Eq < 2 then Continue;
    Key := UpperCase(Copy(Entry, 1, Eq - 1));
    Value := Copy(Entry, Eq + 1, MaxInt);
    case Key of
      'TITLE': Info.AppendField(tfTitle, Value);
      'ARTIST': Info.AppendField(tfArtist, Value);
      'ALBUM': Info.AppendField(tfAlbum, Value);
      'DATE': Info.SetField(tfYear, Value);
      'YEAR': Info.SetField(tfYear, Value, False);
      'TRACKNUMBER': Info.SetField(tfTrack, Value);
      'TRACKTOTAL', 'TOTALTRACKS': TrackTotal := Trim(Value);
      'DISCNUMBER': Info.SetField(tfDisc, Value);
      'DISCTOTAL', 'TOTALDISCS': DiscTotal := Trim(Value);
      'GENRE': Info.AppendField(tfGenre, Value);
      'COMMENT': Info.SetField(tfComment, Value);
      'DESCRIPTION': Info.SetField(tfComment, Value, False);
      'ALBUMARTIST', 'ALBUM ARTIST', 'ALBUM_ARTIST': Info.AppendField(tfAlbumArtist, Value);
      'COMPOSER': Info.AppendField(tfComposer, Value);
      'BPM': Info.SetField(tfBpm, Value);
      'METADATA_BLOCK_PICTURE': ParseBase64Picture(Value, Info);
      'COVERART': Info.HasCover := True; // old, non-standard; not loaded
    end;
  end;
  if (TrackTotal <> '') and (Info.Fields[tfTrack] <> '') and (Pos('/', Info.Fields[tfTrack]) = 0) then
    Info.Fields[tfTrack] := Info.Fields[tfTrack] + '/' + TrackTotal;
  if (DiscTotal <> '') and (Info.Fields[tfDisc] <> '') and (Pos('/', Info.Fields[tfDisc]) = 0) then
    Info.Fields[tfDisc] := Info.Fields[tfDisc] + '/' + DiscTotal;
end;

{ STREAMINFO block body -> sample rate, channels, duration. }
procedure ParseStreamInfo(const B: TBytes; P: SizeInt; Info: TAudioInfo);
var
  Total: QWord;
begin
  Info.SampleRate := (Integer(B[P + 10]) shl 12) or (Integer(B[P + 11]) shl 4) or (B[P + 12] shr 4);
  Info.Channels := ((B[P + 12] shr 1) and 7) + 1;
  Total := (QWord(B[P + 13] and $0F) shl 32) or BE32(B, P + 14);
  if Info.SampleRate > 0 then
    Info.Duration := Total / Info.SampleRate;
end;

procedure ReadFlac(S: TStream; Info: TAudioInfo);
var
  Skip: Int64;
  H, B: TBytes;
  Last: Boolean;
  BlockType: Byte;
  Len: Cardinal;
begin
  Info.Supported := True;
  Info.Codec := 'FLAC';
  ReadID3v2(S, Info, Skip); // rare, but some taggers prepend ID3v2
  S.Position := Skip;
  H := ReadStreamBytes(S, 4);
  if not BytesAre(H, 0, 'fLaC') then
    raise Exception.Create('Ikke en gyldig FLAC-fil');
  repeat
    H := ReadStreamBytes(S, 4);
    if Length(H) < 4 then Break;
    Last := H[0] and $80 <> 0;
    BlockType := H[0] and $7F;
    Len := BE24(H, 1);
    case BlockType of
      0: begin
           B := ReadStreamBytes(S, Len);
           if Length(B) >= 18 then ParseStreamInfo(B, 0, Info);
         end;
      4: begin
           B := ReadStreamBytes(S, Len);
           ParseVorbisComment(B, 0, Info);
         end;
      6: if Info.WantPictures then
           ParseFlacPicture(ReadStreamBytes(S, Len), Info)
         else
         begin
           Info.HasCover := True;
           S.Seek(Len, soCurrent);
         end;
    else
      S.Seek(Len, soCurrent);
    end;
  until Last or (S.Position >= S.Size);
  if Info.Duration > 0 then
    Info.Bitrate := Round((S.Size - S.Position) * 8 / Info.Duration / 1000);
end;

{ ---------- Ogg ---------- }

procedure AppendBytes(var Dest: TBytes; const Src: TBytes; P, Len: SizeInt);
var
  Old: SizeInt;
begin
  if Len <= 0 then Exit;
  Old := Length(Dest);
  SetLength(Dest, Old + Len);
  Move(Src[P], Dest[Old], Len);
end;

{ Reads the first Count packets of the first logical stream. }
function ReadOggPackets(S: TStream; Count: Integer): TPacketArray;
const
  MaxBytes = 32 * 1024 * 1024;
var
  H, Segs, Data: TBytes;
  Cur: TBytes;
  NSeg, I: Integer;
  DataLen, DataP, Total: SizeInt;
begin
  Result := nil;
  Cur := nil;
  Total := 0;
  S.Position := 0;
  while Length(Result) < Count do
  begin
    H := ReadStreamBytes(S, 27);
    if (Length(H) < 27) or not BytesAre(H, 0, 'OggS') then Break;
    NSeg := H[26];
    Segs := ReadStreamBytes(S, NSeg);
    if Length(Segs) < NSeg then Break;
    DataLen := 0;
    for I := 0 to NSeg - 1 do Inc(DataLen, Segs[I]);
    Data := ReadStreamBytes(S, DataLen);
    Inc(Total, DataLen);
    if (Length(Data) < DataLen) or (Total > MaxBytes) then Break;
    DataP := 0;
    for I := 0 to NSeg - 1 do
    begin
      AppendBytes(Cur, Data, DataP, Segs[I]);
      Inc(DataP, Segs[I]);
      if Segs[I] < 255 then // packet ends here
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Cur;
        Cur := nil;
        if Length(Result) >= Count then Break;
      end;
    end;
  end;
end;

{ Granule position of the last Ogg page = total samples. }
function LastGranule(S: TStream): Int64;
var
  B: TBytes;
  Start: Int64;
  I: SizeInt;
begin
  Result := 0;
  Start := S.Size - 65536;
  if Start < 0 then Start := 0;
  S.Position := Start;
  B := ReadStreamBytes(S, 65536);
  for I := Length(B) - 27 downto 0 do
    if BytesAre(B, I, 'OggS') then
      Exit(Int64(LE64(B, I + 6)));
end;

procedure ReadOgg(S: TStream; Info: TAudioInfo);
var
  Pk: TPacketArray;
  RateForDuration, PreSkip: Integer;
  Granule: Int64;
begin
  Info.Supported := True;
  Pk := ReadOggPackets(S, 2);
  if Length(Pk) < 1 then
    raise Exception.Create('Ikke en gyldig Ogg-fil');
  RateForDuration := 0;
  PreSkip := 0;
  if (Length(Pk[0]) >= 30) and (Pk[0][0] = 1) and BytesAre(Pk[0], 1, 'vorbis') then
  begin
    Info.Codec := 'Vorbis';
    Info.Channels := Pk[0][11];
    Info.SampleRate := LE32(Pk[0], 12);
    RateForDuration := Info.SampleRate;
    if (Length(Pk) > 1) and (Pk[1][0] = 3) and BytesAre(Pk[1], 1, 'vorbis') then
      ParseVorbisComment(Pk[1], 7, Info);
  end
  else if BytesAre(Pk[0], 0, 'OpusHead') then
  begin
    Info.Codec := 'Opus';
    Info.Channels := Pk[0][9];
    PreSkip := LE16(Pk[0], 10);
    Info.SampleRate := LE32(Pk[0], 12);
    RateForDuration := 48000; // Opus granule positions are always 48 kHz
    if (Length(Pk) > 1) and BytesAre(Pk[1], 0, 'OpusTags') then
      ParseVorbisComment(Pk[1], 8, Info);
  end
  else if (Length(Pk[0]) >= 13 + 34) and (Pk[0][0] = $7F) and BytesAre(Pk[0], 1, 'FLAC') then
  begin
    // Ogg FLAC: mapping header (9 bytes) + 'fLaC' + STREAMINFO block header (4)
    Info.Codec := 'FLAC (Ogg)';
    ParseStreamInfo(Pk[0], 17, Info);
    RateForDuration := Info.SampleRate;
    if (Length(Pk) > 1) and (Length(Pk[1]) > 4) and ((Pk[1][0] and $7F) = 4) then
      ParseVorbisComment(Pk[1], 4, Info);
  end
  else
    raise Exception.Create('Ukendt Ogg-codec');

  if RateForDuration > 0 then
  begin
    Granule := LastGranule(S) - PreSkip;
    if Granule > 0 then
      Info.Duration := Granule / RateForDuration;
  end;
  if Info.Duration > 0 then
    Info.Bitrate := Round(S.Size * 8 / Info.Duration / 1000);
end;

end.
