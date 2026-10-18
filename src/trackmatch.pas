unit TrackMatch;

{ Pairs the user's files with the tracks of a MusicBrainz release, and turns a
  release track into tag values. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, AudioTypes, MusicBrainz;

type
  TMatchRow = record
    TrackIdx: Integer;  // index in Detail.Tracks, -1 = no track for this row
    FileIdx: Integer;   // index in the file array, -1 = no file
  end;
  TMatchRows = array of TMatchRow;

  TWebFieldSet = set of TTagField;
  TMatchMethod = (mmTitle, mmHit, mmNumber, mmOrder);

  TWebWriteOptions = record
    Fields: TWebFieldSet;     // which fields to fill
    YearOnly: Boolean;        // '1975-10-14' -> '1975'
    TrackWithTotal: Boolean;  // '07/10' instead of '7'
  end;

{ Rows = max(tracks, files). Files are paired by title when every file's title matches
  exactly one track; a single file goes to HitDisc/HitPos (the song a song search found);
  then by disc/track numbers when every file has one on the release; else in list order. }
function MatchFilesToTracks(const Files: array of TAudioInfo; const Detail: TMBReleaseDetail;
  out Method: TMatchMethod; HitDisc: Integer = 0; HitPos: Integer = 0): TMatchRows;
{ Title for comparing: lower case, letters and digits only; Strip also drops (...) and [...]. }
function NormTitle(const S: string; Strip: Boolean): string;
procedure MoveFile(var Rows: TMatchRows; Row, Delta: Integer);
{ Writes the chosen fields of a release track into Info.Fields. }
procedure ApplyTrack(Info: TAudioInfo; const Detail: TMBReleaseDetail; TrackIdx: Integer;
  const Opt: TWebWriteOptions);

implementation

uses
  TrackCore;

function NormTitle(const S: string; Strip: Boolean): string;
var
  U: UnicodeString;
  C: WideChar;
  Depth: Integer;
begin
  U := WideLowerCase(UTF8Decode(S));
  Result := '';
  Depth := 0;
  for C in U do
  begin
    if Strip and ((C = '(') or (C = '[')) then Inc(Depth)
    else if Strip and ((C = ')') or (C = ']')) then
    begin
      if Depth > 0 then Dec(Depth);
    end
    else if (Depth = 0) and ((WideUpperCase(C) <> WideLowerCase(C)) or ((C >= '0') and (C <= '9'))) then
      Result := Result + UTF8Encode(UnicodeString(C));
  end;
end;

{ Index of the only unused track whose title matches T (full, else without brackets); -1 if none or several. }
function FindTitle(const Detail: TMBReleaseDetail; const T: string; const Used: array of Boolean): Integer;
var
  Pass, J, Hits: Integer;
  Want: string;
begin
  Result := -1;
  for Pass := 0 to 1 do
  begin
    Want := NormTitle(T, Pass = 1);
    if Want = '' then Exit;
    Hits := 0;
    for J := 0 to High(Detail.Tracks) do
      if not Used[J] and (NormTitle(Detail.Tracks[J].Title, Pass = 1) = Want) then
      begin
        Inc(Hits);
        Result := J;
      end;
    if Hits = 1 then Exit;
    Result := -1;
    if Hits > 1 then Exit;
  end;
end;

function MatchFilesToTracks(const Files: array of TAudioInfo; const Detail: TMBReleaseDetail;
  out Method: TMatchMethod; HitDisc: Integer; HitPos: Integer): TMatchRows;
var
  NT, NF, N, I, J, Num, Total, Disc, Found: Integer;
  Used: array of Boolean;
  Pick: array of Integer;
  ByNumber, ByTitle: Boolean;
begin
  NT := Length(Detail.Tracks);
  NF := Length(Files);
  N := NT;
  if NF > N then N := NF;
  Result := nil;
  SetLength(Result, N);
  for I := 0 to N - 1 do
  begin
    if I < NT then Result[I].TrackIdx := I else Result[I].TrackIdx := -1;
    Result[I].FileIdx := -1;
  end;

  Pick := nil;
  SetLength(Pick, NF);
  // Titles first: also right for single songs whose track number is from another release.
  Used := nil;
  SetLength(Used, NT);
  ByTitle := (NF > 0) and (NF <= NT);
  if ByTitle then
    for I := 0 to NF - 1 do
    begin
      Found := FindTitle(Detail, Files[I].Fields[tfTitle], Used);
      if Found < 0 then
      begin
        ByTitle := False;
        Break;
      end;
      Used[Found] := True;
      Pick[I] := Found;
    end;
  if ByTitle then
  begin
    Method := mmTitle;
    for I := 0 to NF - 1 do Result[Pick[I]].FileIdx := I;
    Exit;
  end;
  // One file and a song search: the track the search found.
  if (NF = 1) and (HitPos > 0) then
    for J := 0 to NT - 1 do
      if (Detail.Tracks[J].Position = HitPos) and ((HitDisc = 0) or (Detail.Tracks[J].Disc = HitDisc)) then
      begin
        Method := mmHit;
        Result[J].FileIdx := 0;
        Exit;
      end;

  // Try disc/track numbers: all-or-nothing, so a half-tagged album is not mixed up.
  ByNumber := (NF > 0) and (NF <= NT);
  Used := nil;
  SetLength(Used, NT);
  if ByNumber then
    for I := 0 to NF - 1 do
    begin
      if not ParseTrack(Files[I].Fields[tfTrack], Num, Total) then
      begin
        ByNumber := False;
        Break;
      end;
      if not ParseTrack(Files[I].Fields[tfDisc], Disc, Total) then Disc := 1;
      Found := -1;
      for J := 0 to NT - 1 do
        if (Detail.Tracks[J].Disc = Disc) and (Detail.Tracks[J].Position = Num) then
        begin
          Found := J;
          Break;
        end;
      if (Found < 0) or Used[Found] then
      begin
        ByNumber := False;
        Break;
      end;
      Used[Found] := True;
      Pick[I] := Found;
    end;

  if ByNumber then
  begin
    Method := mmNumber;
    for I := 0 to NF - 1 do
      Result[Pick[I]].FileIdx := I;
  end
  else
  begin
    Method := mmOrder;
    for I := 0 to NF - 1 do
      Result[I].FileIdx := I;
  end;
end;

procedure MoveFile(var Rows: TMatchRows; Row, Delta: Integer);
var
  Other, Tmp: Integer;
begin
  Other := Row + Delta;
  if (Row < 0) or (Row > High(Rows)) or (Other < 0) or (Other > High(Rows)) then Exit;
  Tmp := Rows[Row].FileIdx;
  Rows[Row].FileIdx := Rows[Other].FileIdx;
  Rows[Other].FileIdx := Tmp;
end;

procedure ApplyTrack(Info: TAudioInfo; const Detail: TMBReleaseDetail; TrackIdx: Integer;
  const Opt: TWebWriteOptions);
var
  T: TMBTrack;
  Year: string;
  Total: Integer;
begin
  T := Detail.Tracks[TrackIdx];
  if tfTitle in Opt.Fields then Info.Fields[tfTitle] := T.Title;
  if tfArtist in Opt.Fields then Info.Fields[tfArtist] := T.Artist;
  if tfAlbum in Opt.Fields then Info.Fields[tfAlbum] := Detail.Release.Title;
  if tfAlbumArtist in Opt.Fields then Info.Fields[tfAlbumArtist] := Detail.AlbumArtist;
  if (tfYear in Opt.Fields) and (Detail.Release.Date <> '') then
  begin
    Year := Detail.Release.Date;
    if Opt.YearOnly then Year := Copy(Year, 1, 4);
    Info.Fields[tfYear] := Year;
  end;
  if tfTrack in Opt.Fields then
  begin
    Total := 0;
    if (T.Disc >= 1) and (T.Disc <= Length(Detail.DiscTrackCounts)) then
      Total := Detail.DiscTrackCounts[T.Disc - 1];
    if Opt.TrackWithTotal then
      Info.Fields[tfTrack] := FormatTrack(T.Position, Total, nfTwoDigitsTotal)
    else
      Info.Fields[tfTrack] := IntToStr(T.Position);
  end;
  // Disc numbers only for real multi-disc releases.
  if (tfDisc in Opt.Fields) and (Detail.DiscCount > 1) then
    Info.Fields[tfDisc] := Format('%d/%d', [T.Disc, Detail.DiscCount]);
  if (tfGenre in Opt.Fields) and (Detail.Genre <> '') then
    Info.Fields[tfGenre] := Detail.Genre;
  if (tfPublisher in Opt.Fields) and (Detail.Release.LabelName <> '') then
    Info.Fields[tfPublisher] := Detail.Release.LabelName;
  if (tfCatalogNo in Opt.Fields) and (Detail.Release.CatalogNo <> '') then
    Info.Fields[tfCatalogNo] := Detail.Release.CatalogNo;
end;

end.
