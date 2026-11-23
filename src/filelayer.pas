unit FileLayer;

{ One way to open and change files for local paths and for files on a phone running
  TidyTag Companion. Phone paths look like network paths:
    \\TidyTag-Phone\<phone name>\Music\Rock\song.mp3
  so TidyTag's path functions keep working; everything else goes to the phone over the
  network (PhoneClient). Local paths behave exactly as before.
  Reads fetch only the bytes that are needed (plus what PrefetchTags got for a folder in
  one request); writes are sent as byte ranges; a copy between two phone files is done by
  the phone. No LCL. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, PhoneClient;

const
  PhonePrefix = '\\TidyTag-Phone\';

function IsPhonePath(const Path: string): Boolean;
{ Phone file names may hold characters Windows forbids (\ : * ? " < > |); in TidyTag paths
  they become private-use characters (U+F000 + code, as WSL does) and back again. }
function PhoneToLocalName(const Name: string): string;
function LocalToPhoneName(const Name: string): string;
{ The connected phone for a phone path; raises EPhoneError when it cannot be reached. }
function PhoneForPath(const Path: string): TPhone;
{ Forgets connections (after pairing changes or a lost phone). }
procedure ResetPhones;

function OpenFileStream(const FileName: string; Mode: Word): TStream;
function FileExistsL(const FileName: string): Boolean;
function DirectoryExistsL(const Dir: string): Boolean;
function RenameFileL(const OldName, NewName: string): Boolean;
{ A real delete locally; on a phone only TidyTag's own temporary files are "deleted" (the
  app removes them at the next listing), anything else goes to the trash. }
function DeleteFileL(const FileName: string): Boolean;
{ Phone files to Android's trash; returns the paths that were not trashed (non-media files,
  and every local path: those go to the Recycle Bin through FileOps). }
function TrashFiles(const Files: array of string): TStringArray;
function ForceDirectoriesL(const Dir: string): Boolean;
function ListDirL(const Dir: string): TPhoneEntries;
{ Fetches the start and end of many phone files in one request, for reading their tags. }
procedure PrefetchTags(const Files: array of string);
{ Modified time in ms since 1970 (phone paths only). }
function GetPhoneMTime(const FileName: string; out Ms: Int64): Boolean;
procedure SetPhoneMTime(const FileName: string; Ms: Int64);
{ TagUtils.ReplaceFileWith for phone paths: an atomic rename over the target. }
procedure ReplacePhoneFile(const TempName, Target: string);
{ TagUtils.CopyStreamRange: True when it could let the phone copy (both streams on one phone). }
function CopyOnPhone(Src, Dst: TStream; From, Count: Int64): Boolean;

implementation

uses
  SyncObjs;

resourcestring
  rsTelefonIkkeFundet = 'Telefonen "%s" er ikke parret eller kan ikke nås. Start TidyTag Companion på telefonen.';
  rsKunLaesning = 'Filen er åbnet kun til læsning';

const
  BlockSize = 65536;
  FlushAt = 1024 * 1024;
  PeekHead = 65536;
  PeekTail = 8192;
  Forbidden = '\:*?"<>|';

type
  TPeekEntry = class
    Size: Int64;
    Head, Tail: TBytes;
  end;

  TPending = record
    Offset: Int64;
    Data: TBytes;
  end;

  TPhoneStream = class(TStream)
  private
    FPhone: TPhone;
    FPath, FRel: string;
    FPos, FSize: Int64;
    FWritable: Boolean;
    FHead, FTail, FWin: TBytes;
    FTailStart, FWinStart: Int64;
    FPending: array of TPending;
    FPendingBytes: Int64;
    procedure DropCaches;
  protected
    function GetSize: Int64; override;
    procedure SetSize(const NewSize: Int64); override;
  public
    constructor Create(const Path: string; Mode: Word);
    destructor Destroy; override;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
    procedure Flush;
    procedure CopyRangeFrom(Src: TPhoneStream; From, Count: Int64);
  end;

var
  Lock: TCriticalSection;
  Phones: TStringList;   // name -> TPhone
  Peeks: TStringList;    // path -> TPeekEntry

{ Names and paths }

function IsPhonePath(const Path: string): Boolean;
begin
  Result := SameText(Copy(Path, 1, Length(PhonePrefix)), PhonePrefix);
end;

{ Byte by byte on the UTF-8 text, so the string's code page is never touched:
  a forbidden ASCII character c becomes U+F000 + c (EF 80/81 xx in UTF-8). }
function PhoneToLocalName(const Name: string): string;
var
  I, C: Integer;
begin
  Result := '';
  for I := 1 to Length(Name) do
    if Pos(Name[I], Forbidden) > 0 then
    begin
      C := $F000 + Ord(Name[I]);
      Result := Result + Char($E0 or (C shr 12)) + Char($80 or ((C shr 6) and $3F)) + Char($80 or (C and $3F));
    end
    else
      Result := Result + Name[I];
end;

function LocalToPhoneName(const Name: string): string;
var
  I, C: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(Name) do
  begin
    if (I + 2 <= Length(Name)) and (Name[I] = #$EF) and (Name[I + 1] in [#$80, #$81]) then
    begin
      C := ((Ord(Name[I + 1]) and $3F) shl 6) or (Ord(Name[I + 2]) and $3F);
      if (C < 128) and (Pos(Char(C), Forbidden) > 0) then
      begin
        Result := Result + Char(C);
        Inc(I, 3);
        Continue;
      end;
    end;
    Result := Result + Name[I];
    Inc(I);
  end;
end;

{ '\\TidyTag-Phone\Pixel\Music\a.mp3' -> 'Pixel', 'Music/a.mp3' }
procedure SplitPhonePath(const Path: string; out PhoneName, Rel: string);
var
  Rest: string;
  Parts: TStringArray;
  I: Integer;
begin
  Rest := ExcludeTrailingPathDelimiter(Copy(Path, Length(PhonePrefix) + 1, MaxInt));
  I := Pos('\', Rest);
  if I = 0 then
  begin
    PhoneName := Rest;
    Rel := '';
    Exit;
  end;
  PhoneName := Copy(Rest, 1, I - 1);
  Parts := Copy(Rest, I + 1, MaxInt).Split(['\']);
  Rel := '';
  for I := 0 to High(Parts) do
  begin
    if I > 0 then Rel := Rel + '/';
    Rel := Rel + LocalToPhoneName(Parts[I]);
  end;
end;

function RelOf(const Path: string): string;
var
  N: string;
begin
  SplitPhonePath(Path, N, Result);
end;

function PhoneForPath(const Path: string): TPhone;
var
  Name, Rel: string;
  I: Integer;
begin
  SplitPhonePath(Path, Name, Rel);
  Lock.Enter;
  try
    I := Phones.IndexOf(Name);
    if I >= 0 then Exit(TPhone(Phones.Objects[I]));
    Result := PhoneByName(Name);
    if Result = nil then raise EPhoneError.CreateFmt(rsTelefonIkkeFundet, [Name]);
    Phones.AddObject(Name, Result);
  finally
    Lock.Leave;
  end;
end;

procedure ResetPhones;
var
  I: Integer;
begin
  Lock.Enter;
  try
    for I := 0 to Phones.Count - 1 do Phones.Objects[I].Free;
    Phones.Clear;
    for I := 0 to Peeks.Count - 1 do Peeks.Objects[I].Free;
    Peeks.Clear;
  finally
    Lock.Leave;
  end;
end;

procedure ForgetPeek(const Path: string);
var
  I: Integer;
begin
  Lock.Enter;
  try
    I := Peeks.IndexOf(Path);
    if I >= 0 then
    begin
      Peeks.Objects[I].Free;
      Peeks.Delete(I);
    end;
  finally
    Lock.Leave;
  end;
end;

{ TPhoneStream }

constructor TPhoneStream.Create(const Path: string; Mode: Word);
var
  E: TPhoneEntry;
  I: Integer;
  P: TPeekEntry;
begin
  inherited Create;
  FPhone := PhoneForPath(Path);
  FPath := Path;
  FRel := RelOf(Path);
  FWritable := (Mode and 3 <> fmOpenRead) or (Mode and fmCreate = fmCreate);
  Lock.Enter;
  try
    if Mode and fmCreate = fmCreate then
    begin
      FPhone.CreateFile(FRel);
      FSize := 0;
    end
    else
    begin
      if not FPhone.Stat(FRel, E) or E.IsDir then
        raise EFOpenError.CreateFmt('Unable to open file "%s"', [Path]);
      FSize := E.Size;
      // what PrefetchTags already fetched for a read
      I := Peeks.IndexOf(Path);
      if (I >= 0) and not FWritable then
      begin
        P := TPeekEntry(Peeks.Objects[I]);
        if P.Size = FSize then
        begin
          FHead := Copy(P.Head);
          FTail := Copy(P.Tail);
          FTailStart := FSize - Length(FTail);
        end;
      end;
    end;
  finally
    Lock.Leave;
  end;
  if FWritable then ForgetPeek(Path);
end;

destructor TPhoneStream.Destroy;
begin
  try
    Flush; // a failed write must reach the caller as an error, not be lost
  finally
    if FWritable then ForgetPeek(FPath);
    inherited Destroy;
  end;
end;

procedure TPhoneStream.DropCaches;
begin
  FHead := nil;
  FTail := nil;
  FWin := nil;
end;

function TPhoneStream.GetSize: Int64;
begin
  Result := FSize;
end;

procedure TPhoneStream.SetSize(const NewSize: Int64);
begin
  if not FWritable then raise EStreamError.Create(rsKunLaesning);
  Flush;
  Lock.Enter;
  try
    FPhone.Truncate(FRel, NewSize);
  finally
    Lock.Leave;
  end;
  FSize := NewSize;
  DropCaches;
end;

function TPhoneStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  case Origin of
    soBeginning: FPos := Offset;
    soCurrent: Inc(FPos, Offset);
    soEnd: FPos := FSize + Offset;
  end;
  Result := FPos;
end;

function TPhoneStream.Read(var Buffer; Count: Longint): Longint;
var
  Dest: PByte;
  N, Take: Int64;
  Start, Len: Int64;
begin
  Result := 0;
  if FPending <> nil then Flush;
  if (Count <= 0) or (FPos >= FSize) then Exit;
  N := Count;
  if FPos + N > FSize then N := FSize - FPos;
  Dest := @Buffer;
  while N > 0 do
  begin
    if FPos < Length(FHead) then
    begin
      Take := Length(FHead) - FPos;
      if Take > N then Take := N;
      Move(FHead[FPos], Dest^, Take);
    end
    else if (FTail <> nil) and (FPos >= FTailStart) then
    begin
      Take := FSize - FPos;
      if Take > N then Take := N;
      Move(FTail[FPos - FTailStart], Dest^, Take);
    end
    else if (FWin <> nil) and (FPos >= FWinStart) and (FPos < FWinStart + Length(FWin)) then
    begin
      Take := FWinStart + Length(FWin) - FPos;
      if Take > N then Take := N;
      Move(FWin[FPos - FWinStart], Dest^, Take);
    end
    else
    begin
      // one request for everything still needed, in whole blocks
      Start := FPos - FPos mod BlockSize;
      Len := ((FPos + N - Start + BlockSize - 1) div BlockSize) * BlockSize;
      if Start + Len > FSize then Len := FSize - Start;
      Lock.Enter;
      try
        FWin := FPhone.Read(FRel, Start, Len);
      finally
        Lock.Leave;
      end;
      FWinStart := Start;
      if Length(FWin) = 0 then Break;
      Continue;
    end;
    Inc(Dest, Take);
    Inc(FPos, Take);
    Inc(Result, Take);
    Dec(N, Take);
  end;
end;

function TPhoneStream.Write(const Buffer; Count: Longint): Longint;
var
  L: Integer;
begin
  if not FWritable then raise EStreamError.Create(rsKunLaesning);
  Result := Count;
  if Count <= 0 then Exit;
  DropCaches;
  L := High(FPending);
  if (L >= 0) and (FPending[L].Offset + Length(FPending[L].Data) = FPos) then
  begin
    SetLength(FPending[L].Data, Length(FPending[L].Data) + Count);
    Move(Buffer, FPending[L].Data[Length(FPending[L].Data) - Count], Count);
  end
  else
  begin
    SetLength(FPending, L + 2);
    FPending[L + 1].Offset := FPos;
    SetLength(FPending[L + 1].Data, Count);
    Move(Buffer, FPending[L + 1].Data[0], Count);
  end;
  Inc(FPos, Count);
  if FPos > FSize then FSize := FPos;
  Inc(FPendingBytes, Count);
  if FPendingBytes >= FlushAt then Flush;
end;

procedure TPhoneStream.Flush;
var
  I: Integer;
begin
  if FPending = nil then Exit;
  Lock.Enter;
  try
    for I := 0 to High(FPending) do FPhone.Write(FRel, FPending[I].Offset, FPending[I].Data);
  finally
    Lock.Leave;
  end;
  FPending := nil;
  FPendingBytes := 0;
end;

procedure TPhoneStream.CopyRangeFrom(Src: TPhoneStream; From, Count: Int64);
begin
  Flush;
  Src.Flush;
  Lock.Enter;
  try
    FPhone.CopyRange(Src.FRel, From, Count, FRel, FPos);
  finally
    Lock.Leave;
  end;
  Inc(FPos, Count);
  if FPos > FSize then FSize := FPos;
  DropCaches;
end;

function CopyOnPhone(Src, Dst: TStream; From, Count: Int64): Boolean;
begin
  Result := (Src is TPhoneStream) and (Dst is TPhoneStream) and
    (TPhoneStream(Src).FPhone = TPhoneStream(Dst).FPhone);
  if Result then TPhoneStream(Dst).CopyRangeFrom(TPhoneStream(Src), From, Count);
end;

{ Operations }

function OpenFileStream(const FileName: string; Mode: Word): TStream;
begin
  if IsPhonePath(FileName) then Result := TPhoneStream.Create(FileName, Mode)
  else Result := TFileStream.Create(FileName, Mode);
end;

function PhoneStat(const Path: string; out E: TPhoneEntry): Boolean;
var
  P: TPhone;
begin
  try
    P := PhoneForPath(Path);
    Lock.Enter;
    try
      Result := P.Stat(RelOf(Path), E);
    finally
      Lock.Leave;
    end;
  except
    on EPhoneError do Result := False;
  end;
end;

function FileExistsL(const FileName: string): Boolean;
var
  E: TPhoneEntry;
begin
  if not IsPhonePath(FileName) then Exit(FileExists(FileName));
  Result := PhoneStat(FileName, E) and not E.IsDir;
end;

function DirectoryExistsL(const Dir: string): Boolean;
var
  E: TPhoneEntry;
begin
  if not IsPhonePath(Dir) then Exit(DirectoryExists(Dir));
  Result := PhoneStat(Dir, E) and E.IsDir;
end;

function RenameFileL(const OldName, NewName: string): Boolean;
var
  P: TPhone;
begin
  if IsPhonePath(OldName) <> IsPhonePath(NewName) then Exit(False); // not between the PC and a phone
  if not IsPhonePath(OldName) then Exit(RenameFile(OldName, NewName));
  try
    P := PhoneForPath(OldName);
    if P <> PhoneForPath(NewName) then Exit(False);
    Lock.Enter;
    try
      P.Rename(RelOf(OldName), RelOf(NewName), False);
    finally
      Lock.Leave;
    end;
    ForgetPeek(OldName);
    Result := True;
  except
    on EPhoneError do Result := False;
  end;
end;

function DeleteFileL(const FileName: string): Boolean;
begin
  if not IsPhonePath(FileName) then Exit(DeleteFile(FileName));
  if SameText(ExtractFileExt(FileName), '.tidytag-tmp') then Exit(True);
  Result := Length(TrashFiles([FileName])) = 0;
end;

function TrashFiles(const Files: array of string): TStringArray;
var
  F: string;
  Refused: TStringArray;
  P: TPhone;
begin
  Result := nil;
  begin
    for F in Files do
    begin
      if not IsPhonePath(F) then
      begin
        Insert(F, Result, Length(Result));
        Continue;
      end;
      try
        P := PhoneForPath(F);
      except
        on EPhoneError do
        begin
          Insert(F, Result, Length(Result));
          Continue;
        end;
      end;
      Lock.Enter;
      try
        Refused := P.Trash([RelOf(F)]);
      finally
        Lock.Leave;
      end;
      if Length(Refused) > 0 then Insert(F, Result, Length(Result)) else ForgetPeek(F);
    end;
  end;
end;

function ForceDirectoriesL(const Dir: string): Boolean;
var
  P: TPhone;
begin
  if not IsPhonePath(Dir) then Exit(ForceDirectories(Dir));
  try
    P := PhoneForPath(Dir);
    Lock.Enter;
    try
      P.MakeDir(RelOf(Dir));
    finally
      Lock.Leave;
    end;
    Result := True;
  except
    on EPhoneError do Result := False;
  end;
end;

function ListDirL(const Dir: string): TPhoneEntries;
var
  SR: TSearchRec;
  E: TPhoneEntry;
  P: TPhone;
  I: Integer;
begin
  Result := nil;
  if IsPhonePath(Dir) then
  begin
    P := PhoneForPath(Dir);
    Lock.Enter;
    try
      Result := P.List(RelOf(Dir));
    finally
      Lock.Leave;
    end;
    for I := 0 to High(Result) do Result[I].Name := PhoneToLocalName(Result[I].Name);
    Exit;
  end;
  if FindFirst(IncludeTrailingPathDelimiter(Dir) + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then Continue;
      E.Name := SR.Name;
      E.IsDir := SR.Attr and faDirectory <> 0;
      E.Size := SR.Size;
      E.MTime := Round((FileDateToDateTime(SR.Time) - EncodeDate(1970, 1, 1)) * 86400000);
      Insert(E, Result, Length(Result));
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

procedure PrefetchTags(const Files: array of string);
var
  F: string;
  P, Q: TPhone;
  Rels, Paths: TStringArray;

  procedure Fetch;
  var
    R: TPhonePeeks;
    I, K, J: Integer;
    E: TPeekEntry;
  begin
    if Rels = nil then Exit;
    Lock.Enter;
    try
      R := P.Peek(Rels, PeekHead, PeekTail);
      for I := 0 to High(R) do
        for K := 0 to High(Rels) do
          if Rels[K] = R[I].Path then
          begin
            E := TPeekEntry.Create;
            E.Size := R[I].Size;
            E.Head := R[I].Head;
            E.Tail := R[I].Tail;
            J := Peeks.IndexOf(Paths[K]);
            if J >= 0 then
            begin
              Peeks.Objects[J].Free;
              Peeks.Delete(J);
            end;
            Peeks.AddObject(Paths[K], E);
            Break;
          end;
    finally
      Lock.Leave;
    end;
    Rels := nil;
    Paths := nil;
  end;

begin
  P := nil;
  Rels := nil;
  Paths := nil;
  for F in Files do
  begin
    if not IsPhonePath(F) then Continue;
    try
      Q := PhoneForPath(F);
    except
      on EPhoneError do Continue;
    end;
    if (Q <> P) or (Length(Rels) >= 100) then
    begin
      Fetch;
      P := Q;
    end;
    Insert(RelOf(F), Rels, Length(Rels));
    Insert(F, Paths, Length(Paths));
  end;
  Fetch;
end;

function GetPhoneMTime(const FileName: string; out Ms: Int64): Boolean;
var
  E: TPhoneEntry;
begin
  Result := PhoneStat(FileName, E);
  if Result then Ms := E.MTime else Ms := 0;
end;

procedure SetPhoneMTime(const FileName: string; Ms: Int64);
var
  P: TPhone;
begin
  P := PhoneForPath(FileName);
  Lock.Enter;
  try
    P.SetMTime(RelOf(FileName), Ms);
  finally
    Lock.Leave;
  end;
end;

procedure ReplacePhoneFile(const TempName, Target: string);
var
  P: TPhone;
begin
  P := PhoneForPath(Target);
  Lock.Enter;
  try
    P.Rename(RelOf(TempName), RelOf(Target), True);
  finally
    Lock.Leave;
  end;
  ForgetPeek(Target);
end;

initialization
  Lock := TCriticalSection.Create;
  Phones := TStringList.Create;
  Peeks := TStringList.Create;
  Peeks.CaseSensitive := True;

finalization
  ResetPhones;
  Phones.Free;
  Peeks.Free;
  Lock.Free;
end.
