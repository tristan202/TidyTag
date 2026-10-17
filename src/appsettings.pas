unit AppSettings;

{ Location of the settings file plus small helpers for remembered masks. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IniFiles;

function SettingsFileName: string;
function OpenSettings: TIniFile;
{ Fills Items with remembered masks (most recent first), or Defaults the first time. }
procedure LoadMaskHistory(const Section: string; Items: TStrings; const Defaults: array of string);
{ Moves Mask to the top of the history and saves at most MaxMasks entries. }
procedure AddMaskToHistory(const Section, Mask: string; Items: TStrings);

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

end.
