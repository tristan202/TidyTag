unit OggWriter;

{ Writes Vorbis comments (incl. pictures as METADATA_BLOCK_PICTURE) into Ogg Vorbis and
  Ogg Opus files. The comment header packet (plus the Vorbis setup header that shares its
  pages) is put on new pages; all following pages of the stream get new sequence numbers
  and checksums. Audio data is copied unchanged. The file is always rewritten via a
  temporary file. Multiplexed/chained streams and Ogg FLAC are refused. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, AudioTypes;

procedure WriteOggTags(const FileName: string; Info: TAudioInfo);
{ Ogg page checksum over the whole page with the CRC field set to zero. }
function OggCrc(const B: TBytes; P, Len: SizeInt): Cardinal;

implementation

uses
  TagUtils, FlacWriter;

var
  CrcTable: array[0..255] of Cardinal;

procedure InitCrc;
var
  I, J: Integer;
  R: Cardinal;
begin
  for I := 0 to 255 do
  begin
    R := Cardinal(I) shl 24;
    for J := 0 to 7 do
      if R and $80000000 <> 0 then R := (R shl 1) xor $04C11DB7 else R := R shl 1;
    CrcTable[I] := R;
  end;
end;

function OggCrc(const B: TBytes; P, Len: SizeInt): Cardinal;
var
  I: SizeInt;
begin
  Result := 0;
  for I := P to P + Len - 1 do
    Result := (Result shl 8) xor CrcTable[((Result shr 24) xor B[I]) and $FF];
end;

type
  TOggPage = record
    Raw: TBytes;        // complete page as read (header, segment table, data)
    HeaderType: Byte;
    Serial, Seq: Cardinal;
    Segs: TBytes;
    DataOfs: SizeInt;   // start of the data inside Raw
  end;

{ Reads the page at the current position; False at end of file. }
function ReadPage(S: TStream; out Pg: TOggPage): Boolean;
var
  H, Segs, Data: TBytes;
  N, I, DataLen: Integer;
begin
  Result := False;
  H := ReadStreamBytes(S, 27);
  if Length(H) = 0 then Exit;
  if (Length(H) < 27) or not BytesAre(H, 0, 'OggS') then
    raise Exception.Create('Ugyldig Ogg-side (filen er beskadiget eller ikke Ogg)');
  N := H[26];
  Segs := ReadStreamBytes(S, N);
  DataLen := 0;
  for I := 0 to N - 1 do Inc(DataLen, Segs[I]);
  Data := ReadStreamBytes(S, DataLen);
  if (Length(Segs) < N) or (Length(Data) < DataLen) then
    raise Exception.Create('Ogg-filen er afkortet');
  SetLength(Pg.Raw, 27 + N + DataLen);
  Move(H[0], Pg.Raw[0], 27);
  if N > 0 then Move(Segs[0], Pg.Raw[27], N);
  if DataLen > 0 then Move(Data[0], Pg.Raw[27 + N], DataLen);
  Pg.HeaderType := H[5];
  Pg.Serial := LE32(H, 14);
  Pg.Seq := LE32(H, 18);
  Pg.Segs := Segs;
  Pg.DataOfs := 27 + N;
  Result := True;
end;

procedure PutLE32(var B: TBytes; P: SizeInt; V: Cardinal);
begin
  B[P] := V and $FF; B[P + 1] := (V shr 8) and $FF; B[P + 2] := (V shr 16) and $FF; B[P + 3] := V shr 24;
end;

procedure SetSeqAndCrc(var Raw: TBytes; Seq: Cardinal);
begin
  PutLE32(Raw, 18, Seq);
  PutLE32(Raw, 22, 0);
  PutLE32(Raw, 22, OggCrc(Raw, 0, Length(Raw)));
end;

{ Lays out Packets on new pages (max 255 segments each), starting at sequence FirstSeq. }
procedure WritePackets(Dest: TStream; const Packets: array of TBytes; Serial, FirstSeq: Cardinal;
  out PagesWritten: Integer);
var
  Lacing: array of Byte;
  Ends: array of Boolean;   // segment i ends a packet
  Data: TBytesStream;
  AllData: TBytes;
  I, J, N, Len, SegStart, SegCount, DataPos, PageData: Integer;
  Page: TBytes;
  Continued, AnyEnd: Boolean;
  Seq: Cardinal;
begin
  Lacing := nil;
  Ends := nil;
  Data := TBytesStream.Create;
  try
    for I := 0 to High(Packets) do
    begin
      Len := Length(Packets[I]);
      repeat
        N := Length(Lacing);
        SetLength(Lacing, N + 1);
        SetLength(Ends, N + 1);
        if Len >= 255 then Lacing[N] := 255 else Lacing[N] := Len;
        Dec(Len, Lacing[N]);
        Ends[N] := Lacing[N] < 255;
      until Ends[N];
      WriteBytes(Data, Packets[I]);
    end;
    AllData := StreamBytes(Data);
  finally
    Data.Free;
  end;

  PagesWritten := 0;
  Seq := FirstSeq;
  SegStart := 0;
  DataPos := 0;
  Continued := False;
  while SegStart < Length(Lacing) do
  begin
    SegCount := Length(Lacing) - SegStart;
    if SegCount > 255 then SegCount := 255;
    PageData := 0;
    AnyEnd := False;
    for J := SegStart to SegStart + SegCount - 1 do
    begin
      Inc(PageData, Lacing[J]);
      if Ends[J] then AnyEnd := True;
    end;
    SetLength(Page, 27 + SegCount + PageData);
    FillChar(Page[0], 27, 0);
    Page[0] := Ord('O'); Page[1] := Ord('g'); Page[2] := Ord('g'); Page[3] := Ord('S');
    Page[4] := 0;
    if Continued then Page[5] := 1 else Page[5] := 0;
    // header pages: granule 0 when a packet ends here, else -1 ("no packet completes")
    if AnyEnd then
      PutBE64(Page, 6, 0)
    else
      for J := 6 to 13 do Page[J] := $FF;
    PutLE32(Page, 14, Serial);
    Page[26] := SegCount;
    for J := 0 to SegCount - 1 do Page[27 + J] := Lacing[SegStart + J];
    if PageData > 0 then Move(AllData[DataPos], Page[27 + SegCount], PageData);
    SetSeqAndCrc(Page, Seq);
    WriteBytes(Dest, Page);
    Inc(PagesWritten);
    Inc(Seq);
    Inc(DataPos, PageData);
    Continued := not Ends[SegStart + SegCount - 1];
    Inc(SegStart, SegCount);
  end;
end;

procedure WriteOggTags(const FileName: string; Info: TAudioInfo);
var
  Src, Dst: TFileStream;
  Pg: TOggPage;
  Serial: Cardinal;
  Packets: array of TBytes;
  Cur, Body, NewComment: TBytes;
  Needed, I, N, HeaderPages, NewPages: Integer;
  Off: SizeInt;
  IsOpus, Done: Boolean;
  FirstPage: TBytes;
  Delta: Integer;
  Temp: string;
  B: TBytesStream;
begin
  Src := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    // ---- read the header packets
    if not ReadPage(Src, Pg) or (Pg.HeaderType and 2 = 0) then
      raise Exception.Create('Ugyldig Ogg-fil');
    Serial := Pg.Serial;
    FirstPage := Pg.Raw;
    if (Length(Pg.Segs) = 0) or (Pg.Segs[High(Pg.Segs)] = 255) then
      raise Exception.Create('Uventet Ogg-struktur (identifikationspakken fylder mere end én side)');
    Body := Copy(Pg.Raw, Pg.DataOfs, Length(Pg.Raw) - Pg.DataOfs);
    if (Length(Body) >= 7) and (Body[0] = 1) and BytesAre(Body, 1, 'vorbis') then
    begin
      IsOpus := False;
      Needed := 2; // comment + setup after the identification packet
    end
    else if BytesAre(Body, 0, 'OpusHead') then
    begin
      IsOpus := True;
      Needed := 1; // tags
    end
    else
      raise Exception.Create('Kun Ogg Vorbis og Ogg Opus kan gemmes');
    if Length(Pg.Segs) > 1 then
    begin
      // the first page must hold the identification packet only
      I := 0;
      while (I < Length(Pg.Segs)) and (Pg.Segs[I] = 255) do Inc(I);
      if I <> High(Pg.Segs) then raise Exception.Create('Uventet Ogg-struktur (første side)');
    end;

    Packets := nil;
    Cur := nil;
    HeaderPages := 1;
    Done := False;
    while not Done do
    begin
      if not ReadPage(Src, Pg) then raise Exception.Create('Ogg-filen slutter før header-pakkerne');
      if Pg.Serial <> Serial then
        raise Exception.Create('Ogg-filer med flere strømme kan ikke gemmes endnu');
      Inc(HeaderPages);
      I := 0;
      Off := 0;
      while I < Length(Pg.Segs) do
      begin
        N := Length(Cur);
        SetLength(Cur, N + Pg.Segs[I]);
        if Pg.Segs[I] > 0 then
          Move(Pg.Raw[Pg.DataOfs + Off], Cur[N], Pg.Segs[I]);
        Inc(Off, Pg.Segs[I]);
        if Pg.Segs[I] < 255 then
        begin
          SetLength(Packets, Length(Packets) + 1);
          Packets[High(Packets)] := Cur;
          Cur := nil;
          if Length(Packets) = Needed then
          begin
            if I <> High(Pg.Segs) then
              raise Exception.Create('Uventet Ogg-struktur (lyd på samme side som header)');
            Done := True;
            Break;
          end;
        end;
        Inc(I);
      end;
    end;

    // ---- new comment packet (pictures as base64 METADATA_BLOCK_PICTURE)
    B := TBytesStream.Create;
    try
      if IsOpus then
      begin
        if not BytesAre(Packets[0], 0, 'OpusTags') then raise Exception.Create('Mangler OpusTags');
        WriteAscii(B, 'OpusTags');
        WriteBytes(B, BuildVorbisComment(Packets[0], 8, Info, True));
      end
      else
      begin
        if (Packets[0][0] <> 3) or not BytesAre(Packets[0], 1, 'vorbis') then
          raise Exception.Create('Mangler Vorbis-kommentarpakken');
        B.WriteByte(3);
        WriteAscii(B, 'vorbis');
        WriteBytes(B, BuildVorbisComment(Packets[0], 7, Info, True));
        B.WriteByte(1); // framing bit
      end;
      NewComment := StreamBytes(B);
    finally
      B.Free;
    end;
    Packets[0] := NewComment;

    // ---- write: first page, new header pages, then the rest renumbered
    Temp := TempFileFor(FileName);
    try
      Dst := TFileStream.Create(Temp, fmCreate);
      try
        WriteBytes(Dst, FirstPage);
        WritePackets(Dst, Packets, Serial, 1, NewPages);
        Delta := NewPages - (HeaderPages - 1);
        while ReadPage(Src, Pg) do
        begin
          if Pg.Serial <> Serial then
            raise Exception.Create('Ogg-filer med flere strømme kan ikke gemmes endnu');
          SetSeqAndCrc(Pg.Raw, Cardinal(Int64(Pg.Seq) + Delta));
          WriteBytes(Dst, Pg.Raw);
        end;
      finally
        Dst.Free;
      end;
      FreeAndNil(Src);
      ReplaceFileWith(Temp, FileName);
    except
      DeleteFile(Temp);
      raise;
    end;
  finally
    Src.Free;
  end;
end;

initialization
  InitCrc;
end.
