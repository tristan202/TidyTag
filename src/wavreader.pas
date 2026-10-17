unit WavReader;

{ WAV (RIFF) and AIFF/AIFC: audio properties from 'fmt '/'data' resp. 'COMM', tags from an
  ID3v2 chunk ('id3 ' / 'ID3 '). RIFF LIST/INFO fills fields the ID3 tag does not set;
  AIFF NAME/AUTH/ANNO/(c) text chunks are only read when there is no ID3 chunk. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, AudioTypes;

type
  TChunk = record
    ID: string;       // four characters as stored
    HeaderPos: Int64; // position of the chunk ID
    DataPos: Int64;   // position of the chunk data
    Size: Int64;      // data size as stored (without pad byte)
  end;
  TChunkArray = array of TChunk;

  TChunkFile = record
    IsAiff: Boolean;  // big-endian FORM container instead of RIFF
    FormType: string; // 'WAVE', 'AIFF' or 'AIFC'
    Chunks: TChunkArray;
  end;

{ Lists the top-level chunks. Raises if the file is not RIFF/WAVE or FORM/AIFF. }
function ReadChunkFile(S: TStream): TChunkFile;
{ The ID3 chunk and the RIFF LIST/INFO chunk are the only chunks the writer replaces. }
function IsTagChunk(S: TStream; const C: TChunk): Boolean;
function IsID3ChunkID(const ID: string): Boolean;
{ RIFF INFO id -> field; False for ids the program does not manage. }
function InfoField(const ID: string; out F: TTagField): Boolean;
procedure ReadWavAiff(S: TStream; Info: TAudioInfo);

implementation

uses
  Math, TagUtils, Mp3Reader;

resourcestring
  rsRfFilerWavOverGb = 'RF64-filer (WAV over 4 GB) understøttes ikke';
  rsIkkeEnWavEllerAiff = 'Ikke en WAV- eller AIFF-fil';


function ReadChunkFile(S: TStream): TChunkFile;
var
  H: TBytes;
  P, Size, Limit: Int64;
  N: Integer;
begin
  Result.Chunks := nil;
  S.Position := 0;
  H := ReadStreamBytes(S, 12);
  if (Length(H) = 12) and BytesAre(H, 0, 'RIFF') and BytesAre(H, 8, 'WAVE') then
    Result.IsAiff := False
  else if (Length(H) = 12) and BytesAre(H, 0, 'FORM') and
    (BytesAre(H, 8, 'AIFF') or BytesAre(H, 8, 'AIFC')) then
    Result.IsAiff := True
  else if (Length(H) = 12) and BytesAre(H, 0, 'RF64') then
    raise Exception.Create(rsRfFilerWavOverGb)
  else
    raise Exception.Create(rsIkkeEnWavEllerAiff);
  Result.FormType := BytesToAscii(H, 8, 4);
  P := 12;
  Limit := S.Size;
  while P + 8 <= Limit do
  begin
    S.Position := P;
    H := ReadStreamBytes(S, 8);
    if Result.IsAiff then Size := BE32(H, 4) else Size := LE32(H, 4);
    if (H[0] < 32) or (H[0] > 126) then Break; // garbage after the last chunk
    N := Length(Result.Chunks);
    SetLength(Result.Chunks, N + 1);
    Result.Chunks[N].ID := BytesToAscii(H, 0, 4);
    Result.Chunks[N].HeaderPos := P;
    Result.Chunks[N].DataPos := P + 8;
    // a truncated last chunk (often 'data') is clipped to the file
    Result.Chunks[N].Size := Min(Size, Limit - P - 8);
    P := P + 8 + Size + (Size and 1);
  end;
end;

function IsID3ChunkID(const ID: string): Boolean;
begin
  Result := (ID = 'id3 ') or (ID = 'ID3 ') or (ID = 'ID32');
end;

function IsTagChunk(S: TStream; const C: TChunk): Boolean;
var
  H: TBytes;
begin
  if IsID3ChunkID(C.ID) then Exit(True);
  Result := False;
  if (C.ID = 'LIST') and (C.Size >= 4) then
  begin
    S.Position := C.DataPos;
    H := ReadStreamBytes(S, 4);
    Result := BytesAre(H, 0, 'INFO');
  end;
end;

function InfoField(const ID: string; out F: TTagField): Boolean;
begin
  Result := True;
  case ID of
    'INAM': F := tfTitle;
    'IART': F := tfArtist;
    'IPRD': F := tfAlbum;
    'ICRD': F := tfYear;
    'IPRT', 'ITRK': F := tfTrack;
    'IGNR': F := tfGenre;
    'ICMT': F := tfComment;
    'ICOP': F := tfCopyright;
    'IMUS': F := tfComposer;
    'IENC': F := tfEncodedBy;
  else
    Result := False;
  end;
end;

{ RIFF text: UTF-8 if the bytes are valid UTF-8, else Windows-1252 (stored as Latin-1 here). }
function InfoText(const B: TBytes; P, Len: SizeInt): string;
var
  I: SizeInt;
  Utf: string;
begin
  while (Len > 0) and (B[P + Len - 1] = 0) do Dec(Len);
  Utf := RawUTF8(B, P, Len);
  // RawUTF8 keeps the bytes; check that they form valid UTF-8
  I := 1;
  while I <= Length(Utf) do
  begin
    case Ord(Utf[I]) of
      $00..$7F: Inc(I);
      $C2..$DF: if (I + 1 <= Length(Utf)) and (Ord(Utf[I + 1]) and $C0 = $80) then Inc(I, 2) else Break;
      $E0..$EF: if (I + 2 <= Length(Utf)) and (Ord(Utf[I + 1]) and $C0 = $80) and
                  (Ord(Utf[I + 2]) and $C0 = $80) then Inc(I, 3) else Break;
      $F0..$F4: if (I + 3 <= Length(Utf)) and (Ord(Utf[I + 1]) and $C0 = $80) and
                  (Ord(Utf[I + 2]) and $C0 = $80) and (Ord(Utf[I + 3]) and $C0 = $80) then Inc(I, 4) else Break;
    else
      Break;
    end;
  end;
  if I > Length(Utf) then
    Result := Utf
  else
    Result := Latin1ToUTF8(B, P, Len);
  Result := CleanTagText(Result);
end;

procedure ReadInfoList(const B: TBytes; Info: TAudioInfo);
var
  P, Size: Int64;
  F: TTagField;
  Any: Boolean;
begin
  Any := False;
  P := 4; // after 'INFO'
  while P + 8 <= Length(B) do
  begin
    Size := LE32(B, P + 4);
    if P + 8 + Size > Length(B) then Size := Length(B) - P - 8;
    if InfoField(BytesToAscii(B, P, 4), F) then
    begin
      Info.SetField(F, InfoText(B, P + 8, Size), Info.Fields[F] = '');
      Any := True;
    end;
    P := P + 8 + Size + (Size and 1);
  end;
  if Any then Info.AddTagType('RIFF INFO');
end;

{ 80-bit IEEE 754 extended (big-endian), as used for the AIFF sample rate. }
function Extended80(const B: TBytes; P: SizeInt): Double;
var
  Expo: Integer;
  Mant: QWord;
begin
  Expo := (BE16(B, P) and $7FFF);
  Mant := BE64(B, P + 2);
  if (Expo = 0) and (Mant = 0) then Exit(0);
  Result := Mant * Power(2, Expo - 16383 - 63);
  if B[P] and $80 <> 0 then Result := -Result;
end;

procedure ReadWavAiff(S: TStream; Info: TAudioInfo);
var
  CF: TChunkFile;
  C: TChunk;
  B: TBytes;
  Tag: TBytesStream;
  TagSize, DataSize, Frames: Int64;
  ByteRate, Bits, FormatTag: Integer;
  HaveID3: Boolean;
begin
  Info.Supported := True;
  CF := ReadChunkFile(S);
  if CF.IsAiff then Info.Codec := CF.FormType else Info.Codec := 'WAV';
  DataSize := -1;
  ByteRate := 0;
  HaveID3 := False;
  // ID3 first so that the text chunks only fill gaps
  for C in CF.Chunks do
    if IsID3ChunkID(C.ID) and not HaveID3 then
    begin
      S.Position := C.DataPos;
      Tag := TBytesStream.Create(ReadStreamBytes(S, C.Size));
      try
        ReadID3v2(Tag, Info, TagSize);
        HaveID3 := TagSize > 0;
      finally
        Tag.Free;
      end;
    end;
  for C in CF.Chunks do
  begin
    if not CF.IsAiff then
    begin
      if (C.ID = 'fmt ') and (C.Size >= 16) then
      begin
        S.Position := C.DataPos;
        B := ReadStreamBytes(S, 16);
        FormatTag := LE16(B, 0);
        Info.Channels := LE16(B, 2);
        Info.SampleRate := LE32(B, 4);
        ByteRate := LE32(B, 8);
        Bits := LE16(B, 14);
        case FormatTag of
          1, $FFFE: Info.Codec := Format('WAV PCM %d-bit', [Bits]);
          3: Info.Codec := Format('WAV float %d-bit', [Bits]);
          $55: Info.Codec := 'WAV (MP3)';
        else
          Info.Codec := Format('WAV (format $%.4x)', [FormatTag]);
        end;
      end
      else if C.ID = 'data' then
        DataSize := C.Size
      else if (C.ID = 'LIST') and (C.Size >= 4) and (C.Size < 16 * 1024 * 1024) then
      begin
        S.Position := C.DataPos;
        B := ReadStreamBytes(S, C.Size);
        if BytesAre(B, 0, 'INFO') then ReadInfoList(B, Info);
      end;
    end
    else
    begin
      if (C.ID = 'COMM') and (C.Size >= 18) then
      begin
        S.Position := C.DataPos;
        B := ReadStreamBytes(S, Min(C.Size, 22));
        Info.Channels := BE16(B, 0);
        Frames := BE32(B, 2);
        Bits := BE16(B, 6);
        Info.SampleRate := Round(Extended80(B, 8));
        if Info.SampleRate > 0 then
        begin
          Info.Duration := Frames / Info.SampleRate;
          Info.Bitrate := Round(Info.SampleRate * Info.Channels * Bits / 1000);
        end;
        if (CF.FormType = 'AIFC') and (Length(B) >= 22) then
          Info.Codec := 'AIFC ' + Trim(BytesToAscii(B, 18, 4))
        else
          Info.Codec := Format('AIFF PCM %d-bit', [Bits]);
      end
      // AIFF text chunks belong to other programs and are never written by us: once an
      // ID3 chunk exists it is the only source, so cleared fields do not come back.
      else if not HaveID3 and ((C.ID = 'NAME') or (C.ID = 'AUTH') or (C.ID = 'ANNO') or
        (C.ID = '(c) ')) and (C.Size < 65536) then
      begin
        S.Position := C.DataPos;
        B := ReadStreamBytes(S, C.Size);
        if Pos('AIFF-tekst', Info.TagTypes) = 0 then Info.AddTagType('AIFF-tekst');
        case C.ID of
          'NAME': Info.SetField(tfTitle, InfoText(B, 0, Length(B)), Info.Fields[tfTitle] = '');
          'AUTH': Info.SetField(tfArtist, InfoText(B, 0, Length(B)), Info.Fields[tfArtist] = '');
          'ANNO': Info.SetField(tfComment, InfoText(B, 0, Length(B)), Info.Fields[tfComment] = '');
          '(c) ': Info.SetField(tfCopyright, InfoText(B, 0, Length(B)), Info.Fields[tfCopyright] = '');
        end;
      end;
    end;
  end;
  if (not CF.IsAiff) and (DataSize >= 0) and (ByteRate > 0) then
  begin
    Info.Duration := DataSize / ByteRate;
    Info.Bitrate := Round(ByteRate * 8 / 1000);
  end;
end;

end.
