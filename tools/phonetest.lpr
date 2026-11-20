program phonetest;

{ Phone sync checks with an ordinary folder standing in for the phone (the shell copies,
  renames and moves the same way): download, changed file, rename, folder rename, new file,
  deleted file, renamed root.
  Usage: phonetest <work folder> <audio file> [<audio file> ...] }

{$mode objfpc}{$H+}

uses
  Windows, Classes, SysUtils, PhoneSync;

var
  Failures: Integer = 0;
  Checks: Integer = 0;

procedure Check(Ok: Boolean; const What: string);
begin
  Inc(Checks);
  if Ok then WriteLn('   ok   ', What)
  else
  begin
    Inc(Failures);
    WriteLn('   FEJL ', What);
  end;
end;

function SameContent(const A, B: string): Boolean;
var
  SA, SB: TMemoryStream;
begin
  Result := False;
  if not FileExists(A) or not FileExists(B) then Exit;
  SA := TMemoryStream.Create;
  SB := TMemoryStream.Create;
  try
    SA.LoadFromFile(A);
    SB.LoadFromFile(B);
    Result := (SA.Size = SB.Size) and CompareMem(SA.Memory, SB.Memory, SA.Size);
  finally
    SA.Free;
    SB.Free;
  end;
end;

procedure ChangeFile(const F: string);
var
  S: TFileStream;
  B: Byte;
begin
  // flip a byte near the start, where tags live; size and write time stay as they were
  S := TFileStream.Create(F, fmOpenReadWrite);
  try
    S.Position := 100;
    S.Read(B, 1);
    B := B xor $FF;
    S.Position := 100;
    S.Write(B, 1);
  finally
    S.Free;
  end;
end;

function SyncTwice(M: TPhoneMirror; Errors: TStrings): Integer;
begin
  // the first scan only notes the state; the second sends what did not change in between
  Result := M.Sync(False, Errors);
  Sleep(50);
  Inc(Result, M.Sync(False, Errors));
end;

var
  Work, Phone, Mirror, Rel: string;
  I: Integer;
  M: TPhoneMirror;
  Errors: TStringList;
  Names: TStringList;
begin
  DefaultSystemCodePage := CP_UTF8;
  if ParamCount < 2 then
  begin
    WriteLn('phonetest <work folder> <audio file> [<audio file> ...]');
    Halt(2);
  end;
  Work := IncludeTrailingPathDelimiter(UTF8Encode(UnicodeString(ParamStr(1))));
  Phone := Work + 'phone' + PathDelim + 'Rock';
  Mirror := Work + 'mirror' + PathDelim + 'Rock';
  ForceDirectories(Phone + PathDelim + 'Live');
  Names := TStringList.Create;
  for I := 2 to ParamCount do
  begin
    Rel := ExtractFileName(UTF8Encode(UnicodeString(ParamStr(I))));
    Names.Add(Rel);
    CopyFile(PChar(ParamStr(I)), PChar(Phone + PathDelim + Rel), False);
  end;
  CopyFile(PChar(ParamStr(2)), PChar(Phone + PathDelim + 'Live' + PathDelim + 'live.mp3'), False);
  Errors := TStringList.Create;
  M := TPhoneMirror.Create;
  try
    WriteLn('== download');
    Check(DownloadPhoneFolder(0, Phone, 'Test\Rock', Mirror) = '', 'download');
    Check(FindMirrorRoot(Mirror + PathDelim + 'Live') = Mirror, 'mirror root found from a subfolder');
    for Rel in Names do
      Check(SameContent(Phone + PathDelim + Rel, Mirror + PathDelim + Rel), 'copied ' + Rel);
    Check(SameContent(Phone + '\Live\live.mp3', Mirror + '\Live\live.mp3'), 'subfolder copied');
    M.Load(Mirror);
    Check(M.Sync(True, Errors) = 0, 'nothing to send right after the download');
    // a working copy may be named differently ('?' and ':' are not allowed here): no rename
    Check(DownloadPhoneFolder(0, Phone, 'Test\Rock', Work + 'other\Andet navn') = '', 'download under another name');
    M.Load(Work + 'other\Andet navn');
    Check((M.Sync(True, Errors) = 0) and DirectoryExists(Phone), 'phone folder keeps its name');
    M.Load(Mirror);

    WriteLn('== changed file');
    ChangeFile(Mirror + PathDelim + Names[0]);
    Check(M.Sync(False, Errors) = 0, 'not sent on the first scan (may still be writing)');
    Check(M.Sync(False, Errors) = 1, 'sent on the second scan');
    Check(SameContent(Phone + PathDelim + Names[0], Mirror + PathDelim + Names[0]), 'phone has the change');

    WriteLn('== rename');
    RenameFile(Mirror + PathDelim + Names[0], Mirror + PathDelim + 'Omdøbt ÆØÅ.mp3');
    M.Renamed(Mirror + PathDelim + Names[0], Mirror + PathDelim + 'Omdøbt ÆØÅ.mp3');
    Check(SyncTwice(M, Errors) = 1, 'renamed on the phone');
    Check(FileExists(Phone + PathDelim + 'Omdøbt ÆØÅ.mp3') and not FileExists(Phone + PathDelim + Names[0]),
      'new name only');

    WriteLn('== folder rename');
    RenameFile(Mirror + '\Live', Mirror + '\Koncert');
    M.Renamed(Mirror + '\Live', Mirror + '\Koncert');
    Check(SyncTwice(M, Errors) = 1, 'folder renamed on the phone');
    Check(FileExists(Phone + '\Koncert\live.mp3') and not DirectoryExists(Phone + '\Live'), 'files went along');
    ChangeFile(Mirror + '\Koncert\live.mp3');
    Check(SyncTwice(M, Errors) = 1, 'change in the renamed folder sent');
    Check(SameContent(Phone + '\Koncert\live.mp3', Mirror + '\Koncert\live.mp3'), 'phone has it');

    WriteLn('== move into a new folder');
    ForceDirectories(Mirror + '\CD1');
    RenameFile(Mirror + PathDelim + 'Omdøbt ÆØÅ.mp3', Mirror + '\CD1\01 Flyttet.mp3');
    M.Renamed(Mirror + PathDelim + 'Omdøbt ÆØÅ.mp3', Mirror + '\CD1\01 Flyttet.mp3');
    Check(SyncTwice(M, Errors) = 1, 'moved on the phone');
    Check(FileExists(Phone + '\CD1\01 Flyttet.mp3') and not FileExists(Phone + PathDelim + 'Omdøbt ÆØÅ.mp3'),
      'in the new folder only');

    WriteLn('== new and deleted files');
    CopyFile(PChar(ParamStr(2)), PChar(Mirror + '\folder.jpg'), False);
    Check(SyncTwice(M, Errors) = 1, 'new file sent');
    Check(SameContent(Phone + '\folder.jpg', Mirror + '\folder.jpg'), 'phone has the new file');
    if Names.Count > 1 then
    begin
      DeleteFile(Mirror + PathDelim + Names[1]);
      SyncTwice(M, Errors);
      Check(FileExists(Phone + PathDelim + Names[1]), 'deleted here: still on the phone');
    end;

    WriteLn('== reload and root rename');
    M.Free;
    M := TPhoneMirror.Create;
    M.Load(Mirror);
    Check(M.Sync(True, Errors) = 0, 'nothing pending after reloading the manifest');
    RenameFile(Mirror, Work + 'mirror\Rock (2024)');
    M.Renamed(Mirror, Work + 'mirror\Rock (2024)');
    Check(M.Sync(True, Errors) = 1, 'picked folder renamed on the phone');
    Check(DirectoryExists(Work + 'phone\Rock (2024)') and not DirectoryExists(Phone), 'phone folder has the new name');
    // stored phone paths below the renamed folder are stale now; found again by name
    ChangeFile(Work + 'mirror\Rock (2024)\Koncert\live.mp3');
    Check(SyncTwice(M, Errors) = 1, 'change below the renamed folder sent');
    Check(SameContent(Work + 'phone\Rock (2024)\Koncert\live.mp3', Work + 'mirror\Rock (2024)\Koncert\live.mp3'),
      'phone has it');
    for I := 0 to Errors.Count - 1 do WriteLn('   fejl fra Windows: ', Errors[I]);
    Check(Errors.Count = 0, 'no errors');
  finally
    M.Free;
    Errors.Free;
    Names.Free;
  end;
  WriteLn(Format('%d tjek, %d fejl', [Checks, Failures]));
  if Failures > 0 then Halt(1);
  WriteLn('ALLE TESTS OK');
end.
