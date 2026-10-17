unit Discogs;

{ Discogs API client. Results are returned in the same records as MusicBrainz, so the
  lookup dialog, the file/track pairing and the writing are shared.

  - Searching needs a personal access token (discogs.com > Settings > Developers).
    Release details and images work without one.
  - Discogs allows 60 requests/minute with a token (25 without); we keep >= 1.1 s apart
    and retry on 429.
  - Artist names carry disambiguation suffixes like 'Kim Larsen (2)'; they are removed.
  - Track positions like 'A1', 'B2', '2-05', 'CD2-3' become disc + running number. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, MusicBrainz;

function DiscogsSearch(const Artist, Album, Token: string): TMBReleases;
function DiscogsRelease(const ReleaseId, Token: string): TMBReleaseDetail;
{ Downloads the release's primary image (Detail.CoverUrl); nil if there is none. }
function DiscogsCover(const Url, Token: string): TBytes;
function ParseDiscogsSearchJson(const Json: string): TMBReleases;
function ParseDiscogsReleaseJson(const Json: string): TMBReleaseDetail;
{ 'Kim Larsen (2)' -> 'Kim Larsen'; 'Various' -> 'Various Artists'. }
function CleanDiscogsName(const S: string): string;
{ Splits a Discogs track position: '2-05' -> disc 2; 'CD2-3' -> disc 2; 'A1' -> disc 1. }
function DiscogsDisc(const Position: string): Integer;

implementation

uses
  SyncObjs, fpjson, jsonparser;

var
  RateLock: TCriticalSection;
  LastRequest: QWord = 0;

function AuthHeader(const Token: string): string;
begin
  if Trim(Token) <> '' then
    Result := 'Authorization: Discogs token=' + Trim(Token) + #13#10
  else
    Result := '';
end;

function DiscogsGet(const PathAndQuery, Token: string): string;
var
  Data: TBytes;
  Status, Attempt: Integer;
  Wait: Int64;
begin
  for Attempt := 1 to 3 do
  begin
    RateLock.Enter;
    try
      Wait := 1100 - Int64(GetTickCount64 - LastRequest);
      if Wait > 0 then Sleep(Wait);
      LastRequest := GetTickCount64;
    finally
      RateLock.Leave;
    end;
    Status := HttpGet('https://api.discogs.com/' + PathAndQuery, Data, AuthHeader(Token));
    case Status of
      200: Exit(BytesToString(Data));
      429: if Attempt < 3 then
           begin
             Sleep(3000 * Attempt);
             Continue;
           end
           else
             raise EWebError.Create('Discogs: for mange forespørgsler - vent et minut og prøv igen.');
      401: raise EWebError.Create('Discogs afviste dit token. Tjek det under "Discogs-token...".');
      404: raise EWebError.Create('Discogs kender ikke denne udgivelse');
    else
      raise EWebError.CreateFmt('Discogs svarede med fejl %d', [Status]);
    end;
  end;
  Result := '';
end;

{ ---------- JSON helpers (same idea as in MusicBrainz) ---------- }

function JStr(O: TJSONObject; const Key: string): string;
var
  D: TJSONData;
begin
  Result := '';
  if O = nil then Exit;
  D := O.Find(Key);
  if (D <> nil) and (D.JSONType in [jtString, jtNumber]) then Result := D.AsString;
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

function ArrStr(A: TJSONArray; I: Integer): string;
begin
  Result := '';
  if (A <> nil) and (I < A.Count) and (A.Items[I].JSONType = jtString) then
    Result := A.Items[I].AsString;
end;

function CleanDiscogsName(const S: string): string;
var
  P: Integer;
begin
  Result := Trim(S);
  // trailing ' (n)' added by Discogs to tell same-named artists apart
  P := Length(Result);
  if (P > 3) and (Result[P] = ')') then
  begin
    Dec(P);
    while (P > 0) and (Result[P] in ['0'..'9']) do Dec(P);
    if (P > 1) and (P < Length(Result) - 1) and (Result[P] = '(') and (Result[P - 1] = ' ') then
      Result := Copy(Result, 1, P - 2);
  end;
  if SameText(Result, 'Various') then Result := 'Various Artists';
end;

{ 'Artist A & Artist B' from an artists array (anv = name variation used on the release). }
function ArtistsText(A: TJSONArray): string;
var
  I: Integer;
  O: TJSONObject;
  Name, Join: string;
begin
  Result := '';
  if A = nil then Exit;
  for I := 0 to A.Count - 1 do
  begin
    O := ArrObj(A, I);
    Name := JStr(O, 'anv');
    if Name = '' then Name := JStr(O, 'name');
    Result := Result + CleanDiscogsName(Name);
    Join := Trim(JStr(O, 'join'));
    if I < A.Count - 1 then
    begin
      if (Join = '') or (Join = ',') then Result := Result + Join + ' '
      else Result := Result + ' ' + Join + ' ';
    end;
  end;
  Result := Trim(Result);
end;

function DiscogsDisc(const Position: string): Integer;
var
  P, Start: Integer;
  S: string;
begin
  Result := 1;
  S := UpperCase(Trim(Position));
  if Copy(S, 1, 2) = 'CD' then Delete(S, 1, 2);
  if Copy(S, 1, 3) = 'DVD' then Delete(S, 1, 3);
  // 'd-n' or 'd.n'
  P := 1;
  Start := 1;
  while (P <= Length(S)) and (S[P] in ['0'..'9']) do Inc(P);
  if (P > Start) and (P < Length(S)) and (S[P] in ['-', '.']) then
    Result := StrToIntDef(Copy(S, Start, P - Start), 1);
  if Result < 1 then Result := 1;
end;

{ Discogs durations are 'm:ss' or 'h:mm:ss'. }
function DurationMs(const S: string): Integer;
var
  Parts: TStringArray;
  I: Integer;
begin
  Result := 0;
  if Trim(S) = '' then Exit;
  Parts := Trim(S).Split([':']);
  for I := 0 to High(Parts) do
    Result := Result * 60 + StrToIntDef(Parts[I], 0);
  Result := Result * 1000;
end;

function ParseDiscogsSearchJson(const Json: string): TMBReleases;
var
  Root: TJSONData;
  A, Fmt, Lab: TJSONArray;
  O: TJSONObject;
  I, J, Dash: Integer;
  FullTitle: string;
begin
  Result := nil;
  Root := GetJSON(Json);
  try
    if Root.JSONType <> jtObject then Exit;
    A := JArr(TJSONObject(Root), 'results');
    if A = nil then Exit;
    SetLength(Result, A.Count);
    for I := 0 to A.Count - 1 do
    begin
      O := ArrObj(A, I);
      // Search titles are 'Artist - Album'.
      FullTitle := JStr(O, 'title');
      Dash := Pos(' - ', FullTitle);
      with Result[I] do
      begin
        Id := JStr(O, 'id');
        if Dash > 0 then
        begin
          Artist := CleanDiscogsName(Copy(FullTitle, 1, Dash - 1));
          Title := Copy(FullTitle, Dash + 3, MaxInt);
        end
        else
        begin
          Artist := '';
          Title := FullTitle;
        end;
        Date := JStr(O, 'year');
        Country := JStr(O, 'country');
        ReleaseGroupId := JStr(O, 'master_id');
        Disambiguation := '';
        Status := '';
        Score := 0;
        TrackCount := 0; // not part of Discogs search results
        Formats := '';
        Fmt := JArr(O, 'format');
        if Fmt <> nil then
          for J := 0 to Fmt.Count - 1 do
            if J < 3 then
            begin
              if Formats <> '' then Formats := Formats + ', ';
              Formats := Formats + ArrStr(Fmt, J);
            end;
        Lab := JArr(O, 'label');
        LabelName := ArrStr(Lab, 0);
        CatalogNo := JStr(O, 'catno');
      end;
    end;
  finally
    Root.Free;
  end;
end;

function ParseDiscogsReleaseJson(const Json: string): TMBReleaseDetail;
var
  Root: TJSONData;
  O, T, L, Img: TJSONObject;
  Tracks, Arr: TJSONArray;
  I, N, DiscNo: Integer;
  Released, TypeName: string;
  Counts: array of Integer;
begin
  Result.Tracks := nil;
  Result.DiscTrackCounts := nil;
  Result.DiscCount := 0;
  Result.CoverUrl := '';
  Result.Compilation := False;
  Root := GetJSON(Json);
  try
    if Root.JSONType <> jtObject then raise EWebError.Create('Uventet svar fra Discogs');
    O := TJSONObject(Root);
    with Result.Release do
    begin
      Id := JStr(O, 'id');
      Title := JStr(O, 'title');
      Artist := ArtistsText(JArr(O, 'artists'));
      Country := JStr(O, 'country');
      ReleaseGroupId := JStr(O, 'master_id');
      Disambiguation := '';
      Status := '';
      Score := 0;
      // 'released' may be '1975-10-14', '1975-00-00' or empty
      Released := JStr(O, 'released');
      if Copy(Released, 5, 6) = '-00-00' then Released := Copy(Released, 1, 4)
      else if Copy(Released, 8, 3) = '-00' then Released := Copy(Released, 1, 7);
      if Released = '' then Released := JStr(O, 'year');
      if Released = '0' then Released := '';
      Date := Released;
      Arr := JArr(O, 'labels');
      L := ArrObj(Arr, 0);
      LabelName := CleanDiscogsName(JStr(L, 'name'));
      CatalogNo := JStr(L, 'catno');
      Formats := '';
      Arr := JArr(O, 'formats');
      if Arr <> nil then
        for I := 0 to Arr.Count - 1 do
        begin
          if Formats <> '' then Formats := Formats + ' + ';
          if JStr(ArrObj(Arr, I), 'qty') <> '1' then
            Formats := Formats + JStr(ArrObj(Arr, I), 'qty') + '×';
          Formats := Formats + JStr(ArrObj(Arr, I), 'name');
        end;
    end;
    Result.AlbumArtist := Result.Release.Artist;
    Result.Compilation := SameText(Result.AlbumArtist, 'Various Artists');

    // Style is more specific than genre ('Hard Rock' vs 'Rock').
    Result.Genre := ArrStr(JArr(O, 'styles'), 0);
    if Result.Genre = '' then Result.Genre := ArrStr(JArr(O, 'genres'), 0);

    // Primary image first, else the first one.
    Arr := JArr(O, 'images');
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
      begin
        Img := ArrObj(Arr, I);
        if (Result.CoverUrl = '') or (JStr(Img, 'type') = 'primary') then
        begin
          Result.CoverUrl := JStr(Img, 'uri');
          if JStr(Img, 'type') = 'primary' then Break;
        end;
      end;

    Tracks := JArr(O, 'tracklist');
    Counts := nil;
    N := 0;
    if Tracks <> nil then
      for I := 0 to Tracks.Count - 1 do
      begin
        T := ArrObj(Tracks, I);
        TypeName := JStr(T, 'type_');
        // 'heading' = section title, not a track; 'index' = a track made of sub-tracks.
        if (TypeName <> '') and (TypeName <> 'track') and (TypeName <> 'index') then Continue;
        DiscNo := DiscogsDisc(JStr(T, 'position'));
        if DiscNo > Length(Counts) then SetLength(Counts, DiscNo);
        Inc(Counts[DiscNo - 1]);
        SetLength(Result.Tracks, N + 1);
        with Result.Tracks[N] do
        begin
          Number := JStr(T, 'position');
          Disc := DiscNo;
          Position := Counts[DiscNo - 1];
          Title := JStr(T, 'title');
          Artist := ArtistsText(JArr(T, 'artists'));
          if Artist = '' then Artist := Result.AlbumArtist;
          LengthMs := DurationMs(JStr(T, 'duration'));
        end;
        Inc(N);
      end;
    Result.DiscCount := Length(Counts);
    Result.DiscTrackCounts := Counts;
    Result.Release.TrackCount := N;
  finally
    Root.Free;
  end;
end;

function DiscogsSearch(const Artist, Album, Token: string): TMBReleases;
var
  Q: string;
begin
  if Trim(Token) = '' then
    raise EWebError.Create('Søgning på Discogs kræver et personligt token. Tryk "Discogs-token..." ' +
      'og indsæt det token, du kan lave på discogs.com under Settings > Developers.');
  Q := 'type=release&per_page=50';
  if Trim(Artist) <> '' then Q := Q + '&artist=' + UrlEncode(Trim(Artist));
  if Trim(Album) <> '' then Q := Q + '&release_title=' + UrlEncode(Trim(Album));
  Result := ParseDiscogsSearchJson(DiscogsGet('database/search?' + Q, Token));
end;

function DiscogsRelease(const ReleaseId, Token: string): TMBReleaseDetail;
begin
  Result := ParseDiscogsReleaseJson(DiscogsGet('releases/' + ReleaseId, Token));
end;

function DiscogsCover(const Url, Token: string): TBytes;
begin
  Result := nil;
  if Url = '' then Exit;
  if HttpGet(Url, Result, AuthHeader(Token)) <> 200 then Result := nil;
end;

initialization
  RateLock := TCriticalSection.Create;
finalization
  RateLock.Free;
end.
