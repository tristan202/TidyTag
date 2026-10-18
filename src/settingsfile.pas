unit SettingsFile;

{ Location of the settings file (no LCL, so the console tools can use it too). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IniFiles;

function SettingsFileName: string;
{ Opens (and creates the folder of) the settings file; the caller frees it. }
function OpenSettings: TIniFile;

implementation

{ %LOCALAPPDATA%\TidyTag\, whatever the exe is called. }
function SettingsDir: string;
begin
  Result := ExtractFilePath(ExcludeTrailingPathDelimiter(GetAppConfigDir(False))) + 'TidyTag' +
    PathDelim;
end;

function SettingsFileName: string;
begin
  Result := SettingsDir + 'tidytag.ini';
end;

{ The program used to be called TagKlon: its settings are copied over the first time
  (the old file stays where it was). }
procedure MigrateOldSettings;
var
  OldFile: string;
  Src, Dst: TFileStream;
begin
  if FileExists(SettingsFileName) then Exit;
  OldFile := ExtractFilePath(ExcludeTrailingPathDelimiter(SettingsDir)) + 'TagKlon' + PathDelim +
    'tagklon.ini';
  if not FileExists(OldFile) then Exit;
  try
    Src := TFileStream.Create(OldFile, fmOpenRead or fmShareDenyNone);
    try
      Dst := TFileStream.Create(SettingsFileName, fmCreate);
      try
        Dst.CopyFrom(Src, 0);
      finally
        Dst.Free;
      end;
    finally
      Src.Free;
    end;
  except
    // a failed copy just means starting with default settings
  end;
end;

function OpenSettings: TIniFile;
begin
  ForceDirectories(SettingsDir);
  MigrateOldSettings;
  Result := TIniFile.Create(SettingsFileName);
end;

end.
