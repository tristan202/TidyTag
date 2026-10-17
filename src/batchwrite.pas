unit BatchWrite;

{ Saving a few fields (and optionally a new front cover) in one file, re-reading it
  with pictures first so nothing else in the file changes. Shared by the inline tabs,
  paste tag, cover drag-and-drop and the web lookup. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, AudioTypes;

type
  TTagFieldSet = set of TTagField;
  TFieldValues = array[TTagField] of string;

{ Writes Values[F] for every F in Fields (and Cover as front cover when not nil) into
  Info's file, then updates Info itself. Returns False with Err set on failure;
  Skipped = True when the file type cannot be written yet. }
function UpdateFileTags(Info: TAudioInfo; const Values: TFieldValues; Fields: TTagFieldSet;
  const Cover: TBytes; KeepTimestamp: Boolean; out Err: string; out Skipped: Boolean): Boolean;
{ Puts Data first as front cover; other pictures (back, booklet, ...) are kept. }
procedure SetFrontCover(Info: TAudioInfo; const Data: TBytes);
function FieldValuesOf(Info: TAudioInfo): TFieldValues;

implementation

uses
  AudioTags, TagWriter;

procedure SetFrontCover(Info: TAudioInfo; const Data: TBytes);
var
  Keep: TTagPictures;
  I, N: Integer;
begin
  Keep := nil;
  SetLength(Keep, Length(Info.Pictures) + 1);
  Keep[0].PicType := PicTypeFrontCover;
  Keep[0].MimeType := DetectImageMime(Data);
  Keep[0].Description := '';
  Keep[0].Data := Data;
  N := 1;
  for I := 0 to High(Info.Pictures) do
    if Info.Pictures[I].PicType <> PicTypeFrontCover then
    begin
      Keep[N] := Info.Pictures[I];
      Inc(N);
    end;
  SetLength(Keep, N);
  Info.Pictures := Keep;
end;

function FieldValuesOf(Info: TAudioInfo): TFieldValues;
var
  F: TTagField;
begin
  for F := Low(TTagField) to High(TTagField) do Result[F] := Info.Fields[F];
end;

function UpdateFileTags(Info: TAudioInfo; const Values: TFieldValues; Fields: TTagFieldSet;
  const Cover: TBytes; KeepTimestamp: Boolean; out Err: string; out Skipped: Boolean): Boolean;
var
  Full: TAudioInfo;
  F: TTagField;
begin
  Result := False;
  Err := '';
  Skipped := not CanWriteTags(Info.FileName);
  if Skipped then
  begin
    Err := 'filtypen kan ikke gemmes endnu';
    Exit;
  end;
  Full := ReadAudioInfo(Info.FileName, True);
  try
    if Full.Error <> '' then
    begin
      Err := Full.Error;
      Exit;
    end;
    for F in Fields do Full.Fields[F] := Values[F];
    if Cover <> nil then SetFrontCover(Full, Cover);
    try
      WriteAudioTags(Full, KeepTimestamp);
    except
      on E: Exception do
      begin
        Err := E.Message;
        Exit;
      end;
    end;
    for F in Fields do Info.Fields[F] := Values[F];
    Info.HasCover := Length(Full.Pictures) > 0;
    Result := True;
  finally
    Full.Free;
  end;
end;

end.
