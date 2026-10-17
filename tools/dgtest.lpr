program DGTest;

{ Live test of the Discogs client.
    dgtest <release-id>                       release details + cover (no token needed)
    dgtest search "<artist>" "<album>" <token>  search (needs a personal token) }

{$mode objfpc}{$H+}

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  Classes, SysUtils, AudioTypes, MusicBrainz, Discogs, TagUtils;

var
  D: TMBReleaseDetail;
  R: TMBReleases;
  Cover: TBytes;
  I, W, H: Integer;
begin
  SetMultiByteConversionCodePage(CP_UTF8);
  {$IFDEF WINDOWS}SetConsoleOutputCP(CP_UTF8);{$ENDIF}
  SetTextCodePage(Output, CP_UTF8);
  try
    if (ParamCount >= 4) and (ParamStr(1) = 'search') then
    begin
      R := DiscogsSearch(UTF8Encode(UnicodeString(ParamStr(2))), UTF8Encode(UnicodeString(ParamStr(3))), ParamStr(4));
      WriteLn(Length(R), ' resultater');
      for I := 0 to High(R) do
        if I < 10 then
          WriteLn(Format('  %s  %s - %s [%s %s] %s, %s %s', [R[I].Id, R[I].Artist, R[I].Title, R[I].Date,
            R[I].Country, R[I].Formats, R[I].LabelName, R[I].CatalogNo]));
      Exit;
    end;
    if ParamCount < 1 then
    begin
      WriteLn('Brug: dgtest <release-id>   eller   dgtest search "<kunstner>" "<album>" <token>');
      Halt(2);
    end;
    D := DiscogsRelease(ParamStr(1), '');
    WriteLn(D.Release.Artist, ' - ', D.Release.Title, ' [', D.Release.Date, ' ', D.Release.Country, '] ',
      D.Release.Formats, ', ', D.Release.LabelName, ' ', D.Release.CatalogNo, ', genre: ', D.Genre,
      ', diske: ', D.DiscCount);
    for I := 0 to High(D.Tracks) do
      with D.Tracks[I] do
        WriteLn(Format('  %d-%.2d (%s)  %s - %s (%s)', [Disc, Position, Number, Artist, Title,
          FormatDuration(LengthMs / 1000)]));
    WriteLn('Cover-URL: ', D.CoverUrl);
    Cover := DiscogsCover(D.CoverUrl, '');
    if Cover = nil then
      WriteLn('Cover: kunne ikke hentes uden token')
    else
    begin
      ImageDimensions(Cover, W, H);
      WriteLn(Format('Cover: %s, %d KB, %dx%d', [DetectImageMime(Cover), Length(Cover) div 1024, W, H]));
    end;
  except
    on E: Exception do
    begin
      WriteLn('FEJL: ', E.Message);
      Halt(1);
    end;
  end;
end.
