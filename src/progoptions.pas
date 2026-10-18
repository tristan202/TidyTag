unit ProgOptions;

{ Program options from the Settings dialog that have no menu of their own: file list
  look, start folder, ID3 text encoding, genre list, players and playlists. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IniFiles;

type
  { Program options without a menu of their own (Settings dialog). }
  TAppOptions = record
    // file list
    MarkLowBitrate: Boolean;
    LowBitrate: Integer;          // kbit/s; below this the bitrate is shown in red
    MarkNoID3v1: Boolean;         // MP3 files without ID3v1: file name in another colour
    HideExtensions: Boolean;
    GridLines: Boolean;
    ListFontSize: Integer;        // points; 0 = Windows default
    FixedStartFolder: Boolean;    // otherwise the last folder
    StartFolder: string;
    // tags
    ID3Unicode: Boolean;          // ID3v2.3: always UTF-16 (else Latin-1 when it fits)
    CustomGenres: TStringArray;   // added to the standard ID3 genres
    HiddenGenres: TStringArray;   // standard genres left out of the lists
    // players: 'mp3=C:\Program\player.exe' (extension without dot; '*' = all)
    Players: TStringArray;
    // playlists
    PlExtInf: Boolean;
    PlInfoMask: string;           // text after #EXTINF:<seconds>,
    PlFullPaths: Boolean;
    PlFolder: string;             // '' = the files' folder
    PlNameMask: string;           // quick save file name
  end;

var
  AppOptions: TAppOptions;

procedure LoadAppOptions;
procedure SaveAppOptions;
{ Genres for the combo boxes: shown standard genres plus own genres, sorted. }
function GenreList: TStringArray;
{ Program configured for a file's extension, '' for the Windows default. }
function PlayerFor(const FileName: string): string;

implementation

uses
  SettingsFile, TagUtils;

function Unquote(const S: string): string;
begin
  if (Length(S) >= 2) and (S[1] = '"') and (S[Length(S)] = '"') then
    Result := Copy(S, 2, Length(S) - 2)
  else
    Result := S;
end;

function ReadList(Ini: TIniFile; const Section: string): TStringArray;
var
  L: TStringList;
  I: Integer;
begin
  L := TStringList.Create;
  try
    Ini.ReadSectionValues(Section, L);
    SetLength(Result, L.Count);
    for I := 0 to L.Count - 1 do Result[I] := L.ValueFromIndex[I];
  finally
    L.Free;
  end;
end;

procedure WriteList(Ini: TIniFile; const Section: string; const Items: TStringArray);
var
  I: Integer;
begin
  Ini.EraseSection(Section);
  for I := 0 to High(Items) do
    // quoted, so leading/trailing spaces and '=' survive
    Ini.WriteString(Section, 'Item' + IntToStr(I), '"' + Items[I] + '"');
end;

procedure LoadAppOptions;
var
  Ini: TIniFile;
  I: Integer;
begin
  Ini := OpenSettings;
  try
    with AppOptions do
    begin
      MarkLowBitrate := Ini.ReadBool('FileList', 'MarkLowBitrate', False);
      LowBitrate := Ini.ReadInteger('FileList', 'LowBitrate', 128);
      MarkNoID3v1 := Ini.ReadBool('FileList', 'MarkNoID3v1', False);
      HideExtensions := Ini.ReadBool('FileList', 'HideExtensions', False);
      GridLines := Ini.ReadBool('FileList', 'GridLines', False);
      ListFontSize := Ini.ReadInteger('FileList', 'FontSize', 0);
      FixedStartFolder := Ini.ReadBool('Main', 'FixedStartFolder', False);
      StartFolder := Ini.ReadString('Main', 'StartFolder', '');
      ID3Unicode := Ini.ReadBool('Tags', 'ID3Unicode', False);
      CustomGenres := ReadList(Ini, 'CustomGenres');
      HiddenGenres := ReadList(Ini, 'HiddenGenres');
      Players := ReadList(Ini, 'Players');
      PlExtInf := Ini.ReadBool('Playlist', 'ExtInf', True);
      PlInfoMask := Ini.ReadString('Playlist', 'InfoMask', '%1 - %2');
      PlFullPaths := Ini.ReadBool('Playlist', 'FullPaths', False);
      PlFolder := Ini.ReadString('Playlist', 'Folder', '');
      PlNameMask := Ini.ReadString('Playlist', 'NameMask', '%f');
      for I := 0 to High(CustomGenres) do CustomGenres[I] := Unquote(CustomGenres[I]);
      for I := 0 to High(HiddenGenres) do HiddenGenres[I] := Unquote(HiddenGenres[I]);
      for I := 0 to High(Players) do Players[I] := Unquote(Players[I]);
    end;
  finally
    Ini.Free;
  end;
end;

procedure SaveAppOptions;
var
  Ini: TIniFile;
begin
  Ini := OpenSettings;
  try
    with AppOptions do
    begin
      Ini.WriteBool('FileList', 'MarkLowBitrate', MarkLowBitrate);
      Ini.WriteInteger('FileList', 'LowBitrate', LowBitrate);
      Ini.WriteBool('FileList', 'MarkNoID3v1', MarkNoID3v1);
      Ini.WriteBool('FileList', 'HideExtensions', HideExtensions);
      Ini.WriteBool('FileList', 'GridLines', GridLines);
      Ini.WriteInteger('FileList', 'FontSize', ListFontSize);
      Ini.WriteBool('Main', 'FixedStartFolder', FixedStartFolder);
      Ini.WriteString('Main', 'StartFolder', StartFolder);
      Ini.WriteBool('Tags', 'ID3Unicode', ID3Unicode);
      WriteList(Ini, 'CustomGenres', CustomGenres);
      WriteList(Ini, 'HiddenGenres', HiddenGenres);
      WriteList(Ini, 'Players', Players);
      Ini.WriteBool('Playlist', 'ExtInf', PlExtInf);
      Ini.WriteString('Playlist', 'InfoMask', PlInfoMask);
      Ini.WriteBool('Playlist', 'FullPaths', PlFullPaths);
      Ini.WriteString('Playlist', 'Folder', PlFolder);
      Ini.WriteString('Playlist', 'NameMask', PlNameMask);
    end;
  finally
    Ini.Free;
  end;
end;

function GenreList: TStringArray;
var
  L: TStringList;
  I: Integer;
  S: string;

  function Hidden(const G: string): Boolean;
  var
    H: string;
  begin
    for H in AppOptions.HiddenGenres do
      if SameText(H, G) then Exit(True);
    Result := False;
  end;

begin
  L := TStringList.Create;
  try
    L.Sorted := True;
    L.Duplicates := dupIgnore;
    L.CaseSensitive := False;
    for I := 0 to ID3GenreCount - 1 do
      if not Hidden(ID3GenreName(I)) then L.Add(ID3GenreName(I));
    for S in AppOptions.CustomGenres do
      if Trim(S) <> '' then L.Add(Trim(S));
    Result := L.ToStringArray;
  finally
    L.Free;
  end;
end;

function PlayerFor(const FileName: string): string;
var
  Ext, P, K: string;
  Star: string;
  E: Integer;
begin
  Result := '';
  Star := '';
  Ext := LowerCase(Copy(ExtractFileExt(FileName), 2, MaxInt));
  for P in AppOptions.Players do
  begin
    E := Pos('=', P);
    if E < 2 then Continue;
    K := LowerCase(Trim(Copy(P, 1, E - 1)));
    if (K <> '') and (K[1] = '.') then Delete(K, 1, 1);
    if K = Ext then Exit(Trim(Copy(P, E + 1, MaxInt)));
    if K = '*' then Star := Trim(Copy(P, E + 1, MaxInt));
  end;
  Result := Star;
end;

end.
