unit ID3Sync;

{ MP3 tag synchronisation: copies title, artist, album, year, comment, track and genre
  from ID3v1 to ID3v2 or the other way round. For the existing target tag the caller
  chooses: leave it alone, fill only its empty fields, or overwrite the fields. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, AudioTypes;

type
  TSyncDirection = (sdV1ToV2, sdV2ToV1);
  TSyncExisting = (seSkip, seBlankOnly, seOverwrite);

{ Returns True when the file was changed. Raises on write errors. }
function SyncID3(const FileName: string; Direction: TSyncDirection; Existing: TSyncExisting;
  KeepTimestamp: Boolean): Boolean;

implementation

uses
  TagUtils, Mp3Reader, ID3Writer, AudioTags, TagWriter;

const
  V1Fields: array[0..6] of TTagField = (tfTitle, tfArtist, tfAlbum, tfYear, tfComment,
    tfTrack, tfGenre);

procedure ReadSeparately(const FileName: string; V1, V2: TAudioInfo; out HasV1: Boolean);
var
  S: TFileStream;
  Size: Int64;
begin
  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    S.Position := 0;
    ReadID3v2(S, V2, Size);
    HasV1 := ReadID3v1(S, V1);
  finally
    S.Free;
  end;
end;

function LastBytes(const FileName: string; Count: Integer): TBytes;
var
  S: TFileStream;
begin
  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    S.Position := S.Size - Count;
    Result := ReadStreamBytes(S, Count);
  finally
    S.Free;
  end;
end;

procedure PutLastBytes(const FileName: string; const B: TBytes);
var
  S: TFileStream;
begin
  S := TFileStream.Create(FileName, fmOpenReadWrite or fmShareExclusive);
  try
    S.Position := S.Size - Length(B);
    S.WriteBuffer(B[0], Length(B));
  finally
    S.Free;
  end;
end;

function SyncID3(const FileName: string; Direction: TSyncDirection; Existing: TSyncExisting;
  KeepTimestamp: Boolean): Boolean;
var
  V1, V2, Full: TAudioInfo;
  HasV1, HasV2: Boolean;
  F: TTagField;
  Stamp: TFileStamp;
  OldV1: TBytes;
begin
  Result := False;
  V1 := TAudioInfo.Create;
  V2 := TAudioInfo.Create;
  try
    ReadSeparately(FileName, V1, V2, HasV1);
    HasV2 := V2.TagTypes <> '';
    if Direction = sdV1ToV2 then
    begin
      if not HasV1 or (HasV2 and (Existing = seSkip)) then Exit;
      Full := ReadAudioInfo(FileName, True);
      try
        if Full.Error <> '' then raise Exception.Create(Full.Error);
        for F in V1Fields do
        begin
          if V1.Fields[F] = '' then Continue;
          if (Existing = seBlankOnly) and (V2.Fields[F] <> '') then Continue;
          // the reader shows ID3v1 values in empty ID3v2 fields: compare with ID3v2 itself
          if V2.Fields[F] <> V1.Fields[F] then Result := True;
          Full.Fields[F] := V1.Fields[F];
        end;
        if not HasV2 then Result := True;
        if Result then
        begin
          // the MP3 writer also updates ID3v1 from the same values; this direction must
          // leave ID3v1 as it was
          OldV1 := LastBytes(FileName, 128);
          if KeepTimestamp then Stamp := GetFileStamp(FileName);
          WriteAudioTags(Full, False);
          PutLastBytes(FileName, OldV1);
          if KeepTimestamp then SetFileStamp(FileName, Stamp);
        end;
      finally
        Full.Free;
      end;
    end
    else
    begin
      if not HasV2 or (HasV1 and (Existing = seSkip)) then Exit;
      for F in V1Fields do
      begin
        if V2.Fields[F] = '' then Continue;
        if HasV1 and (Existing = seBlankOnly) and (V1.Fields[F] <> '') then Continue;
        if V1.Fields[F] <> V2.Fields[F] then Result := True;
        V1.Fields[F] := V2.Fields[F];
      end;
      if not HasV1 then Result := True;
      if Result then
      begin
        if KeepTimestamp then Stamp := GetFileStamp(FileName);
        WriteID3v1(FileName, V1, True);
        if KeepTimestamp then SetFileStamp(FileName, Stamp);
      end;
    end;
  finally
    V1.Free;
    V2.Free;
  end;
end;

end.
