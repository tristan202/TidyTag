unit PhoneClient;

{ Talks to TidyTag Companion on an Android phone (docs/phone-protocol.md): HTTP over the
  local network with a pairing token, UDP broadcast to find phones, and the list of paired
  phones in the settings. Errors raise EPhoneError with a text for the user. No LCL. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TPhoneEntry = record
    Name: string;
    IsDir: Boolean;
    Size: Int64;
    MTime: Int64; // ms since 1970
  end;
  TPhoneEntries = array of TPhoneEntry;

  TPhoneInfo = record
    Id, Name, Host: string;
    Port: Integer;
  end;
  TPhoneInfos = array of TPhoneInfo;

  TPhonePeek = record
    Path: string;
    Size, MTime: Int64;
    Head, Tail: TBytes;
  end;
  TPhonePeeks = array of TPhonePeek;

  EPhoneError = class(Exception);

  TPhone = class
  private
    FInfo: TPhoneInfo;
    FToken: string;
    FNet, FConn: Pointer;
    FBytesSent: Int64;
    function Request(const Method, Path: string; const Query: array of string; const Body: TBytes;
      out Status: Integer): TBytes;
    function Call(const Method, Path: string; const Query: array of string; const Body: TBytes): TBytes;
  public
    constructor Create(const AInfo: TPhoneInfo; const AToken: string);
    destructor Destroy; override;
    function List(const Rel: string): TPhoneEntries;
    function Read(const Rel: string; Offset: Int64; Len: Integer): TBytes;
    function Peek(const Rels: TStringArray; Head, Tail: Integer): TPhonePeeks;
    procedure Write(const Rel: string; Offset: Int64; const Data: TBytes);
    procedure Truncate(const Rel: string; Len: Int64);
    procedure CreateFile(const Rel: string);
    procedure Rename(const FromRel, ToRel: string; Replace: Boolean);
    procedure MakeDir(const Rel: string);
    function Stat(const Rel: string; out E: TPhoneEntry): Boolean;
    procedure CopyRange(const Src: string; SrcOffset, Len: Int64; const Dst: string; DstOffset: Int64);
    function Trash(const Rels: TStringArray): TStringArray; // the files it refused
    procedure SetMTime(const Rel: string; Ms: Int64);
    property Info: TPhoneInfo read FInfo;
    { Bytes sent in request bodies (the tests check that rewrites do not upload audio). }
    property BytesSent: Int64 read FBytesSent;
  end;

var
  { '' = the normal settings file; the tests point it elsewhere. }
  PhoneSettingsFile: string = '';
  PhoneDiscoveryPort: Integer = 47101;

function DiscoverPhones(TimeoutMs: Integer = 1500; Port: Integer = 0): TPhoneInfos;
function PairPhone(const Info: TPhoneInfo; const Code: string; out Token: string): Boolean;
{ A paired phone from the settings, found again by broadcast if its address changed; nil if
  it is not paired or cannot be reached. }
function PhoneByName(const Name: string): TPhone;
procedure SavePairedPhone(const Info: TPhoneInfo; const Token: string);
function PairedPhoneNames: TStringArray;
procedure ForgetPhone(const Name: string);

implementation

uses
  Windows, WinInet, WinSock2, IniFiles, fpjson, jsonparser, base64, SettingsFile;

resourcestring
  rsTelefonSvarerIkke = 'Telefonen svarer ikke (%s). Er TidyTag Companion tændt, og er telefonen på samme Wi-Fi?';
  rsTelefonFejl = 'Telefonen svarede: %s';
  rsIkkeParret = 'Telefonen kender ikke denne pc længere. Par den igen under "Tilføj telefon".';

const
  Section = 'Phones';

function UrlEncode(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    if S[I] in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', '~', '/'] then Result := Result + S[I]
    else Result := Result + '%' + IntToHex(Ord(S[I]), 2);
end;

function BytesOf(const S: string): TBytes;
begin
  SetLength(Result, Length(S));
  if S <> '' then Move(S[1], Result[0], Length(S));
end;

function StringOf(const B: TBytes): string;
begin
  SetLength(Result, Length(B));
  if Length(B) > 0 then Move(B[0], Result[1], Length(B));
end;

{ TPhone }

constructor TPhone.Create(const AInfo: TPhoneInfo; const AToken: string);
var
  Timeout: DWORD;
begin
  inherited Create;
  FInfo := AInfo;
  FToken := AToken;
  // direct: a proxy must never see local traffic
  FNet := InternetOpenW('TidyTag', INTERNET_OPEN_TYPE_DIRECT, nil, nil, 0);
  Timeout := 15000;
  InternetSetOptionW(FNet, INTERNET_OPTION_CONNECT_TIMEOUT, @Timeout, SizeOf(Timeout));
  InternetSetOptionW(FNet, INTERNET_OPTION_RECEIVE_TIMEOUT, @Timeout, SizeOf(Timeout));
  InternetSetOptionW(FNet, INTERNET_OPTION_SEND_TIMEOUT, @Timeout, SizeOf(Timeout));
  FConn := InternetConnectW(FNet, PWideChar(UnicodeString(FInfo.Host)), FInfo.Port, nil, nil,
    INTERNET_SERVICE_HTTP, 0, 0);
end;

destructor TPhone.Destroy;
begin
  if FConn <> nil then InternetCloseHandle(FConn);
  if FNet <> nil then InternetCloseHandle(FNet);
  inherited Destroy;
end;

function TPhone.Request(const Method, Path: string; const Query: array of string; const Body: TBytes;
  out Status: Integer): TBytes;
var
  Url, Headers: UnicodeString;
  U: string;
  I: Integer;
  Req: HINTERNET;
  Buf: array[0..65535] of Byte;
  Got, Len, Idx, St: DWORD;
  N: SizeInt;
begin
  Result := nil;
  U := Path;
  for I := 0 to High(Query) div 2 do
  begin
    if I = 0 then U := U + '?' else U := U + '&';
    U := U + Query[2 * I] + '=' + UrlEncode(Query[2 * I + 1]);
  end;
  Url := UnicodeString(U);
  Req := HttpOpenRequestW(FConn, PWideChar(UnicodeString(Method)), PWideChar(Url), nil, nil, nil,
    INTERNET_FLAG_RELOAD or INTERNET_FLAG_NO_CACHE_WRITE or INTERNET_FLAG_KEEP_CONNECTION, 0);
  if Req = nil then raise EPhoneError.CreateFmt(rsTelefonSvarerIkke, [IntToStr(GetLastError)]);
  try
    // WinInet refuses a header without a value (pairing has no token yet)
    if FToken <> '' then Headers := UnicodeString('X-TidyTag-Token: ' + FToken + #13#10)
    else Headers := 'Content-Type: application/json'#13#10;
    if Length(Body) > 0 then
    begin
      if not HttpSendRequestW(Req, PWideChar(Headers), Length(Headers), @Body[0], Length(Body)) then
        raise EPhoneError.CreateFmt(rsTelefonSvarerIkke, [IntToStr(GetLastError)]);
      Inc(FBytesSent, Length(Body));
    end
    else if not HttpSendRequestW(Req, PWideChar(Headers), Length(Headers), nil, 0) then
      raise EPhoneError.CreateFmt(rsTelefonSvarerIkke, [IntToStr(GetLastError)]);
    St := 0;
    Len := SizeOf(St);
    Idx := 0;
    if not HttpQueryInfoW(Req, HTTP_QUERY_STATUS_CODE or HTTP_QUERY_FLAG_NUMBER, @St, @Len, @Idx) then St := 0;
    Status := St;
    N := 0;
    repeat
      Got := 0;
      if not InternetReadFile(Req, @Buf[0], SizeOf(Buf), @Got) then
        raise EPhoneError.CreateFmt(rsTelefonSvarerIkke, [IntToStr(GetLastError)]);
      if Got > 0 then
      begin
        SetLength(Result, N + Got);
        Move(Buf[0], Result[N], Got);
        Inc(N, Got);
      end;
    until Got = 0;
  finally
    InternetCloseHandle(Req);
  end;
end;

function TPhone.Call(const Method, Path: string; const Query: array of string; const Body: TBytes): TBytes;
var
  Status: Integer;
  Msg: string;
  J: TJSONData;
begin
  Result := Request(Method, Path, Query, Body, Status);
  if Status = 200 then Exit;
  if Status = 401 then raise EPhoneError.Create(rsIkkeParret);
  Msg := IntToStr(Status);
  try
    J := GetJSON(StringOf(Result));
    try
      Msg := J.FindPath('error').AsString;
    finally
      J.Free;
    end;
  except
    // not JSON: the status code says enough
  end;
  raise EPhoneError.CreateFmt(rsTelefonFejl, [Msg]);
end;

function EntryFrom(O: TJSONObject): TPhoneEntry;
begin
  Result.Name := O.Get('name', '');
  Result.IsDir := O.Get('dir', False);
  Result.Size := O.Get('size', Int64(0));
  Result.MTime := O.Get('mtime', Int64(0));
end;

function TPhone.List(const Rel: string): TPhoneEntries;
var
  J: TJSONData;
  I: Integer;
begin
  J := GetJSON(StringOf(Call('GET', '/v1/list', ['path', Rel], nil)));
  try
    SetLength(Result, J.Count);
    for I := 0 to J.Count - 1 do Result[I] := EntryFrom(J.Items[I] as TJSONObject);
  finally
    J.Free;
  end;
end;

function TPhone.Read(const Rel: string; Offset: Int64; Len: Integer): TBytes;
begin
  Result := Call('GET', '/v1/read', ['path', Rel, 'offset', IntToStr(Offset), 'len', IntToStr(Len)], nil);
end;

function TPhone.Peek(const Rels: TStringArray; Head, Tail: Integer): TPhonePeeks;
var
  Req: TJSONObject;
  Arr: TJSONArray;
  J: TJSONData;
  O: TJSONObject;
  R: string;
  I: Integer;
begin
  Req := TJSONObject.Create;
  try
    Arr := TJSONArray.Create;
    for R in Rels do Arr.Add(R);
    Req.Add('paths', Arr);
    Req.Add('head', Head);
    Req.Add('tail', Tail);
    J := GetJSON(StringOf(Call('POST', '/v1/peek', [], BytesOf(Req.AsJSON))));
  finally
    Req.Free;
  end;
  try
    SetLength(Result, J.Count);
    for I := 0 to J.Count - 1 do
    begin
      O := J.Items[I] as TJSONObject;
      Result[I].Path := O.Get('path', '');
      Result[I].Size := O.Get('size', Int64(0));
      Result[I].MTime := O.Get('mtime', Int64(0));
      Result[I].Head := BytesOf(DecodeStringBase64(O.Get('head', '')));
      Result[I].Tail := BytesOf(DecodeStringBase64(O.Get('tail', '')));
    end;
  finally
    J.Free;
  end;
end;

procedure TPhone.Write(const Rel: string; Offset: Int64; const Data: TBytes);
begin
  Call('POST', '/v1/write', ['path', Rel, 'offset', IntToStr(Offset)], Data);
end;

procedure TPhone.Truncate(const Rel: string; Len: Int64);
begin
  Call('POST', '/v1/truncate', ['path', Rel, 'len', IntToStr(Len)], nil);
end;

procedure TPhone.CreateFile(const Rel: string);
begin
  Call('POST', '/v1/create', ['path', Rel], nil);
end;

procedure TPhone.Rename(const FromRel, ToRel: string; Replace: Boolean);
const
  Flag: array[Boolean] of string = ('0', '1');
begin
  Call('POST', '/v1/rename', ['from', FromRel, 'to', ToRel, 'replace', Flag[Replace]], nil);
end;

procedure TPhone.MakeDir(const Rel: string);
begin
  Call('POST', '/v1/mkdir', ['path', Rel], nil);
end;

function TPhone.Stat(const Rel: string; out E: TPhoneEntry): Boolean;
var
  Status: Integer;
  B: TBytes;
  J: TJSONData;
begin
  B := Request('GET', '/v1/stat', ['path', Rel], nil, Status);
  if Status = 404 then Exit(False);
  if Status <> 200 then B := Call('GET', '/v1/stat', ['path', Rel], nil); // raises with the message
  J := GetJSON(StringOf(B));
  try
    E := EntryFrom(J as TJSONObject);
  finally
    J.Free;
  end;
  Result := True;
end;

procedure TPhone.CopyRange(const Src: string; SrcOffset, Len: Int64; const Dst: string; DstOffset: Int64);
begin
  Call('POST', '/v1/copy', ['src', Src, 'srcOffset', IntToStr(SrcOffset), 'len', IntToStr(Len),
    'dst', Dst, 'dstOffset', IntToStr(DstOffset)], nil);
end;

function TPhone.Trash(const Rels: TStringArray): TStringArray;
var
  Req: TJSONObject;
  Arr: TJSONArray;
  J: TJSONData;
  R: string;
  I: Integer;
begin
  Req := TJSONObject.Create;
  try
    Arr := TJSONArray.Create;
    for R in Rels do Arr.Add(R);
    Req.Add('paths', Arr);
    J := GetJSON(StringOf(Call('POST', '/v1/trash', [], BytesOf(Req.AsJSON))));
  finally
    Req.Free;
  end;
  try
    Arr := J.FindPath('refused') as TJSONArray;
    SetLength(Result, Arr.Count);
    for I := 0 to Arr.Count - 1 do Result[I] := Arr.Strings[I];
  finally
    J.Free;
  end;
end;

procedure TPhone.SetMTime(const Rel: string; Ms: Int64);
begin
  Call('POST', '/v1/mtime', ['path', Rel, 'ms', IntToStr(Ms)], nil);
end;

{ Discovery }

function DiscoverPhones(TimeoutMs: Integer; Port: Integer): TPhoneInfos;
var
  WSA: TWSAData;
  S: TSocket;
  Addr, From: TSockAddrIn;
  FromLen, N: Integer;
  Yes: Integer;
  Q: AnsiString;
  Buf: array[0..1023] of Char;
  T: QWord;
  Tv: DWORD;
  J: TJSONData;
  I: TPhoneInfo;
  K: Integer;
  Dup: Boolean;

  procedure Send(IP: Cardinal);
  begin
    FillChar(Addr, SizeOf(Addr), 0);
    Addr.sin_family := AF_INET;
    Addr.sin_port := htons(Port);
    Addr.sin_addr.S_addr := IP;
    sendto(S, PChar(Q), Length(Q), 0, PSockAddr(@Addr), SizeOf(Addr));
  end;

begin
  Result := nil;
  if Port = 0 then Port := PhoneDiscoveryPort;
  WSAStartup($0202, WSA);
  S := socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
  if S = INVALID_SOCKET then Exit;
  try
    Yes := 1;
    setsockopt(S, SOL_SOCKET, SO_BROADCAST, @Yes, SizeOf(Yes));
    Tv := 200;
    setsockopt(S, SOL_SOCKET, SO_RCVTIMEO, @Tv, SizeOf(Tv));
    Q := 'TIDYTAG?';
    Send(INADDR_BROADCAST);
    Send(htonl(INADDR_LOOPBACK)); // the desktop test server
    T := GetTickCount64;
    while GetTickCount64 - T < QWord(TimeoutMs) do
    begin
      FromLen := SizeOf(From);
      N := recvfrom(S, @Buf[0], SizeOf(Buf), 0, PSockAddr(@From), @FromLen);
      if N <= 0 then Continue;
      try
        J := GetJSON(Copy(string(Buf), 1, N));
        try
          I.Name := J.FindPath('name').AsString;
          I.Port := J.FindPath('port').AsInteger;
          I.Id := J.FindPath('id').AsString;
          I.Host := string(inet_ntoa(From.sin_addr));
        finally
          J.Free;
        end;
      except
        Continue; // not ours
      end;
      Dup := False;
      for K := 0 to High(Result) do
        if Result[K].Id = I.Id then Dup := True;
      if not Dup then Insert(I, Result, Length(Result));
    end;
  finally
    closesocket(S);
  end;
end;

function PairPhone(const Info: TPhoneInfo; const Code: string; out Token: string): Boolean;
var
  P: TPhone;
  Req: TJSONObject;
  Status: Integer;
  B: TBytes;
  J: TJSONData;
begin
  Token := '';
  P := TPhone.Create(Info, '');
  Req := TJSONObject.Create;
  try
    Req.Add('code', Code);
    Req.Add('pcName', SysUtils.GetEnvironmentVariable('COMPUTERNAME'));
    B := P.Request('POST', '/v1/pair', [], BytesOf(Req.AsJSON), Status);
    Result := Status = 200;
    if not Result then Exit;
    J := GetJSON(StringOf(B));
    try
      Token := J.FindPath('token').AsString;
    finally
      J.Free;
    end;
  finally
    Req.Free;
    P.Free;
  end;
end;

{ Paired phones: [Phones] <id>=<name>|<host>|<port>|<token> }

function OpenPhoneIni: TIniFile;
begin
  if PhoneSettingsFile <> '' then Result := TIniFile.Create(PhoneSettingsFile)
  else Result := OpenSettings;
end;

procedure SavePairedPhone(const Info: TPhoneInfo; const Token: string);
var
  Ini: TIniFile;
begin
  Ini := OpenPhoneIni;
  try
    Ini.WriteString(Section, Info.Id, Info.Name + '|' + Info.Host + '|' + IntToStr(Info.Port) + '|' + Token);
  finally
    Ini.Free;
  end;
end;

function ReadPaired(out Infos: TPhoneInfos; out Tokens: TStringArray): Integer;
var
  Ini: TIniFile;
  L: TStringList;
  P: TStringArray;
  I: Integer;
  Info: TPhoneInfo;
begin
  Infos := nil;
  Tokens := nil;
  Ini := OpenPhoneIni;
  L := TStringList.Create;
  try
    Ini.ReadSectionValues(Section, L);
    for I := 0 to L.Count - 1 do
    begin
      P := L.ValueFromIndex[I].Split(['|']);
      if Length(P) < 4 then Continue;
      Info.Id := L.Names[I];
      Info.Name := P[0];
      Info.Host := P[1];
      Info.Port := StrToIntDef(P[2], 0);
      Insert(Info, Infos, Length(Infos));
      Insert(P[3], Tokens, Length(Tokens));
    end;
  finally
    L.Free;
    Ini.Free;
  end;
  Result := Length(Infos);
end;

function PairedPhoneNames: TStringArray;
var
  Infos: TPhoneInfos;
  Tokens: TStringArray;
  I: Integer;
begin
  Result := nil;
  ReadPaired(Infos, Tokens);
  for I := 0 to High(Infos) do Insert(Infos[I].Name, Result, Length(Result));
end;

procedure ForgetPhone(const Name: string);
var
  Infos: TPhoneInfos;
  Tokens: TStringArray;
  I: Integer;
  Ini: TIniFile;
begin
  ReadPaired(Infos, Tokens);
  Ini := OpenPhoneIni;
  try
    for I := 0 to High(Infos) do
      if SameText(Infos[I].Name, Name) then Ini.DeleteKey(Section, Infos[I].Id);
  finally
    Ini.Free;
  end;
end;

function Reachable(P: TPhone): Boolean;
var
  E: TPhoneEntry;
begin
  try
    P.Stat('', E);
    Result := True;
  except
    on EPhoneError do Result := False;
  end;
end;

function PhoneByName(const Name: string): TPhone;
var
  Infos, Found: TPhoneInfos;
  Tokens: TStringArray;
  I, K: Integer;
begin
  Result := nil;
  ReadPaired(Infos, Tokens);
  for I := 0 to High(Infos) do
  begin
    if not SameText(Infos[I].Name, Name) then Continue;
    Result := TPhone.Create(Infos[I], Tokens[I]);
    if Reachable(Result) then Exit;
    FreeAndNil(Result);
    // the address may have changed (DHCP, app restarted): ask the network
    Found := DiscoverPhones;
    for K := 0 to High(Found) do
      if Found[K].Id = Infos[I].Id then
      begin
        SavePairedPhone(Found[K], Tokens[I]);
        Result := TPhone.Create(Found[K], Tokens[I]);
        if Reachable(Result) then Exit;
        FreeAndNil(Result);
      end;
    Exit;
  end;
end;

end.
