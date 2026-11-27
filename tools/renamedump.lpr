program RenameDump;

{ What TidyTag 1.2's rename engine makes of one file, for TidyTag 2's rename cross-check
  (src-tauri/core/tests/golden_rename.rs):
    renamedump <file>
  One JSON line per case:
    file masks x 5 case modes x underscores off/on x words off/on, two folder masks the
    same way, and the default tags-from-filename masks.
  The file's folder is written as '<dir>' and its parent as '<parent>', so the lines do not
  depend on where the corpus lies. The lists below must match golden_rename.rs. }

{$mode objfpc}{$H+}

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  Classes, SysUtils, fpjson, AudioTypes, AudioTags, RenameCore, FileNameTags;

const
  FileMasks: array[0..9] of string = ('%1 - %2', '%6 - %2', '%6 - %1 - %2', '%1 - %3 - %6 - %2',
    '%1\%3\%6 - %2', '%aa\%4 - %3\%6 - %2', '%7 (%0 kbit, %t)', '%cat %key %khz %ext %grp',
    '%# %b %9 %5', '%rt %enc %dbit %cp %co %lb %rb %md');
  FolderMasks: array[0..1] of string = ('%1 - %4 - %3', '%aa\%3');
  F2TMasks: array[0..6] of string = ('%1 - %2', '%6 - %2', '%6 - %1 - %2', '%6. %2', '%6 %1 - %2',
    '%1\%3\%6 - %2', '%1\%4 - %3\%6 - %2');

var
  Info: TAudioInfo;
  Dir, Parent: string;

function Placeholders(const S: string): string;
begin
  Result := S;
  if (Dir <> '') and SameFileName(Copy(Result, 1, Length(Dir)), Dir) then
    Result := '<dir>\' + Copy(Result, Length(Dir) + 1, MaxInt)
  else if (Parent <> '') and SameFileName(Copy(Result, 1, Length(Parent)), Parent) then
    Result := '<parent>\' + Copy(Result, Length(Parent) + 1, MaxInt);
end;

function Options(CaseMode: Integer; Us, Words: Boolean): TRenameOptions;
begin
  Result.CaseMode := TCaseMode(CaseMode);
  Result.SpacesToUnderscores := Us;
  Result.PadTrack := True;
  if Words then
  begin
    Result.KeepCaseWords := ['AC/DC', 'ABBA'];
    Result.ReplaceFrom := [' & '];
    Result.ReplaceTo := [' and '];
  end
  else
  begin
    Result.KeepCaseWords := nil;
    Result.ReplaceFrom := nil;
    Result.ReplaceTo := nil;
  end;
end;

procedure Emit(const Kind, Mask: string; CaseMode: Integer; Us, Words: Boolean;
  const Res, Status, Missing: string);
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  try
    O.Add('kind', Kind);
    O.Add('mask', Mask);
    O.Add('case', CaseMode);
    O.Add('us', Us);
    O.Add('words', Words);
    O.Add('result', Placeholders(Res));
    O.Add('status', Status);
    O.Add('missing', Missing);
    WriteLn(O.AsJSON);
  finally
    O.Free;
  end;
end;

var
  M, Missing, Res, Vals, S: string;
  Subjects: TStringList;
  C, U, W: Integer;
  Plan: TRenamePlan;
  Match: TFileNameMatch;
  F: TTagField;
begin
  SetMultiByteConversionCodePage(CP_UTF8);
  SetMultiByteFileSystemCodePage(CP_UTF8);
  {$IFDEF WINDOWS}SetConsoleOutputCP(CP_UTF8);{$ENDIF}
  SetTextCodePage(Output, CP_UTF8);
  if ParamCount <> 1 then
  begin
    WriteLn('Brug: renamedump <fil>');
    Halt(2);
  end;
  Info := ReadAudioInfo(UTF8Encode(UnicodeString(ParamStr(1))), False);
  try
    Dir := IncludeTrailingPathDelimiter(ExtractFileDir(Info.FileName));
    Parent := IncludeTrailingPathDelimiter(ExtractFileDir(ExcludeTrailingPathDelimiter(Dir)));
    for C := 0 to 4 do
      for U := 0 to 1 do
        for W := 0 to 1 do
        begin
          for M in FileMasks do
          begin
            Res := ExpandRenameMask(M, Info, 1, 2, Options(C, U = 1, W = 1), Missing);
            Emit('file', M, C, U = 1, W = 1, Res, '', Missing);
          end;
          for M in FolderMasks do
          begin
            Plan := PlanFolderRename([Info], M, Options(C, U = 1, W = 1));
            Emit('folder', M, C, U = 1, W = 1, Plan[0].NewName, RenameStatusText[Plan[0].Status], Plan[0].Detail);
          end;
        end;
    // tags from file name: every F2T mask against the file's own name and against the names
    // the file masks give it (real tag text), with case mode 0 and 1
    Subjects := TStringList.Create;
    try
      Subjects.Add(Info.FileName);
      for M in FileMasks do
      begin
        Res := ExpandRenameMask(M, Info, 1, 2, Options(0, False, False), Missing);
        if Res <> '' then Subjects.Add(UTF8Encode(UnicodeString(Res))); // ExpandFileName gives a 1252 string
      end;
      for S in Subjects do
        for M in F2TMasks do
          for C := 0 to 1 do
          begin
            Match := MatchFileName(M, S, C = 0, TCaseMode(C));
            Vals := '';
            if Match.Ok then
              for F := Low(TTagField) to High(TTagField) do
                if F in Match.Used then Vals := Vals + IntToStr(Ord(F)) + '=' + Match.Values[F] + ';';
            Emit('f2t', M + ' @ ' + Placeholders(S), C, C = 0, False, Vals, BoolToStr(Match.Ok, 'ok', 'no'), '');
          end;
    finally
      Subjects.Free;
    end;
  finally
    Info.Free;
  end;
end.
