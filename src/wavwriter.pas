unit WavWriter;

{ Writes tags into WAV and AIFF files: an ID3v2 chunk (all fields and pictures) and, for
  WAV, a LIST/INFO chunk with the basic fields so that Windows and older players show
  them too. Both chunks are placed after the audio. When the tag chunks already are the
  last chunks the file is updated in place (cut and appended); otherwise it is rewritten
  via a temporary file. Audio and other chunks are copied unchanged. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, AudioTypes;

procedure WriteWavAiffTags(const FileName: string; Info: TAudioInfo);

implementation

uses
  TagUtils, WavReader, ID3Writer;

resourcestring
  rsFilenBliverStoerreEndGb = 'Filen bliver større end 4 GB, hvilket WAV/AIFF ikke tillader';
  rsFilenIndeholderIngenLyd = 'Filen indeholder ingen lyd';


procedure WriteSize(S: TStream; V: Int64; BigEndian: Boolean);
begin
  if V > High(Cardinal) then
    raise Exception.Create(rsFilenBliverStoerreEndGb);
  if BigEndian then WriteBE32(S, V) else WriteLE32(S, V);
end;

procedure WriteChunk(S: TStream; const ID: string; const Data: TBytes; BigEndian: Boolean);
begin
  WriteAscii(S, ID);
  WriteSize(S, Length(Data), BigEndian);
  WriteBytes(S, Data);
  if Odd(Length(Data)) then S.WriteByte(0);
end;

{ Text for an INFO item: Latin-1 when every character fits, else UTF-8; zero-terminated. }
function InfoBytes(const Value: string): TBytes;
var
  W: UnicodeString;
  I: Integer;
  Latin: Boolean;
begin
  W := UTF8Decode(Value);
  Latin := True;
  for I := 1 to Length(W) do
    if (Ord(W[I]) > $FF) or ((Ord(W[I]) >= $80) and (Ord(W[I]) < $A0)) then
    begin
      Latin := False;
      Break;
    end;
  if Latin then
  begin
    SetLength(Result, Length(W) + 1);
    for I := 1 to Length(W) do Result[I - 1] := Ord(W[I]);
  end
  else
  begin
    Result := UTF8Bytes(Value);
    SetLength(Result, Length(Result) + 1);
  end;
  Result[High(Result)] := 0;
end;

{ New LIST/INFO body: unmanaged items of the old list are kept, managed ones rebuilt.
  Returns nil when the list would be empty. }
function BuildInfoList(const Old: TBytes; Info: TAudioInfo): TBytes;
const
  Items: array[0..9] of string = ('INAM', 'IART', 'IPRD', 'ICRD', 'ITRK', 'IGNR', 'ICMT',
    'ICOP', 'IMUS', 'IENC');
var
  B: TBytesStream;
  P, Size: Int64;
  F: TTagField;
  ID: string;
  Any: Boolean;
begin
  Any := False;
  B := TBytesStream.Create;
  try
    WriteAscii(B, 'INFO');
    P := 4;
    while P + 8 <= Length(Old) do
    begin
      ID := BytesToAscii(Old, P, 4);
      Size := LE32(Old, P + 4);
      if P + 8 + Size > Length(Old) then Break;
      if not InfoField(ID, F) then
      begin
        WriteChunk(B, ID, Copy(Old, P + 8, Size), False);
        Any := True;
      end;
      P := P + 8 + Size + (Size and 1);
    end;
    for ID in Items do
      if InfoField(ID, F) and (Info.Fields[F] <> '') then
      begin
        WriteChunk(B, ID, InfoBytes(Info.Fields[F]), False);
        Any := True;
      end;
    if Any then Result := StreamBytes(B) else Result := nil;
  finally
    B.Free;
  end;
end;

function ChunkEnd(const C: TChunk): Int64;
begin
  Result := C.DataPos + C.Size + (C.Size and 1);
end;

procedure WriteWavAiffTags(const FileName: string; Info: TAudioInfo);
var
  S, Dst: TFileStream;
  CF: TChunkFile;
  I, LastAudio: Integer;
  OldID3, OldInfo, NewID3, NewInfo: TBytes;
  ID3ID: string;
  InPlace: Boolean;
  Tail: TBytesStream;
  TailBytes: TBytes;
  KeepEnd: Int64;
  Temp: string;
begin
  OldID3 := nil;
  OldInfo := nil;
  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    CF := ReadChunkFile(S);
    if CF.IsAiff then ID3ID := 'ID3 ' else ID3ID := 'id3 ';
    LastAudio := -1;
    for I := 0 to High(CF.Chunks) do
      if IsTagChunk(S, CF.Chunks[I]) then
      begin
        S.Position := CF.Chunks[I].DataPos;
        if IsID3ChunkID(CF.Chunks[I].ID) then
        begin
          if OldID3 = nil then
          begin
            OldID3 := ReadStreamBytes(S, CF.Chunks[I].Size);
            ID3ID := CF.Chunks[I].ID;
          end;
        end
        else if OldInfo = nil then
          OldInfo := ReadStreamBytes(S, CF.Chunks[I].Size);
      end
      else
        LastAudio := I;
    if LastAudio < 0 then raise Exception.Create(rsFilenIndeholderIngenLyd);

    NewID3 := BuildID3TagBytes(OldID3, Info, 0);
    if CF.IsAiff then NewInfo := nil else NewInfo := BuildInfoList(OldInfo, Info);
    Tail := TBytesStream.Create;
    try
      WriteChunk(Tail, ID3ID, NewID3, CF.IsAiff);
      if NewInfo <> nil then WriteChunk(Tail, 'LIST', NewInfo, False);
      TailBytes := StreamBytes(Tail);
    finally
      Tail.Free;
    end;

    // in place when no tag chunk sits before the last audio/other chunk
    InPlace := True;
    for I := 0 to LastAudio - 1 do
      if IsTagChunk(S, CF.Chunks[I]) then InPlace := False;
    // a truncated last chunk is repaired by the rewrite
    KeepEnd := ChunkEnd(CF.Chunks[LastAudio]);
    if CF.Chunks[LastAudio].DataPos + CF.Chunks[LastAudio].Size > S.Size then InPlace := False;

    if not InPlace then
    begin
      Temp := TempFileFor(FileName);
      try
        Dst := TFileStream.Create(Temp, fmCreate);
        try
          if CF.IsAiff then WriteAscii(Dst, 'FORM') else WriteAscii(Dst, 'RIFF');
          WriteSize(Dst, 0, CF.IsAiff);
          WriteAscii(Dst, CF.FormType);
          for I := 0 to High(CF.Chunks) do
            if not IsTagChunk(S, CF.Chunks[I]) then
            begin
              WriteAscii(Dst, CF.Chunks[I].ID);
              WriteSize(Dst, CF.Chunks[I].Size, CF.IsAiff);
              CopyStreamRange(S, Dst, CF.Chunks[I].DataPos, CF.Chunks[I].Size);
              if Odd(CF.Chunks[I].Size) then Dst.WriteByte(0);
            end;
          WriteBytes(Dst, TailBytes);
          Dst.Position := 4;
          WriteSize(Dst, Dst.Size - 8, CF.IsAiff);
        finally
          Dst.Free;
        end;
        FreeAndNil(S);
        ReplaceFileWith(Temp, FileName);
      except
        DeleteFile(Temp);
        raise;
      end;
      Exit;
    end;
  finally
    S.Free;
  end;

  if KeepEnd + Length(TailBytes) - 8 > High(Cardinal) then
    raise Exception.Create(rsFilenBliverStoerreEndGb);
  S := TFileStream.Create(FileName, fmOpenReadWrite or fmShareExclusive);
  try
    S.Size := KeepEnd; // also restores a missing pad byte after the audio
    S.Position := KeepEnd;
    WriteBytes(S, TailBytes);
    S.Position := 4;
    WriteSize(S, S.Size - 8, CF.IsAiff);
  finally
    S.Free;
  end;
end;

end.
