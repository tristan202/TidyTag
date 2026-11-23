program phoneclienttest;

{ Phone client checks against the companion's desktop jar serving a scratch folder.
  Usage: phoneclienttest <work folder> <companion-desktop.jar> [<java.exe>] }

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, Process, PhoneClient;

const
  Port1 = 47210;
  Port2 = 47220;
  DiscoveryPort = 47211;

var
  Failures: Integer = 0;
  Checks: Integer = 0;
  Work, Jar, Java: string;
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

procedure StartServer(Port: Integer);
var
  T: QWord;
begin
  Server := TProcess.Create(nil);
  Server.Executable := Java;
  Server.Parameters.AddStrings(['-jar', Jar, '--root', Work + 'root', '--port', IntToStr(Port),
    '--token', 'tok', '--code', '123456', '--discovery', IntToStr(DiscoveryPort), '--name', 'Testtelefon',
    '--id', 'dev-1']);
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

procedure WriteFile(const Name: string; Size: Integer);
var
  S: TFileStream;
  B: TBytes;
  I: Integer;
begin
  ForceDirectories(ExtractFileDir(Name));
  SetLength(B, Size);
  for I := 0 to Size - 1 do B[I] := Byte(I mod 251);
  S := TFileStream.Create(Name, fmCreate);
  try
    if Size > 0 then S.WriteBuffer(B[0], Size);
  finally
    S.Free;
  end;
end;

function Info: TPhoneInfo;
var
  L: TPhoneInfos;
begin
  L := DiscoverPhones(1500, DiscoveryPort);
  if Length(L) = 0 then raise Exception.Create('no phone found');
  Result := L[0];
end;

procedure TestPairAndToken;
var
  Token: string;
  P: TPhone;
begin
  WriteLn('== pairing');
  Check(Info.Name = 'Testtelefon', 'found by broadcast: ' + Info.Name);
  Check(Info.Port = Port1, 'port from the answer');
  Check(not PairPhone(Info, '000000', Token), 'wrong code refused');
  Check(PairPhone(Info, '123456', Token) and (Token <> ''), 'right code gives a token');
  P := TPhone.Create(Info, Token);
  try
    Check(Length(P.List('')) >= 1, 'token works');
  finally
    P.Free;
  end;
end;

procedure TestListReadWrite;
var
  P: TPhone;
  L: TPhoneEntries;
  B: TBytes;
  Found: Boolean;
  E: TPhoneEntry;
begin
  WriteLn('== list, read, write');
  P := TPhone.Create(Info, 'tok');
  try
    L := P.List('Music');
    Found := False;
    for E in L do
      if (E.Name = 'a.mp3') and not E.IsDir and (E.Size = 5000) then Found := True;
    Check(Found, 'Music/a.mp3 listed with its size');
    B := P.Read('Music/a.mp3', 4990, 100);
    Check((Length(B) = 10) and (B[0] = Byte(4990 mod 251)), 'read across the end');
    P.Write('Music/a.mp3', 10, TBytes.Create(1, 2, 3));
    B := P.Read('Music/a.mp3', 9, 5);
    Check((B[0] = Byte(9 mod 251)) and (B[1] = 1) and (B[3] = 3), 'write applied');
    P.CreateFile('Music/b.mp3.tidytag-tmp');
    P.Write('Music/b.mp3.tidytag-tmp', 0, TBytes.Create(9));
    P.Rename('Music/b.mp3.tidytag-tmp', 'Music/Ny/b.mp3', False);
    Check(P.Stat('Music/Ny/b.mp3', E) and (E.Size = 1), 'create, rename into a new folder');
    P.CopyRange('Music/a.mp3', 0, 100, 'Music/Ny/b.mp3', 1);
    Check(P.Stat('Music/Ny/b.mp3', E) and (E.Size = 101), 'copy on the phone');
    Check(not P.Stat('Music/findes-ikke.mp3', E), 'stat of a missing file');
    Check(Length(P.Trash(['Music/Ny/b.mp3'])) = 1, 'trash refused by the desktop storage');
  finally
    P.Free;
  end;
end;

procedure TestPeekBatch;
var
  P: TPhone;
  Names: TStringArray;
  R: TPhonePeeks;
  I: Integer;
begin
  WriteLn('== peek');
  SetLength(Names, 300);
  for I := 0 to 299 do
  begin
    Names[I] := Format('Mange/%.3d.mp3', [I]);
    WriteFile(Work + 'root\Mange\' + Format('%.3d.mp3', [I]), 3000);
  end;
  P := TPhone.Create(Info, 'tok');
  try
    R := P.Peek(Names, 1024, 512);
    Check(Length(R) = 300, '300 files in one request');
    Check((Length(R[7].Head) = 1024) and (Length(R[7].Tail) = 512) and (R[7].Size = 3000), 'head and tail sizes');
    Check(R[7].Tail[0] = Byte((3000 - 512) mod 251), 'tail from the end');
  finally
    P.Free;
  end;
end;

procedure TestErrorsRaise;
var
  P: TPhone;
  Raised: Boolean;
begin
  WriteLn('== errors');
  P := TPhone.Create(Info, 'wrong');
  try
    Raised := False;
    try
      P.List('');
    except
      on E: EPhoneError do Raised := True;
    end;
    Check(Raised, 'wrong token raises EPhoneError');
  finally
    P.Free;
  end;
end;

procedure TestRediscover;
var
  I: TPhoneInfo;
  P: TPhone;
begin
  WriteLn('== found again after a new address');
  I := Info;
  SavePairedPhone(I, 'tok');
  StopServer;
  StartServer(Port2);
  P := PhoneByName('Testtelefon');
  try
    Check(P <> nil, 'paired phone by name');
    if P <> nil then Check(Length(P.List('Music')) >= 1, 'works on the new port without pairing again');
  finally
    P.Free;
  end;
  P := PhoneByName('Testtelefon');
  try
    Check((P <> nil) and (P.Info.Port = Port2), 'new port saved');
  finally
    P.Free;
  end;
end;

begin
  if ParamCount < 2 then
  begin
    WriteLn('phoneclienttest <work folder> <companion-desktop.jar> [<java.exe>]');
    Halt(2);
  end;
  Work := IncludeTrailingPathDelimiter(ParamStr(1));
  Jar := ParamStr(2);
  if ParamCount >= 3 then Java := ParamStr(3) else Java := 'java';
  ForceDirectories(Work + 'root');
  WriteFile(Work + 'root\Music\a.mp3', 5000);
  PhoneSettingsFile := Work + 'phones.ini'; // never the user's tidytag.ini
  PhoneDiscoveryPort := DiscoveryPort;
  DeleteFile(PhoneSettingsFile);
  StartServer(Port1);
  try
    TestPairAndToken;
    TestListReadWrite;
    TestPeekBatch;
    TestErrorsRaise;
    TestRediscover;
  finally
    StopServer;
  end;
  WriteLn(Format('%d tjek, %d fejl', [Checks, Failures]));
  if Failures > 0 then Halt(1);
  WriteLn('ALLE TESTS OK');
end.
