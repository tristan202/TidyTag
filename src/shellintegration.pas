unit ShellIntegration;

{ Explorer integration: the "Open in TidyTag" context menu entries (per user, under
  HKCU\Software\Classes) and the single-instance hand-over. Explorer starts one process
  per selected item; every process after the first sends its path to the running
  TidyTag with WM_COPYDATA and exits. The running window's handle is published in a
  small named shared memory block; a hidden message window of our own receives the
  paths, so nothing depends on the LCL's handling of WM_COPYDATA. No LCL. }

{$mode objfpc}{$H+}

interface

uses
  Windows, SysUtils, Classes;

const
  CopyDataPaths = $59444954; // 'TIDY': WM_COPYDATA marker for a list of paths

{ The existing files and folders named on the command line (switches skipped). }
function CommandLinePaths: TStringArray;
{ Becomes the primary instance when no TidyTag runs. Otherwise sends Paths to the
  running one and returns True (the caller exits); False when there is nothing to send
  or no window answers. }
function ForwardToRunningInstance(const Paths: TStringArray): Boolean;
type
  TPathsEvent = procedure(const Paths: TStringArray) of object;

{ The primary instance starts receiving: OnPaths runs in the calling (main) thread. }
procedure StartReceiving(OnPaths: TPathsEvent);
{ Gives up the primary role, e.g. before a restart that must not hand over to us. }
procedure ReleaseInstance;

function ExplorerMenuInstalled: Boolean;
{ Writes (or rewrites) every entry for this exe with the given menu caption. }
procedure InstallExplorerMenu(const Caption: string; const Extensions: array of string);
procedure RemoveExplorerMenu(const Extensions: array of string);
{ Rewrites installed entries that point to another exe or use another caption. }
procedure RefreshExplorerMenu(const Caption: string; const Extensions: array of string);

implementation

uses
  Registry;

const
  MappingName = 'Local\TidyTag.Instance';
  VerbKey = 'TidyTag';
  WaitForPrimaryMs = 10000;
  HWND_MESSAGE = HWND(-3);

var
  Mapping: THandle = 0;
  View: PHandle = nil;
  Receiver: HWND = 0;
  Receive: TPathsEvent = nil;

function CommandLineToArgvW(lpCmdLine: PWideChar; out pNumArgs: Integer): PPWideChar;
  stdcall; external 'shell32.dll';

{ Read from the wide command line: ParamStr would lose characters outside the ANSI code page. }
function CommandLinePaths: TStringArray;
var
  Argv: PPWideChar;
  N, I: Integer;
  P: string;
begin
  Result := nil;
  Argv := CommandLineToArgvW(GetCommandLineW, N);
  if Argv = nil then Exit;
  try
    for I := 1 to N - 1 do
    begin
      P := UTF8Encode(UnicodeString(Argv[I]));
      if Copy(P, 1, 2) = '--' then Exit(nil); // developer modes take no part
      if FileExists(P) or DirectoryExists(P) then
        Insert(ExpandFileName(P), Result, Length(Result));
    end;
  finally
    LocalFree(HLOCAL(Argv));
  end;
end;

function AllowSetForegroundWindow(dwProcessId: DWORD): BOOL; stdcall; external 'user32.dll';

function ExeName: string;
var
  Buf: array[0..32767] of WideChar;
begin
  if GetModuleFileNameW(0, Buf, Length(Buf)) > 0 then
    Result := UTF8Encode(UnicodeString(PWideChar(@Buf[0])))
  else
    Result := ParamStr(0);
end;

procedure ReleaseInstance;
begin
  if View <> nil then View^ := 0;
  if Receiver <> 0 then DestroyWindow(Receiver);
  Receiver := 0;
  Receive := nil;
  if View <> nil then UnmapViewOfFile(View);
  if Mapping <> 0 then CloseHandle(Mapping);
  View := nil;
  Mapping := 0;
end;

function PathsFromCopyData(Data: PCopyDataStruct): TStringArray; forward;

function ReceiverProc(Wnd: HWND; Msg: UINT; WP: WPARAM; LP: LPARAM): LRESULT; stdcall;
var
  Paths: TStringArray;
begin
  if Msg = WM_COPYDATA then
  begin
    Paths := PathsFromCopyData(PCopyDataStruct(LP));
    if (Length(Paths) > 0) and Assigned(Receive) then
    begin
      Receive(Paths);
      Exit(1);
    end;
    Exit(0);
  end;
  Result := DefWindowProcW(Wnd, Msg, WP, LP);
end;

procedure StartReceiving(OnPaths: TPathsEvent);
var
  WC: TWndClassW;
begin
  if (View = nil) or (Receiver <> 0) then Exit;
  FillChar(WC, SizeOf(WC), 0);
  WC.lpfnWndProc := @ReceiverProc;
  WC.hInstance := HInstance;
  WC.lpszClassName := 'TidyTagReceiver';
  Windows.RegisterClassW(WC);
  Receiver := CreateWindowExW(0, 'TidyTagReceiver', 'TidyTag', 0, 0, 0, 0, 0, HWND_MESSAGE, 0, HInstance, nil);
  Receive := OnPaths;
  View^ := Receiver;
end;

function SendPaths(Wnd: HWND; const Paths: TStringArray): Boolean;
var
  Data: UnicodeString;
  CD: TCopyDataStruct;
  Pid: DWORD;
  P: string;
  Res: DWORD_PTR;
begin
  Data := '';
  for P in Paths do Data := Data + UTF8Decode(P) + #0;
  CD.dwData := CopyDataPaths;
  CD.cbData := Length(Data) * SizeOf(WideChar);
  CD.lpData := PWideChar(Data);
  // We got the foreground right from Explorer; pass it on so the window can come forward.
  GetWindowThreadProcessId(Wnd, @Pid);
  AllowSetForegroundWindow(Pid);
  Res := 0;
  Result := (SendMessageTimeout(Wnd, WM_COPYDATA, 0, LPARAM(@CD), SMTO_ABORTIFHUNG, 15000, @Res) <> 0)
    and (Res <> 0);
end;

function ForwardToRunningInstance(const Paths: TStringArray): Boolean;
var
  H: THandle;
  V: PHandle;
  Wnd: HWND;
  Start: QWord;
  Existed: Boolean;
begin
  Result := False;
  H := CreateFileMappingW(INVALID_HANDLE_VALUE, nil, PAGE_READWRITE, 0, SizeOf(THandle), MappingName);
  if H = 0 then Exit;
  Existed := GetLastError = ERROR_ALREADY_EXISTS;
  V := MapViewOfFile(H, FILE_MAP_ALL_ACCESS, 0, 0, SizeOf(THandle));
  if V = nil then
  begin
    CloseHandle(H);
    Exit;
  end;
  if not Existed then
  begin
    // First one: new mappings are zero-filled, the window is published once it exists.
    Mapping := H;
    View := V;
    Exit;
  end;
  try
    if Length(Paths) = 0 then Exit; // a plain start opens a window of its own
    // Explorer may have started the primary a moment ago; wait for its window.
    Start := GetTickCount64;
    repeat
      Wnd := HWND(V^);
      if (Wnd <> 0) and IsWindow(Wnd) then Exit(SendPaths(Wnd, Paths));
      Sleep(50);
    until GetTickCount64 - Start > WaitForPrimaryMs;
  finally
    UnmapViewOfFile(V);
    CloseHandle(H);
  end;
end;

function PathsFromCopyData(Data: PCopyDataStruct): TStringArray;
var
  W: UnicodeString;
  P: PWideChar;
begin
  Result := nil;
  if (Data = nil) or (Data^.dwData <> CopyDataPaths) or (Data^.cbData = 0) then Exit;
  SetLength(W, Data^.cbData div SizeOf(WideChar));
  Move(Data^.lpData^, W[1], Length(W) * SizeOf(WideChar));
  P := PWideChar(W);
  while (P - PWideChar(W) < Length(W)) and (P^ <> #0) do
  begin
    Insert(UTF8Encode(UnicodeString(P)), Result, Length(Result));
    Inc(P, StrLen(P) + 1);
  end;
end;

{ Explorer menu }

function ExeCommand(const Arg: string): string;
begin
  Result := '"' + ExeName + '" "' + Arg + '"';
end;

{ Every key we write, with its command argument. }
procedure ListKeys(const Extensions: array of string; Keys, Args: TStrings);
var
  E: string;
begin
  Keys.Add('Software\Classes\Directory\shell\' + VerbKey);
  Args.Add('%1');
  Keys.Add('Software\Classes\Directory\Background\shell\' + VerbKey);
  Args.Add('%V');
  Keys.Add('Software\Classes\Drive\shell\' + VerbKey);
  Args.Add('%1');
  for E in Extensions do
  begin
    Keys.Add('Software\Classes\SystemFileAssociations\' + E + '\shell\' + VerbKey);
    Args.Add('%1');
  end;
end;

function ExplorerMenuInstalled: Boolean;
var
  R: TRegistry;
begin
  R := TRegistry.Create(KEY_READ);
  try
    R.RootKey := HKEY_CURRENT_USER;
    Result := R.KeyExists('Software\Classes\Directory\shell\' + VerbKey + '\command');
  finally
    R.Free;
  end;
end;

procedure InstallExplorerMenu(const Caption: string; const Extensions: array of string);
var
  R: TRegistry;
  Keys, Args: TStringList;
  I: Integer;
begin
  Keys := TStringList.Create;
  Args := TStringList.Create;
  R := TRegistry.Create;
  try
    R.RootKey := HKEY_CURRENT_USER;
    ListKeys(Extensions, Keys, Args);
    for I := 0 to Keys.Count - 1 do
    begin
      if not R.OpenKey(Keys[I], True) then Continue;
      R.WriteString('', Caption);
      R.WriteString('Icon', '"' + ExeName + '",0');
      // without it the entry disappears when more than 15 files are selected
      if Pos('SystemFileAssociations', Keys[I]) > 0 then R.WriteString('MultiSelectModel', 'Player');
      R.CloseKey;
      if R.OpenKey(Keys[I] + '\command', True) then
      begin
        R.WriteString('', ExeCommand(Args[I]));
        R.CloseKey;
      end;
    end;
  finally
    R.Free;
    Keys.Free;
    Args.Free;
  end;
end;

procedure RemoveExplorerMenu(const Extensions: array of string);
var
  R: TRegistry;
  Keys, Args: TStringList;
  I: Integer;
begin
  Keys := TStringList.Create;
  Args := TStringList.Create;
  R := TRegistry.Create;
  try
    R.RootKey := HKEY_CURRENT_USER;
    ListKeys(Extensions, Keys, Args);
    for I := 0 to Keys.Count - 1 do
    begin
      R.DeleteKey(Keys[I] + '\command');
      R.DeleteKey(Keys[I]);
    end;
  finally
    R.Free;
    Keys.Free;
    Args.Free;
  end;
end;

procedure RefreshExplorerMenu(const Caption: string; const Extensions: array of string);
var
  R: TRegistry;
  Stale: Boolean;
begin
  if not ExplorerMenuInstalled then Exit;
  R := TRegistry.Create(KEY_READ);
  try
    R.RootKey := HKEY_CURRENT_USER;
    Stale := not R.OpenKeyReadOnly('Software\Classes\Directory\shell\' + VerbKey);
    if not Stale then
    begin
      Stale := R.ReadString('') <> Caption;
      R.CloseKey;
    end;
    if not Stale and R.OpenKeyReadOnly('Software\Classes\Directory\shell\' + VerbKey + '\command') then
    begin
      Stale := R.ReadString('') <> ExeCommand('%1');
      R.CloseKey;
    end;
  finally
    R.Free;
  end;
  if Stale then InstallExplorerMenu(Caption, Extensions);
end;

end.
