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

  TWebWriteOptions = record
    Fields: TWebFieldSet;     // which fields to fill
    YearOnly: Boolean;        // '1975-10-14' -> '1975'
    TrackWithTotal: Boolean;  // '07/10' instead of '7'
  end;

{ Rows = max(tracks, files). Files are paired by their disc/track numbers when every
  file has one and they all exist on the release; otherwise in the given order. }
function MatchFilesToTracks(const Files: array of TAudioInfo; const Detail: TMBReleaseDetail;
  out ByNumber: Boolean): TMatchRows;
procedure MoveFile(var Rows: TMatchRows; Row, Delta: Integer);
{ Writes the chosen fields of a release track into Info.Fields. }
procedure ApplyTrack(Info: TAudioInfo; const Detail: TMBReleaseDetail; TrackIdx: Integer;
  const Opt: TWebWriteOptions);

implementation

uses
  TrackCore;

function MatchFilesToTracks(const Files: array of TAudioInfo; const Detail: TMBReleaseDetail;
  out ByNumber: Boolean): TMatchRows;
var
  NT, NF, N, I, J, Num, Total, Disc, Found: Integer;
  Used: array of Boolean;
  Pick: array of Integer;
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

  // Try disc/track numbers: all-or-nothing, so a half-tagged album is not mixed up.
  ByNumber := (NF > 0) and (NF <= NT);
  Pick := nil;
  SetLength(Pick, NF);
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
    for I := 0 to NF - 1 do
      Result[Pick[I]].FileIdx := I
  else
    for I := 0 to NF - 1 do
      Result[I].FileIdx := I;
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
