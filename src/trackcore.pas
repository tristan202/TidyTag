unit TrackCore;

{ Track number tools: reformat existing numbers ('7/12' -> '07') and number files
  in list order. Pure functions; the dialog writes the result. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, AudioTypes;

type
  TTrackFormat = (nfPlain, nfTwoDigits, nfThreeDigits, nfPlainTotal, nfTwoDigitsTotal);
  TTrackMode = (tmFormat, tmNumber);

const
  TrackFormatNames: array[TTrackFormat] of string = ('7', '07', '007', '7/12', '07/12');

{ Leading number and optional '/total'. False if S does not start with a number. }
function ParseTrack(const S: string; out Num, Total: Integer): Boolean;
{ Total <= 0 means unknown; formats with a total then show the number only. }
function FormatTrack(Num, Total: Integer; Fmt: TTrackFormat): string;
{ New track value for every item, in the same order. In tmFormat mode items without a
  number keep their value. Totals for the '/12' formats come from the existing value,
  else the number of items in the same folder (tmNumber: files numbered in that run). }
function PlanTrackNumbers(const Items: array of TAudioInfo; Mode: TTrackMode;
  Fmt: TTrackFormat; StartAt: Integer; PerFolder: Boolean): TStringArray;

implementation

function ParseTrack(const S: string; out Num, Total: Integer): Boolean;
var
  T: string;
  I, Slash: Integer;
begin
  Num := 0;
  Total := 0;
  T := Trim(S);
  I := 1;
  while (I <= Length(T)) and (T[I] in ['0'..'9']) do Inc(I);
  if I = 1 then Exit(False);
  Num := StrToIntDef(Copy(T, 1, I - 1), 0);
  Slash := Pos('/', T);
  if Slash > 0 then
    Total := StrToIntDef(Trim(Copy(T, Slash + 1, MaxInt)), 0);
  Result := True;
end;

function FormatTrack(Num, Total: Integer; Fmt: TTrackFormat): string;
begin
  case Fmt of
    nfPlain, nfPlainTotal: Result := IntToStr(Num);
    nfThreeDigits: Result := Format('%.3d', [Num]);
  else
    Result := Format('%.2d', [Num]);
  end;
  if (Fmt in [nfPlainTotal, nfTwoDigitsTotal]) and (Total > 0) then
  begin
    if Fmt = nfTwoDigitsTotal then
      Result := Result + '/' + Format('%.2d', [Total])
    else
      Result := Result + '/' + IntToStr(Total);
  end;
end;

{ Small counter per key; folder paths may contain any character, so no Name=Value lists. }
function Bump(L: TStringList; const Key: string; Start: Integer): Integer;
var
  Idx: Integer;
begin
  Idx := L.IndexOf(Key);
  if Idx < 0 then
  begin
    L.AddObject(Key, TObject(PtrInt(Start)));
    Result := Start;
  end
  else
  begin
    Result := PtrInt(L.Objects[Idx]) + 1;
    L.Objects[Idx] := TObject(PtrInt(Result));
  end;
end;

function CountOf(L: TStringList; const Key: string): Integer;
begin
  Result := PtrInt(L.Objects[L.IndexOf(Key)]);
end;

function PlanTrackNumbers(const Items: array of TAudioInfo; Mode: TTrackMode;
  Fmt: TTrackFormat; StartAt: Integer; PerFolder: Boolean): TStringArray;
var
  Counts, Counters: TStringList;
  I, Num, Total: Integer;
  Key: string;

  function FolderKey(Info: TAudioInfo): string;
  begin
    if PerFolder or (Mode = tmFormat) then
      Result := LowerCase(ExtractFileDir(Info.FileName))
    else
      Result := '*';
  end;

begin
  Result := nil;
  SetLength(Result, Length(Items));
  Counts := TStringList.Create;
  Counters := TStringList.Create;
  try
    // How many items share each folder (the total for '/12' formats).
    for I := 0 to High(Items) do
      Bump(Counts, FolderKey(Items[I]), 1);

    for I := 0 to High(Items) do
    begin
      Key := FolderKey(Items[I]);
      if Mode = tmFormat then
      begin
        if not ParseTrack(Items[I].Fields[tfTrack], Num, Total) then
        begin
          Result[I] := Items[I].Fields[tfTrack];
          Continue;
        end;
        if Total <= 0 then Total := CountOf(Counts, Key);
      end
      else
      begin
        Num := Bump(Counters, Key, StartAt);
        Total := StartAt - 1 + CountOf(Counts, Key);
      end;
      Result[I] := FormatTrack(Num, Total, Fmt);
    end;
  finally
    Counts.Free;
    Counters.Free;
  end;
end;

end.
