program filelayertest;

{ File layer checks: phone paths served by the companion's desktop jar over a scratch
  folder, and local paths unchanged.
  Usage: filelayertest <work folder> <companion-desktop.jar> <java.exe> }

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, Process, PhoneClient, FileLayer, TagUtils;

const
  Port = 47240;
  DiscoveryPort = 47241;

var
  Failures: Integer = 0;
  Checks: Integer = 0;
  Work, Root, Jar, Java, P: string;
  Server: TProcess = nil;

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

procedure StartServer;
var
  T: QWord;
begin
  Server := TProcess.Create(nil);
  Server.Executable := Java;
  Server.Parameters.AddStrings(['-jar', Jar, '--root', Root, '--port', IntToStr(Port), '--token', 'tok',
    '--discovery', IntToStr(DiscoveryPort), '--name', 'Testtelefon', '--id', 'dev-1']);
  Server.Options := [poNoConsole];
  Server.Execute;
  T := GetTickCount64;
  while (Length(DiscoverPhones(300, DiscoveryPort)) = 0) and (GetTickCount64 - T < 15000) do ;
end;

procedure StopServer;
begin
  if Server = nil then Exit;
  Server.Terminate(0);
  Server.WaitOnExit;
  FreeAndNil(Server);
end;

function Pattern(Size, Seed: Integer): TBytes;
var
  I: Integer;
begin
  SetLength(Result, Size);
  for I := 0 to Size - 1 do Result[I] := Byte((I + Seed) mod 251);
end;

procedure SaveBytes(const Name: string; const B: TBytes);
var
  S: TFileStream;
begin
  ForceDirectories(ExtractFileDir(Name));
  S := TFileStream.Create(Name, fmCreate);
  try
    if Length(B) > 0 then S.WriteBuffer(B[0], Length(B));
  finally
    S.Free;
  end;
end;

function LoadBytes(const Name: string): TBytes;
var
  S: TFileStream;
begin
  S := TFileStream.Create(Name, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, S.Size);
    if S.Size > 0 then S.ReadBuffer(Result[0], S.Size);
  finally
    S.Free;
  end;
end;

function Same(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

procedure TestPaths;
begin
  WriteLn('== paths');
  Check(IsPhonePath(P + 'Music\a.mp3') and not IsPhonePath('C:\Music\a.mp3'), 'phone paths are recognised');
  Check(PhoneToLocalName('Hvad?.mp3') <> 'Hvad?.mp3', '? is mapped to a Windows-safe character');
  Check(LocalToPhoneName(PhoneToLocalName('A:B*"<>|?.mp3')) = 'A:B*"<>|?.mp3', 'forbidden characters round-trip');
  Check(ExtractFileName(P + 'Music\' + PhoneToLocalName('A:B.mp3')) = PhoneToLocalName('A:B.mp3'),
    'a mapped name stays one file name');
  Check(PhoneToLocalName('Æblegrød & co (100%).mp3') = 'Æblegrød & co (100%).mp3', 'allowed characters unchanged');
end;

procedure TestReadAcrossBlocks;
var
  S: TStream;
  B: TBytes;
begin
  WriteLn('== reading');
  SaveBytes(Root + 'Music\blocks.bin', Pattern(200000, 0));
  S := OpenFileStream(P + 'Music\blocks.bin', fmOpenRead);
  try
    Check(S.Size = 200000, 'size');
    S.Position := 65500;
    SetLength(B, 100);
    Check(S.Read(B[0], 100) = 100, 'read across a block border');
    Check(Same(B, Copy(Pattern(200000, 0), 65500, 100)), 'the right bytes');
    S.Position := 199990;
    Check(S.Read(B[0], 100) = 10, 'read stops at the end');
  finally
    S.Free;
  end;
  Check(FileExistsL(P + 'Music\blocks.bin') and not FileExistsL(P + 'Music\none.bin'), 'FileExistsL');
  Check(DirectoryExistsL(P + 'Music') and not DirectoryExistsL(P + 'Music\blocks.bin'), 'DirectoryExistsL');
end;

procedure TestInPlaceWrite;
var
  S: TStream;
  B, Want: TBytes;
begin
  WriteLn('== writing in place');
  SaveBytes(Root + 'Music\w.bin', Pattern(1000, 3));
  S := OpenFileStream(P + 'Music\w.bin', fmOpenReadWrite);
  try
    S.Position := 10;
    S.WriteBuffer(TBytes.Create(7, 8, 9)[0], 3);
    S.Position := 0;
    SetLength(B, 14);
    S.ReadBuffer(B[0], 14);
    Check((B[10] = 7) and (B[12] = 9), 'a write is read back through the same stream');
  finally
    S.Free;
  end;
  Want := Pattern(1000, 3);
  Want[10] := 7; Want[11] := 8; Want[12] := 9;
  Check(Same(LoadBytes(Root + 'Music\w.bin'), Want), 'the phone file has exactly the change');
end;

procedure TestServerSideCopy;
var
  Src, Dst: TStream;
  Phone: TPhone;
  Before: Int64;
  Orig, Tag, Want: TBytes;
begin
  WriteLn('== rewrite without sending the audio');
  Orig := Pattern(5000000, 11);
  SaveBytes(Root + 'Music\big.mp3', Orig);
  Tag := Pattern(300000, 99);
  Phone := PhoneForPath(P + 'Music\big.mp3');
  Before := Phone.BytesSent;
  // the writers' rewrite: new tag into a temporary file, the audio copied, then replace
  Src := OpenFileStream(P + 'Music\big.mp3', fmOpenRead);
  try
    Dst := OpenFileStream(TempFileFor(P + 'Music\big.mp3'), fmCreate);
    try
      Dst.WriteBuffer(Tag[0], Length(Tag));
      CopyStreamRange(Src, Dst, 1000, Src.Size - 1000);
    finally
      Dst.Free;
    end;
  finally
    Src.Free;
  end;
  ReplaceFileWith(TempFileFor(P + 'Music\big.mp3'), P + 'Music\big.mp3');
  WriteLn('   bytes sent: ', Phone.BytesSent - Before);
  Check(Phone.BytesSent - Before < 400000, 'less than 400 KB sent for a 5 MB file');
  Want := Concat(Tag, Copy(Orig, 1000, Length(Orig)));
  Check(Same(LoadBytes(Root + 'Music\big.mp3'), Want), 'the file is the new tag plus the audio');
  Check(not FileExists(Root + 'Music\big.mp3.tidytag-tmp'), 'no temporary file left');
end;

procedure TestCacheFresh;
var
  S: TStream;
  B: TBytes;
begin
  WriteLn('== cache');
  SaveBytes(Root + 'Music\c.mp3', Pattern(3000, 0));
  PrefetchTags([P + 'Music\c.mp3']);
  S := OpenFileStream(P + 'Music\c.mp3', fmOpenReadWrite);
  try
    S.Position := 0;
    S.WriteBuffer(TBytes.Create(42)[0], 1);
  finally
    S.Free;
  end;
  S := OpenFileStream(P + 'Music\c.mp3', fmOpenRead);
  try
    SetLength(B, 1);
    S.ReadBuffer(B[0], 1);
    Check(B[0] = 42, 'a new stream sees the write, not the prefetched bytes');
  finally
    S.Free;
  end;
end;

procedure TestRenamesAndList;
var
  L: TPhoneEntries;
  E: TPhoneEntry;
  Found: Boolean;
begin
  WriteLn('== rename, folders, listing');
  SaveBytes(Root + 'Music\r.mp3', Pattern(10, 0));
  Check(ForceDirectoriesL(P + 'Music\Ny\Under'), 'ForceDirectoriesL');
  Check(RenameFileL(P + 'Music\r.mp3', P + 'Music\Ny\Under\Æblegrød & co (100%).mp3'), 'RenameFileL into the new folder');
  Check(FileExists(Root + 'Music\Ny\Under\Æblegrød & co (100%).mp3'), 'renamed on the phone');
  Check(not RenameFileL(P + 'Music\w.bin', 'C:\x.bin'), 'no rename between the phone and the PC');
  L := ListDirL(P + 'Music\Ny\Under');
  Found := False;
  for E in L do
    if E.Name = 'Æblegrød & co (100%).mp3' then Found := True;
  Check(Found, 'ListDirL on the phone');
  Check(DeleteFileL(TempFileFor(P + 'Music\x.mp3')), 'deleting a temporary file is accepted');
  Check(Length(TrashFiles([P + 'Music\w.bin'])) = 1, 'trash refused by the desktop storage: kept');
  Check(FileExists(Root + 'Music\w.bin'), 'still there');
end;

procedure TestStamp;
var
  St: TFileStamp;
begin
  WriteLn('== keep file date');
  SaveBytes(Root + 'Music\d.mp3', Pattern(10, 0));
  FileSetDate(Root + 'Music\d.mp3', DateTimeToFileDate(EncodeDate(2001, 2, 3)));
  St := GetFileStamp(P + 'Music\d.mp3');
  Check(St.Valid, 'stamp read from the phone');
  FileSetDate(Root + 'Music\d.mp3', DateTimeToFileDate(EncodeDate(2020, 1, 1)));
  SetFileStamp(P + 'Music\d.mp3', St);
  Check(Abs(FileDateToDateTime(FileAge(Root + 'Music\d.mp3')) - EncodeDate(2001, 2, 3)) < 1 / 1440, 'date put back');
end;

procedure TestDroppedConnection;
var
  Src, Dst: TStream;
  Orig: TBytes;
  Failed: Boolean;
begin
  WriteLn('== connection lost during a rewrite');
  Orig := Pattern(100000, 5);
  SaveBytes(Root + 'Music\drop.mp3', Orig);
  Src := OpenFileStream(P + 'Music\drop.mp3', fmOpenRead);
  Dst := OpenFileStream(TempFileFor(P + 'Music\drop.mp3'), fmCreate);
  Dst.WriteBuffer(Pattern(5000, 1)[0], 5000);
  CopyStreamRange(Src, Dst, 0, 1000);
  StopServer; // gone before the replace
  Failed := False;
  try
    Dst.Free;
    Src.Free;
    ReplaceFileWith(TempFileFor(P + 'Music\drop.mp3'), P + 'Music\drop.mp3');
  except
    Failed := True;
  end;
  Check(Failed, 'the save reports an error');
  StartServer;
  Check(Same(LoadBytes(Root + 'Music\drop.mp3'), Orig), 'the original is untouched');
  ListDirL(P + 'Music');
  Check(not FileExists(Root + 'Music\drop.mp3.tidytag-tmp'), 'the half temporary file is gone after a listing');
end;

procedure TestLocalUnchanged;
var
  S: TStream;
begin
  WriteLn('== local paths');
  S := OpenFileStream(Work + 'local.bin', fmCreate);
  try
    Check(S is TFileStream, 'a local path gives a TFileStream');
    S.WriteBuffer(Pattern(10, 0)[0], 10);
  finally
    S.Free;
  end;
  Check(FileExistsL(Work + 'local.bin') and RenameFileL(Work + 'local.bin', Work + 'local2.bin'), 'local rename');
  Check(FileExists(Work + 'local2.bin'), 'renamed');
end;

var
  Info: TPhoneInfo;
begin
  DefaultSystemCodePage := CP_UTF8; // as in TidyTag (LCL)
  if ParamCount < 3 then
  begin
    WriteLn('filelayertest <work folder> <companion-desktop.jar> <java.exe>');
    Halt(2);
  end;
  Work := IncludeTrailingPathDelimiter(ParamStr(1));
  Root := Work + 'root\';
  Jar := ParamStr(2);
  Java := ParamStr(3);
  ForceDirectories(Root + 'Music');
  PhoneSettingsFile := Work + 'phones.ini';
  PhoneDiscoveryPort := DiscoveryPort;
  StartServer;
  try
    Info := DiscoverPhones(1500, DiscoveryPort)[0];
    SavePairedPhone(Info, 'tok');
    P := PhonePrefix + 'Testtelefon\';
    TestPaths;
    TestReadAcrossBlocks;
    TestInPlaceWrite;
    TestServerSideCopy;
    TestCacheFresh;
    TestRenamesAndList;
    TestStamp;
    TestDroppedConnection;
    TestLocalUnchanged;
  finally
    StopServer;
  end;
  WriteLn(Format('%d tjek, %d fejl', [Checks, Failures]));
  if Failures > 0 then Halt(1);
  WriteLn('ALLE TESTS OK');
end.
