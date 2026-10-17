unit FieldTools;

{ Batch tag tools that work on field values: swap two fields, copy one field into
  another, clean up spaces. Each function only plans the change for one file; the
  caller writes it with BatchWrite.UpdateFileTags. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, AudioTypes, BatchWrite;

type
  TFieldPlan = record
    Values: TFieldValues;
    Fields: TTagFieldSet; // empty = nothing to do for this file
  end;

function PlanSwap(Info: TAudioInfo; A, B: TTagField): TFieldPlan;
{ OnlyIfEmpty: leave Dst alone when it already has a value. }
function PlanCopy(Info: TAudioInfo; Src, Dst: TTagField; OnlyIfEmpty: Boolean): TFieldPlan;
{ Every non-empty field is written again without leading/trailing spaces and, except in
  lyrics and comments, with runs of spaces reduced to one. Values are shown trimmed
  already, so the file itself is what changes. }
function PlanCleanSpaces(Info: TAudioInfo): TFieldPlan;
function CleanSpaces(const S: string; Collapse: Boolean): string;

implementation

procedure ClearPlan(out P: TFieldPlan);
var
  F: TTagField;
begin
  for F := Low(TTagField) to High(TTagField) do P.Values[F] := '';
  P.Fields := [];
end;

function PlanSwap(Info: TAudioInfo; A, B: TTagField): TFieldPlan;
begin
  ClearPlan(Result);
  if (A = B) or (Info.Fields[A] = Info.Fields[B]) then Exit;
  Result.Values[A] := Info.Fields[B];
  Result.Values[B] := Info.Fields[A];
  Result.Fields := [A, B];
end;

function PlanCopy(Info: TAudioInfo; Src, Dst: TTagField; OnlyIfEmpty: Boolean): TFieldPlan;
begin
  ClearPlan(Result);
  if (Src = Dst) or (Info.Fields[Src] = Info.Fields[Dst]) then Exit;
  if OnlyIfEmpty and (Info.Fields[Dst] <> '') then Exit;
  if Info.Fields[Src] = '' then Exit; // copying nothing would clear the target
  Result.Values[Dst] := Info.Fields[Src];
  Result.Fields := [Dst];
end;

function CleanSpaces(const S: string; Collapse: Boolean): string;
begin
  Result := Trim(S);
  if Collapse then
  begin
    Result := StringReplace(Result, #9, ' ', [rfReplaceAll]);
    while Pos('  ', Result) > 0 do
      Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
  end;
end;

function PlanCleanSpaces(Info: TAudioInfo): TFieldPlan;
var
  F: TTagField;
begin
  ClearPlan(Result);
  for F := Low(TTagField) to High(TTagField) do
    if Info.Fields[F] <> '' then
    begin
      Result.Values[F] := CleanSpaces(Info.Fields[F], not (F in [tfLyrics, tfComment]));
      Include(Result.Fields, F);
    end;
end;

end.
