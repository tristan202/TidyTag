unit TagUtils;

{ Byte helpers and text decoding shared by the tag readers.
  All read functions are bounds-safe and return 0 / '' when out of range. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

function BE16(const B: TBytes; P: SizeInt): Word;
function BE24(const B: TBytes; P: SizeInt): Cardinal;
function BE32(const B: TBytes; P: SizeInt): Cardinal;
function BE64(const B: TBytes; P: SizeInt): QWord;
function LE16(const B: TBytes; P: SizeInt): Word;
function LE32(const B: TBytes; P: SizeInt): Cardinal;
function LE64(const B: TBytes; P: SizeInt): QWord;
function SyncSafe32(const B: TBytes; P: SizeInt): Cardinal;

{ True if the bytes at P equal the ASCII text S. }
function BytesAre(const B: TBytes; P: SizeInt; const S: string): Boolean;
function BytesToAscii(const B: TBytes; P, Len: SizeInt): string;

function Latin1ToUTF8(const B: TBytes; P, Len: SizeInt): string;
function UTF16ToUTF8(const B: TBytes; P, Len: SizeInt; BigEndian: Boolean): string;
function RawUTF8(const B: TBytes; P, Len: SizeInt): string;

{ Reads up to Count bytes from the current stream position. }
function ReadStreamBytes(S: TStream; Count: Int64): TBytes;

{ Removes trailing NULs and turns embedded NULs (multi-value separators) into '; '. }
function CleanTagText(const S: string): string;

function ID3GenreName(Index: Integer): string;
{ Index in the ID3v1 genre list (case-insensitive), -1 if not a standard genre. }
function ID3GenreIndex(const Name: string): Integer;
function ID3GenreCount: Integer;
function FormatDuration(Seconds: Double): string;

{ ---------- writing helpers ---------- }

procedure WriteBE16(S: TStream; V: Word);
procedure WriteBE32(S: TStream; V: Cardinal);
procedure WriteBE64(S: TStream; V: QWord);
procedure WriteLE32(S: TStream; V: Cardinal);
procedure WriteBytes(S: TStream; const B: TBytes);
procedure WriteZeros(S: TStream; Count: Int64);
{ Writes the raw bytes of an ASCII string (atom/frame names, MIME types). }
procedure WriteAscii(S: TStream; const Str: string);
function StreamBytes(S: TBytesStream): TBytes;
function UTF8Bytes(const S: string): TBytes;
procedure CopyStreamRange(Src, Dst: TStream; From, Count: Int64);
procedure PutBE32(var B: TBytes; P: SizeInt; V: Cardinal);
procedure PutBE64(var B: TBytes; P: SizeInt; V: QWord);

{ Name of a temporary file next to Target. }
function TempFileFor(const Target: string): string;
{ Replaces Target by TempName (same folder), as atomically as the OS allows. }
procedure ReplaceFileWith(const TempName, Target: string);

type
  TFileStamp = record
    Valid: Boolean;
    Data: array[0..2] of Int64; // creation, access, write
  end;

function GetFileStamp(const FileName: string): TFileStamp;
procedure SetFileStamp(const FileName: string; const Stamp: TFileStamp);

implementation

{$IFDEF WINDOWS}
uses
  Windows;
{$ENDIF}

function InRange(const B: TBytes; P, Len: SizeInt): Boolean; inline;
begin
  Result := (P >= 0) and (Len >= 0) and (P + Len <= Length(B));
end;

function BE16(const B: TBytes; P: SizeInt): Word;
begin
  if not InRange(B, P, 2) then Exit(0);
  Result := (Word(B[P]) shl 8) or B[P + 1];
end;

function BE24(const B: TBytes; P: SizeInt): Cardinal;
begin
  if not InRange(B, P, 3) then Exit(0);
  Result := (Cardinal(B[P]) shl 16) or (Cardinal(B[P + 1]) shl 8) or B[P + 2];
end;

function BE32(const B: TBytes; P: SizeInt): Cardinal;
begin
  if not InRange(B, P, 4) then Exit(0);
  Result := (Cardinal(B[P]) shl 24) or (Cardinal(B[P + 1]) shl 16) or
    (Cardinal(B[P + 2]) shl 8) or B[P + 3];
end;

function BE64(const B: TBytes; P: SizeInt): QWord;
begin
  if not InRange(B, P, 8) then Exit(0);
  Result := (QWord(BE32(B, P)) shl 32) or BE32(B, P + 4);
end;

function LE16(const B: TBytes; P: SizeInt): Word;
begin
  if not InRange(B, P, 2) then Exit(0);
  Result := B[P] or (Word(B[P + 1]) shl 8);
end;

function LE32(const B: TBytes; P: SizeInt): Cardinal;
begin
  if not InRange(B, P, 4) then Exit(0);
  Result := B[P] or (Cardinal(B[P + 1]) shl 8) or (Cardinal(B[P + 2]) shl 16) or
    (Cardinal(B[P + 3]) shl 24);
end;

function LE64(const B: TBytes; P: SizeInt): QWord;
begin
  if not InRange(B, P, 8) then Exit(0);
  Result := QWord(LE32(B, P)) or (QWord(LE32(B, P + 4)) shl 32);
end;

function SyncSafe32(const B: TBytes; P: SizeInt): Cardinal;
begin
  if not InRange(B, P, 4) then Exit(0);
  Result := (Cardinal(B[P] and $7F) shl 21) or (Cardinal(B[P + 1] and $7F) shl 14) or
    (Cardinal(B[P + 2] and $7F) shl 7) or (B[P + 3] and $7F);
end;

function BytesAre(const B: TBytes; P: SizeInt; const S: string): Boolean;
var
  I: Integer;
begin
  if not InRange(B, P, Length(S)) then Exit(False);
  for I := 1 to Length(S) do
    if B[P + I - 1] <> Ord(S[I]) then Exit(False);
  Result := True;
end;

function BytesToAscii(const B: TBytes; P, Len: SizeInt): string;
var
  I: SizeInt;
begin
  Result := '';
  if not InRange(B, P, Len) then Exit;
  SetLength(Result, Len);
  for I := 0 to Len - 1 do
    if B[P + I] in [32..126] then
      Result[I + 1] := Chr(B[P + I])
    else
      Result[I + 1] := '?';
end;

function Latin1ToUTF8(const B: TBytes; P, Len: SizeInt): string;
var
  U: UnicodeString;
  I: SizeInt;
begin
  Result := '';
  if Len <= 0 then Exit;
  if P + Len > Length(B) then Len := Length(B) - P;
  if (P < 0) or (Len <= 0) then Exit;
  SetLength(U, Len);
  for I := 0 to Len - 1 do
    U[I + 1] := WideChar(B[P + I]);
  Result := UTF8Encode(U);
end;

function UTF16ToUTF8(const B: TBytes; P, Len: SizeInt; BigEndian: Boolean): string;
var
  U: UnicodeString;
  I, N, Count: SizeInt;
  W: Word;
begin
  Result := '';
  if P + Len > Length(B) then Len := Length(B) - P;
  if (P < 0) or (Len < 2) then Exit;
  N := Len div 2;
  SetLength(U, N);
  Count := 0;
  for I := 0 to N - 1 do
  begin
    if BigEndian then
      W := (Word(B[P + 2 * I]) shl 8) or B[P + 2 * I + 1]
    else
      W := B[P + 2 * I] or (Word(B[P + 2 * I + 1]) shl 8);
    if (W = $FEFF) or (W = $FFFE) then Continue; // BOMs of later values in a multi-value frame
    Inc(Count);
    U[Count] := WideChar(W);
  end;
  SetLength(U, Count);
  Result := UTF8Encode(U);
end;

function RawUTF8(const B: TBytes; P, Len: SizeInt): string;
var
  R: RawByteString;
begin
  Result := '';
  if P + Len > Length(B) then Len := Length(B) - P;
  if (P < 0) or (Len <= 0) then Exit;
  SetLength(R, Len);
  Move(B[P], R[1], Len);
  SetCodePage(R, CP_UTF8, False);
  Result := R;
end;

function ReadStreamBytes(S: TStream; Count: Int64): TBytes;
var
  Avail: Int64;
begin
  Result := nil;
  Avail := S.Size - S.Position;
  if Count > Avail then Count := Avail;
  if Count <= 0 then Exit;
  SetLength(Result, Count);
  SetLength(Result, S.Read(Result[0], Count));
end;

function CleanTagText(const S: string): string;
var
  E: Integer;
begin
  E := Length(S);
  while (E > 0) and (S[E] = #0) do Dec(E);
  Result := StringReplace(Copy(S, 1, E), #0, '; ', [rfReplaceAll]);
  Result := Trim(Result);
end;

const
  ID3Genres: array[0..191] of string = (
    'Blues', 'Classic Rock', 'Country', 'Dance', 'Disco', 'Funk', 'Grunge',
    'Hip-Hop', 'Jazz', 'Metal', 'New Age', 'Oldies', 'Other', 'Pop', 'R&B',
    'Rap', 'Reggae', 'Rock', 'Techno', 'Industrial', 'Alternative', 'Ska',
    'Death Metal', 'Pranks', 'Soundtrack', 'Euro-Techno', 'Ambient',
    'Trip-Hop', 'Vocal', 'Jazz+Funk', 'Fusion', 'Trance', 'Classical',
    'Instrumental', 'Acid', 'House', 'Game', 'Sound Clip', 'Gospel', 'Noise',
    'AlternRock', 'Bass', 'Soul', 'Punk', 'Space', 'Meditative',
    'Instrumental Pop', 'Instrumental Rock', 'Ethnic', 'Gothic', 'Darkwave',
    'Techno-Industrial', 'Electronic', 'Pop-Folk', 'Eurodance', 'Dream',
    'Southern Rock', 'Comedy', 'Cult', 'Gangsta', 'Top 40', 'Christian Rap',
    'Pop/Funk', 'Jungle', 'Native American', 'Cabaret', 'New Wave',
    'Psychadelic', 'Rave', 'Showtunes', 'Trailer', 'Lo-Fi', 'Tribal',
    'Acid Punk', 'Acid Jazz', 'Polka', 'Retro', 'Musical', 'Rock & Roll',
    'Hard Rock', 'Folk', 'Folk-Rock', 'National Folk', 'Swing', 'Fast Fusion',
    'Bebob', 'Latin', 'Revival', 'Celtic', 'Bluegrass', 'Avantgarde',
    'Gothic Rock', 'Progressive Rock', 'Psychedelic Rock', 'Symphonic Rock',
    'Slow Rock', 'Big Band', 'Chorus', 'Easy Listening', 'Acoustic', 'Humour',
    'Speech', 'Chanson', 'Opera', 'Chamber Music', 'Sonata', 'Symphony',
    'Booty Bass', 'Primus', 'Porn Groove', 'Satire', 'Slow Jam', 'Club',
    'Tango', 'Samba', 'Folklore', 'Ballad', 'Power Ballad', 'Rhythmic Soul',
    'Freestyle', 'Duet', 'Punk Rock', 'Drum Solo', 'A capella', 'Euro-House',
    'Dance Hall', 'Goa', 'Drum & Bass', 'Club-House', 'Hardcore', 'Terror',
    'Indie', 'BritPop', 'Afro-Punk', 'Polsk Punk', 'Beat',
    'Christian Gangsta Rap', 'Heavy Metal', 'Black Metal', 'Crossover',
    'Contemporary Christian', 'Christian Rock', 'Merengue', 'Salsa',
    'Thrash Metal', 'Anime', 'JPop', 'Synthpop', 'Abstract', 'Art Rock',
    'Baroque', 'Bhangra', 'Big Beat', 'Breakbeat', 'Chillout', 'Downtempo',
    'Dub', 'EBM', 'Eclectic', 'Electro', 'Electroclash', 'Emo',
    'Experimental', 'Garage', 'Global', 'IDM', 'Illbient', 'Industro-Goth',
    'Jam Band', 'Krautrock', 'Leftfield', 'Lounge', 'Math Rock',
    'New Romantic', 'Nu-Breakz', 'Post-Punk', 'Post-Rock', 'Psytrance',
    'Shoegaze', 'Space Rock', 'Trop Rock', 'World Music', 'Neoclassical',
    'Audiobook', 'Audio Theatre', 'Neue Deutsche Welle', 'Podcast',
    'Indie Rock', 'G-Funk', 'Dubstep', 'Garage Rock', 'Psybient');

function ID3GenreName(Index: Integer): string;
begin
  if (Index >= Low(ID3Genres)) and (Index <= High(ID3Genres)) then
    Result := ID3Genres[Index]
  else
    Result := '';
end;

function ID3GenreIndex(const Name: string): Integer;
var
  I: Integer;
begin
  for I := Low(ID3Genres) to High(ID3Genres) do
    if SameText(ID3Genres[I], Name) then Exit(I);
  Result := -1;
end;

function ID3GenreCount: Integer;
begin
  Result := Length(ID3Genres);
end;

function FormatDuration(Seconds: Double): string;
var
  T: Int64;
begin
  if Seconds <= 0 then Exit('');
  T := Round(Seconds);
  if T >= 3600 then
    Result := Format('%d:%.2d:%.2d', [T div 3600, (T div 60) mod 60, T mod 60])
  else
    Result := Format('%d:%.2d', [T div 60, T mod 60]);
end;

procedure WriteBE16(S: TStream; V: Word);
var
  B: array[0..1] of Byte;
begin
  B[0] := V shr 8; B[1] := V and $FF;
  S.WriteBuffer(B, 2);
end;

procedure WriteBE32(S: TStream; V: Cardinal);
var
  B: array[0..3] of Byte;
begin
  B[0] := V shr 24; B[1] := (V shr 16) and $FF; B[2] := (V shr 8) and $FF; B[3] := V and $FF;
  S.WriteBuffer(B, 4);
end;

procedure WriteBE64(S: TStream; V: QWord);
begin
  WriteBE32(S, V shr 32);
  WriteBE32(S, V and $FFFFFFFF);
end;

procedure WriteLE32(S: TStream; V: Cardinal);
var
  B: array[0..3] of Byte;
begin
  B[0] := V and $FF; B[1] := (V shr 8) and $FF; B[2] := (V shr 16) and $FF; B[3] := V shr 24;
  S.WriteBuffer(B, 4);
end;

procedure WriteBytes(S: TStream; const B: TBytes);
begin
  if Length(B) > 0 then S.WriteBuffer(B[0], Length(B));
end;

procedure WriteZeros(S: TStream; Count: Int64);
var
  Z: array[0..4095] of Byte;
  N: Integer;
begin
  FillChar(Z, SizeOf(Z), 0);
  while Count > 0 do
  begin
    if Count > SizeOf(Z) then N := SizeOf(Z) else N := Count;
    S.WriteBuffer(Z, N);
    Dec(Count, N);
  end;
end;

procedure WriteAscii(S: TStream; const Str: string);
begin
  if Str <> '' then S.WriteBuffer(Str[1], Length(Str));
end;

function StreamBytes(S: TBytesStream): TBytes;
begin
  Result := Copy(S.Bytes, 0, S.Size);
end;

function UTF8Bytes(const S: string): TBytes;
var
  U: UTF8String;
begin
  Result := nil;
  U := UTF8String(S);
  SetLength(Result, Length(U));
  if Length(U) > 0 then Move(U[1], Result[0], Length(U));
end;

procedure CopyStreamRange(Src, Dst: TStream; From, Count: Int64);
begin
  if Count <= 0 then Exit;
  Src.Position := From;
  if Dst.CopyFrom(Src, Count) <> Count then
    raise EStreamError.Create('Kunne ikke kopiere lyddata');
end;

procedure PutBE32(var B: TBytes; P: SizeInt; V: Cardinal);
begin
  B[P] := V shr 24; B[P + 1] := (V shr 16) and $FF; B[P + 2] := (V shr 8) and $FF; B[P + 3] := V and $FF;
end;

procedure PutBE64(var B: TBytes; P: SizeInt; V: QWord);
begin
  PutBE32(B, P, V shr 32);
  PutBE32(B, P + 4, V and $FFFFFFFF);
end;

function TempFileFor(const Target: string): string;
begin
  Result := Target + '.tidytag-tmp';
end;

procedure ReplaceFileWith(const TempName, Target: string);
begin
  {$IFDEF WINDOWS}
  if not MoveFileExW(PWideChar(UTF8Decode(TempName)), PWideChar(UTF8Decode(Target)),
    MOVEFILE_REPLACE_EXISTING or $8 {MOVEFILE_WRITE_THROUGH}) then
    raise EInOutError.CreateFmt('Kunne ikke erstatte filen (Windows-fejl %d): %s',
      [GetLastError, SysErrorMessage(GetLastError)]);
  {$ELSE}
  if not RenameFile(TempName, Target) then
    raise EInOutError.Create('Kunne ikke erstatte filen');
  {$ENDIF}
end;

function GetFileStamp(const FileName: string): TFileStamp;
{$IFDEF WINDOWS}
var
  H: THandle;
{$ENDIF}
begin
  Result.Valid := False;
  FillChar(Result.Data, SizeOf(Result.Data), 0);
  {$IFDEF WINDOWS}
  H := CreateFileW(PWideChar(UTF8Decode(FileName)), GENERIC_READ,
    FILE_SHARE_READ or FILE_SHARE_WRITE, nil, OPEN_EXISTING, 0, 0);
  if H = INVALID_HANDLE_VALUE then Exit;
  Result.Valid := GetFileTime(H, @Result.Data[0], @Result.Data[1], @Result.Data[2]);
  CloseHandle(H);
  {$ELSE}
  Result.Data[2] := FileAge(FileName);
  Result.Valid := Result.Data[2] <> -1;
  {$ENDIF}
end;

procedure SetFileStamp(const FileName: string; const Stamp: TFileStamp);
{$IFDEF WINDOWS}
var
  H: THandle;
{$ENDIF}
begin
  if not Stamp.Valid then Exit;
  {$IFDEF WINDOWS}
  H := CreateFileW(PWideChar(UTF8Decode(FileName)), FILE_WRITE_ATTRIBUTES,
    FILE_SHARE_READ or FILE_SHARE_WRITE, nil, OPEN_EXISTING, 0, 0);
  if H = INVALID_HANDLE_VALUE then Exit;
  SetFileTime(H, @Stamp.Data[0], @Stamp.Data[1], @Stamp.Data[2]);
  CloseHandle(H);
  {$ELSE}
  FileSetDate(FileName, Stamp.Data[2]);
  {$ENDIF}
end;

end.
