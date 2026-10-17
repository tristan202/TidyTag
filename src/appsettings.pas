unit AppSettings;

{ Location of the settings file plus small helpers for remembered masks. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IniFiles, StdCtrls, RenameCore;

type
  { Settings > Rename word lists, used by every rename. }
  TRenameWords = record
    ReplaceFrom, ReplaceTo, KeepCase: TStringArray;
  end;

  { Tools > Rename actions: named presets of a file mask and/or a folder mask. }
  TRenameAction = record
    Name, FileMask, FolderMask: string;
  end;
  TRenameActions = array of TRenameAction;

function SettingsFileName: string;
function OpenSettings: TIniFile;
{ Fills Items with remembered masks (most recent first), or Defaults the first time. }
procedure LoadMaskHistory(const Section: string; Items: TStrings; const Defaults: array of string);
{ Moves Mask to the top of the history and saves at most MaxMasks entries. }
procedure AddMaskToHistory(const Section, Mask: string; Items: TStrings);
{ Same for a combo box, keeping its text: deleting the shown item would clear it. }
procedure AddComboMaskToHistory(const Section: string; Combo: TComboBox);

function LoadRenameWords: TRenameWords;
procedure SaveRenameWords(const W: TRenameWords);
{ Copies the word lists into rename options. }
procedure ApplyRenameWords(var Opt: TRenameOptions);
function LoadRenameActions: TRenameActions;
procedure SaveRenameActions(const A: TRenameActions);

const
  MaxMasks = 15;

implementation

function SettingsFileName: string;
begin
  Result := GetAppConfigDir(False) + 'tagklon.ini';
end;

function OpenSettings: TIniFile;
begin
  ForceDirectories(GetAppConfigDir(False));
  Result := TIniFile.Create(SettingsFileName);
end;

procedure LoadMaskHistory(const Section: string; Items: TStrings; const Defaults: array of string);
var
  Ini: TIniFile;
  I: Integer;
  S: string;
begin
  Items.Clear;
  Ini := OpenSettings;
  try
    for I := 0 to MaxMasks - 1 do
    begin
      S := Ini.ReadString(Section, 'Mask' + IntToStr(I), '');
      if S <> '' then Items.Add(S);
    end;
  finally
    Ini.Free;
  end;
  if Items.Count = 0 then
    for S in Defaults do Items.Add(S);
end;

procedure AddMaskToHistory(const Section, Mask: string; Items: TStrings);
var
  Ini: TIniFile;
  I: Integer;
begin
  if Trim(Mask) = '' then Exit;
  I := Items.IndexOf(Mask);
  if I >= 0 then Items.Delete(I);
  Items.Insert(0, Mask);
  while Items.Count > MaxMasks do Items.Delete(Items.Count - 1);
  Ini := OpenSettings;
  try
    Ini.EraseSection(Section);
    for I := 0 to Items.Count - 1 do
      Ini.WriteString(Section, 'Mask' + IntToStr(I), Items[I]);
  finally
    Ini.Free;
  end;
end;

procedure AddComboMaskToHistory(const Section: string; Combo: TComboBox);
var
  Mask: string;
begin
  Mask := Combo.Text;
  AddMaskToHistory(Section, Mask, Combo.Items);
  Combo.Text := Mask;
end;

{ Values are written in quotes so that leading/trailing spaces (' & ') survive the ini file. }
function Quote(const S: string): string;
begin
  Result := '"' + S + '"';
end;

function Unquote(const S: string): string;
begin
  if (Length(S) >= 2) and (S[1] = '"') and (S[Length(S)] = '"') then
    Result := Copy(S, 2, Length(S) - 2)
  else
    Result := S;
end;

function LoadRenameWords: TRenameWords;
var
  Ini: TIniFile;
  I, N: Integer;
begin
  Result.ReplaceFrom := nil;
  Result.ReplaceTo := nil;
  Result.KeepCase := nil;
  Ini := OpenSettings;
  try
    N := Ini.ReadInteger('RenameReplace', 'Count', 0);
    SetLength(Result.ReplaceFrom, N);
    SetLength(Result.ReplaceTo, N);
    for I := 0 to N - 1 do
    begin
      Result.ReplaceFrom[I] := Unquote(Ini.ReadString('RenameReplace', 'From' + IntToStr(I + 1), ''));
      Result.ReplaceTo[I] := Unquote(Ini.ReadString('RenameReplace', 'To' + IntToStr(I + 1), ''));
    end;
    N := Ini.ReadInteger('RenameKeepCase', 'Count', 0);
    SetLength(Result.KeepCase, N);
    for I := 0 to N - 1 do
      Result.KeepCase[I] := Unquote(Ini.ReadString('RenameKeepCase', 'Word' + IntToStr(I + 1), ''));
  finally
    Ini.Free;
  end;
end;

procedure SaveRenameWords(const W: TRenameWords);
var
  Ini: TIniFile;
  I: Integer;
begin
  Ini := OpenSettings;
  try
    Ini.EraseSection('RenameReplace');
    Ini.WriteInteger('RenameReplace', 'Count', Length(W.ReplaceFrom));
    for I := 0 to High(W.ReplaceFrom) do
    begin
      Ini.WriteString('RenameReplace', 'From' + IntToStr(I + 1), Quote(W.ReplaceFrom[I]));
      Ini.WriteString('RenameReplace', 'To' + IntToStr(I + 1), Quote(W.ReplaceTo[I]));
    end;
    Ini.EraseSection('RenameKeepCase');
    Ini.WriteInteger('RenameKeepCase', 'Count', Length(W.KeepCase));
    for I := 0 to High(W.KeepCase) do
      Ini.WriteString('RenameKeepCase', 'Word' + IntToStr(I + 1), Quote(W.KeepCase[I]));
  finally
    Ini.Free;
  end;
end;

procedure ApplyRenameWords(var Opt: TRenameOptions);
var
  W: TRenameWords;
begin
  W := LoadRenameWords;
  Opt.ReplaceFrom := W.ReplaceFrom;
  Opt.ReplaceTo := W.ReplaceTo;
  Opt.KeepCaseWords := W.KeepCase;
end;

function LoadRenameActions: TRenameActions;
var
  Ini: TIniFile;
  I, N: Integer;
  K: string;
begin
  Ini := OpenSettings;
  try
    N := Ini.ReadInteger('RenameActions', 'Count', 0);
    SetLength(Result, N);
    for I := 0 to N - 1 do
    begin
      K := IntToStr(I + 1);
      Result[I].Name := Unquote(Ini.ReadString('RenameActions', 'Name' + K, ''));
      Result[I].FileMask := Unquote(Ini.ReadString('RenameActions', 'FileMask' + K, ''));
      Result[I].FolderMask := Unquote(Ini.ReadString('RenameActions', 'FolderMask' + K, ''));
    end;
  finally
    Ini.Free;
  end;
end;

procedure SaveRenameActions(const A: TRenameActions);
var
  Ini: TIniFile;
  I: Integer;
  K: string;
begin
  Ini := OpenSettings;
  try
    Ini.EraseSection('RenameActions');
    Ini.WriteInteger('RenameActions', 'Count', Length(A));
    for I := 0 to High(A) do
    begin
      K := IntToStr(I + 1);
      Ini.WriteString('RenameActions', 'Name' + K, Quote(A[I].Name));
      Ini.WriteString('RenameActions', 'FileMask' + K, Quote(A[I].FileMask));
      Ini.WriteString('RenameActions', 'FolderMask' + K, Quote(A[I].FolderMask));
    end;
  finally
    Ini.Free;
  end;
end;

end.
