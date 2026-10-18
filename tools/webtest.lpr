program WebTest;

{ Offline tests for the MusicBrainz JSON parsers and the file/track matching. }

{$mode objfpc}{$H+}

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  Classes, SysUtils, AudioTypes, MusicBrainz, TrackMatch, Discogs;

const
  ReleaseJson =
    '{"id":"r1","title":"Bedste \u00e6ndringer","date":"1999-05-01","country":"DK",' +
    '"artist-credit":[{"name":"Various Artists","joinphrase":"","artist":{"name":"Various Artists"}}],' +
    '"release-group":{"id":"rg1","primary-type":"Album","secondary-types":["Compilation"],' +
    '"genres":[{"name":"pop","count":3},{"name":"hard rock","count":5}]},' +
    '"label-info":[{"catalog-number":"CAT 1","label":{"name":"Pladeselskab"}}],' +
    '"media":[' +
    ' {"position":1,"format":"CD","track-count":2,"tracks":[' +
    '   {"position":1,"number":"1","title":"Sang A","length":180000,' +
    '    "artist-credit":[{"name":"Kunstner A","joinphrase":" feat. "},{"name":"Gæst","joinphrase":""}]},' +
    '   {"position":2,"number":"2","title":"Sang B","length":200500,' +
    '    "artist-credit":[{"name":"Kunstner B","joinphrase":""}]}]},' +
    ' {"position":2,"format":"CD","track-count":1,"tracks":[' +
    '   {"position":1,"number":"1","title":"Sang C","recording":{"length":99000},' +
    '    "artist-credit":[{"name":"Kunstner C","joinphrase":""}]}]}' +
    ']}';
  SearchJson =
    '{"created":"x","count":2,"offset":0,"releases":[' +
    ' {"id":"a","score":100,"title":"Gas 5","date":"1975","country":"DK","track-count":10,' +
    '  "artist-credit":[{"name":"Gasolin\u2019"}],"release-group":{"id":"g"},' +
    '  "media":[{"format":"12\" Vinyl","track-count":10}],' +
    '  "label-info":[{"catalog-number":"CBS 80993","label":{"name":"CBS"}}]},' +
    ' {"id":"b","score":88,"title":"Gas 5 & 6","media":[{"format":"CD"},{"format":"CD"}],' +
    '  "artist-credit":[{"name":"Gasolin\u2019"}]}' +
    ']}';

const
  RecordingJson =
    '{"count":3,"recordings":[' +
    ' {"id":"rec1","score":100,"title":"Sangen","artist-credit":[{"name":"Bandet","joinphrase":""}],"releases":[' +
    '   {"id":"comp","title":"De bedste","status":"Official","date":"2002-07-01","country":"DK","track-count":21,' +
    '    "release-group":{"id":"g1","primary-type":"Album","secondary-types":["Compilation"]},' +
    '    "media":[{"position":1,"format":"CD","track-offset":8,"track":[{"number":"9","title":"Sangen"}],"track-count":10}]},' +
    '   {"id":"alb","title":"Debut","status":"Official","date":"1975-10-14","country":"DK","track-count":10,' +
    '    "artist-credit":[{"name":"Bandet","joinphrase":""}],' +
    '    "release-group":{"id":"g2","primary-type":"Album"},' +
    '    "media":[{"position":1,"format":"12\" Vinyl","track-offset":2,"track":[{"number":"A3","title":"Sangen"}],"track-count":10}]}]},' +
    ' {"id":"rec2","score":98,"title":"Sangen","releases":[' +
    '   {"id":"alb","title":"Debut","status":"Official","date":"1975-10-14"},' +
    '   {"id":"single","title":"Sangen","status":"Official","date":"1975-09-01","track-count":2,' +
    '    "release-group":{"id":"g3","primary-type":"Single"},' +
    '    "media":[{"position":1,"format":"7\" Vinyl","track-offset":0,"track":[{"number":"A","title":"Sangen"}]}]},' +
    '   {"id":"boot","title":"Live bootleg","status":"Bootleg","date":"1970","release-group":{"primary-type":"Album"}}]},' +
    ' {"id":"rec3","score":45,"title":"En helt anden sang","releases":[{"id":"other","title":"Andet"}]}' +
    ']}';

  DiscogsSearchJson =
    '{"pagination":{"items":2},"results":[' +
    ' {"id":1234,"type":"release","title":"Gasolin'' (2) - Gas 5","year":"1975","country":"Denmark",' +
    '  "format":["Vinyl","LP","Album","Stereo"],"label":["CBS","CBS"],"catno":"CBS 80993","master_id":99},' +
    ' {"id":5678,"type":"release","title":"Gasolin''","year":"1991","format":["CD"],"label":[],"catno":""}' +
    ']}';
  DiscogsReleaseJson =
    '{"id":1234,"title":"Gas 5","released":"1975-00-00","year":1975,"country":"Denmark","master_id":99,' +
    '"artists":[{"name":"Gasolin'' (2)","anv":"","join":""}],' +
    '"labels":[{"name":"CBS (3)","catno":"CBS 80993"}],' +
    '"formats":[{"name":"Vinyl","qty":"1"}],' +
    '"genres":["Rock"],"styles":["Hard Rock","Pop Rock"],' +
    '"images":[{"type":"secondary","uri":"https://i.discogs.com/back.jpg"},' +
    '          {"type":"primary","uri":"https://i.discogs.com/front.jpg"}],' +
    '"tracklist":[' +
    ' {"position":"","type_":"heading","title":"Side A"},' +
    ' {"position":"A1","type_":"track","title":"Rabalderstræde","duration":"4:57","artists":[]},' +
    ' {"position":"A2","type_":"track","title":"Fatherless Hill","duration":"4:15",' +
    '  "artists":[{"name":"Kim Larsen (2)","anv":"Kim","join":"&"},{"name":"Franz Beckerlee","anv":"","join":""}]},' +
    ' {"position":"B1","type_":"index","title":"Medley","duration":"1:02:03","sub_tracks":[]}' +
    ']}';
  DiscogsMultiDiscJson =
    '{"id":1,"title":"Boks","released":"2001-05-00","artists":[{"name":"Various","join":""}],' +
    '"tracklist":[{"position":"1-1","title":"a"},{"position":"1-2","title":"b"},' +
    '{"position":"2-1","title":"c"},{"position":"CD2-2","title":"d"}]}';

var
  Failures: Integer = 0;

procedure Check(Cond: Boolean; const What: string);
begin
  if Cond then WriteLn('ok   ', What)
  else
  begin
    WriteLn('FEJL ', What);
    Inc(Failures);
  end;
end;

procedure Eq(const Got, Expected, What: string);
begin
  Check(Got = Expected, Format('%s: "%s"%s', [What, Got,
    BoolToStr(Got = Expected, '', ' (forventet "' + Expected + '")')]));
end;

function MakeFile(const Name, Track, Disc: string): TAudioInfo;
begin
  Result := TAudioInfo.Create;
  Result.FileName := 'C:\x\' + Name;
  Result.Fields[tfTrack] := Track;
  Result.Fields[tfDisc] := Disc;
  Result.Fields[tfComment] := 'bevares';
end;

var
  R: TMBReleases;
  D: TMBReleaseDetail;
  Files: array of TAudioInfo;
  Rows: TMatchRows;
  Method: TMatchMethod;
  Opt: TWebWriteOptions;
  I: Integer;
begin
  SetMultiByteConversionCodePage(CP_UTF8);
  {$IFDEF WINDOWS}SetConsoleOutputCP(CP_UTF8);{$ENDIF}
  SetTextCodePage(Output, CP_UTF8);

  WriteLn('-- søgesvar');
  R := ParseSearchJson(SearchJson);
  Check(Length(R) = 2, '2 udgivelser');
  Eq(R[0].Artist, 'Gasolin’', 'unicode-escape i kunstner');
  Eq(R[0].Formats, '12" Vinyl', 'format');
  Eq(R[0].LabelName + ' / ' + R[0].CatalogNo, 'CBS / CBS 80993', 'label');
  Eq(R[1].Formats, '2×CD', 'flere diske');
  Check(R[1].Date = '', 'manglende dato er tom');

  WriteLn('-- udgivelse');
  D := ParseReleaseJson(ReleaseJson);
  Eq(D.Release.Title, 'Bedste ændringer', 'titel med \u00e6');
  Check(D.Compilation, 'opsamling genkendt');
  Eq(D.Genre, 'Hard Rock', 'genre fra release-group, højeste antal');
  Check(D.DiscCount = 2, '2 diske');
  Check(Length(D.Tracks) = 3, '3 spor');
  Eq(D.Tracks[0].Artist, 'Kunstner A feat. Gæst', 'kunstner med joinphrase');
  Check((D.Tracks[2].Disc = 2) and (D.Tracks[2].Position = 1), 'disk 2 spor 1');
  Check(D.Tracks[2].LengthMs = 99000, 'længde fra recording');

  WriteLn('-- matchning');
  SetLength(Files, 3);
  Files[0] := MakeFile('c.mp3', '1', '2');
  Files[1] := MakeFile('a.mp3', '1/2', '1/2');
  Files[2] := MakeFile('b.mp3', '02', '');
  Rows := MatchFilesToTracks(Files, D, Method);
  Check(Method = mmNumber, 'matchet efter numre');
  Check((Rows[0].FileIdx = 1) and (Rows[1].FileIdx = 2) and (Rows[2].FileIdx = 0), 'rigtige par efter disk/spor');

  Files[2].Fields[tfTrack] := '';
  Rows := MatchFilesToTracks(Files, D, Method);
  Check(Method = mmOrder, 'falder tilbage til rækkefølge');
  Check((Rows[0].FileIdx = 0) and (Rows[1].FileIdx = 1) and (Rows[2].FileIdx = 2), 'rækkefølge');
  MoveFile(Rows, 0, 1);
  Check((Rows[0].FileIdx = 1) and (Rows[1].FileIdx = 0), 'flyt ned');

  SetLength(Files, 4);
  Files[3] := MakeFile('ekstra.mp3', '', '');
  Rows := MatchFilesToTracks(Files, D, Method);
  Check((Length(Rows) = 4) and (Rows[3].TrackIdx = -1) and (Rows[3].FileIdx = 3), 'ekstra fil uden spor');

  WriteLn('-- matchning efter titel og sangsøgning');
  SetLength(Files, 2);
  Files[0].Fields[tfTitle] := 'SANG b!';
  Files[1].Fields[tfTitle] := 'Sang C (Remastered 2011)';
  Rows := MatchFilesToTracks(Files, D, Method);
  Check(Method = mmTitle, 'matchet efter titler');
  Check((Rows[1].FileIdx = 0) and (Rows[2].FileIdx = 1), 'titel uden store/små og tegn; parentes ignoreres');
  Files[1].Fields[tfTitle] := 'Sang A';
  Files[1].Fields[tfTrack] := '7';
  Rows := MatchFilesToTracks(Files, D, Method);
  Check((Method = mmTitle) and (Rows[0].FileIdx = 1), 'titel slår et forkert spornummer');
  SetLength(Files, 1);
  Files[0].Fields[tfTitle] := 'Ukendt titel';
  Files[0].Fields[tfTrack] := '1';
  Rows := MatchFilesToTracks(Files, D, Method, 2, 1);
  Check((Method = mmHit) and (Rows[2].FileIdx = 0), 'én fil: sporet fra sangsøgningen (disk 2 spor 1)');
  Rows := MatchFilesToTracks(Files, D, Method);
  Check((Method = mmNumber) and (Rows[2].FileIdx = 0), 'uden søgehit: disk/spornummer (disk 2 spor 1)');
  Eq(NormTitle('Rock''n''Roll [Live] (1975)', True), 'rocknroll', 'normaliseret titel');
  SetLength(Files, 4);
  Files[1] := MakeFile('a.mp3', '1/2', '1/2');
  Files[2] := MakeFile('b.mp3', '02', '');
  Files[3] := MakeFile('ekstra.mp3', '', '');

  WriteLn('-- sangsøgning');
  R := ParseRecordingSearchJson(RecordingJson);
  Check(Length(R) = 4, Format('4 udgivelser (dubletter og svage hits fjernet): %d', [Length(R)]));
  if Length(R) = 4 then
  begin
    Eq(R[0].Id + ' ' + R[1].Id + ' ' + R[2].Id + ' ' + R[3].Id, 'alb single comp boot',
      'album først, så single, opsamling, bootleg');
    Eq(R[0].ReleaseType, 'Album', 'type album');
    Eq(R[2].ReleaseType, 'Compilation', 'type opsamling');
    Check((R[0].HitDisc = 1) and (R[0].HitPosition = 3), 'sangens plads på albummet (track-offset + 1)');
    Eq(R[2].Artist, 'Bandet', 'kunstner fra optagelsen, når udgivelsen ikke har en');
    Check(R[2].TrackCount = 21, 'sporantal for hele udgivelsen');
  end;
  Eq(BuildRecordingQuery('Gasolin''', 'Rabalderstræde', ''), 'recording:"Rabalderstræde" AND artist:"Gasolin''"',
    'forespørgsel for sang');

  WriteLn('-- anvend spor');
  Opt.Fields := [tfTitle, tfArtist, tfAlbum, tfAlbumArtist, tfYear, tfTrack, tfDisc, tfGenre];
  Opt.YearOnly := True;
  Opt.TrackWithTotal := True;
  ApplyTrack(Files[0], D, 1, Opt);
  Eq(Files[0].Fields[tfTitle], 'Sang B', 'titel');
  Eq(Files[0].Fields[tfAlbumArtist], 'Various Artists', 'albumkunstner');
  Eq(Files[0].Fields[tfYear], '1999', 'kun årstal');
  Eq(Files[0].Fields[tfTrack], '02/02', 'spor med total for disken');
  Eq(Files[0].Fields[tfDisc], '1/2', 'disk');
  Eq(Files[0].Fields[tfComment], 'bevares', 'andre felter røres ikke');
  Opt.Fields := [tfTitle];
  Opt.TrackWithTotal := False;
  Files[1].Fields[tfArtist] := 'Uændret';
  ApplyTrack(Files[1], D, 2, Opt);
  Eq(Files[1].Fields[tfTitle] + ' / ' + Files[1].Fields[tfArtist], 'Sang C / Uændret', 'kun valgte felter');
  for I := 0 to High(Files) do Files[I].Free;

  WriteLn('-- Discogs');
  Eq(CleanDiscogsName('Kim Larsen (2)'), 'Kim Larsen', 'fjern (2)');
  Eq(CleanDiscogsName('Blink-182'), 'Blink-182', 'tal uden parentes bevares');
  Eq(CleanDiscogsName('Various'), 'Various Artists', 'Various');
  Check((DiscogsDisc('A1') = 1) and (DiscogsDisc('2-05') = 2) and (DiscogsDisc('CD3-1') = 3) and
    (DiscogsDisc('12') = 1), 'diskposition');
  R := ParseDiscogsSearchJson(DiscogsSearchJson);
  Check(Length(R) = 2, '2 søgeresultater');
  Eq(R[0].Artist + ' / ' + R[0].Title, 'Gasolin'' / Gas 5', 'kunstner/titel delt');
  Eq(R[0].Formats, 'Vinyl, LP, Album', 'format (højst 3)');
  Eq(R[0].ReleaseType, 'Album', 'type fra formatbeskrivelsen');
  Eq(R[0].LabelName + ' ' + R[0].CatalogNo, 'CBS CBS 80993', 'label');
  Eq(R[0].Id, '1234', 'id');
  Eq(R[1].Artist + '|' + R[1].Title, '|Gasolin''', 'titel uden bindestreg');
  D := ParseDiscogsReleaseJson(DiscogsReleaseJson);
  Eq(D.Release.Artist, 'Gasolin''', 'udgivelseskunstner renset');
  Eq(D.Release.Date, '1975', 'dato 1975-00-00 -> 1975');
  Eq(D.Release.LabelName, 'CBS', 'label renset');
  Eq(D.Genre, 'Hard Rock', 'stil foran genre');
  Eq(D.CoverUrl, 'https://i.discogs.com/front.jpg', 'primært billede');
  Check(Length(D.Tracks) = 3, 'overskrift er ikke et spor');
  Eq(D.Tracks[0].Title, 'Rabalderstræde', 'unicode-titel');
  Eq(D.Tracks[0].Artist, 'Gasolin''', 'sporkunstner = albumkunstner');
  Eq(D.Tracks[1].Artist, 'Kim & Franz Beckerlee', 'anv + join');
  Check((D.Tracks[2].Position = 3) and (D.Tracks[2].Number = 'B1'), 'løbenummer over vinylsider');
  Check(D.Tracks[2].LengthMs = 3723000, 'varighed h:mm:ss');
  Check((D.DiscCount = 1) and (D.DiscTrackCounts[0] = 3), '1 disk med 3 spor');
  D := ParseDiscogsReleaseJson(DiscogsMultiDiscJson);
  Check(D.Compilation, 'Various = opsamling');
  Eq(D.Release.Date, '2001-05', 'dato 2001-05-00 -> 2001-05');
  Check((D.DiscCount = 2) and (D.Tracks[3].Disc = 2) and (D.Tracks[3].Position = 2), 'CD2-2 = disk 2 spor 2');

  WriteLn('-- URL og forespørgsel');
  Eq(UrlEncode('Æ ø/"'), '%C3%86%20%C3%B8%2F%22', 'url-kodning');
  Eq(BuildReleaseQuery('A "B"', ''), 'artist:"A \"B\""', 'escaping af citationstegn');

  WriteLn;
  if Failures = 0 then WriteLn('ALLE TESTS OK') else WriteLn(Failures, ' FEJL');
  ExitCode := Ord(Failures > 0);
end.
