unit FileOps;

{ File operations on the files of the list: delete to the recycle bin, copy or move to
  another folder. Existing files at the target are never overwritten. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

var
  { False: delete for good instead (used by the self-test, so that it does not fill the
    recycle bin; the recycle bin itself is tested by tooltest). }
  UseRecycleBin: Boolean = True;

{ Moves the files to the recycle bin. Returns the number of files that are gone;
  problems go to Errors. }
function RecycleFiles(const Files: array of string; Errors: TStrings): Integer;
{ Copies (Move = False) or moves the files into Dir. Done[i] tells whether file i was
  handled; NewNames[i] is its new full path. Returns the number of files handled. }
function CopyOrMoveFiles(const Files: array of string; const Dir: string; Move: Boolean;
  out Done: array of Boolean; out NewNames: array of string; Errors: TStrings): Integer;

implementation

uses
  {$IFDEF WINDOWS}Windows, ShellApi,{$ENDIF} TagUtils;

resourcestring
  rsFindesAlleredeIMaalmappen = 'findes allerede i målmappen';
  rsKunneIkkeLaeggesIPapirkurven = 'kunne ikke lægges i papirkurven';

function RecycleFiles(const Files: array of string; Errors: TStrings): Integer;
{$IFDEF WINDOWS}
var
  I: Integer;
  Op: TSHFileOpStructW;
  From: UnicodeString;
begin
  Result := 0;
  if not UseRecycleBin then
  begin
    for I := 0 to High(Files) do
      if SysUtils.DeleteFile(Files[I]) then Inc(Result)
      else Errors.Add(ExtractFileName(Files[I]) + ': ' + SysErrorMessage(GetLastOSError));
    Exit;
  end;
  for I := 0 to High(Files) do
  begin
    // one file per call: a failure stays with its own file
    From := UTF8Decode(Files[I]) + #0#0;
    FillChar(Op, SizeOf(Op), 0);
    Op.wFunc := FO_DELETE;
    Op.pFrom := PWideChar(From);
    Op.fFlags := FOF_ALLOWUNDO or FOF_NOCONFIRMATION or FOF_SILENT or FOF_NOERRORUI;
    if (SHFileOperationW(@Op) = 0) and not Op.fAnyOperationsAborted and not FileExists(Files[I]) then
      Inc(Result)
    else
      Errors.Add(ExtractFileName(Files[I]) + ': ' + rsKunneIkkeLaeggesIPapirkurven);
  end;
end;
{$ELSE}
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Files) do
    if DeleteFile(Files[I]) then Inc(Result)
    else Errors.Add(ExtractFileName(Files[I]) + ': ' + SysErrorMessage(GetLastOSError));
end;
{$ENDIF}

function CopyOrMoveFiles(const Files: array of string; const Dir: string; Move: Boolean;
  out Done: array of Boolean; out NewNames: array of string; Errors: TStrings): Integer;
var
  I: Integer;
  Target: string;
  Ok: Boolean;
begin
  Result := 0;
  for I := 0 to High(Files) do
  begin
    Done[I] := False;
    NewNames[I] := Files[I];
    Target := IncludeTrailingPathDelimiter(Dir) + ExtractFileName(Files[I]);
    if SameFileName(ExpandFileName(Target), ExpandFileName(Files[I])) then Continue;
    if FileExists(Target) then
    begin
      Errors.Add(ExtractFileName(Files[I]) + ': ' + rsFindesAlleredeIMaalmappen);
      Continue;
    end;
    {$IFDEF WINDOWS}
    if Move then
      Ok := MoveFileExW(PWideChar(UTF8Decode(Files[I])), PWideChar(UTF8Decode(Target)),
        MOVEFILE_COPY_ALLOWED)
    else
      Ok := CopyFileW(PWideChar(UTF8Decode(Files[I])), PWideChar(UTF8Decode(Target)), True);
    {$ELSE}
    if Move then Ok := RenameFile(Files[I], Target) else Ok := False;
    {$ENDIF}
    if Ok then
    begin
      Done[I] := True;
      NewNames[I] := Target;
      Inc(Result);
    end
    else
      Errors.Add(ExtractFileName(Files[I]) + ': ' + SysErrorMessage(GetLastOSError));
  end;
end;

end.
