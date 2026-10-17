unit MusicBrainz;

{ MusicBrainz web service (release search and details) and Cover Art Archive.
  The release records are also used for Discogs (see Discogs unit).
  HTTP goes through Windows' own WinInet, so HTTPS needs no OpenSSL DLLs and the
  system proxy settings are used. MusicBrainz allows one request per second; the
  calls below wait as needed. All functions block - call them from a worker thread. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TMBRelease = record
    Id, Title, Artist, Date, Country, Formats, LabelName, CatalogNo: string;
    ReleaseGroupId, Disambiguation, Status: string;
    TrackCount, Score: Integer;
  end;
  TMBReleases = array of TMBRelease;

  TMBTrack = record
    Disc, Position: Integer;    // disc (medium) number and position on it, 1-based
    Number, Title, Artist: string;
    LengthMs: Integer;
  end;
  TMBTracks = array of TMBTrack;

  TMBReleaseDetail = record
    Release: TMBRelease;
    AlbumArtist: string;
    Genre: string;
    DiscCount: Integer;
    DiscTrackCounts: array of Integer; // tracks per disc, index 0 = disc 1
    Compilation: Boolean;
    CoverUrl: string;          // Discogs: image URL; MusicBrainz uses Cover Art Archive
    Tracks: TMBTracks;
  end;

  EWebError = class(Exception);

const
  UserAgent = 'TagKlon/0.1 ( personal music tag editor )';

{ Plain HTTP GET. Returns the status code (200, 404, ...); raises EWebError on network errors.
  ExtraHeaders: e.g. 'Authorization: ...'#13#10. }
function HttpGet(const Url: string; out Data: TBytes; const ExtraHeaders: string = ''): Integer;
function BytesToString(const B: TBytes): string;
function SearchReleases(const Artist, Album: string): TMBReleases;
function GetReleaseDetail(const ReleaseId: string): TMBReleaseDetail;
{ Front cover (Size 250, 500 or 1200 px) from the release, else its release group.
  Returns nil if there is none. }
function GetFrontCover(const ReleaseId, ReleaseGroupId: string; Size: Integer): TBytes;
{ The query text MusicBrainz' search expects, e.g. release:"Gas 5" AND artist:"Gasolin'". }
function BuildReleaseQuery(const Artist, Album: string): string;
function UrlEncode(const S: string): string;
{ Parsers, separate from the network for testing. }
function ParseSearchJson(const Json: string): TMBReleases;
function ParseReleaseJson(const Json: string): TMBReleaseDetail;

implementation

uses
  {$IFDEF WINDOWS}Windows, WinInet,{$ENDIF}
  SyncObjs, fpjson, jsonparser;

resourcestring
  rsKunneIkkeStarteNetvaerksforbindelsenFejl = 'Kunne ikke starte netværksforbindelsen (fejl %d)';
  rsIngenForbindelseTilSFejl = 'Ingen forbindelse til %s (fejl %d). Tjek internetforbindelsen.';
  rsForbindelsenBlevAfbrudtFejlD = 'Forbindelsen blev afbrudt (fejl %d)';
  rsWebOpslagUnderstoettesKunPaa = 'Web-opslag understøttes kun på Windows i denne version';
  rsMusicbrainzHarTravltLigeNu = 'MusicBrainz har travlt lige nu (503). Prøv igen om et øjeblik.';
  rsMusicbrainzKenderIkkeDenneUdgivelse = 'MusicBrainz kender ikke denne udgivelse';
  rsMusicbrainzSvaredeMedFejlD = 'MusicBrainz svarede med fejl %d';
  rsBlandet = 'Blandet';
  rsUventetSvarFraMusicbrainz = 'Uventet svar fra MusicBrainz';
  rsSkrivKunstnerOgEllerAlbum = 'Skriv kunstner og/eller album';


var
  RateLock: TCriticalSection;
  LastMBRequest: QWord = 0;

{ ---------- HTTP ---------- }

function HttpGet(const Url: string; out Data: TBytes; const ExtraHeaders: string): Integer;
{$IFDEF WINDOWS}
var
  Net, Req: HINTERNET;
  Buf: array[0..65535] of Byte;
  Got, Len, Idx, Status, Timeout: DWORD;
  N: SizeInt;
  Headers: UnicodeString;
begin
  Data := nil;
  Net := InternetOpenW(PWideChar(UnicodeString(UserAgent)), INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  if Net = nil then
    raise EWebError.CreateFmt(rsKunneIkkeStarteNetvaerksforbindelsenFejl, [GetLastError]);
  try
    Timeout := 20000;
    InternetSetOptionW(Net, INTERNET_OPTION_CONNECT_TIMEOUT, @Timeout, SizeOf(Timeout));
    InternetSetOptionW(Net, INTERNET_OPTION_RECEIVE_TIMEOUT, @Timeout, SizeOf(Timeout));
    Headers := UTF8Decode('Accept: application/json, image/*'#13#10 + ExtraHeaders);
    Req := InternetOpenUrlW(Net, PWideChar(UTF8Decode(Url)), PWideChar(Headers), Length(Headers),
      INTERNET_FLAG_RELOAD or INTERNET_FLAG_NO_CACHE_WRITE or INTERNET_FLAG_KEEP_CONNECTION, 0);
    if Req = nil then
      raise EWebError.CreateFmt(rsIngenForbindelseTilSFejl,
        [Copy(Url, 1, Pos('/', Copy(Url, 9, MaxInt)) + 7), GetLastError]);
    try
      Status := 0;
      Len := SizeOf(Status);
      Idx := 0;
      if not HttpQueryInfoW(Req, HTTP_QUERY_STATUS_CODE or HTTP_QUERY_FLAG_NUMBER, @Status, @Len, @Idx) then
        Status := 0;
      N := 0;
      repeat
        Got := 0;
        if not InternetReadFile(Req, @Buf[0], SizeOf(Buf), @Got) then
          raise EWebError.CreateFmt(rsForbindelsenBlevAfbrudtFejlD, [GetLastError]);
        if Got > 0 then
        begin
          SetLength(Data, N + Got);
          Move(Buf[0], Data[N], Got);
          Inc(N, Got);
        end;
      until Got = 0;
      Result := Status;
    finally
      InternetCloseHandle(Req);
    end;
  finally
    InternetCloseHandle(Net);
  end;
end;
{$ELSE}
begin
  raise EWebError.Create(rsWebOpslagUnderstoettesKunPaa);
end;
{$ENDIF}

function BytesToString(const B: TBytes): string;
begin
  SetLength(Result, Length(B));
  if Length(B) > 0 then Move(B[0], Result[1], Length(B));
end;

{ MusicBrainz request with the 1-per-second limit. 503 means MusicBrainz is shedding
  load (it happens even within the limit), so retry a few times with growing pauses. }
function MBGet(const PathAndQuery: string): string;
const
  Attempts = 4;
  Pause: array[1..Attempts - 1] of Integer = (1500, 3000, 5000);
var
  Data: TBytes;
  Status: Integer;
  Wait: Int64;
  Attempt: Integer;
begin
  for Attempt := 1 to Attempts do
  begin
    RateLock.Enter;
    try
      Wait := 1100 - Int64(GetTickCount64 - LastMBRequest);
      if Wait > 0 then Sleep(Wait);
      LastMBRequest := GetTickCount64;
    finally
      RateLock.Leave;
    end;
    Status := HttpGet('https://musicbrainz.org/ws/2/' + PathAndQuery, Data);
    if Status = 200 then Exit(BytesToString(Data));
    if (Status = 503) and (Attempt < Attempts) then
    begin
      Sleep(Pause[Attempt]);
      Continue;
    end;
    if Status = 503 then
      raise EWebError.Create(rsMusicbrainzHarTravltLigeNu);
    if Status = 404 then raise EWebError.Create(rsMusicbrainzKenderIkkeDenneUdgivelse);
    raise EWebError.CreateFmt(rsMusicbrainzSvaredeMedFejlD, [Status]);
  end;
  Result := '';
end;

function UrlEncode(const S: string): string;
var
  U: UTF8String;
  I: Integer;
  C: Char;
begin
  U := UTF8String(S);
  Result := '';
  for I := 1 to Length(U) do
  begin
    C := U[I];
    if C in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', '~'] then
      Result := Result + C
    else
      Result := Result + '%' + IntToHex(Ord(C), 2);
  end;
end;

function QuoteTerm(const S: string): string;
begin
  // Inside quotes only the quote and the backslash need escaping.
  Result := '"' + StringReplace(StringReplace(Trim(S), '\', '\\', [rfReplaceAll]),
    '"', '\"', [rfReplaceAll]) + '"';
end;

function BuildReleaseQuery(const Artist, Album: string): string;
begin
  Result := '';
  if Trim(Album) <> '' then Result := 'release:' + QuoteTerm(Album);
  if Trim(Artist) <> '' then
  begin
    if Result <> '' then Result := Result + ' AND ';
    Result := Result + 'artist:' + QuoteTerm(Artist);
  end;
end;

{ ---------- JSON helpers ---------- }

function JStr(O: TJSONObject; const Key: string): string;
var
  D: TJSONData;
begin
  Result := '';
  if O = nil then Exit;
  D := O.Find(Key);
  if (D <> nil) and (D.JSONType in [jtString, jtNumber]) then Result := D.AsString;
end;

function JInt(O: TJSONObject; const Key: string): Integer;
var
  D: TJSONData;
begin
  Result := 0;
  if O = nil then Exit;
  D := O.Find(Key);
  if (D <> nil) and (D.JSONType = jtNumber) then Result := D.AsInteger
  else if (D <> nil) and (D.JSONType = jtString) then Result := StrToIntDef(D.AsString, 0);
end;

function JObj(O: TJSONObject; const Key: string): TJSONObject;
var
  D: TJSONData;
begin
  Result := nil;
  if O = nil then Exit;
  D := O.Find(Key);
  if (D <> nil) and (D.JSONType = jtObject) then Result := TJSONObject(D);
end;

function JArr(O: TJSONObject; const Key: string): TJSONArray;
var
  D: TJSONData;
begin
  Result := nil;
  if O = nil then Exit;
  D := O.Find(Key);
  if (D <> nil) and (D.JSONType = jtArray) then Result := TJSONArray(D);
end;

function ArrObj(A: TJSONArray; I: Integer): TJSONObject;
begin
  Result := nil;
  if (A <> nil) and (I < A.Count) and (A.Items[I].JSONType = jtObject) then
    Result := TJSONObject(A.Items[I]);
end;

{ 'Artist A feat. Artist B' from an artist-credit array. }
function CreditText(O: TJSONObject): string;
var
  A: TJSONArray;
  I: Integer;
  C: TJSONObject;
  Name: string;
begin
  Result := '';
  A := JArr(O, 'artist-credit');
  if A = nil then Exit;
  for I := 0 to A.Count - 1 do
  begin
    C := ArrObj(A, I);
    if C = nil then Continue;
    Name := JStr(C, 'name');
    if Name = '' then Name := JStr(JObj(C, 'artist'), 'name');
    Result := Result + Name + JStr(C, 'joinphrase');
  end;
end;

procedure FillRelease(O: TJSONObject; var R: TMBRelease);
var
  Media, Labels: TJSONArray;
  I: Integer;
  Fmt: string;
  L: TJSONObject;
begin
  R.Id := JStr(O, 'id');
  R.Title := JStr(O, 'title');
  R.Artist := CreditText(O);
  R.Date := JStr(O, 'date');
  R.Country := JStr(O, 'country');
  R.Status := JStr(O, 'status');
  R.Disambiguation := JStr(O, 'disambiguation');
  R.Score := JInt(O, 'score');
  R.TrackCount := JInt(O, 'track-count');
  R.ReleaseGroupId := JStr(JObj(O, 'release-group'), 'id');
  R.Formats := '';
  Media := JArr(O, 'media');
  if Media <> nil then
  begin
    if R.TrackCount = 0 then
      for I := 0 to Media.Count - 1 do
        Inc(R.TrackCount, JInt(ArrObj(Media, I), 'track-count'));
    for I := 0 to Media.Count - 1 do
    begin
      Fmt := JStr(ArrObj(Media, I), 'format');
      if Fmt = '' then Fmt := '?';
      if R.Formats = '' then
        R.Formats := Fmt
      else if R.Formats <> Fmt then
        R.Formats := rsBlandet; // e.g. CD + DVD
    end;
    if Media.Count > 1 then R.Formats := IntToStr(Media.Count) + '×' + R.Formats;
  end;
  R.LabelName := '';
  R.CatalogNo := '';
  Labels := JArr(O, 'label-info');
  if (Labels <> nil) and (Labels.Count > 0) then
  begin
    L := ArrObj(Labels, 0);
    R.LabelName := JStr(JObj(L, 'label'), 'name');
    R.CatalogNo := JStr(L, 'catalog-number');
  end;
end;

function ParseSearchJson(const Json: string): TMBReleases;
var
  Root: TJSONData;
  A: TJSONArray;
  I: Integer;
begin
  Result := nil;
  Root := GetJSON(Json);
  try
    if Root.JSONType <> jtObject then Exit;
    A := JArr(TJSONObject(Root), 'releases');
    if A = nil then Exit;
    SetLength(Result, A.Count);
    for I := 0 to A.Count - 1 do
      FillRelease(ArrObj(A, I), Result[I]);
  finally
    Root.Free;
  end;
end;

function CapitalizeGenre(const S: string): string;
var
  I: Integer;
  Up: Boolean;
begin
  Result := S;
  Up := True;
  for I := 1 to Length(Result) do
  begin
    if Up and (Result[I] in ['a'..'z']) then Result[I] := UpCase(Result[I]);
    Up := Result[I] in [' ', '-', '/', '&'];
  end;
end;

function TopGenre(O: TJSONObject): string;
var
  A: TJSONArray;
  I, Best: Integer;
begin
  Result := '';
  A := JArr(O, 'genres');
  if A = nil then Exit;
  Best := -1;
  for I := 0 to A.Count - 1 do
    if JInt(ArrObj(A, I), 'count') > Best then
    begin
      Best := JInt(ArrObj(A, I), 'count');
      Result := CapitalizeGenre(JStr(ArrObj(A, I), 'name'));
    end;
end;

function ParseReleaseJson(const Json: string): TMBReleaseDetail;
var
  Root: TJSONData;
  O, M, T, RG: TJSONObject;
  Media, Tracks, Sec: TJSONArray;
  I, J, N: Integer;
begin
  Result.Tracks := nil;
  Result.DiscTrackCounts := nil;
  Result.DiscCount := 0;
  Result.Compilation := False;
  Result.CoverUrl := '';
  Root := GetJSON(Json);
  try
    if Root.JSONType <> jtObject then raise EWebError.Create(rsUventetSvarFraMusicbrainz);
    O := TJSONObject(Root);
    FillRelease(O, Result.Release);
    Result.AlbumArtist := Result.Release.Artist;
    Result.Genre := TopGenre(O);
    RG := JObj(O, 'release-group');
    if Result.Genre = '' then Result.Genre := TopGenre(RG);
    Sec := JArr(RG, 'secondary-types');
    if Sec <> nil then
      for I := 0 to Sec.Count - 1 do
        if SameText(Sec.Strings[I], 'Compilation') then Result.Compilation := True;
    if SameText(Result.AlbumArtist, 'Various Artists') then Result.Compilation := True;

    Media := JArr(O, 'media');
    if Media = nil then Exit;
    Result.DiscCount := Media.Count;
    SetLength(Result.DiscTrackCounts, Media.Count);
    N := 0;
    for I := 0 to Media.Count - 1 do
    begin
      M := ArrObj(Media, I);
      Tracks := JArr(M, 'tracks');
      if Tracks = nil then Continue;
      Result.DiscTrackCounts[I] := Tracks.Count;
      for J := 0 to Tracks.Count - 1 do
      begin
        T := ArrObj(Tracks, J);
        SetLength(Result.Tracks, N + 1);
        with Result.Tracks[N] do
        begin
          Disc := JInt(M, 'position');
          if Disc = 0 then Disc := I + 1;
          Position := JInt(T, 'position');
          if Position = 0 then Position := J + 1;
          Number := JStr(T, 'number');
          Title := JStr(T, 'title');
          if Title = '' then Title := JStr(JObj(T, 'recording'), 'title');
          Artist := CreditText(T);
          if Artist = '' then Artist := CreditText(JObj(T, 'recording'));
          if Artist = '' then Artist := Result.AlbumArtist;
          LengthMs := JInt(T, 'length');
          if LengthMs = 0 then LengthMs := JInt(JObj(T, 'recording'), 'length');
        end;
        Inc(N);
      end;
    end;
  finally
    Root.Free;
  end;
end;

function SearchReleases(const Artist, Album: string): TMBReleases;
var
  Q: string;
begin
  Q := BuildReleaseQuery(Artist, Album);
  if Q = '' then raise EWebError.Create(rsSkrivKunstnerOgEllerAlbum);
  Result := ParseSearchJson(MBGet('release/?query=' + UrlEncode(Q) + '&fmt=json&limit=40'));
end;

function GetReleaseDetail(const ReleaseId: string): TMBReleaseDetail;
begin
  Result := ParseReleaseJson(MBGet('release/' + ReleaseId +
    '?inc=artist-credits+labels+recordings+release-groups+genres&fmt=json'));
end;

function GetFrontCover(const ReleaseId, ReleaseGroupId: string; Size: Integer): TBytes;
begin
  if HttpGet(Format('https://coverartarchive.org/release/%s/front-%d', [ReleaseId, Size]), Result) = 200 then
    Exit;
  Result := nil;
  if (ReleaseGroupId <> '') and
    (HttpGet(Format('https://coverartarchive.org/release-group/%s/front-%d', [ReleaseGroupId, Size]), Result) = 200) then
    Exit;
  Result := nil;
end;

initialization
  RateLock := TCriticalSection.Create;
finalization
  RateLock.Free;
end.
