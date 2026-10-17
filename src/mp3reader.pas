unit Mp3Reader;

{ ID3v2.2/2.3/2.4 and ID3v1 tags plus MPEG audio properties (incl. Xing/VBRI VBR headers). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, AudioTypes;

type
  TID3Frame = record
    ID: string;   // as stored: 3 chars for v2.2, 4 chars otherwise
    Flags: Word;  // frame flags as stored (0 for v2.2)
    Raw: TBytes;  // frame body as stored (tag-level unsynchronisation already removed)
    Data: TBytes; // body ready for decoding; nil if compressed or encrypted
  end;
  TID3Frames = array of TID3Frame;

{ Splits an ID3v2 tag at the start of the stream into frames.
  Returns False if there is no (supported) tag; TagSize is still set when a tag exists. }
function ParseID3v2(S: TStream; out Version: Byte; out Frames: TID3Frames; out TagSize: Int64): Boolean;
function DecodeID3Text(const B: TBytes; P, Len: SizeInt; Enc: Byte): string;
function SkipTerminated(const B: TBytes; P: SizeInt; Enc: Byte): SizeInt;
function V22ToV23(const ID: string): string;

{ Reads an ID3v2 tag at the start of the stream (if any).
  TagSize returns the total tag length incl. header/footer, 0 if there is none. }
procedure ReadID3v2(S: TStream; Info: TAudioInfo; out TagSize: Int64);
{ Fills only empty fields from an ID3v1 tag at the end of the stream. Returns True if found. }
function ReadID3v1(S: TStream; Info: TAudioInfo): Boolean;
procedure ReadMp3(S: TStream; Info: TAudioInfo);

implementation

uses
  StrUtils, TagUtils;

{ ---------- ID3v2 ---------- }

function RemoveUnsync(const B: TBytes): TBytes;
var
  I, N: SizeInt;
begin
  Result := nil;
  SetLength(Result, Length(B));
  N := 0;
  I := 0;
  while I < Length(B) do
  begin
    Result[N] := B[I];
    Inc(N);
    if (B[I] = $FF) and (I + 1 < Length(B)) and (B[I + 1] = $00) then
      Inc(I);
    Inc(I);
  end;
  SetLength(Result, N);
end;

function DecodeID3Text(const B: TBytes; P, Len: SizeInt; Enc: Byte): string;
begin
  case Enc of
    1:
      if (Len >= 2) and (B[P] = $FE) and (B[P + 1] = $FF) then
        Result := UTF16ToUTF8(B, P + 2, Len - 2, True)
      else if (Len >= 2) and (B[P] = $FF) and (B[P + 1] = $FE) then
        Result := UTF16ToUTF8(B, P + 2, Len - 2, False)
      else
        Result := UTF16ToUTF8(B, P, Len, False);
    2: Result := UTF16ToUTF8(B, P, Len, True);
    3: Result := RawUTF8(B, P, Len);
  else
    Result := Latin1ToUTF8(B, P, Len);
  end;
  Result := CleanTagText(Result);
end;

{ Position just after the NUL terminator of a string starting at P. }
function SkipTerminated(const B: TBytes; P: SizeInt; Enc: Byte): SizeInt;
begin
  if Enc in [1, 2] then
  begin
    while P + 1 < Length(B) do
    begin
      if (B[P] = 0) and (B[P + 1] = 0) then Exit(P + 2);
      Inc(P, 2);
    end;
  end
  else
    while P < Length(B) do
    begin
      if B[P] = 0 then Exit(P + 1);
      Inc(P);
    end;
  Result := Length(B);
end;

{ '(17)', '17', '(17)Rock', 'Rock', 'RX', 'CR' -> readable genre. }
function NormalizeGenre(const G: string): string;
var
  Rest: string;
  P, N: Integer;
begin
  Result := G;
  Rest := G;
  while (Rest <> '') and (Rest[1] = '(') do
  begin
    P := Pos(')', Rest);
    if P = 0 then Break;
    if TryStrToInt(Copy(Rest, 2, P - 2), N) then
      Result := ID3GenreName(N)
    else if Copy(Rest, 2, P - 2) = 'RX' then
      Result := 'Remix'
    else if Copy(Rest, 2, P - 2) = 'CR' then
      Result := 'Cover';
    Rest := Copy(Rest, P + 1, MaxInt);
  end;
  if Rest <> G then
  begin
    if Rest <> '' then Result := Rest; // refinement text wins over the number
  end
  else if TryStrToInt(G, N) then
    Result := ID3GenreName(N);
end;

function V22ToV23(const ID: string): string;
const
  Map: array[0..25, 0..1] of string = (
    ('TT2', 'TIT2'), ('TP1', 'TPE1'), ('TAL', 'TALB'), ('TYE', 'TYER'),
    ('TRK', 'TRCK'), ('TPA', 'TPOS'), ('TCO', 'TCON'), ('COM', 'COMM'),
    ('TP2', 'TPE2'), ('TCM', 'TCOM'), ('TBP', 'TBPM'), ('PIC', 'APIC'),
    ('TP3', 'TPE3'), ('TXT', 'TEXT'), ('TOA', 'TOPE'), ('TP4', 'TPE4'),
    ('TPB', 'TPUB'), ('TRC', 'TSRC'), ('TCR', 'TCOP'), ('TEN', 'TENC'),
    ('TT1', 'TIT1'), ('TT3', 'TIT3'), ('TKE', 'TKEY'), ('ULT', 'USLT'),
    ('WXX', 'WXXX'), ('TXX', 'TXXX'));
var
  I: Integer;
begin
  for I := Low(Map) to High(Map) do
    if Map[I, 0] = ID then Exit(Map[I, 1]);
  Result := ID;
end;

{ APIC: encoding, MIME<NUL>, picture type, description<NUL>, data }
procedure ReadApicFrame(const F: TBytes; Info: TAudioInfo);
var
  Enc, PicType: Byte;
  P, Q: SizeInt;
  Mime, Desc: string;
begin
  if Length(F) < 4 then Exit;
  Enc := F[0];
  Q := SkipTerminated(F, 1, 0);
  Mime := Latin1ToUTF8(F, 1, Q - 2);
  if Q >= Length(F) then Exit;
  PicType := F[Q];
  P := SkipTerminated(F, Q + 1, Enc);
  Desc := DecodeID3Text(F, Q + 1, P - Q - 1, Enc);
  if Pos('/', Mime) = 0 then Mime := ''; // e.g. 'JPG' written by broken taggers
  Info.AddPicture(PicType, Mime, Desc, Copy(F, P, Length(F) - P));
end;

{ v2.2 PIC: encoding, 3-char image format, picture type, description<NUL>, data }
procedure ReadPicFrame(const F: TBytes; Info: TAudioInfo);
var
  Enc: Byte;
  P: SizeInt;
begin
  if Length(F) < 6 then Exit;
  Enc := F[0];
  P := SkipTerminated(F, 5, Enc);
  Info.AddPicture(F[4], '', DecodeID3Text(F, 5, P - 5, Enc), Copy(F, P, Length(F) - P));
end;

procedure ProcessFrame(const ID: string; const F: TBytes; Info: TAudioInfo;
  var CommentIsDefault: Boolean);
var
  Txt, Desc: string;
  Enc: Byte;
  P: SizeInt;
begin
  if Length(F) = 0 then Exit;
  if (ID <> 'TXXX') and (ID[1] = 'T') then
  begin
    Txt := DecodeID3Text(F, 1, Length(F) - 1, F[0]);
    if ID = 'TIT2' then Info.SetField(tfTitle, Txt)
    else if ID = 'TPE1' then Info.SetField(tfArtist, Txt)
    else if ID = 'TALB' then Info.SetField(tfAlbum, Txt)
    else if ID = 'TDRC' then Info.SetField(tfYear, Txt)
    else if ID = 'TYER' then Info.SetField(tfYear, Txt, False)
    else if ID = 'TRCK' then Info.SetField(tfTrack, Txt)
    else if ID = 'TPOS' then Info.SetField(tfDisc, Txt)
    else if ID = 'TCON' then Info.SetField(tfGenre, NormalizeGenre(Txt))
    else if ID = 'TPE2' then Info.SetField(tfAlbumArtist, Txt)
    else if ID = 'TCOM' then Info.SetField(tfComposer, Txt)
    else if ID = 'TBPM' then Info.SetField(tfBpm, Txt)
    else if ID = 'TPE3' then Info.SetField(tfConductor, Txt)
    else if ID = 'TEXT' then Info.SetField(tfLyricist, Txt)
    else if ID = 'TOPE' then Info.SetField(tfOrigArtist, Txt)
    else if ID = 'TPE4' then Info.SetField(tfRemixer, Txt)
    else if ID = 'TPUB' then Info.SetField(tfPublisher, Txt)
    else if ID = 'TSRC' then Info.SetField(tfIsrc, Txt)
    else if ID = 'TCOP' then Info.SetField(tfCopyright, Txt)
    else if ID = 'TENC' then Info.SetField(tfEncodedBy, Txt)
    else if ID = 'TIT1' then Info.SetField(tfGrouping, Txt)
    else if ID = 'GRP1' then Info.SetField(tfGrouping, Txt, False) // newer iTunes
    else if ID = 'TIT3' then Info.SetField(tfSubtitle, Txt)
    else if ID = 'TMOO' then Info.SetField(tfMood, Txt)
    else if ID = 'TKEY' then Info.SetField(tfInitialKey, Txt)
    else if ID = 'TSOT' then Info.SetField(tfSortTitle, Txt)
    else if ID = 'TSOP' then Info.SetField(tfSortArtist, Txt)
    else if ID = 'TSO2' then Info.SetField(tfSortAlbumArtist, Txt)
    else if ID = 'TSOA' then Info.SetField(tfSortAlbum, Txt)
    else if ID = 'TSOC' then Info.SetField(tfSortComposer, Txt);
  end
  else if ID = 'TXXX' then
  begin
    // encoding, description<NUL>, value
    Enc := F[0];
    P := SkipTerminated(F, 1, Enc);
    Desc := UpperCase(DecodeID3Text(F, 1, P - 1, Enc));
    Txt := DecodeID3Text(F, P, Length(F) - P, Enc);
    if Desc = 'CATALOGNUMBER' then Info.SetField(tfCatalogNo, Txt)
    else if Desc = 'MOOD' then Info.SetField(tfMood, Txt, False)
    else if Desc = 'LABEL' then Info.SetField(tfPublisher, Txt, False);
  end
  else if ID = 'USLT' then
  begin
    // encoding, language, description<NUL>, lyrics; prefer the one without description
    Enc := F[0];
    P := SkipTerminated(F, 4, Enc);
    Desc := DecodeID3Text(F, 4, P - 4, Enc);
    Txt := DecodeID3Text(F, P, Length(F) - P, Enc);
    Info.SetField(tfLyrics, Txt, Desc = '');
  end
  else if ID = 'WXXX' then
  begin
    // encoding, description<NUL>, URL (always Latin-1)
    Enc := F[0];
    P := SkipTerminated(F, 1, Enc);
    Desc := DecodeID3Text(F, 1, P - 1, Enc);
    Info.SetField(tfUrl, CleanTagText(Latin1ToUTF8(F, P, Length(F) - P)), Desc = '');
  end
  else if ID = 'COMM' then
  begin
    // encoding, 3-byte language, description<NUL>, text
    Enc := F[0];
    P := SkipTerminated(F, 4, Enc);
    Desc := DecodeID3Text(F, 4, P - 4, Enc);
    Txt := DecodeID3Text(F, P, Length(F) - P, Enc);
    if Desc = '' then
    begin
      if not CommentIsDefault then
      begin
        Info.SetField(tfComment, Txt);
        CommentIsDefault := Txt <> '';
      end;
    end
    else if not SameText(Copy(Desc, 1, 4), 'iTun') then
      Info.SetField(tfComment, Txt, False);
  end
  else if ID = 'APIC' then
    ReadApicFrame(F, Info);
end;

function ValidFrameID(const ID: string): Boolean;
var
  C: Char;
begin
  Result := ID <> '';
  for C in ID do
    if not (C in ['A'..'Z', '0'..'9']) then Exit(False);
end;

function ParseID3v2(S: TStream; out Version: Byte; out Frames: TID3Frames; out TagSize: Int64): Boolean;
var
  H, Body: TBytes;
  Flags: Byte;
  Size: Cardinal;
  P, HdrLen, DataP, DataLen, N: SizeInt;
  FSize: Cardinal;
  FFlags: Word;
  ID: string;
  Usable: Boolean;
begin
  Result := False;
  Version := 0;
  Frames := nil;
  TagSize := 0;
  S.Position := 0;
  H := ReadStreamBytes(S, 10);
  if (Length(H) < 10) or not BytesAre(H, 0, 'ID3') then Exit;
  Version := H[3];
  Flags := H[5];
  Size := SyncSafe32(H, 6);
  TagSize := 10 + Int64(Size);
  if (Version >= 4) and (Flags and $10 <> 0) then Inc(TagSize, 10); // footer
  if not (Version in [2..4]) then Exit;
  Result := True;

  Body := ReadStreamBytes(S, Size);
  if (Version < 4) and (Flags and $80 <> 0) then
    Body := RemoveUnsync(Body);

  P := 0;
  if Flags and $40 <> 0 then // extended header
  begin
    if Version = 3 then
      P := 4 + BE32(Body, 0)
    else if Version = 4 then
      P := SyncSafe32(Body, 0);
  end;

  if Version = 2 then HdrLen := 6 else HdrLen := 10;
  while P + HdrLen <= Length(Body) do
  begin
    if Body[P] = 0 then Break; // padding
    if Version = 2 then
    begin
      ID := BytesToAscii(Body, P, 3);
      FSize := BE24(Body, P + 3);
      FFlags := 0;
    end
    else
    begin
      ID := BytesToAscii(Body, P, 4);
      FFlags := BE16(Body, P + 8);
      if Version = 4 then
      begin
        FSize := SyncSafe32(Body, P + 4);
        // Some writers (old iTunes) store plain sizes in v2.4.
        if (BE32(Body, P + 4) and $80808080 <> 0) or
          ((P + HdrLen + FSize + 4 <= Length(Body)) and (Body[P + HdrLen + FSize] <> 0) and
          not ValidFrameID(BytesToAscii(Body, P + HdrLen + FSize, 4)) and
          ValidFrameID(BytesToAscii(Body, P + HdrLen + BE32(Body, P + 4), 4))) then
          FSize := BE32(Body, P + 4);
      end
      else
        FSize := BE32(Body, P + 4);
    end;
    if not ValidFrameID(ID) then Break;
    if P + HdrLen + Int64(FSize) > Length(Body) then Break;

    // A v2.4 tag-wide unsync flag means every frame is unsynchronised; record it on the
    // frame so the raw body stays valid when it is written into a tag without that flag.
    if (Version = 4) and (Flags and $80 <> 0) then FFlags := FFlags or $0002;

    N := Length(Frames);
    SetLength(Frames, N + 1);
    Frames[N].ID := ID;
    Frames[N].Flags := FFlags;
    Frames[N].Raw := Copy(Body, P + HdrLen, FSize);
    Frames[N].Data := nil;

    DataP := P + HdrLen;
    DataLen := FSize;
    P := DataP + DataLen;

    Usable := True;
    if Version = 3 then
    begin
      if FFlags and $00C0 <> 0 then Usable := False; // compressed / encrypted
      if FFlags and $0020 <> 0 then begin Inc(DataP); Dec(DataLen); end; // grouping id
    end
    else if Version = 4 then
    begin
      if FFlags and $000C <> 0 then Usable := False; // compressed / encrypted
      if FFlags and $0040 <> 0 then begin Inc(DataP); Dec(DataLen); end; // grouping id
      if FFlags and $0001 <> 0 then begin Inc(DataP, 4); Dec(DataLen, 4); end; // data length
    end;
    if not Usable or (DataLen <= 0) then Continue;

    Frames[N].Data := Copy(Body, DataP, DataLen);
    if (Version = 4) and ((FFlags and $0002 <> 0) or (Flags and $80 <> 0)) then
      Frames[N].Data := RemoveUnsync(Frames[N].Data);
  end;
end;

procedure ReadID3v2(S: TStream; Info: TAudioInfo; out TagSize: Int64);
var
  Ver: Byte;
  Frames: TID3Frames;
  I: Integer;
  CommentIsDefault: Boolean;
  Date: string;
begin
  if not ParseID3v2(S, Ver, Frames, TagSize) then Exit;
  Info.AddTagType('ID3v2.' + IntToStr(Ver));
  CommentIsDefault := False;
  for I := 0 to High(Frames) do
    if Frames[I].Data <> nil then
    begin
      if (Ver = 2) and (Frames[I].ID = 'PIC') then
        ReadPicFrame(Frames[I].Data, Info)
      else if Ver = 2 then
        ProcessFrame(V22ToV23(Frames[I].ID), Frames[I].Data, Info, CommentIsDefault)
      else
        ProcessFrame(Frames[I].ID, Frames[I].Data, Info, CommentIsDefault);
    end;
  // v2.3 keeps the day and month (DDMM) in TDAT; show the full date like v2.4 does.
  if Ver = 3 then
    for I := 0 to High(Frames) do
      if (Frames[I].ID = 'TDAT') and (Frames[I].Data <> nil) then
      begin
        Date := DecodeID3Text(Frames[I].Data, 1, Length(Frames[I].Data) - 1, Frames[I].Data[0]);
        if (Length(Date) = 4) and (StrToIntDef(Date, -1) >= 0) and
          (Length(Info.Fields[tfYear]) = 4) and (StrToIntDef(Info.Fields[tfYear], -1) >= 0) then
          Info.Fields[tfYear] := Info.Fields[tfYear] + '-' + Copy(Date, 3, 2) + '-' + Copy(Date, 1, 2);
      end;
end;

{ ---------- ID3v1 ---------- }

function ID3v1Text(const B: TBytes; P, Len: SizeInt): string;
var
  E: SizeInt;
begin
  E := 0;
  while (E < Len) and (B[P + E] <> 0) do Inc(E);
  Result := Trim(Latin1ToUTF8(B, P, E));
end;

function ReadID3v1(S: TStream; Info: TAudioInfo): Boolean;
var
  B: TBytes;
begin
  Result := False;
  if S.Size < 128 then Exit;
  S.Position := S.Size - 128;
  B := ReadStreamBytes(S, 128);
  if (Length(B) < 128) or not BytesAre(B, 0, 'TAG') then Exit;
  Result := True;
  Info.AddTagType('ID3v1');
  Info.SetField(tfTitle, ID3v1Text(B, 3, 30), False);
  Info.SetField(tfArtist, ID3v1Text(B, 33, 30), False);
  Info.SetField(tfAlbum, ID3v1Text(B, 63, 30), False);
  Info.SetField(tfYear, ID3v1Text(B, 93, 4), False);
  if (B[125] = 0) and (B[126] <> 0) then
  begin
    Info.SetField(tfComment, ID3v1Text(B, 97, 28), False);
    Info.SetField(tfTrack, IntToStr(B[126]), False);
  end
  else
    Info.SetField(tfComment, ID3v1Text(B, 97, 30), False);
  Info.SetField(tfGenre, ID3GenreName(B[127]), False);
end;

{ ---------- MPEG audio ---------- }

type
  TMpegHeader = record
    Version: Integer;   // 1, 2 or 25 (= 2.5)
    Layer: Integer;     // 1..3
    Bitrate: Integer;   // kbit/s
    SampleRate: Integer;
    Mono: Boolean;
    FrameLen: Integer;
    SamplesPerFrame: Integer;
  end;

const
  BitratesV1: array[1..3, 0..15] of Integer = (
    (0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448, 0),
    (0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 0),
    (0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0));
  BitratesV2: array[1..3, 0..15] of Integer = (
    (0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256, 0),
    (0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0),
    (0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0));
  SampleRates: array[0..2, 0..2] of Integer = (
    (44100, 48000, 32000), (22050, 24000, 16000), (11025, 12000, 8000));

function ParseMpegHeader(const B: TBytes; P: SizeInt; out H: TMpegHeader): Boolean;
var
  VerBits, LayerBits, BrIdx, SrIdx, Pad: Integer;
begin
  Result := False;
  if P + 4 > Length(B) then Exit;
  if (B[P] <> $FF) or (B[P + 1] and $E0 <> $E0) then Exit;
  VerBits := (B[P + 1] shr 3) and 3;
  LayerBits := (B[P + 1] shr 1) and 3;
  BrIdx := B[P + 2] shr 4;
  SrIdx := (B[P + 2] shr 2) and 3;
  Pad := (B[P + 2] shr 1) and 1;
  if (VerBits = 1) or (LayerBits = 0) or (BrIdx = 0) or (BrIdx = 15) or (SrIdx = 3) then Exit;
  case VerBits of
    3: H.Version := 1;
    2: H.Version := 2;
  else
    H.Version := 25;
  end;
  H.Layer := 4 - LayerBits;
  if H.Version = 1 then
  begin
    H.Bitrate := BitratesV1[H.Layer, BrIdx];
    H.SampleRate := SampleRates[0, SrIdx];
  end
  else
  begin
    H.Bitrate := BitratesV2[H.Layer, BrIdx];
    if H.Version = 2 then
      H.SampleRate := SampleRates[1, SrIdx]
    else
      H.SampleRate := SampleRates[2, SrIdx];
  end;
  H.Mono := (B[P + 3] shr 6) = 3;
  case H.Layer of
    1: begin
         H.SamplesPerFrame := 384;
         H.FrameLen := (12 * H.Bitrate * 1000 div H.SampleRate + Pad) * 4;
       end;
    2: begin
         H.SamplesPerFrame := 1152;
         H.FrameLen := 144 * H.Bitrate * 1000 div H.SampleRate + Pad;
       end;
  else
    if H.Version = 1 then
    begin
      H.SamplesPerFrame := 1152;
      H.FrameLen := 144 * H.Bitrate * 1000 div H.SampleRate + Pad;
    end
    else
    begin
      H.SamplesPerFrame := 576;
      H.FrameLen := 72 * H.Bitrate * 1000 div H.SampleRate + Pad;
    end;
  end;
  Result := H.FrameLen > 4;
end;

procedure ReadMpegAudio(S: TStream; Info: TAudioInfo; AudioStart, AudioEnd: Int64);
var
  B: TBytes;
  H, H2: TMpegHeader;
  I, XingOff: SizeInt;
  Found: Boolean;
  Frames: Cardinal;
  AudioBytes: Int64;
begin
  S.Position := AudioStart;
  B := ReadStreamBytes(S, 256 * 1024);
  Found := False;
  I := 0;
  while I + 4 <= Length(B) do
  begin
    if ParseMpegHeader(B, I, H) then
    begin
      // Require a second frame right after, unless the buffer ends first.
      if (I + H.FrameLen + 4 > Length(B)) or
        (ParseMpegHeader(B, I + H.FrameLen, H2) and (H2.SampleRate = H.SampleRate) and
         (H2.Layer = H.Layer)) then
      begin
        Found := True;
        Break;
      end;
    end;
    Inc(I);
  end;
  if not Found then Exit;

  Info.Codec := Format('MPEG-%s Layer %s',
    [IfThen(H.Version = 25, '2.5', IntToStr(H.Version)), Copy('III', 1, H.Layer)]);
  if (H.Version = 1) and (H.Layer = 3) then Info.Codec := 'MP3';
  Info.SampleRate := H.SampleRate;
  if H.Mono then Info.Channels := 1 else Info.Channels := 2;

  AudioBytes := AudioEnd - (AudioStart + I);
  Frames := 0;
  if H.Version = 1 then
  begin
    if H.Mono then XingOff := 4 + 17 else XingOff := 4 + 32;
  end
  else if H.Mono then XingOff := 4 + 9 else XingOff := 4 + 17;

  if BytesAre(B, I + XingOff, 'Xing') or BytesAre(B, I + XingOff, 'Info') then
  begin
    if BE32(B, I + XingOff + 4) and 1 <> 0 then
      Frames := BE32(B, I + XingOff + 8);
  end
  else if BytesAre(B, I + 4 + 32, 'VBRI') then
    Frames := BE32(B, I + 4 + 32 + 14);

  if Frames > 0 then
  begin
    Info.Duration := Frames * H.SamplesPerFrame / H.SampleRate;
    if Info.Duration > 0 then
      Info.Bitrate := Round(AudioBytes * 8 / Info.Duration / 1000);
  end
  else
  begin
    Info.Bitrate := H.Bitrate;
    Info.Duration := AudioBytes * 8 / (H.Bitrate * 1000);
  end;
end;

procedure ReadMp3(S: TStream; Info: TAudioInfo);
var
  TagSize, AudioEnd: Int64;
begin
  Info.Supported := True;
  ReadID3v2(S, Info, TagSize);
  AudioEnd := S.Size;
  if ReadID3v1(S, Info) then Dec(AudioEnd, 128);
  ReadMpegAudio(S, Info, TagSize, AudioEnd);
end;

end.
