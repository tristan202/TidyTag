unit PhoneSync;

{ Folders on phones and other devices without a drive letter (Android over USB = MTP).
  Their files cannot be changed in place, so a picked folder is copied to a local working
  copy ("mirror"), TidyTag works on that as on any folder, and Sync sends the changes back:
  changed files are copied over the phone's, renamed or moved files are renamed or moved on
  the phone. Nothing is ever deleted on the phone.
  All transfers go through the Windows shell (IFileOperation), like Explorer's own copying.
  A manifest file in the mirror root keeps every file's and folder's phone item (by its
  shell parsing name), its name on the phone and the state it was last sent in. No LCL. }

{$mode objfpc}{$H+}
{$interfaces com}

interface

uses
  Windows, SysUtils, Classes, ShlObj, ActiveX;

const
  ManifestName = '.tidytag-phone.txt';

type
  TPhoneEntry = record
    Rel: string;           // path relative to the mirror root, as it is now
    Parsing: string;       // the phone item
    PhoneRel: string;      // its path on the phone (differs after a rename until synced)
    Stamp: string;         // size/write time/change time when last in step with the phone
    Hash: QWord;           // fingerprint of the start and end of the file (where tags live)
    IsDir: Boolean;
  end;

  TPhoneMirror = class
  private
    FEntries: array of TPhoneEntry;
    FPrevStamps: TStringList; // last scan's stamps: a file is sent once it stops changing
    FBusy: Boolean;           // in Sync: the shell's progress dialog lets other events run
    FQueued: TStringList;     // renames reported meanwhile: old path #9 new path
    function DoSync(Force: Boolean; Errors: TStrings): Integer;
    function ResolvePhone(const PhoneRel: string): IShellItem;
    function PhoneItem(I: Integer): IShellItem;
    function IndexOf(const Rel: string): Integer;
    function FolderItem(const RelDir: string; Ops: Pointer; out Err: string): IShellItem;
    function Owner: HWND;
  public
    Root: string;          // local mirror root folder
    RootParsing: string;   // the picked phone folder
    RootPhoneName: string; // its name on the phone
    RootLocalName: string; // the working copy's own name when last in step (may differ: '?' or ':')
    Title: string;         // shown to the user: 'Pixel 9 Pro XL\...\Music\Rock'
    OwnerWnd: HWND;
    constructor Create;
    destructor Destroy; override;
    procedure Load(const ARoot: string);
    procedure Save;
    { A file or folder in the mirror was renamed or moved by TidyTag. }
    procedure Renamed(const OldPath, NewPath: string);
    { Sends what changed; Force sends files even if they changed since the last scan.
      Returns the number of files sent or renamed; problems are added to Errors. }
    function Sync(Force: Boolean; Errors: TStrings): Integer;
  end;

{ Windows' folder picker, which can show phones. Picked is a normal folder path when the
  choice has one (then no mirror is needed), else ''. False when cancelled. }
function PickDeviceFolder(Owner: HWND; const Caption: string; out Picked, Parsing, Title: string): Boolean;
{ Copies the phone folder to LocalRoot (emptied first) and writes the manifest. '' on success. }
function DownloadPhoneFolder(Owner: HWND; const Parsing, Title, LocalRoot: string): string;
{ The mirror root that Dir lies in, or ''. }
function FindMirrorRoot(const Dir: string): string;
{ Where working copies live: %LOCALAPPDATA%\TidyTag\Phone\<name>. }
function MirrorFolderFor(const Title: string): string;
{ The parts the tests check. }
function FileStamp(const FileName: string): string;
function FileFingerprint(const FileName: string): QWord;

implementation

uses
  Math, AudioTags, SettingsFile, FileLayer;

resourcestring
  rsMappenFindesIkkePaaTelefonen = 'mappen findes ikke længere på telefonen (er den tilsluttet og låst op?)';
  rsKopieringMislykkedes = 'kopieringen mislykkedes (fejl %s)';
  rsFejlVed = '%s: fejl %s';
  rsFindesIkke = '%s findes ikke på telefonen';

const
  CLSID_FileOperation: TGUID = '{3ad05575-8857-4850-9277-11b85bdb8e09}';
  BHID_EnumItems: TGUID = '{94F60519-2850-4924-AA5A-D15E84868039}';
  IID_IEnumShellItems: TGUID = '{70629033-e363-4a28-a567-0db78006e6d7}';
  ThisPC = '::{20D04FE0-3AEA-1069-A2D8-08002B30309D}';
  FOF_NOCONFIRMATION = $10;
  FOF_NOCONFIRMMKDIR = $200;
  FOFX_EARLYFAILURE = $00100000;
  ProbeSize = 256 * 1024;

type
  IFileOperation = interface(IUnknown)
    ['{947aab5f-0a5c-4c13-b4d6-4bf7836fc9f8}']
    function Advise(pfops: IFileOperationProgressSink; out pdwCookie: DWORD): HRESULT; stdcall;
    function Unadvise(dwCookie: DWORD): HRESULT; stdcall;
    function SetOperationFlags(dwOperationFlags: DWORD): HRESULT; stdcall;
    function SetProgressMessage(pszMessage: PWideChar): HRESULT; stdcall;
    function SetProgressDialog(popd: IUnknown): HRESULT; stdcall;
    function SetProperties(pproparray: IUnknown): HRESULT; stdcall;
    function SetOwnerWindow(hwndOwner: HWND): HRESULT; stdcall;
    function ApplyPropertiesToItem(psiItem: IShellItem): HRESULT; stdcall;
    function ApplyPropertiesToItems(punkItems: IUnknown): HRESULT; stdcall;
    function RenameItem(psiItem: IShellItem; pszNewName: PWideChar; pfopsItem: IFileOperationProgressSink): HRESULT; stdcall;
    function RenameItems(pUnkItems: IUnknown; pszNewName: PWideChar): HRESULT; stdcall;
    function MoveItem(psiItem: IShellItem; psiDestinationFolder: IShellItem; pszNewName: PWideChar;
      pfopsItem: IFileOperationProgressSink): HRESULT; stdcall;
    function MoveItems(punkItems: IUnknown; psiDestinationFolder: IShellItem): HRESULT; stdcall;
    function CopyItem(psiItem: IShellItem; psiDestinationFolder: IShellItem; pszCopyName: PWideChar;
      pfopsItem: IFileOperationProgressSink): HRESULT; stdcall;
    function CopyItems(punkItems: IUnknown; psiDestinationFolder: IShellItem): HRESULT; stdcall;
    function DeleteItem(psiItem: IShellItem; pfopsItem: IFileOperationProgressSink): HRESULT; stdcall;
    function DeleteItems(punkItems: IUnknown): HRESULT; stdcall;
    function NewItem(psiDestinationFolder: IShellItem; dwFileAttributes: DWORD; pszName: PWideChar;
      pszTemplateName: PWideChar; pfopsItem: IFileOperationProgressSink): HRESULT; stdcall;
    function PerformOperations: HRESULT; stdcall;
    function GetAnyOperationsAborted(out pfAnyOperationsAborted: BOOL): HRESULT; stdcall;
  end;

  { Collects the items the shell created: key (see below) = parsing name of the new item. }
  TOpSink = class(TInterfacedObject, IFileOperationProgressSink)
  public
    Created: TStringList;
    Errors: TStringList;
    constructor Create;
    destructor Destroy; override;
    function StartOperations: HResult; stdcall;
    function FinishOperations(hrResult: HResult): HResult; stdcall;
    function PreRenameItem(dwFlags: DWORD; psiItem: IShellItem; pszNewName: LPCWSTR): HResult; stdcall;
    function PostRenameItem(dwFlags: DWORD; psiItem: IShellItem; pszNewName: LPCWSTR; hrRename: HRESULT; psiNewlyCreated: IShellItem): HResult; stdcall;
    function PreMoveItem(dwFlags: DWORD; psiItem: IShellItem; psiDestinationFolder: IShellItem; pszNewName: LPCWSTR): HResult; stdcall;
    function PostMoveItem(dwFlags: DWORD; psiItem: IShellItem; psiDestinationFolder: IShellItem; pszNewName: LPCWSTR; hrMove: HRESULT; psiNewlyCreated: IShellItem): HResult; stdcall;
    function PreCopyItem(dwFlags: DWORD; psiItem: IShellItem; psiDestinationFolder: IShellItem; pszNewName: LPCWSTR): HResult; stdcall;
    function PostCopyItem(dwFlags: DWORD; psiItem: IShellItem; psiDestinationFolder: IShellItem; pszNewName: LPCWSTR; hrCopy: HRESULT; psiNewlyCreated: IShellItem): HResult; stdcall;
    function PreDeleteItem(dwFlags: DWORD; psiItem: IShellItem): HResult; stdcall;
    function PostDeleteItem(dwFlags: DWORD; psiItem: IShellItem; hrDelete: HRESULT; psiNewlyCreated: IShellItem): HResult; stdcall;
    function PreNewItem(dwFlags: DWORD; psiDestinationFolder: IShellItem; pszNewName: LPCWSTR): HResult; stdcall;
    function PostNewItem(dwFlags: DWORD; psiDestinationFolder: IShellItem; pszNewName: LPCWSTR; pszTemplateName: LPCWSTR; dwFileAttributes: DWORD; hrNew: HRESULT; psiNewItem: IShellItem): HResult; stdcall;
    function UpdateProgress(iWorkTotal: UINT; iWorkSoFar: UINT): HResult; stdcall;
    function ResetTimer: HResult; stdcall;
    function PauseTimer: HResult; stdcall;
    function ResumeTimer: HResult; stdcall;
  end;

  TFileBasicInfo = record
    CreationTime, LastAccessTime, LastWriteTime, ChangeTime: Int64;
    FileAttributes: DWORD;
    Pad: DWORD;
  end;

function SHCreateItemFromParsingName(pszPath: PWideChar; pbc: Pointer; constref riid: TGUID;
  out ppv): HRESULT; stdcall; external 'shell32.dll';
function GetFileInformationByHandleEx(hFile: THandle; FileInformationClass: Integer;
  lpFileInformation: Pointer; dwBufferSize: DWORD): BOOL; stdcall; external 'kernel32.dll';
function GetFileSizeEx(hFile: THandle; lpFileSize: PInt64): BOOL; stdcall; external 'kernel32.dll';
function SHGetIDListFromObject(punk: IUnknown; out ppidl: Pointer): HRESULT; stdcall; external 'shell32.dll';
function SHCreateItemFromIDList(pidl: Pointer; constref riid: TGUID; out ppv): HRESULT; stdcall; external 'shell32.dll';
function ILGetSize(pidl: Pointer): UINT; stdcall; external 'shell32.dll';

{ Shell helpers }

{ Items are kept as 'P:' + their ID list in hex: the phone folder does not accept its own
  parsing names below the device ('...\SID-{...}\{...}' gives E_INVALIDARG). }
function ItemFrom(const Key: string): IShellItem;
var
  Raw: RawByteString;
begin
  Result := nil;
  if Copy(Key, 1, 2) = 'P:' then
  begin
    SetLength(Raw, (Length(Key) - 2) div 2);
    if (Raw = '') or (HexToBin(PChar(Key) + 2, PChar(Raw), Length(Raw)) <> Length(Raw)) or
      Failed(SHCreateItemFromIDList(PChar(Raw), IShellItem, Result)) then
      Result := nil;
  end
  else if Failed(SHCreateItemFromParsingName(PWideChar(UTF8Decode(Key)), nil, IShellItem, Result)) then
    Result := nil;
end;

function ItemName(Item: IShellItem; Kind: DWORD): string;
var
  P: PWideChar;
begin
  Result := '';
  P := nil;
  if Succeeded(Item.GetDisplayName(Kind, LPWSTR(@P))) and (P <> nil) then
  begin
    Result := UTF8Encode(UnicodeString(P));
    CoTaskMemFree(P);
  end;
end;

function ItemParsing(Item: IShellItem): string;
var
  Pidl: Pointer;
  Hex: string;
begin
  Result := '';
  if Item = nil then Exit;
  // ordinary folders by path: the copy engine cancels overwrites of items made from ID lists
  Result := ItemName(Item, SIGDN_FILESYSPATH);
  if (Result <> '') or Failed(SHGetIDListFromObject(Item, Pidl)) then Exit;
  SetLength(Hex, 2 * ILGetSize(Pidl));
  BinToHex(PChar(Pidl), PChar(Hex), ILGetSize(Pidl));
  CoTaskMemFree(Pidl);
  Result := 'P:' + Hex;
end;

function ItemIsFolder(Item: IShellItem): Boolean;
var
  A: SFGAOF;
begin
  A := 0;
  Result := Succeeded(Item.GetAttributes(SFGAO_FOLDER or SFGAO_STREAM, @A)) and
    (A and SFGAO_FOLDER <> 0) and (A and SFGAO_STREAM = 0); // zip files are both
end;

function Children(Item: IShellItem): TInterfaceList;
var
  E: IEnumShellItems;
  C: IShellItem;
  N: ULONG;
begin
  Result := TInterfaceList.Create;
  E := nil;
  if Failed(Item.BindToHandler(nil, @BHID_EnumItems, @IID_IEnumShellItems, @E)) or (E = nil) then Exit;
  N := 0;
  while (E.Next(1, C, N) = S_OK) and (N = 1) do Result.Add(C);
end;

function NewOperation(Owner: HWND; Flags: DWORD): IFileOperation;
begin
  Result := nil;
  if Failed(CoCreateInstance(CLSID_FileOperation, nil, CLSCTX_ALL, IFileOperation, Result)) then
    Exit(nil);
  Result.SetOperationFlags(Flags);
  if Owner <> 0 then Result.SetOwnerWindow(Owner);
end;

{ TOpSink }

constructor TOpSink.Create;
begin
  inherited Create;
  Created := TStringList.Create;
  Errors := TStringList.Create;
end;

destructor TOpSink.Destroy;
begin
  Created.Free;
  Errors.Free;
  inherited Destroy;
end;

function TOpSink.StartOperations: HResult; stdcall;
begin
  Result := S_OK;
end;

function TOpSink.FinishOperations(hrResult: HResult): HResult; stdcall;
begin
  Result := S_OK;
end;

function TOpSink.PreRenameItem(dwFlags: DWORD; psiItem: IShellItem; pszNewName: LPCWSTR): HResult; stdcall;
begin
  Result := S_OK;
end;

procedure Note(Sink: TOpSink; const Key, Name: string; Hr: HRESULT; NewItem: IShellItem);
begin
  if Succeeded(Hr) and (NewItem <> nil) then Sink.Created.Values[Key] := ItemParsing(NewItem)
  else if Failed(Hr) then Sink.Errors.Add(Format(rsFejlVed, [Name, IntToHex(DWORD(Hr), 8)]));
end;

function TOpSink.PostRenameItem(dwFlags: DWORD; psiItem: IShellItem; pszNewName: LPCWSTR; hrRename: HRESULT; psiNewlyCreated: IShellItem): HResult; stdcall;
begin
  Note(Self, ItemParsing(psiItem), ItemName(psiItem, SIGDN_NORMALDISPLAY), hrRename, psiNewlyCreated);
  Result := S_OK;
end;

function TOpSink.PreMoveItem(dwFlags: DWORD; psiItem: IShellItem; psiDestinationFolder: IShellItem; pszNewName: LPCWSTR): HResult; stdcall;
begin
  Result := S_OK;
end;

function TOpSink.PostMoveItem(dwFlags: DWORD; psiItem: IShellItem; psiDestinationFolder: IShellItem; pszNewName: LPCWSTR; hrMove: HRESULT; psiNewlyCreated: IShellItem): HResult; stdcall;
begin
  Note(Self, ItemParsing(psiItem), ItemName(psiItem, SIGDN_NORMALDISPLAY), hrMove, psiNewlyCreated);
  Result := S_OK;
end;

function TOpSink.PreCopyItem(dwFlags: DWORD; psiItem: IShellItem; psiDestinationFolder: IShellItem; pszNewName: LPCWSTR): HResult; stdcall;
begin
  Result := S_OK;
end;

function TOpSink.PostCopyItem(dwFlags: DWORD; psiItem: IShellItem; psiDestinationFolder: IShellItem; pszNewName: LPCWSTR; hrCopy: HRESULT; psiNewlyCreated: IShellItem): HResult; stdcall;
begin
  Note(Self, ItemParsing(psiItem), ItemName(psiItem, SIGDN_NORMALDISPLAY), hrCopy, psiNewlyCreated);
  Result := S_OK;
end;

function TOpSink.PreDeleteItem(dwFlags: DWORD; psiItem: IShellItem): HResult; stdcall;
begin
  Result := S_OK;
end;

function TOpSink.PostDeleteItem(dwFlags: DWORD; psiItem: IShellItem; hrDelete: HRESULT; psiNewlyCreated: IShellItem): HResult; stdcall;
begin
  Result := S_OK;
end;

function TOpSink.PreNewItem(dwFlags: DWORD; psiDestinationFolder: IShellItem; pszNewName: LPCWSTR): HResult; stdcall;
begin
  Result := S_OK;
end;

function TOpSink.PostNewItem(dwFlags: DWORD; psiDestinationFolder: IShellItem; pszNewName: LPCWSTR; pszTemplateName: LPCWSTR; dwFileAttributes: DWORD; hrNew: HRESULT; psiNewItem: IShellItem): HResult; stdcall;
begin
  Note(Self, ItemParsing(psiDestinationFolder) + '\' + UTF8Encode(UnicodeString(pszNewName)),
    UTF8Encode(UnicodeString(pszNewName)), hrNew, psiNewItem);
  Result := S_OK;
end;

function TOpSink.UpdateProgress(iWorkTotal: UINT; iWorkSoFar: UINT): HResult; stdcall;
begin
  Result := S_OK;
end;

function TOpSink.ResetTimer: HResult; stdcall;
begin
  Result := S_OK;
end;

function TOpSink.PauseTimer: HResult; stdcall;
begin
  Result := S_OK;
end;

function TOpSink.ResumeTimer: HResult; stdcall;
begin
  Result := S_OK;
end;

{ Local file state }

function FileStamp(const FileName: string): string;
var
  H: THandle;
  Info: TFileBasicInfo;
  Size: Int64;
begin
  Result := '';
  H := CreateFileW(PWideChar(UTF8Decode(FileName)), 0, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
    nil, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, 0);
  if H = INVALID_HANDLE_VALUE then Exit;
  try
    FillChar(Info, SizeOf(Info), 0);
    // ChangeTime moves on every write, also when the write time is put back ("keep file date")
    if not GetFileInformationByHandleEx(H, 0 {FileBasicInfo}, @Info, SizeOf(Info)) then Exit;
    if not GetFileSizeEx(H, @Size) then Size := -1;
    Result := IntToStr(Size) + '/' + IntToStr(Info.LastWriteTime) + '/' + IntToStr(Info.ChangeTime);
  finally
    CloseHandle(H);
  end;
end;

function FileFingerprint(const FileName: string): QWord;
var
  S: TFileStream;
  Buf: array of Byte;
  N, I: Integer;

  procedure Mix(Count: Integer);
  var
    J: Integer;
  begin
    for J := 0 to Count - 1 do
      Result := (Result xor Buf[J]) * QWord(1099511628211); // FNV-1a
  end;

begin
  Result := QWord(14695981039346656037);
  try
    S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  except
    Exit(0);
  end;
  try
    SetLength(Buf, ProbeSize);
    N := S.Read(Buf[0], ProbeSize);
    Mix(N);
    if S.Size > ProbeSize then
    begin
      S.Position := Max(ProbeSize, S.Size - ProbeSize);
      N := S.Read(Buf[0], ProbeSize);
      Mix(N);
    end;
    for I := 0 to 7 do
    begin
      Buf[I] := (S.Size shr (8 * I)) and $FF;
    end;
    Mix(8);
  finally
    S.Free;
  end;
end;

{ Picking and downloading }

function PickDeviceFolder(Owner: HWND; const Caption: string; out Picked, Parsing, Title: string): Boolean;
var
  D: IFileOpenDialog;
  Item, Start: IShellItem;
  Opt: DWORD;
begin
  Result := False;
  Picked := '';
  Parsing := '';
  Title := '';
  if Failed(CoCreateInstance(CLSID_FileOpenDialog, nil, CLSCTX_INPROC_SERVER, IFileOpenDialog, D)) then Exit;
  D.GetOptions(@Opt);
  D.SetOptions(Opt or FOS_PICKFOLDERS or FOS_ALLNONSTORAGEITEMS);
  D.SetTitle(PWideChar(UTF8Decode(Caption)));
  Start := ItemFrom(ThisPC);
  if Start <> nil then D.SetFolder(Start);
  if D.Show(Owner) <> S_OK then Exit;
  Item := nil;
  if Failed(D.GetResult(@Item)) or (Item = nil) then Exit;
  Picked := ItemName(Item, SIGDN_FILESYSPATH);
  Parsing := ItemParsing(Item);
  Title := ItemName(Item, SIGDN_DESKTOPABSOLUTEEDITING);
  if Title = '' then Title := ItemName(Item, SIGDN_NORMALDISPLAY);
  // 'This PC\Pixel\...' -> 'Pixel\...'
  if (Start <> nil) and SameText(Copy(Title, 1, Length(ItemName(Start, SIGDN_NORMALDISPLAY)) + 1),
    ItemName(Start, SIGDN_NORMALDISPLAY) + '\') then
    Delete(Title, 1, Length(ItemName(Start, SIGDN_NORMALDISPLAY)) + 1);
  Result := True;
end;

function WantedOnDownload(const Name: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(Name));
  // a name without extension may just hide it (Explorer setting)
  Result := (Ext = '') or IsAudioFile(Name) or (Ext = '.jpg') or (Ext = '.jpeg') or (Ext = '.png') or
    (Ext = '.m3u') or (Ext = '.m3u8') or (Ext = '.lrc') or (Ext = '.cue');
end;

function MirrorFolderFor(const Title: string): string;
var
  S: string;
  I: Integer;
begin
  S := Title;
  for I := 1 to Length(S) do
    if S[I] in ['\', '/', ':', '*', '?', '"', '<', '>', '|'] then S[I] := '_';
  Result := IncludeTrailingPathDelimiter(SettingsDir) + 'Phone' + PathDelim + S;
end;

function FindMirrorRoot(const Dir: string): string;
var
  D, P: string;
begin
  Result := '';
  // a companion phone folder is never a mirror; asking Windows would be a slow network lookup
  if IsPhonePath(Dir) then Exit;
  D := ExcludeTrailingPathDelimiter(Dir);
  while D <> '' do
  begin
    if FileExists(IncludeTrailingPathDelimiter(D) + ManifestName) then Exit(D);
    P := ExtractFileDir(D);
    if (P = D) or (P = '') then Break;
    D := P;
  end;
  Result := '';
end;

procedure DeleteTree(const Dir: string);
var
  SR: TSearchRec;
  P: string;
begin
  P := IncludeTrailingPathDelimiter(Dir);
  if FindFirst(P + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then Continue;
      if SR.Attr and faDirectory <> 0 then DeleteTree(P + SR.Name)
      else
      begin
        FileSetAttr(P + SR.Name, 0);
        DeleteFile(P + SR.Name);
      end;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  RemoveDir(Dir);
end;

function DownloadPhoneFolder(Owner: HWND; const Parsing, Title, LocalRoot: string): string;
var
  Root: IShellItem;
  Op: IFileOperation;
  Sink: TOpSink;
  SinkRef: IFileOperationProgressSink;
  Pending, Lines: TStringList;
  Cookie: DWORD;
  Hr: HRESULT;
  I: Integer;
  Local, Rel, Src: string;

  // queues the copies of one folder's wanted files and walks its subfolders
  procedure Walk(Folder: IShellItem; const RelDir: string);
  var
    Kids: TInterfaceList;
    K: Integer;
    C, Dest: IShellItem;
    Name: string;
  begin
    ForceDirectories(IncludeTrailingPathDelimiter(LocalRoot) + RelDir);
    Lines.Add('D'#9 + RelDir + #9 + ItemParsing(Folder) + #9 + RelDir);
    Dest := ItemFrom(ExcludeTrailingPathDelimiter(IncludeTrailingPathDelimiter(LocalRoot) + RelDir));
    Kids := Children(Folder);
    try
      for K := 0 to Kids.Count - 1 do
      begin
        C := IShellItem(Kids[K]);
        Name := ItemName(C, SIGDN_NORMALDISPLAY);
        if (Name = '') or (Name[1] = '.') then Continue; // .thumbnails and the like
        if ItemIsFolder(C) then Walk(C, RelDir + Name + PathDelim)
        else if WantedOnDownload(Name) and (Dest <> nil) then
        begin
          Op.CopyItem(C, Dest, nil, nil);
          Pending.Add(ItemParsing(C) + '=' + RelDir);
        end;
      end;
    finally
      Kids.Free;
    end;
  end;

begin
  Result := '';
  Root := ItemFrom(Parsing);
  if Root = nil then Exit(rsMappenFindesIkkePaaTelefonen);
  if DirectoryExists(LocalRoot) then DeleteTree(LocalRoot);
  ForceDirectories(LocalRoot);
  Op := NewOperation(Owner, FOF_NOCONFIRMATION or FOF_NOCONFIRMMKDIR);
  if Op = nil then Exit(Format(rsKopieringMislykkedes, ['CoCreateInstance']));
  Sink := TOpSink.Create;
  SinkRef := Sink;
  Op.Advise(SinkRef, Cookie);
  Pending := TStringList.Create;
  Lines := TStringList.Create;
  try
    Lines.Add('R'#9 + Parsing + #9 + ItemName(Root, SIGDN_NORMALDISPLAY) + #9 + Title + #9 +
      ExtractFileName(ExcludeTrailingPathDelimiter(LocalRoot)));
    Walk(Root, '');
    if Pending.Count > 0 then
    begin
      Hr := Op.PerformOperations;
      if Failed(Hr) then Exit(Format(rsKopieringMislykkedes, [IntToHex(DWORD(Hr), 8)]));
    end;
    // the files that arrived, with their state as it is now
    for I := 0 to Pending.Count - 1 do
    begin
      Src := Pending.Names[I];
      Local := '';
      if Sink.Created.Values[Src] <> '' then
        Local := ItemName(ItemFrom(Sink.Created.Values[Src]), SIGDN_FILESYSPATH);
      if (Local = '') or not FileExists(Local) then Continue;
      Rel := Pending.ValueFromIndex[I] + ExtractFileName(Local);
      Lines.Add('F'#9 + Rel + #9 + Src + #9 + Rel + #9 + FileStamp(Local) + #9 +
        IntToStr(FileFingerprint(Local)));
    end;
    Lines.SaveToFile(IncludeTrailingPathDelimiter(LocalRoot) + ManifestName);
    FileSetAttr(IncludeTrailingPathDelimiter(LocalRoot) + ManifestName, faHidden);
  finally
    Op.Unadvise(Cookie);
    Pending.Free;
    Lines.Free;
  end;
end;

{ TPhoneMirror }

constructor TPhoneMirror.Create;
begin
  inherited Create;
  FPrevStamps := TStringList.Create;
  FQueued := TStringList.Create;
end;

destructor TPhoneMirror.Destroy;
begin
  FPrevStamps.Free;
  FQueued.Free;
  inherited Destroy;
end;

function TPhoneMirror.Owner: HWND;
begin
  Result := OwnerWnd;
end;

procedure TPhoneMirror.Load(const ARoot: string);
var
  L: TStringList;
  P: TStringArray;
  I: Integer;
  E: TPhoneEntry;
begin
  Root := ExcludeTrailingPathDelimiter(ARoot);
  FEntries := nil;
  FPrevStamps.Clear;
  L := TStringList.Create;
  try
    L.LoadFromFile(IncludeTrailingPathDelimiter(Root) + ManifestName);
    for I := 0 to L.Count - 1 do
    begin
      P := L[I].Split([#9]);
      if Length(P) < 4 then Continue;
      if P[0] = 'R' then
      begin
        RootParsing := P[1];
        RootPhoneName := P[2];
        Title := P[3];
        if Length(P) >= 5 then RootLocalName := P[4] else RootLocalName := ExtractFileName(Root);
        Continue;
      end;
      E.IsDir := P[0] = 'D';
      E.Rel := P[1];
      E.Parsing := P[2];
      E.PhoneRel := P[3];
      E.Stamp := '';
      E.Hash := 0;
      if (Length(P) >= 6) and not E.IsDir then
      begin
        E.Stamp := P[4];
        E.Hash := StrToQWordDef(P[5], 0);
      end;
      Insert(E, FEntries, Length(FEntries));
    end;
  finally
    L.Free;
  end;
end;

procedure TPhoneMirror.Save;
var
  L: TStringList;
  E: TPhoneEntry;
  F: string;
begin
  L := TStringList.Create;
  try
    L.Add('R'#9 + RootParsing + #9 + RootPhoneName + #9 + Title + #9 + RootLocalName);
    for E in FEntries do
      if E.IsDir then L.Add('D'#9 + E.Rel + #9 + E.Parsing + #9 + E.PhoneRel)
      else L.Add('F'#9 + E.Rel + #9 + E.Parsing + #9 + E.PhoneRel + #9 + E.Stamp + #9 + IntToStr(E.Hash));
    F := IncludeTrailingPathDelimiter(Root) + ManifestName;
    FileSetAttr(F, 0);
    L.SaveToFile(F);
    FileSetAttr(F, faHidden);
  finally
    L.Free;
  end;
end;

function TPhoneMirror.IndexOf(const Rel: string): Integer;
begin
  for Result := 0 to High(FEntries) do
    if SameText(FEntries[Result].Rel, Rel) then Exit;
  Result := -1;
end;

procedure TPhoneMirror.Renamed(const OldPath, NewPath: string);
var
  OldRel, NewRel, R: string;
  I: Integer;
begin
  if FBusy then
  begin
    FQueued.Add(OldPath + #9 + NewPath);
    Exit;
  end;
  R := IncludeTrailingPathDelimiter(Root);
  if SameText(ExcludeTrailingPathDelimiter(OldPath), Root) then
  begin
    // the mirror root itself: sent as a rename of the picked phone folder
    Root := ExcludeTrailingPathDelimiter(NewPath);
    Exit;
  end;
  if not SameText(Copy(OldPath, 1, Length(R)), R) or not SameText(Copy(NewPath, 1, Length(R)), R) then Exit;
  OldRel := Copy(OldPath, Length(R) + 1, MaxInt);
  NewRel := Copy(NewPath, Length(R) + 1, MaxInt);
  if DirectoryExists(NewPath) then
  begin
    OldRel := IncludeTrailingPathDelimiter(OldRel);
    NewRel := IncludeTrailingPathDelimiter(NewRel);
    for I := 0 to High(FEntries) do
      if SameText(Copy(FEntries[I].Rel, 1, Length(OldRel)), OldRel) then
        FEntries[I].Rel := NewRel + Copy(FEntries[I].Rel, Length(OldRel) + 1, MaxInt);
  end
  else
  begin
    I := IndexOf(OldRel);
    if I >= 0 then FEntries[I].Rel := NewRel;
  end;
  Save;
end;

{ The phone folder for RelDir ('' = root, else ending in '\'), created on the phone when
  missing. Ops is unused; folders are made one at a time so their items are known. }
{ Finds an item by its path on the phone, name by name from the picked folder. }
function TPhoneMirror.ResolvePhone(const PhoneRel: string): IShellItem;
var
  Part: string;
  Kids: TInterfaceList;
  K, Loose: Integer;
  N, Path: string;
begin
  Result := ItemFrom(RootParsing);
  Path := ExcludeTrailingPathDelimiter(PhoneRel);
  for Part in Path.Split([PathDelim]) do
  begin
    if Result = nil then Exit;
    Kids := Children(Result);
    try
      Result := nil;
      Loose := -1;
      for K := 0 to Kids.Count - 1 do
      begin
        N := ItemName(IShellItem(Kids[K]), SIGDN_NORMALDISPLAY);
        if SameText(N, Part) then
        begin
          Result := IShellItem(Kids[K]);
          Break;
        end;
        // Explorer may hide extensions
        if SameText(N, ChangeFileExt(Part, '')) then
          if Loose = -1 then Loose := K else Loose := -2;
      end;
      if (Result = nil) and (Loose >= 0) then Result := IShellItem(Kids[Loose]);
    finally
      Kids.Free;
    end;
  end;
end;

{ The phone item of entry I: by its stored key, else by name (a stored path goes stale when
  a parent folder is renamed). }
function TPhoneMirror.PhoneItem(I: Integer): IShellItem;
begin
  Result := ItemFrom(FEntries[I].Parsing);
  if (Result = nil) and (FEntries[I].PhoneRel <> '') then Result := ResolvePhone(FEntries[I].PhoneRel);
end;

function TPhoneMirror.FolderItem(const RelDir: string; Ops: Pointer; out Err: string): IShellItem;
var
  I: Integer;
  Parent: IShellItem;
  Name: string;
  Op: IFileOperation;
  Sink: TOpSink;
  SinkRef: IFileOperationProgressSink;
  Cookie: DWORD;
  E: TPhoneEntry;
begin
  Err := '';
  if RelDir = '' then Exit(ItemFrom(RootParsing));
  for I := 0 to High(FEntries) do
    if FEntries[I].IsDir and SameText(FEntries[I].PhoneRel, RelDir) then
    begin
      Result := PhoneItem(I);
      if Result = nil then Err := RelDir;
      Exit;
    end;
  Parent := FolderItem(ExtractFilePath(ExcludeTrailingPathDelimiter(RelDir)), nil, Err);
  if Parent = nil then Exit(nil);
  Name := ExtractFileName(ExcludeTrailingPathDelimiter(RelDir));
  Op := NewOperation(Owner, FOF_NOCONFIRMATION or FOF_NOCONFIRMMKDIR);
  Sink := TOpSink.Create;
  SinkRef := Sink;
  Op.Advise(SinkRef, Cookie);
  Op.NewItem(Parent, FILE_ATTRIBUTE_DIRECTORY, PWideChar(UTF8Decode(Name)), nil, nil);
  Op.PerformOperations;
  Op.Unadvise(Cookie);
  Result := ItemFrom(Sink.Created.Values[ItemParsing(Parent) + '\' + Name]);
  if Result = nil then
  begin
    Err := RelDir;
    Exit;
  end;
  E.IsDir := True;
  E.Rel := RelDir;
  E.PhoneRel := RelDir;
  E.Parsing := ItemParsing(Result);
  E.Stamp := '';
  E.Hash := 0;
  Insert(E, FEntries, Length(FEntries));
end;

function TPhoneMirror.Sync(Force: Boolean; Errors: TStrings): Integer;
var
  Q: TStringArray;
  I: Integer;
begin
  if FBusy then Exit(0);
  FBusy := True;
  try
    Result := DoSync(Force, Errors);
  finally
    FBusy := False;
  end;
  for I := 0 to FQueued.Count - 1 do
  begin
    Q := FQueued[I].Split([#9]);
    Renamed(Q[0], Q[1]);
  end;
  FQueued.Clear;
end;

function TPhoneMirror.DoSync(Force: Boolean; Errors: TStrings): Integer;
var
  I, J, K: Integer;
  Local, Stamp, Err, OldPhone, NewParsing: string;
  Item, Dest, RootItem: IShellItem;
  Op: IFileOperation;
  Sink: TOpSink;
  SinkRef: IFileOperationProgressSink;
  Cookie: DWORD;
  Known, Stamps: TStringList;
  E: TPhoneEntry;
  H: QWord;
  Copies: array of Integer;

  procedure NewFiles(const RelDir: string);
  var
    SR: TSearchRec;
  begin
    if FindFirst(IncludeTrailingPathDelimiter(Root) + RelDir + '*', faAnyFile, SR) = 0 then
    try
      repeat
        if (SR.Name = '.') or (SR.Name = '..') or (SR.Name = ManifestName) then Continue;
        if SR.Attr and faDirectory <> 0 then NewFiles(RelDir + SR.Name + PathDelim)
        else if (Known.IndexOf(RelDir + SR.Name) < 0) and (LowerCase(ExtractFileExt(SR.Name)) <> '.tmp') then
        begin
          E.IsDir := False;
          E.Rel := RelDir + SR.Name;
          E.PhoneRel := '';   // not on the phone yet
          E.Parsing := '';
          E.Stamp := '';
          E.Hash := 0;
          Insert(E, FEntries, Length(FEntries));
        end;
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  end;

  function StartOp: Boolean;
  begin
    Op := NewOperation(Owner, FOF_NOCONFIRMATION or FOF_NOCONFIRMMKDIR or FOFX_EARLYFAILURE);
    Result := Op <> nil;
    if not Result then Exit;
    Sink := TOpSink.Create;
    SinkRef := Sink;
    Op.Advise(SinkRef, Cookie);
  end;

  procedure EndOp;
  var
    J: Integer;
  begin
    Op.PerformOperations;
    Op.Unadvise(Cookie);
    for J := 0 to Sink.Errors.Count - 1 do Errors.Add(Sink.Errors[J]);
  end;

begin
  Result := 0;
  RootItem := ItemFrom(RootParsing);
  if RootItem = nil then
  begin
    Errors.Add(rsMappenFindesIkkePaaTelefonen);
    Exit;
  end;
  Known := TStringList.Create;
  Stamps := TStringList.Create;
  try
    Known.CaseSensitive := False;
    for E in FEntries do
      if not E.IsDir then Known.Add(E.Rel);
    NewFiles('');

    // 1. the picked folder itself was renamed
    // only a rename done here counts: the working copy's name may differ from the phone's
    if not SameText(ExtractFileName(Root), RootLocalName) and StartOp then
    begin
      Op.RenameItem(RootItem, PWideChar(UTF8Decode(ExtractFileName(Root))), nil);
      EndOp;
      NewParsing := Sink.Created.Values[RootParsing];
      if NewParsing <> '' then
      begin
        RootParsing := NewParsing;
        RootPhoneName := ExtractFileName(Root);
        RootLocalName := RootPhoneName;
        Title := ExtractFilePath(Title) + RootPhoneName;
        Inc(Result);
      end;
      Save;
      RootItem := ItemFrom(RootParsing);
    end;

    // 2. folders renamed or moved, parents first
    for K := 1 to 32 do
      for I := 0 to High(FEntries) do
        if FEntries[I].IsDir and (FEntries[I].Rel <> FEntries[I].PhoneRel) and
          (Length(FEntries[I].Rel.Split([PathDelim])) = K + 1) then
        begin
          Item := PhoneItem(I);
          Dest := FolderItem(ExtractFilePath(ExcludeTrailingPathDelimiter(FEntries[I].Rel)), nil, Err);
          if (Item = nil) or (Dest = nil) then
          begin
            Errors.Add(Format(rsFindesIkke, [FEntries[I].PhoneRel]));
            Continue;
          end;
          if not StartOp then Continue;
          if SameText(ExtractFilePath(ExcludeTrailingPathDelimiter(FEntries[I].Rel)),
            ExtractFilePath(ExcludeTrailingPathDelimiter(FEntries[I].PhoneRel))) then
            Op.RenameItem(Item, PWideChar(UTF8Decode(ExtractFileName(ExcludeTrailingPathDelimiter(FEntries[I].Rel)))), nil)
          else
            Op.MoveItem(Item, Dest, PWideChar(UTF8Decode(ExtractFileName(ExcludeTrailingPathDelimiter(FEntries[I].Rel)))), nil);
          EndOp;
          NewParsing := Sink.Created.Values[FEntries[I].Parsing];
          if NewParsing = '' then Continue;
          // the files and folders inside went along
          OldPhone := FEntries[I].PhoneRel;
          for J := 0 to High(FEntries) do
            if (J <> I) and SameText(Copy(FEntries[J].PhoneRel, 1, Length(OldPhone)), OldPhone) then
              FEntries[J].PhoneRel := FEntries[I].Rel + Copy(FEntries[J].PhoneRel, Length(OldPhone) + 1, MaxInt);
          FEntries[I].Parsing := NewParsing;
          FEntries[I].PhoneRel := FEntries[I].Rel;
          Inc(Result);
          Save;
        end;

    // 3. files: renamed/moved, and changed content
    Copies := nil;
    for I := 0 to High(FEntries) do
    begin
      if FEntries[I].IsDir then Continue;
      Local := IncludeTrailingPathDelimiter(Root) + FEntries[I].Rel;
      if not FileExists(Local) then Continue; // deleted or moved out here: left alone on the phone
      Stamp := FileStamp(Local);
      Stamps.Values[FEntries[I].Rel] := Stamp;
      if (FEntries[I].Parsing <> '') and (FEntries[I].Rel <> FEntries[I].PhoneRel) then
      begin
        Item := PhoneItem(I);
        Dest := FolderItem(ExtractFilePath(FEntries[I].Rel), nil, Err);
        if Item = nil then Errors.Add(Format(rsFindesIkke, [FEntries[I].PhoneRel]));
        if Err <> '' then Errors.Add(Err);
        if (Item <> nil) and (Dest <> nil) and StartOp then
        begin
          if SameText(ExtractFilePath(FEntries[I].Rel), ExtractFilePath(FEntries[I].PhoneRel)) then
            Op.RenameItem(Item, PWideChar(UTF8Decode(ExtractFileName(FEntries[I].Rel))), nil)
          else
            Op.MoveItem(Item, Dest, PWideChar(UTF8Decode(ExtractFileName(FEntries[I].Rel))), nil);
          EndOp;
          NewParsing := Sink.Created.Values[FEntries[I].Parsing];
          if NewParsing <> '' then
          begin
            FEntries[I].Parsing := NewParsing;
            FEntries[I].PhoneRel := FEntries[I].Rel;
            Inc(Result);
            Save;
          end;
        end;
      end;
      if Stamp = FEntries[I].Stamp then Continue;
      // send only what has stopped changing (a save may still be writing)
      if not Force and (FPrevStamps.Values[FEntries[I].Rel] <> Stamp) then Continue;
      H := FileFingerprint(Local);
      if (FEntries[I].Parsing <> '') and (H = FEntries[I].Hash) then
      begin
        FEntries[I].Stamp := Stamp; // touched, not changed
        Continue;
      end;
      Insert(I, Copies, Length(Copies));
    end;
    FPrevStamps.Assign(Stamps);

    for I in Copies do
    begin
      Local := IncludeTrailingPathDelimiter(Root) + FEntries[I].Rel;
      Item := ItemFrom(Local);
      Dest := FolderItem(ExtractFilePath(FEntries[I].Rel), nil, Err);
      if Err <> '' then Errors.Add(Err);
      if Dest = nil then Errors.Add(Format(rsFindesIkke, [ExtractFilePath(FEntries[I].Rel)]));
      if (Item = nil) or (Dest = nil) or not StartOp then Continue;
      Stamp := FileStamp(Local);
      H := FileFingerprint(Local);
      Op.CopyItem(Item, Dest, nil, nil); // replaces the phone's file of the same name
      EndOp;
      NewParsing := Sink.Created.Values[ItemParsing(Item)];
      if NewParsing = '' then Continue;
      FEntries[I].Parsing := NewParsing;
      FEntries[I].PhoneRel := FEntries[I].Rel;
      FEntries[I].Stamp := Stamp;
      FEntries[I].Hash := H;
      Inc(Result);
      Save;
    end;
    Save;
  finally
    Known.Free;
    Stamps.Free;
  end;
end;

initialization
  CoInitialize(nil);
end.
