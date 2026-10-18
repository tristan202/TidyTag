unit ID3Writer;

{ Writes the editable fields and pictures of TAudioInfo into an MP3's ID3v2 tag.
  Frames we do not edit are kept byte for byte. An existing v2.3/v2.4 tag keeps its
  version; files without a tag (or with v2.2) get ID3v2.3, which every player reads.
  An existing ID3v1 tag is updated so both tags agree; none is created. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, AudioTypes;

procedure WriteMp3Tags(const FileName: string; Info: TAudioInfo);
{ A complete ID3v2 tag (header, frames, Padding zero bytes) built from an existing tag
  (OldTag may be nil); used for the ID3 chunk in WAV and AIFF files. }
function BuildID3TagBytes(const OldTag: TBytes; Info: TAudioInfo; Padding: Integer): TBytes;
{ Updates an existing ID3v1 tag at the end of the file; does nothing if there is none. }
procedure UpdateID3v1(const FileName: string; Info: TAudioInfo);
{ Same, but CreateIfMissing appends a new ID3v1 tag when the file has none. }
procedure WriteID3v1(const FileName: string; Info: TAudioInfo; CreateIfMissing: Boolean);

var
  { ID3v2.3 text is always UTF-16; otherwise Latin-1 when every text fits (Settings). }
  ID3AlwaysUnicode: Boolean = False;

implementation

uses
  TagUtils, Mp3Reader;

resourcestring
  rsIdVDUnderstoettesIkke = 'ID3v2.%d understøttes ikke';


const
  NewTagPadding = 4096;

function IsManagedFrame(const ID: string; const Fr: TID3Frame): Boolean;
var
  Desc: string;
  P: SizeInt;
begin
  if (ID = 'TIT2') or (ID = 'TPE1') or (ID = 'TALB') or (ID = 'TYER') or (ID = 'TDAT') or
    (ID = 'TDRC') or (ID = 'TRCK') or (ID = 'TPOS') or (ID = 'TCON') or (ID = 'TPE2') or
    (ID = 'TCOM') or (ID = 'TBPM') or (ID = 'APIC') or (ID = 'PIC') or
    (ID = 'TPE3') or (ID = 'TEXT') or (ID = 'TOPE') or (ID = 'TPE4') or (ID = 'TPUB') or
    (ID = 'TSRC') or (ID = 'TCOP') or (ID = 'TENC') or (ID = 'TIT1') or (ID = 'GRP1') or
    (ID = 'TIT3') or (ID = 'TMOO') or (ID = 'TKEY') or (ID = 'TSOT') or (ID = 'TSOP') or
    (ID = 'TSO2') or (ID = 'TSOA') or (ID = 'TSOC') or (ID = 'USLT') or (ID = 'TCMP') or
    (ID = 'PCST') then
    Exit(True);
  if (ID = 'TXXX') or (ID = 'WXXX') then
  begin
    if Length(Fr.Data) < 2 then Exit(True);
    P := SkipTerminated(Fr.Data, 1, Fr.Data[0]);
    Desc := UpperCase(DecodeID3Text(Fr.Data, 1, P - 1, Fr.Data[0]));
    if ID = 'WXXX' then Exit(Desc = ''); // the plain URL we edit; other links stay
    Exit((Desc = 'CATALOGNUMBER') or (Desc = 'MOOD') or (Desc = 'LABEL') or
      (Desc = 'REPLAYGAIN_TRACK_GAIN') or (Desc = 'REPLAYGAIN_TRACK_PEAK') or
      (Desc = 'REPLAYGAIN_ALBUM_GAIN') or (Desc = 'REPLAYGAIN_ALBUM_PEAK'));
  end;
  if ID = 'COMM' then
  begin
    // iTunes keeps technical data in comments (iTunNORM, iTunSMPB, ...): leave those.
    if Length(Fr.Data) < 4 then Exit(True);
    P := SkipTerminated(Fr.Data, 4, Fr.Data[0]);
    Desc := DecodeID3Text(Fr.Data, 4, P - 4, Fr.Data[0]);
    Exit(not SameText(Copy(Desc, 1, 4), 'iTun'));
  end;
  Result := False;
end;

function FitsLatin1(const U: UnicodeString): Boolean;
var
  C: WideChar;
begin
  for C in U do
    if Ord(C) > 255 then Exit(False);
  Result := True;
end;

{ Text encoding byte: v2.4 -> UTF-8; v2.3 -> Latin-1 when possible, else UTF-16 with BOM. }
function ChooseEncoding(Version: Byte; const Texts: array of string): Byte;
var
  T: string;
begin
  if Version = 4 then Exit(3);
  if ID3AlwaysUnicode then Exit(1);
  for T in Texts do
    if not FitsLatin1(UTF8Decode(T)) then Exit(1);
  Result := 0;
end;

procedure WriteEncoded(S: TStream; const Text: string; Enc: Byte; Terminate: Boolean);
var
  U: UnicodeString;
  C: WideChar;
begin
  case Enc of
    0: begin
         U := UTF8Decode(Text);
         for C in U do S.WriteByte(Ord(C));
         if Terminate then S.WriteByte(0);
       end;
    1: begin
         U := UTF8Decode(Text);
         S.WriteByte($FF); S.WriteByte($FE);
         for C in U do
         begin
           S.WriteByte(Ord(C) and $FF);
           S.WriteByte(Ord(C) shr 8);
         end;
         if Terminate then begin S.WriteByte(0); S.WriteByte(0); end;
       end;
  else // 3 = UTF-8
    WriteBytes(S, UTF8Bytes(Text));
    if Terminate then S.WriteByte(0);
  end;
end;

procedure WriteFrame(Dest: TStream; Version: Byte; const ID: string; Flags: Word; const Body: TBytes);
var
  N: Cardinal;
begin
  WriteAscii(Dest, ID);
  N := Length(Body);
  if Version = 4 then
    WriteBE32(Dest, ((N shr 21) and $7F) shl 24 or ((N shr 14) and $7F) shl 16 or
      ((N shr 7) and $7F) shl 8 or (N and $7F))
  else
    WriteBE32(Dest, N);
  WriteBE16(Dest, Flags);
  WriteBytes(Dest, Body);
end;

procedure AddTextFrame(Dest: TStream; Version: Byte; const ID, Value: string);
var
  B: TBytesStream;
  Enc: Byte;
begin
  if Value = '' then Exit;
  B := TBytesStream.Create;
  try
    Enc := ChooseEncoding(Version, [Value]);
    B.WriteByte(Enc);
    WriteEncoded(B, Value, Enc, False);
    WriteFrame(Dest, Version, ID, 0, StreamBytes(B));
  finally
    B.Free;
  end;
end;

procedure AddCommentFrame(Dest: TStream; Version: Byte; const Value: string);
var
  B: TBytesStream;
  Enc: Byte;
begin
  if Value = '' then Exit;
  B := TBytesStream.Create;
  try
    Enc := ChooseEncoding(Version, [Value]);
    B.WriteByte(Enc);
    WriteAscii(B, 'eng');
    WriteEncoded(B, '', Enc, True); // empty description
    WriteEncoded(B, Value, Enc, False);
    WriteFrame(Dest, Version, 'COMM', 0, StreamBytes(B));
  finally
    B.Free;
  end;
end;

{ TXXX: user-defined text with a description such as 'CATALOGNUMBER'. }
procedure AddTxxxFrame(Dest: TStream; Version: Byte; const Desc, Value: string);
var
  B: TBytesStream;
  Enc: Byte;
begin
  if Value = '' then Exit;
  B := TBytesStream.Create;
  try
    Enc := ChooseEncoding(Version, [Desc, Value]);
    B.WriteByte(Enc);
    WriteEncoded(B, Desc, Enc, True);
    WriteEncoded(B, Value, Enc, False);
    WriteFrame(Dest, Version, 'TXXX', 0, StreamBytes(B));
  finally
    B.Free;
  end;
end;

procedure AddLyricsFrame(Dest: TStream; Version: Byte; const Value: string);
var
  B: TBytesStream;
  Enc: Byte;
begin
  if Value = '' then Exit;
  B := TBytesStream.Create;
  try
    Enc := ChooseEncoding(Version, [Value]);
    B.WriteByte(Enc);
    WriteAscii(B, 'eng');
    WriteEncoded(B, '', Enc, True);
    WriteEncoded(B, Value, Enc, False);
    WriteFrame(Dest, Version, 'USLT', 0, StreamBytes(B));
  finally
    B.Free;
  end;
end;

{ WXXX: encoding, empty description, URL as Latin-1. }
procedure AddUrlFrame(Dest: TStream; Version: Byte; const Url: string);
var
  B: TBytesStream;
  U: UnicodeString;
  C: WideChar;
begin
  if Url = '' then Exit;
  B := TBytesStream.Create;
  try
    B.WriteByte(0);
    B.WriteByte(0);
    U := UTF8Decode(Url);
    for C in U do
      if Ord(C) <= 255 then B.WriteByte(Ord(C)) else B.WriteByte(Ord('?'));
    WriteFrame(Dest, Version, 'WXXX', 0, StreamBytes(B));
  finally
    B.Free;
  end;
end;

procedure AddPictureFrame(Dest: TStream; Version: Byte; const Pic: TTagPicture);
var
  B: TBytesStream;
  Enc: Byte;
begin
  B := TBytesStream.Create;
  try
    Enc := ChooseEncoding(Version, [Pic.Description]);
    B.WriteByte(Enc);
    WriteAscii(B, Pic.MimeType);
    B.WriteByte(0);
    B.WriteByte(Pic.PicType);
    WriteEncoded(B, Pic.Description, Enc, True);
    WriteBytes(B, Pic.Data);
    WriteFrame(Dest, Version, 'APIC', 0, StreamBytes(B));
  finally
    B.Free;
  end;
end;

procedure AddYearFrames(Dest: TStream; Version: Byte; const Year: string);
var
  Y, M, D: string;
begin
  if Year = '' then Exit;
  if Version = 4 then
  begin
    AddTextFrame(Dest, Version, 'TDRC', Year);
    Exit;
  end;
  // v2.3 has a 4-digit year (TYER) and a separate DDMM date (TDAT).
  Y := Copy(Year, 1, 4);
  if (Length(Year) >= 10) and (Year[5] = '-') and (Year[8] = '-') and
    (StrToIntDef(Y, -1) >= 0) then
  begin
    M := Copy(Year, 6, 2);
    D := Copy(Year, 9, 2);
    AddTextFrame(Dest, Version, 'TYER', Y);
    AddTextFrame(Dest, Version, 'TDAT', D + M);
  end
  else
    AddTextFrame(Dest, Version, 'TYER', Year);
end;

function BuildFrames(Version, OldVersion: Byte; const Old: TID3Frames; Info: TAudioInfo): TBytes;
var
  Dest: TBytesStream;
  I: Integer;
  ID: string;
begin
  Dest := TBytesStream.Create;
  try
    // 1. Everything we do not edit, unchanged.
    for I := 0 to High(Old) do
    begin
      ID := Old[I].ID;
      if OldVersion = 2 then
      begin
        ID := V22ToV23(ID);
        if Length(ID) <> 4 then Continue; // v2.2-only frame we cannot convert
        if IsManagedFrame(ID, Old[I]) then Continue;
        WriteFrame(Dest, Version, ID, 0, Old[I].Data);
      end
      else
      begin
        if IsManagedFrame(ID, Old[I]) then Continue;
        WriteFrame(Dest, Version, ID, Old[I].Flags, Old[I].Raw);
      end;
    end;
    // 2. The edited fields.
    AddTextFrame(Dest, Version, 'TIT2', Info.Fields[tfTitle]);
    AddTextFrame(Dest, Version, 'TPE1', Info.Fields[tfArtist]);
    AddTextFrame(Dest, Version, 'TALB', Info.Fields[tfAlbum]);
    AddTextFrame(Dest, Version, 'TPE2', Info.Fields[tfAlbumArtist]);
    AddYearFrames(Dest, Version, Info.Fields[tfYear]);
    AddTextFrame(Dest, Version, 'TRCK', Info.Fields[tfTrack]);
    AddTextFrame(Dest, Version, 'TPOS', Info.Fields[tfDisc]);
    AddTextFrame(Dest, Version, 'TCON', Info.Fields[tfGenre]);
    AddTextFrame(Dest, Version, 'TCOM', Info.Fields[tfComposer]);
    AddTextFrame(Dest, Version, 'TBPM', Info.Fields[tfBpm]);
    AddCommentFrame(Dest, Version, Info.Fields[tfComment]);
    AddTextFrame(Dest, Version, 'TPE3', Info.Fields[tfConductor]);
    AddTextFrame(Dest, Version, 'TEXT', Info.Fields[tfLyricist]);
    AddTextFrame(Dest, Version, 'TOPE', Info.Fields[tfOrigArtist]);
    AddTextFrame(Dest, Version, 'TPE4', Info.Fields[tfRemixer]);
    AddTextFrame(Dest, Version, 'TPUB', Info.Fields[tfPublisher]);
    AddTxxxFrame(Dest, Version, 'CATALOGNUMBER', Info.Fields[tfCatalogNo]);
    AddTextFrame(Dest, Version, 'TSRC', Info.Fields[tfIsrc]);
    AddTextFrame(Dest, Version, 'TCOP', Info.Fields[tfCopyright]);
    AddTextFrame(Dest, Version, 'TENC', Info.Fields[tfEncodedBy]);
    AddUrlFrame(Dest, Version, Info.Fields[tfUrl]);
    AddTextFrame(Dest, Version, 'TIT1', Info.Fields[tfGrouping]);
    AddTextFrame(Dest, Version, 'TIT3', Info.Fields[tfSubtitle]);
    // TMOO only exists in v2.4; v2.3 players read the TXXX:MOOD convention
    if Version = 4 then AddTextFrame(Dest, Version, 'TMOO', Info.Fields[tfMood])
    else AddTxxxFrame(Dest, Version, 'MOOD', Info.Fields[tfMood]);
    AddTextFrame(Dest, Version, 'TKEY', Info.Fields[tfInitialKey]);
    // Sort frames: standard in v2.4, written by iTunes in v2.3 as well
    AddTextFrame(Dest, Version, 'TSOT', Info.Fields[tfSortTitle]);
    AddTextFrame(Dest, Version, 'TSOP', Info.Fields[tfSortArtist]);
    AddTextFrame(Dest, Version, 'TSO2', Info.Fields[tfSortAlbumArtist]);
    AddTextFrame(Dest, Version, 'TSOA', Info.Fields[tfSortAlbum]);
    AddTextFrame(Dest, Version, 'TSOC', Info.Fields[tfSortComposer]);
    // iTunes flags: TCMP "1" = part of a compilation, PCST (4-byte number) = podcast
    if IsTrueFlag(Info.Fields[tfCompilation]) then AddTextFrame(Dest, Version, 'TCMP', '1');
    if IsTrueFlag(Info.Fields[tfPodcast]) then WriteFrame(Dest, Version, 'PCST', 0, TBytes.Create(0, 0, 0, 1));
    AddTxxxFrame(Dest, Version, 'REPLAYGAIN_TRACK_GAIN', Info.Fields[tfRGTrackGain]);
    AddTxxxFrame(Dest, Version, 'REPLAYGAIN_TRACK_PEAK', Info.Fields[tfRGTrackPeak]);
    AddTxxxFrame(Dest, Version, 'REPLAYGAIN_ALBUM_GAIN', Info.Fields[tfRGAlbumGain]);
    AddTxxxFrame(Dest, Version, 'REPLAYGAIN_ALBUM_PEAK', Info.Fields[tfRGAlbumPeak]);
    AddLyricsFrame(Dest, Version, Info.Fields[tfLyrics]);
    for I := 0 to High(Info.Pictures) do
      AddPictureFrame(Dest, Version, Info.Pictures[I]);
    Result := StreamBytes(Dest);
  finally
    Dest.Free;
  end;
end;

procedure WriteTagHeader(Dest: TStream; Version: Byte; BodySize: Cardinal);
begin
  WriteAscii(Dest, 'ID3');
  Dest.WriteByte(Version);
  Dest.WriteByte(0); // revision
  Dest.WriteByte(0); // flags: no unsync, no extended header, no footer
  WriteBE32(Dest, ((BodySize shr 21) and $7F) shl 24 or ((BodySize shr 14) and $7F) shl 16 or
    ((BodySize shr 7) and $7F) shl 8 or (BodySize and $7F));
end;

function BuildID3TagBytes(const OldTag: TBytes; Info: TAudioInfo; Padding: Integer): TBytes;
var
  Src: TBytesStream;
  Dest: TBytesStream;
  OldVersion, Version: Byte;
  Old: TID3Frames;
  OldSize: Int64;
  Body: TBytes;
begin
  Src := TBytesStream.Create(OldTag);
  Dest := TBytesStream.Create;
  try
    if not ParseID3v2(Src, OldVersion, Old, OldSize) then
    begin
      OldVersion := 0;
      Old := nil;
    end;
    if OldVersion in [3, 4] then Version := OldVersion else Version := 3;
    Body := BuildFrames(Version, OldVersion, Old, Info);
    WriteTagHeader(Dest, Version, Length(Body) + Padding);
    WriteBytes(Dest, Body);
    WriteZeros(Dest, Padding);
    Result := StreamBytes(Dest);
  finally
    Src.Free;
    Dest.Free;
  end;
end;

{ ---------- ID3v1 ---------- }

procedure PutLatin1(var B: TBytes; P, MaxLen: Integer; const Text: string);
var
  U: UnicodeString;
  I: Integer;
begin
  FillChar(B[P], MaxLen, 0);
  U := UTF8Decode(Text);
  for I := 1 to Length(U) do
  begin
    if I > MaxLen then Break;
    if Ord(U[I]) <= 255 then B[P + I - 1] := Ord(U[I]) else B[P + I - 1] := Ord('?');
  end;
end;

procedure UpdateID3v1(const FileName: string; Info: TAudioInfo);
begin
  WriteID3v1(FileName, Info, False);
end;

procedure WriteID3v1(const FileName: string; Info: TAudioInfo; CreateIfMissing: Boolean);
var
  S: TFileStream;
  B: TBytes;
  Track, Genre: Integer;
  Exists: Boolean;
begin
  S := TFileStream.Create(FileName, fmOpenReadWrite or fmShareDenyWrite);
  try
    Exists := False;
    if S.Size >= 128 then
    begin
      S.Position := S.Size - 128;
      B := ReadStreamBytes(S, 128);
      Exists := (Length(B) = 128) and BytesAre(B, 0, 'TAG');
    end;
    if not Exists then
    begin
      if not CreateIfMissing then Exit;
      SetLength(B, 128);
      FillChar(B[0], 128, 0);
      B[0] := Ord('T'); B[1] := Ord('A'); B[2] := Ord('G');
      B[127] := 255;
      S.Size := S.Size + 128; // the new tag is written at the very end below
    end;
    PutLatin1(B, 3, 30, Info.Fields[tfTitle]);
    PutLatin1(B, 33, 30, Info.Fields[tfArtist]);
    PutLatin1(B, 63, 30, Info.Fields[tfAlbum]);
    PutLatin1(B, 93, 4, Copy(Info.Fields[tfYear], 1, 4));
    Track := StrToIntDef(Copy(Info.Fields[tfTrack], 1, Pos('/', Info.Fields[tfTrack] + '/') - 1), 0);
    if (Track > 0) and (Track <= 255) then
    begin
      PutLatin1(B, 97, 28, Info.Fields[tfComment]);
      B[125] := 0;
      B[126] := Track;
    end
    else
      PutLatin1(B, 97, 30, Info.Fields[tfComment]);
    Genre := ID3GenreIndex(Info.Fields[tfGenre]);
    if Genre >= 0 then B[127] := Genre
    else if Info.Fields[tfGenre] = '' then B[127] := 255;
    S.Position := S.Size - 128;
    S.WriteBuffer(B[0], 128);
  finally
    S.Free;
  end;
end;

{ ---------- main ---------- }

procedure WriteMp3Tags(const FileName: string; Info: TAudioInfo);
var
  Src, Dst: TFileStream;
  OldVersion, Version: Byte;
  Old: TID3Frames;
  OldTagSize: Int64;
  Body: TBytes;
  Padding: Int64;
  Temp: string;
begin
  Src := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    if not ParseID3v2(Src, OldVersion, Old, OldTagSize) then
    begin
      if OldTagSize > 0 then
        raise Exception.CreateFmt(rsIdVDUnderstoettesIkke, [OldVersion]);
      OldVersion := 0;
    end;
    if OldVersion in [3, 4] then Version := OldVersion else Version := 3;
    Body := BuildFrames(Version, OldVersion, Old, Info);

    if (OldTagSize > 0) and (10 + Int64(Length(Body)) <= OldTagSize) then
    begin
      // Fits in the old tag's space: overwrite it in place, the rest is padding.
      Src.Free;
      Src := nil;
      Padding := OldTagSize - 10 - Length(Body);
      Dst := TFileStream.Create(FileName, fmOpenReadWrite or fmShareDenyWrite);
      try
        WriteTagHeader(Dst, Version, Length(Body) + Padding);
        WriteBytes(Dst, Body);
        WriteZeros(Dst, Padding);
      finally
        Dst.Free;
      end;
    end
    else
    begin
      // Too big: write tag + audio to a new file, then swap it in.
      Temp := TempFileFor(FileName);
      Dst := TFileStream.Create(Temp, fmCreate);
      try
        try
          WriteTagHeader(Dst, Version, Length(Body) + NewTagPadding);
          WriteBytes(Dst, Body);
          WriteZeros(Dst, NewTagPadding);
          CopyStreamRange(Src, Dst, OldTagSize, Src.Size - OldTagSize);
        finally
          Dst.Free;
        end;
        FreeAndNil(Src);
        ReplaceFileWith(Temp, FileName);
      except
        DeleteFile(Temp);
        raise;
      end;
    end;
  finally
    Src.Free;
  end;
  UpdateID3v1(FileName, Info);
end;

end.
