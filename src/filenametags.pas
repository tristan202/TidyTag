unit FileNameTags;

{ Reads tag values out of a file name with a mask such as '%6 - %1 - %2'.
  '\' in the mask also matches folder names: '%1\%3\%6 - %2' uses the last two folders.
  %d skips a part. Matching tries shortest values first, except numeric fields
  (track, disc, year, BPM), which take as many digits as they can. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, AudioTypes, RenameCore;

type
  TFileNameMatch = record
    Ok: Boolean;
    Values: array[TTagField] of string;
    Used: TFieldSet;
  end;

const
  FileToTagVariablesHelp =
    '%1 Kunstner   %2 Titel   %3 Album   %4 År   %5 Genre   %6 Spor   %# Disc' + LineEnding +
    '%9 Kommentar   %b BPM   %aa Albumkunstner   %cp Komponist   %d Spring over' + LineEnding +
    'Filtypen fjernes automatisk. Brug \ for mappenavne, fx  %1\%3\%6 - %2';

{ Which fields a mask fills (for preview columns). }
function MaskFields(const Mask: string): TFieldSet;
function MatchFileName(const Mask, FilePath: string; UnderscoresToSpaces: Boolean;
  CaseMode: TCaseMode): TFileNameMatch;

implementation

type
  TTokenKind = (tkLiteral, tkField, tkSkip);
  TToken = record
    Kind: TTokenKind;
    Field: TTagField;
    Text: UnicodeString; // literal text, lower case
  end;
  TTokens = array of TToken;

function Tokenize(const Mask: string): TTokens;
var
  U: UnicodeString;
  I, N: Integer;
  Code: UnicodeString;
  Lit: UnicodeString;
  Kind: TTokenKind;
  F: TTagField;

  procedure FlushLiteral;
  begin
    if Lit = '' then Exit;
    N := Length(Result);
    SetLength(Result, N + 1);
    Result[N].Kind := tkLiteral;
    Result[N].Text := WideLowerCase(Lit);
    Lit := '';
  end;

begin
  Result := nil;
  U := UTF8Decode(StringReplace(Mask, '/', '\', [rfReplaceAll]));
  Lit := '';
  I := 1;
  while I <= Length(U) do
  begin
    if (U[I] <> '%') or (I = Length(U)) then
    begin
      Lit := Lit + U[I];
      Inc(I);
      Continue;
    end;
    Code := WideLowerCase(Copy(U, I + 1, 2));
    Kind := tkField;
    if (Code = 'aa') or (Code = 'cp') then
    begin
      if Code = 'aa' then F := tfAlbumArtist else F := tfComposer;
      Inc(I, 3);
    end
    else
    begin
      Code := Copy(U, I + 1, 1);
      Inc(I, 2);
      if Code = '1' then F := tfArtist
      else if Code = '2' then F := tfTitle
      else if Code = '3' then F := tfAlbum
      else if Code = '4' then F := tfYear
      else if Code = '5' then F := tfGenre
      else if Code = '6' then F := tfTrack
      else if Code = '#' then F := tfDisc
      else if Code = '9' then F := tfComment
      else if (Code = 'b') or (Code = 'B') then F := tfBpm
      else if (Code = 'd') or (Code = 'D') then Kind := tkSkip
      else
      begin
        Lit := Lit + '%' + Code; // unknown: literal
        Continue;
      end;
    end;
    FlushLiteral;
    N := Length(Result);
    SetLength(Result, N + 1);
    Result[N].Kind := Kind;
    Result[N].Field := F;
  end;
  FlushLiteral;
end;

function MaskFields(const Mask: string): TFieldSet;
var
  T: TToken;
begin
  Result := [];
  for T in Tokenize(Mask) do
    if T.Kind = tkField then Include(Result, T.Field);
end;

function IsNumericField(F: TTagField): Boolean;
begin
  Result := F in [tfTrack, tfDisc, tfYear, tfBpm];
end;

function ValidNumeric(const V: UnicodeString; F: TTagField): Boolean;
var
  C: WideChar;
begin
  Result := V <> '';
  for C in V do
    if not (((C >= '0') and (C <= '9')) or (C = '/') or ((F = tfYear) and (C = '-'))) then
      Exit(False);
end;

{ Backtracking matcher over Subject (lower-cased copy used for literal comparison). }
function MatchFrom(const Tokens: TTokens; TI: Integer; const Subject, Lower: UnicodeString;
  SI: Integer; var Values: array of UnicodeString): Boolean;
var
  T: TToken;
  Len, MaxLen, Step, StartLen: Integer;
  V: UnicodeString;
begin
  if TI > High(Tokens) then Exit(SI > Length(Subject));
  T := Tokens[TI];
  if T.Kind = tkLiteral then
  begin
    if Copy(Lower, SI, Length(T.Text)) <> T.Text then Exit(False);
    Exit(MatchFrom(Tokens, TI + 1, Subject, Lower, SI + Length(T.Text), Values));
  end;

  MaxLen := Length(Subject) - SI + 1;
  if TI = High(Tokens) then
  begin
    // Last token takes the rest.
    V := Copy(Subject, SI, MaxLen);
    if (T.Kind = tkField) and ((Trim(V) = '') or IsNumericField(T.Field) and not ValidNumeric(Trim(V), T.Field)) then
      Exit(False);
    if T.Kind = tkField then Values[TI] := V;
    Exit(True);
  end;

  if (T.Kind = tkField) and IsNumericField(T.Field) then
  begin
    StartLen := MaxLen; Step := -1; // greedy
  end
  else
  begin
    StartLen := 1; Step := 1;       // lazy
    if T.Kind = tkSkip then StartLen := 0;
  end;
  Len := StartLen;
  while (Len >= 0) and (Len <= MaxLen) do
  begin
    V := Copy(Subject, SI, Len);
    if (T.Kind = tkSkip) or ((Trim(V) <> '') and
      (not IsNumericField(T.Field) or ValidNumeric(Trim(V), T.Field))) then
    begin
      if MatchFrom(Tokens, TI + 1, Subject, Lower, SI + Len, Values) then
      begin
        if T.Kind = tkField then Values[TI] := V;
        Exit(True);
      end;
    end;
    Inc(Len, Step);
  end;
  Result := False;
end;

function MatchFileName(const Mask, FilePath: string; UnderscoresToSpaces: Boolean;
  CaseMode: TCaseMode): TFileNameMatch;
var
  Tokens: TTokens;
  Levels, I, K: Integer;
  Subject, Part: UnicodeString;
  Path, Dir: string;
  Values: array of UnicodeString;
  F: TTagField;
  V: string;
begin
  Result.Ok := False;
  Result.Used := [];
  for F := Low(TTagField) to High(TTagField) do Result.Values[F] := '';
  Tokens := Tokenize(Mask);
  if Length(Tokens) = 0 then Exit;

  // Subject = as many trailing path parts as the mask has '\'-separated levels.
  Levels := 1;
  for I := 0 to High(Tokens) do
    if Tokens[I].Kind = tkLiteral then
      for K := 1 to Length(Tokens[I].Text) do
        if Tokens[I].Text[K] = '\' then Inc(Levels);
  Subject := UTF8Decode(ChangeFileExt(ExtractFileName(FilePath), ''));
  Dir := ExtractFileDir(FilePath);
  for I := 2 to Levels do
  begin
    Path := ExtractFileName(Dir);
    if Path = '' then Exit; // not enough folders
    Part := UTF8Decode(Path);
    Subject := Part + '\' + Subject;
    Dir := ExtractFileDir(Dir);
  end;

  Values := nil;
  SetLength(Values, Length(Tokens));
  if not MatchFrom(Tokens, 0, Subject, WideLowerCase(Subject), 1, Values) then Exit;

  for I := 0 to High(Tokens) do
    if Tokens[I].Kind = tkField then
    begin
      V := UTF8Encode(Values[I]);
      if UnderscoresToSpaces then V := StringReplace(V, '_', ' ', [rfReplaceAll]);
      V := Trim(StringReplace(V, '  ', ' ', [rfReplaceAll]));
      if not IsNumericField(Tokens[I].Field) then V := ApplyCase(V, CaseMode);
      Result.Values[Tokens[I].Field] := V;
      Include(Result.Used, Tokens[I].Field);
    end;
  Result.Ok := Result.Used <> [];
end;

end.
