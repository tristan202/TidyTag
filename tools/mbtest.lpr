program MBTest;

{ Live test of the MusicBrainz / Cover Art Archive client.
  Usage: mbtest "<artist>" "<album>" ["<song>"]  (with a song: song search; album may be "") }

{$mode objfpc}{$H+}

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  Classes, SysUtils, AudioTypes, MusicBrainz, TagUtils, TrackMatch;

var
  R: TMBReleases;
  D: TMBReleaseDetail;
  Cover: TBytes;
  I, W, H: Integer;
  T0: QWord;
  Song: string;
  F: TAudioInfo;
  Rows: TMatchRows;
  Method: TMatchMethod;
begin
  SetMultiByteConversionCodePage(CP_UTF8);
  SetMultiByteFileSystemCodePage(CP_UTF8);
  {$IFDEF WINDOWS}SetConsoleOutputCP(CP_UTF8);{$ENDIF}
  SetTextCodePage(Output, CP_UTF8);
  if ParamCount < 2 then
  begin
    WriteLn('Brug: mbtest "<kunstner>" "<album>"');
    Halt(2);
  end;
  try
    Song := '';
    if ParamCount >= 3 then Song := UTF8Encode(UnicodeString(ParamStr(3)));
    T0 := GetTickCount64;
    if Song <> '' then
    begin
      WriteLn('Forespørgsel: ', BuildRecordingQuery(UTF8Encode(UnicodeString(ParamStr(1))), Song,
        UTF8Encode(UnicodeString(ParamStr(2)))));
      R := SearchRecordings(UTF8Encode(UnicodeString(ParamStr(1))), Song, UTF8Encode(UnicodeString(ParamStr(2))));
    end
    else
    begin
      WriteLn('Forespørgsel: ', BuildReleaseQuery(UTF8Encode(UnicodeString(ParamStr(1))), UTF8Encode(UnicodeString(ParamStr(2)))));
      R := SearchReleases(UTF8Encode(UnicodeString(ParamStr(1))), UTF8Encode(UnicodeString(ParamStr(2))));
    end;
    WriteLn(Length(R), ' udgivelser (', GetTickCount64 - T0, ' ms)');
    for I := 0 to High(R) do
      if I < 8 then
        WriteLn(Format('  %3d  %s - %s [%s %s] %d spor, %s, %s %s  {%s; sang %d-%d}', [R[I].Score, R[I].Artist,
          R[I].Title, R[I].Date, R[I].Country, R[I].TrackCount, R[I].Formats, R[I].LabelName, R[I].CatalogNo,
          R[I].ReleaseType, R[I].HitDisc, R[I].HitPosition]));
    if Length(R) = 0 then Halt(1);
    T0 := GetTickCount64;
    D := GetReleaseDetail(R[0].Id);
    WriteLn('Detaljer (', GetTickCount64 - T0, ' ms): ', D.Release.Title, ' / ', D.AlbumArtist,
      ' / ', D.Release.Date, ' / genre: ', D.Genre, ' / diske: ', D.DiscCount,
      ' / opsamling: ', BoolToStr(D.Compilation, 'ja', 'nej'));
    for I := 0 to High(D.Tracks) do
      with D.Tracks[I] do
        WriteLn(Format('  %d-%.2d  %s - %s (%s)', [Disc, Position, Artist, Title, FormatDuration(LengthMs / 1000)]));
    if Song <> '' then
    begin
      F := TAudioInfo.Create;
      F.Fields[tfTitle] := Song;
      F.Fields[tfTrack] := '1';
      Rows := MatchFilesToTracks([F], D, Method, R[0].HitDisc, R[0].HitPosition);
      for I := 0 to High(Rows) do
        if Rows[I].FileIdx = 0 then
          WriteLn(Format('Filen parres med %d-%.2d %s (metode %d)', [D.Tracks[Rows[I].TrackIdx].Disc,
            D.Tracks[Rows[I].TrackIdx].Position, D.Tracks[Rows[I].TrackIdx].Title, Ord(Method)]));
      F.Free;
    end;
    T0 := GetTickCount64;
    Cover := GetFrontCover(R[0].Id, R[0].ReleaseGroupId, 500);
    if Cover = nil then
      WriteLn('Intet cover')
    else
    begin
      ImageDimensions(Cover, W, H);
      WriteLn(Format('Cover: %s, %d KB, %dx%d (%d ms)', [DetectImageMime(Cover), Length(Cover) div 1024, W, H,
        GetTickCount64 - T0]));
    end;
  except
    on E: Exception do
    begin
      WriteLn('FEJL: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
