program TagTest;

{ Write test for the tag writers. Works on COPIES in a test folder:
    tagtest <test-folder> <file> [<file> ...]
  For each file three scenarios are written and read back:
    A  change all fields + add a small PNG    (usually in place)
    B  add a 400 KB picture                   (forces a full rewrite)
    C  clear comment/composer, remove images  (shrinks again, in place)
  After each scenario the fields, pictures and the audio data are verified. }

{$mode objfpc}{$H+}

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  Classes, SysUtils, crc, AudioTypes, AudioTags, TagWriter, TagUtils, Mp3Reader, OggWriter, WavReader, ApeTag,
  BatchWrite, FieldTools, TagRemove;

var
  Failures: Integer = 0;

procedure Check(Cond: Boolean; const What: string);
begin
  if Cond then
    WriteLn('   ok   ', What)
  else
  begin
    WriteLn('   FEJL ', What);
    Inc(Failures);
  end;
end;

function CrcRange(S: TStream; From, Count: Int64; Seed: Cardinal): Cardinal;
var
  Buf: array[0..65535] of Byte;
  N: Integer;
begin
  Result := Seed;
  S.Position := From;
  while Count > 0 do
  begin
    if Count > SizeOf(Buf) then N := SizeOf(Buf) else N := Count;
    N := S.Read(Buf, N);
    if N <= 0 then Break;
    Result := crc32(Result, @Buf[0], N);
    Dec(Count, N);
  end;
end;

{ Collects stco/co64 chunk offsets from a moov payload. }
procedure CollectOffsets(const B: TBytes; P, Limit: Int64; L: TList);
var
  Size: Int64;
  Name: string;
  N, J: Cardinal;
begin
  while P + 8 <= Limit do
  begin
    Size := BE32(B, P);
    if Size < 8 then Exit;
    Name := BytesToAscii(B, P + 4, 4);
    if (Name = 'trak') or (Name = 'mdia') or (Name = 'minf') or (Name = 'stbl') then
      CollectOffsets(B, P + 8, P + Size, L)
    else if Name = 'stco' then
    begin
      N := BE32(B, P + 12);
      for J := 0 to N - 1 do L.Add(Pointer(PtrInt(BE32(B, P + 16 + J * 4))));
    end
    else if Name = 'co64' then
    begin
      N := BE32(B, P + 12);
      for J := 0 to N - 1 do L.Add(Pointer(PtrInt(BE64(B, P + 16 + J * 8))));
    end;
    Inc(P, Size);
  end;
end;

{ Fingerprint of the audio payload, independent of where the tags are. }
{ Ogg: CRC over every packet except the comment packet (index 1); also checks that the
  page checksums are valid and the sequence numbers run 0, 1, 2, ... }
function OggFingerprint(S: TStream): Cardinal;
var
  H, Segs, Data: TBytes;
  N, I, Len, Off, Packet: Integer;
  Seq: Cardinal;
  Raw: TBytes;
begin
  Result := 0;
  Packet := 0;
  Seq := 0;
  S.Position := 0;
  while S.Position < S.Size do
  begin
    H := ReadStreamBytes(S, 27);
    if not BytesAre(H, 0, 'OggS') then begin Check(False, 'Ogg-side ved ' + IntToStr(S.Position)); Exit; end;
    N := H[26];
    Segs := ReadStreamBytes(S, N);
    Len := 0;
    for I := 0 to N - 1 do Inc(Len, Segs[I]);
    Data := ReadStreamBytes(S, Len);
    if LE32(H, 18) <> Seq then Check(False, Format('Ogg-sekvens %d', [Seq]));
    SetLength(Raw, 27 + N + Len);
    Move(H[0], Raw[0], 27);
    if N > 0 then Move(Segs[0], Raw[27], N);
    if Len > 0 then Move(Data[0], Raw[27 + N], Len);
    PutBE32(Raw, 22, 0);
    if OggCrc(Raw, 0, Length(Raw)) <> LE32(H, 22) then Check(False, Format('Ogg-CRC side %d', [Seq]));
    Inc(Seq);
    Off := 0;
    for I := 0 to N - 1 do
    begin
      if (Packet <> 1) and (Segs[I] > 0) then
        Result := crc32(Result, @Data[Off], Segs[I]);
      Inc(Off, Segs[I]);
      if Segs[I] < 255 then Inc(Packet);
    end;
  end;
  Result := Result xor Cardinal(Packet);
end;

{ WAV/AIFF: CRC over id and data of every chunk except the tag chunks. }
function ChunkFingerprint(S: TStream): Cardinal;
var
  CF: TChunkFile;
  C: TChunk;
  Id: string;
begin
  Result := 0;
  CF := ReadChunkFile(S);
  for C in CF.Chunks do
    if not IsTagChunk(S, C) and not (CF.IsAiff and ((C.ID = 'NAME') or (C.ID = 'AUTH') or (C.ID = 'ANNO') or (C.ID = '(c) '))) then
    begin
      Id := C.ID;
      Result := crc32(Result, @Id[1], 4);
      Result := CrcRange(S, C.DataPos, C.Size, Result);
    end;
end;

function AudioFingerprint(const FileName: string): Cardinal;
var
  S: TFileStream;
  Ext: string;
  TagSize, P, Size, AudioEnd: Int64;
  Ver: Byte;
  Frames: TID3Frames;
  H, Moov: TBytes;
  Last: Boolean;
  Offs: TList;
  I: Integer;
begin
  Result := 0;
  Ext := LowerCase(ExtractFileExt(FileName));
  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    if (Ext = '.ogg') or (Ext = '.oga') or (Ext = '.opus') then
      Result := OggFingerprint(S)
    else if (Ext = '.wav') or (Ext = '.aif') or (Ext = '.aiff') or (Ext = '.aifc') then
      Result := ChunkFingerprint(S)
    else if (Ext = '.ape') or (Ext = '.wv') or (Ext = '.mpc') or (Ext = '.ofr') then
      Result := CrcRange(S, 0, FindApeTag(S).AudioEnd, 0)
    else if (Ext = '.wma') or (Ext = '.asf') then
    begin
      // everything after the header object (data and index objects)
      H := ReadStreamBytes(S, 24);
      Result := CrcRange(S, LE64(H, 16), S.Size - LE64(H, 16), 0);
    end
    else if Ext = '.mp3' then
    begin
      ParseID3v2(S, Ver, Frames, TagSize);
      AudioEnd := S.Size;
      S.Position := S.Size - 128;
      H := ReadStreamBytes(S, 3);
      if BytesAre(H, 0, 'TAG') then Dec(AudioEnd, 128);
      Result := CrcRange(S, TagSize, AudioEnd - TagSize, 0);
    end
    else if Ext = '.flac' then
    begin
      ParseID3v2(S, Ver, Frames, TagSize);
      S.Position := TagSize + 4;
      repeat
        H := ReadStreamBytes(S, 4);
        Last := H[0] and $80 <> 0;
        S.Seek(BE24(H, 1), soCurrent);
      until Last;
      Result := CrcRange(S, S.Position, S.Size - S.Position, 0);
    end
    else
    begin
      // MP4: hash 32 bytes at every chunk offset -> proves offsets still point at the same audio.
      P := 0;
      Moov := nil;
      while P + 8 <= S.Size do
      begin
        S.Position := P;
        H := ReadStreamBytes(S, 8);
        Size := BE32(H, 0);
        if Size < 8 then Break;
        if BytesAre(H, 4, 'moov') then Moov := ReadStreamBytes(S, Size - 8);
        Inc(P, Size);
      end;
      Offs := TList.Create;
      try
        CollectOffsets(Moov, 0, Length(Moov), Offs);
        for I := 0 to Offs.Count - 1 do
          Result := CrcRange(S, PtrInt(Offs[I]), 32, Result);
        Result := Result xor Cardinal(Offs.Count);
      finally
        Offs.Free;
      end;
    end;
  finally
    S.Free;
  end;
end;

function MakePng(Size: Integer): TBytes;
const
  // 1x1 transparent PNG
  Tiny: array[0..66] of Byte = ($89, $50, $4E, $47, $0D, $0A, $1A, $0A, $00, $00, $00, $0D,
    $49, $48, $44, $52, $00, $00, $00, $01, $00, $00, $00, $01, $08, $06, $00, $00, $00,
    $1F, $15, $C4, $89, $00, $00, $00, $0A, $49, $44, $41, $54, $78, $9C, $63, $00, $01,
    $00, $00, $05, $00, $01, $0D, $0A, $2D, $B4, $00, $00, $00, $00, $49, $45, $4E, $44,
    $AE, $42, $60, $82);
var
  I: Integer;
begin
  Result := nil;
  if Size < Length(Tiny) then Size := Length(Tiny);
  SetLength(Result, Size);
  Move(Tiny[0], Result[0], Length(Tiny));
  // Extra bytes after IEND are ignored by image readers; they just make the picture big.
  for I := Length(Tiny) to Size - 1 do Result[I] := Random(256);
end;

procedure SetPicture(Info: TAudioInfo; Size: Integer);
begin
  SetLength(Info.Pictures, 1);
  Info.Pictures[0].PicType := PicTypeFrontCover;
  Info.Pictures[0].MimeType := 'image/png';
  Info.Pictures[0].Description := 'Forside æøå';
  Info.Pictures[0].Data := MakePng(Size);
end;

function SamePicture(const A, B: TTagPicture): Boolean;
begin
  Result := (Length(A.Data) = Length(B.Data)) and
    ((Length(A.Data) = 0) or CompareMem(@A.Data[0], @B.Data[0], Length(A.Data)));
end;

procedure Scenario(const FileName, Name: string; Edit: Integer; AudioCrc: Cardinal);
var
  Info, Back: TAudioInfo;
  Expected: array[TTagField] of string;
  F: TTagField;
  Pics: TTagPictures;
  SizeBefore: Int64;
begin
  WriteLn('  Scenarie ', Name);
  Info := ReadAudioInfo(FileName, True);
  try
    SizeBefore := Info.FileSize;
    case Edit of
      0: begin
           Info.Fields[tfTitle] := 'Titel ' + Name + ' – æøå ÆØÅ';
           Info.Fields[tfArtist] := 'Kunstner 漢字 Ünïcödé';
           Info.Fields[tfAlbum] := 'Album Ålborg';
           Info.Fields[tfYear] := '2001-02-03';
           Info.Fields[tfTrack] := '5/9';
           Info.Fields[tfDisc] := '2/3';
           Info.Fields[tfGenre] := 'Rock';
           Info.Fields[tfComment] := 'En kommentar';
           Info.Fields[tfAlbumArtist] := 'Diverse kunstnere';
           Info.Fields[tfComposer] := 'Carl Nielsen';
           Info.Fields[tfBpm] := '120';
           Info.Fields[tfLyrics] := 'Første linje æøå' + #13#10 + 'Anden linje' + #13#10 + '漢字';
           Info.Fields[tfConductor] := 'Dirigent Ø';
           Info.Fields[tfLyricist] := 'Tekstforfatter';
           Info.Fields[tfOrigArtist] := 'Oprindelig';
           Info.Fields[tfRemixer] := 'Remixer';
           Info.Fields[tfPublisher] := 'Pladeselskab A/S';
           Info.Fields[tfCatalogNo] := 'CAT 123';
           Info.Fields[tfIsrc] := 'DKABC2400001';
           Info.Fields[tfCopyright] := '© 2001 Nogen';
           Info.Fields[tfEncodedBy] := 'TagKlon';
           Info.Fields[tfUrl] := 'https://example.com/a?b=1';
           Info.Fields[tfGrouping] := 'Gruppe';
           Info.Fields[tfSubtitle] := 'Undertitel';
           Info.Fields[tfMood] := 'Glad';
           Info.Fields[tfInitialKey] := 'Am';
           Info.Fields[tfSortTitle] := 'Sort titel';
           Info.Fields[tfSortArtist] := 'Kunstner, Sort';
           Info.Fields[tfSortAlbumArtist] := 'Kunstnere, Diverse';
           Info.Fields[tfSortAlbum] := 'Ålborg, Album';
           Info.Fields[tfSortComposer] := 'Nielsen, Carl';
           Info.Fields[tfCompilation] := '1';
           Info.Fields[tfPodcast] := '1';
           SetPicture(Info, 0);
         end;
      1: SetPicture(Info, 400 * 1024);
      2: begin
           Info.Fields[tfComment] := '';
           Info.Fields[tfComposer] := '';
           Info.Fields[tfLyrics] := '';
           Info.Fields[tfMood] := '';
           Info.Fields[tfCatalogNo] := '';
           Info.Fields[tfUrl] := '';
           Info.Pictures := nil;
         end;
    end;
    for F := Low(TTagField) to High(TTagField) do Expected[F] := Info.Fields[F];
    // WMA has no podcast flag
    if SameText(ExtractFileExt(FileName), '.wma') then Expected[tfPodcast] := '';
    Pics := Copy(Info.Pictures);
    try
      WriteAudioTags(Info, True);
    except
      on E: Exception do
      begin
        Check(False, 'skrivning: ' + E.Message);
        Exit;
      end;
    end;
  finally
    Info.Free;
  end;

  Back := ReadAudioInfo(FileName, True);
  try
    Check(Back.Error = '', 'genlæsning uden fejl ' + Back.Error);
    for F := Low(TTagField) to High(TTagField) do
      Check(Back.Fields[F] = Expected[F], Format('%s = "%s" (forventet "%s")',
        [TagFieldCaptions[F], Back.Fields[F], Expected[F]]));
    Check(Length(Back.Pictures) = Length(Pics), Format('%d billede(r)', [Length(Back.Pictures)]));
    if (Length(Pics) > 0) and (Length(Back.Pictures) > 0) then
      Check(SamePicture(Back.Pictures[0], Pics[0]), 'billeddata identiske');
    Check(AudioFingerprint(FileName) = AudioCrc, 'lyddata uændret');
    WriteLn(Format('   filstørrelse %d -> %d', [SizeBefore, Back.FileSize]));
  finally
    Back.Free;
  end;
end;

{ E: swap, copy and clean-spaces tools through BatchWrite. }
procedure ToolScenario(const FileName: string; AudioCrc: Cardinal);
var
  Info: TAudioInfo;
  P: TFieldPlan;
  Err: string;
  Skipped: Boolean;
  Artist, Title: string;
begin
  WriteLn('  Scenarie E (felt-værktøjer)');
  Info := ReadAudioInfo(FileName, False);
  try
    Info.Fields[tfArtist] := '';
    Info.Fields[tfTitle] := '';
    P.Fields := [tfArtist, tfTitle, tfComposer];
    P.Values[tfArtist] := 'Kunstner  med   mellemrum';
    P.Values[tfTitle] := 'Titel æøå';
    P.Values[tfComposer] := '';
    Check(UpdateFileTags(Info, P.Values, P.Fields, nil, False, Err, Skipped), 'forberedelse ' + Err);
    Artist := Info.Fields[tfArtist];
    Title := Info.Fields[tfTitle];
    P := PlanSwap(Info, tfArtist, tfTitle);
    Check(UpdateFileTags(Info, P.Values, P.Fields, nil, False, Err, Skipped), 'byt ' + Err);
    P := PlanCopy(Info, tfTitle, tfComposer, True);
    Check(UpdateFileTags(Info, P.Values, P.Fields, nil, False, Err, Skipped), 'kopiér ' + Err);
    P := PlanCleanSpaces(Info);
    Check(UpdateFileTags(Info, P.Values, P.Fields, nil, False, Err, Skipped), 'mellemrum ' + Err);
  finally
    Info.Free;
  end;
  Info := ReadAudioInfo(FileName, False);
  try
    Check(Info.Fields[tfArtist] = Title, 'kunstner = gammel titel: ' + Info.Fields[tfArtist]);
    Check(Info.Fields[tfTitle] = 'Kunstner med mellemrum', 'titel = gammel kunstner, mellemrum ryddet: ' + Info.Fields[tfTitle]);
    Check(Info.Fields[tfComposer] = 'Kunstner med mellemrum', 'komponist kopieret: ' + Info.Fields[tfComposer]);
  finally
    Info.Free;
  end;
  Check(AudioFingerprint(FileName) = AudioCrc, 'lyddata uændret');
end;

{ D: remove tags. }
procedure RemoveScenario(const FileName: string; AudioCrc: Cardinal);
var
  Info: TAudioInfo;
  F: TTagField;
  Empty: Boolean;
begin
  WriteLn('  Scenarie D (fjern tags)');
  try
    RemoveAllTags(FileName, True);
  except
    on E: Exception do
    begin
      Check(False, 'fjern tags: ' + E.Message);
      Exit;
    end;
  end;
  Info := ReadAudioInfo(FileName, True);
  try
    Check(Info.Error = '', 'genlæsning ' + Info.Error);
    Empty := True;
    for F := Low(TTagField) to High(TTagField) do
      if Info.Fields[F] <> '' then
      begin
        Empty := False;
        WriteLn('     tilbage: ', TagFieldCaptions[F], ' = ', Info.Fields[F]);
      end;
    Check(Empty, 'alle felter tomme');
    Check(Length(Info.Pictures) = 0, 'ingen billeder');
    if RemovesWholeTag(FileName) then
      Check(Info.TagTypes = '', 'ingen tags tilbage: ' + Info.TagTypes);
  finally
    Info.Free;
  end;
  Check(AudioFingerprint(FileName) = AudioCrc, 'lyddata uændret');
end;

var
  I: Integer;
  Dir, Src, Dst: string;
  AudioCrc: Cardinal;
begin
  SetMultiByteConversionCodePage(CP_UTF8);
  SetMultiByteFileSystemCodePage(CP_UTF8);
  {$IFDEF WINDOWS}SetConsoleOutputCP(CP_UTF8);{$ENDIF}
  SetTextCodePage(Output, CP_UTF8);
  Randomize;
  if ParamCount < 2 then
  begin
    WriteLn('Brug: tagtest <testmappe> <fil> [<fil> ...]   (arbejder på kopier)');
    Halt(2);
  end;
  Dir := IncludeTrailingPathDelimiter(UTF8Encode(UnicodeString(ParamStr(1))));
  ForceDirectories(Dir);
  for I := 2 to ParamCount do
  begin
    Src := UTF8Encode(UnicodeString(ParamStr(I)));
    Dst := Dir + ExtractFileName(Src);
    if not CopyFileW(PWideChar(UTF8Decode(Src)), PWideChar(UTF8Decode(Dst)), False) then
    begin
      WriteLn('Kunne ikke kopiere ', Src);
      Inc(Failures);
      Continue;
    end;
    WriteLn('== ', ExtractFileName(Dst));
    AudioCrc := AudioFingerprint(Dst);
    Scenario(Dst, 'A', 0, AudioCrc);
    Scenario(Dst, 'B', 1, AudioCrc);
    Scenario(Dst, 'C', 2, AudioCrc);
    ToolScenario(Dst, AudioCrc);
    RemoveScenario(Dst, AudioCrc);
  end;
  WriteLn;
  if Failures = 0 then WriteLn('ALLE TESTS OK') else WriteLn(Failures, ' FEJL');
  ExitCode := Ord(Failures > 0);
end.
