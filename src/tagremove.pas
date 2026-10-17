unit TagRemove;

{ "Remove tags". MP3 and the APE family (Monkey's, WavPack, Musepack, OptimFROG) lose
  their whole ID3v2, APE and ID3v1 tags; WAV/AIFF lose their ID3 and LIST/INFO chunks
  (AIFF also its NAME/AUTH/ANNO/(c) text chunks).
  The other formats keep their tag structure (it holds stream data too), but every field
  TidyTag knows and every picture is cleared; technical fields such as ReplayGain stay.
  The audio data is never changed. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, AudioTypes;

{ True: the format loses its tags completely (else fields and pictures are cleared). }
function RemovesWholeTag(const FileName: string): Boolean;
procedure RemoveAllTags(const FileName: string; KeepTimestamp: Boolean);

implementation

uses
  TagUtils, Mp3Reader, ApeTag, WavReader, AudioTags, TagWriter;

resourcestring
  rsUventetTagStruktur = 'Uventet tag-struktur';
  rsFiltypenKanIkkeGemmes = 'Skrivning af denne filtype understøttes ikke endnu';

function RemovesWholeTag(const FileName: string): Boolean;
begin
  case LowerCase(ExtractFileExt(FileName)) of
    '.mp3', '.mp2', '.ape', '.wv', '.mpc', '.ofr', '.wav', '.aif', '.aiff', '.aifc': Result := True;
  else
    Result := False;
  end;
end;

{ ID3v2 at the start, APE tag and ID3v1 at the end. }
procedure StripEnds(const FileName: string);
var
  S, Dst: TFileStream;
  Ver: Byte;
  Frames: TID3Frames;
  Start, Stop: Int64;
  Temp: string;
begin
  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    S.Position := 0;
    ParseID3v2(S, Ver, Frames, Start);
    if Start < 0 then Start := 0;
    Stop := FindApeTag(S).AudioEnd;
    if (Start = 0) and (Stop = S.Size) then Exit; // no tags
    if Stop <= Start then raise Exception.Create(rsUventetTagStruktur);
    Temp := TempFileFor(FileName);
    try
      Dst := TFileStream.Create(Temp, fmCreate);
      try
        CopyStreamRange(S, Dst, Start, Stop - Start);
      finally
        Dst.Free;
      end;
      FreeAndNil(S);
      ReplaceFileWith(Temp, FileName);
    except
      DeleteFile(Temp);
      raise;
    end;
  finally
    S.Free;
  end;
end;

{ ID3/LIST-INFO chunks and, for AIFF, the NAME/AUTH/ANNO/(c) text chunks. }
function IsRemovedChunk(S: TStream; const CF: TChunkFile; const C: TChunk): Boolean;
begin
  Result := IsTagChunk(S, C) or (CF.IsAiff and ((C.ID = 'NAME') or (C.ID = 'AUTH') or
    (C.ID = 'ANNO') or (C.ID = '(c) ')));
end;

procedure StripChunks(const FileName: string);
var
  S, Dst: TFileStream;
  CF: TChunkFile;
  C: TChunk;
  Any: Boolean;
  Temp: string;
begin
  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    CF := ReadChunkFile(S);
    Any := False;
    for C in CF.Chunks do
      if IsRemovedChunk(S, CF, C) then Any := True;
    if not Any then Exit;
    Temp := TempFileFor(FileName);
    try
      Dst := TFileStream.Create(Temp, fmCreate);
      try
        if CF.IsAiff then WriteAscii(Dst, 'FORM') else WriteAscii(Dst, 'RIFF');
        WriteLE32(Dst, 0);
        WriteAscii(Dst, CF.FormType);
        for C in CF.Chunks do
          if not IsRemovedChunk(S, CF, C) then
          begin
            WriteAscii(Dst, C.ID);
            if CF.IsAiff then WriteBE32(Dst, C.Size) else WriteLE32(Dst, C.Size);
            CopyStreamRange(S, Dst, C.DataPos, C.Size);
            if Odd(C.Size) then Dst.WriteByte(0);
          end;
        Dst.Position := 4;
        if CF.IsAiff then WriteBE32(Dst, Dst.Size - 8) else WriteLE32(Dst, Dst.Size - 8);
      finally
        Dst.Free;
      end;
      FreeAndNil(S);
      ReplaceFileWith(Temp, FileName);
    except
      DeleteFile(Temp);
      raise;
    end;
  finally
    S.Free;
  end;
end;

procedure ClearFields(const FileName: string; KeepTimestamp: Boolean);
var
  Info: TAudioInfo;
  F: TTagField;
begin
  Info := ReadAudioInfo(FileName, True);
  try
    if Info.Error <> '' then raise Exception.Create(Info.Error);
    for F := Low(TTagField) to High(TTagField) do Info.Fields[F] := '';
    Info.Pictures := nil;
    WriteAudioTags(Info, KeepTimestamp);
  finally
    Info.Free;
  end;
end;

procedure RemoveAllTags(const FileName: string; KeepTimestamp: Boolean);
var
  Stamp: TFileStamp;
begin
  if not RemovesWholeTag(FileName) then
  begin
    if not CanWriteTags(FileName) then
      raise Exception.Create(rsFiltypenKanIkkeGemmes);
    ClearFields(FileName, KeepTimestamp);
    Exit;
  end;
  if KeepTimestamp then Stamp := GetFileStamp(FileName);
  case LowerCase(ExtractFileExt(FileName)) of
    '.wav', '.aif', '.aiff', '.aifc': StripChunks(FileName);
  else
    StripEnds(FileName);
  end;
  if KeepTimestamp then SetFileStamp(FileName, Stamp);
end;

end.
