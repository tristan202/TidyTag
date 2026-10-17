unit Language;

{ User interface language: setting, detection and loading of the .po translations.
  The sources are written in Danish; languages\TidyTag.<code>.po holds the other
  languages (TidyTag.da.po is empty, so switching back to Danish works too) and
  languages\lclstrconsts.<code>.po the texts of the LCL itself (dialog buttons etc.).
  The language is applied once at program start, before the forms are created. }

{$mode objfpc}{$H+}

interface

const
  LanguageCodes: array[0..6] of string = ('da', 'en', 'de', 'fr', 'it', 'sv', 'es');
  { Shown in the language's own words, so everyone can find their language. }
  LanguageNames: array[0..6] of string = ('Dansk', 'English', 'Deutsch', 'Français',
    'Italiano', 'Svenska', 'Español');

{ '' = automatic (the Windows language when it is supported, else English). }
function LanguageSetting: string;
procedure SetLanguageSetting(const Code: string);
function EffectiveLanguage: string;
{ Folder with the .po files: next to the program, or ..\languages while developing. }
function LanguageDir: string;
procedure ApplyLanguage;

implementation

uses
  SysUtils, IniFiles, Translations, LCLTranslator, AppSettings;

function Supported(const Code: string): Boolean;
var
  C: string;
begin
  for C in LanguageCodes do
    if C = Code then Exit(True);
  Result := False;
end;

function LanguageSetting: string;
var
  Ini: TIniFile;
begin
  Ini := OpenSettings;
  try
    Result := LowerCase(Ini.ReadString('Main', 'Language', ''));
  finally
    Ini.Free;
  end;
  if not Supported(Result) then Result := '';
end;

procedure SetLanguageSetting(const Code: string);
var
  Ini: TIniFile;
begin
  Ini := OpenSettings;
  try
    Ini.WriteString('Main', 'Language', Code);
  finally
    Ini.Free;
  end;
end;

function EffectiveLanguage: string;
begin
  Result := LanguageSetting;
  if Result = '' then
  begin
    Result := LowerCase(GetLanguageID.LanguageCode);
    if Result = 'nb' then Result := 'da'; // closest of the supported languages
    if not Supported(Result) then Result := 'en';
  end;
end;

function LanguageDir: string;
var
  AppDir: string;
begin
  AppDir := ExtractFilePath(ParamStr(0));
  Result := AppDir + 'languages';
  if not DirectoryExists(Result) then
    Result := ExpandFileName(AppDir + '..' + PathDelim + 'languages');
end;

procedure ApplyLanguage;
begin
  SetDefaultLang(EffectiveLanguage, LanguageDir, 'TidyTag', False);
end;

end.
