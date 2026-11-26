program TagSet;

{ Developer tool: sets tag fields from the command line.
    tagset <file> artist="Kim Larsen" album="Midt om natten" track=1 ...
    tagset --scenario N <file>    (tagtest's edits 0, 1 and 2; TidyTag 2's write cross-check)
  Field names: title artist album year track disc genre comment albumartist composer bpm
  lyrics conductor lyricist origartist remixer label catalog isrc copyright encodedby url
  grouping subtitle mood key sorttitle sortartist sortalbumartist sortalbum sortcomposer
  Prints 'ok', or 'FEJL: <text>' with exit code 1. }

{$mode objfpc}{$H+}

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  Classes, SysUtils, AudioTypes, AudioTags, TagWriter;

const
  Names: array[TTagField] of string = ('title', 'artist', 'album', 'year', 'track', 'disc',
    'genre', 'comment', 'albumartist', 'composer', 'bpm', 'lyrics', 'conductor', 'lyricist',
    'origartist', 'remixer', 'label', 'catalog', 'isrc', 'copyright', 'encodedby', 'url',
    'grouping', 'subtitle', 'mood', 'key', 'sorttitle', 'sortartist', 'sortalbumartist',
    'sortalbum', 'sortcomposer', 'compilation', 'podcast', 'replaygain_track_gain',
    'replaygain_track_peak', 'replaygain_album_gain', 'replaygain_album_peak');

{ tagtest's 1x1 PNG, padded to Size with byte I = (I * 31 + 7) mod 256 (tagtest pads with
  Random; a fixed pattern lets TidyTag 2 build the very same picture). }
function TestPng(Size: Integer): TBytes;
const
  Tiny: array[0..66] of Byte = ($89, $50, $4E, $47, $0D, $0A, $1A, $0A, $00, $00, $00, $0D,
    $49, $48, $44, $52, $00, $00, $00, $01, $00, $00, $00, $01, $08, $06, $00, $00, $00,
    $1F, $15, $C4, $89, $00, $00, $00, $0A, $49, $44, $41, $54, $78, $9C, $63, $00, $01,
    $00, $00, $05, $00, $01, $0D, $0A, $2D, $B4, $00, $00, $00, $00, $49, $45, $4E, $44,
    $AE, $42, $60, $82);
var
  I: Integer;
begin
  Result := nil;
  if Size < Length(Tiny) then Size := Length(Tiny);
  SetLength(Result, Size);
  Move(Tiny[0], Result[0], Length(Tiny));
  for I := Length(Tiny) to Size - 1 do Result[I] := (I * 31 + 7) mod 256;
end;

procedure SetPicture(Info: TAudioInfo; Size: Integer);
begin
  SetLength(Info.Pictures, 1);
  Info.Pictures[0].PicType := PicTypeFrontCover;
  Info.Pictures[0].MimeType := 'image/png';
  Info.Pictures[0].Description := 'Forside æøå';
  Info.Pictures[0].Data := TestPng(Size);
end;

{ tagtest's Scenario edits: 0 = all fields + a small cover, 1 = a 400 KB cover,
  2 = some fields cleared and no pictures. }
procedure ApplyScenario(Info: TAudioInfo; N: Integer);
begin
  case N of
    0: begin
         Info.Fields[tfTitle] := 'Titel A – æøå ÆØÅ';
         Info.Fields[tfArtist] := 'Kunstner 漢字 Ünïcödé';
         Info.Fields[tfAlbum] := 'Album Ålborg';
         Info.Fields[tfYear] := '2001-02-03';
         Info.Fields[tfTrack] := '5/9';
         Info.Fields[tfDisc] := '2/3';
         Info.Fields[tfGenre] := 'Rock';
         Info.Fields[tfComment] := 'En kommentar';
         Info.Fields[tfAlbumArtist] := 'Diverse kunstnere';
         Info.Fields[tfComposer] := 'Carl Nielsen';
         Info.Fields[tfBpm] := '120';
         Info.Fields[tfLyrics] := 'Første linje æøå' + #13#10 + 'Anden linje' + #13#10 + '漢字';
         Info.Fields[tfConductor] := 'Dirigent Ø';
         Info.Fields[tfLyricist] := 'Tekstforfatter';
         Info.Fields[tfOrigArtist] := 'Oprindelig';
         Info.Fields[tfRemixer] := 'Remixer';
         Info.Fields[tfPublisher] := 'Pladeselskab A/S';
         Info.Fields[tfCatalogNo] := 'CAT 123';
         Info.Fields[tfIsrc] := 'DKABC2400001';
         Info.Fields[tfCopyright] := '© 2001 Nogen';
         Info.Fields[tfEncodedBy] := 'TidyTag';
         Info.Fields[tfUrl] := 'https://example.com/a?b=1';
         Info.Fields[tfGrouping] := 'Gruppe';
         Info.Fields[tfSubtitle] := 'Undertitel';
         Info.Fields[tfMood] := 'Glad';
         Info.Fields[tfInitialKey] := 'Am';
         Info.Fields[tfSortTitle] := 'Sort titel';
         Info.Fields[tfSortArtist] := 'Kunstner, Sort';
         Info.Fields[tfSortAlbumArtist] := 'Kunstnere, Diverse';
         Info.Fields[tfSortAlbum] := 'Ålborg, Album';
         Info.Fields[tfSortComposer] := 'Nielsen, Carl';
         Info.Fields[tfCompilation] := '1';
         Info.Fields[tfPodcast] := '1';
         Info.Fields[tfRGTrackGain] := '-6.52 dB';
         Info.Fields[tfRGTrackPeak] := '0.988553';
         Info.Fields[tfRGAlbumGain] := '-7.10 dB';
         Info.Fields[tfRGAlbumPeak] := '1.000000';
         SetPicture(Info, 0);
       end;
    1: SetPicture(Info, 400 * 1024);
    2: begin
         Info.Fields[tfComment] := '';
         Info.Fields[tfComposer] := '';
         Info.Fields[tfLyrics] := '';
         Info.Fields[tfMood] := '';
         Info.Fields[tfCatalogNo] := '';
         Info.Fields[tfUrl] := '';
         Info.Pictures := nil;
       end;
  end;
end;

var
  Info: TAudioInfo;
  I, Eq, First, Scen: Integer;
  Arg, Key, FileName: string;
  F: TTagField;
  Found: Boolean;
begin
  SetMultiByteConversionCodePage(CP_UTF8);
  SetMultiByteFileSystemCodePage(CP_UTF8);
  {$IFDEF WINDOWS}SetConsoleOutputCP(CP_UTF8);{$ENDIF}
  SetTextCodePage(Output, CP_UTF8);
  Scen := -1;
  First := 1;
  if (ParamCount >= 3) and (ParamStr(1) = '--scenario') then
  begin
    Scen := StrToIntDef(ParamStr(2), -1);
    First := 3;
  end;
  if (ParamCount < First + 1) and (Scen < 0) or (ParamCount < First) then
  begin
    WriteLn('Brug: tagset <fil> felt=værdi ...  |  tagset --scenario N <fil>');
    Halt(2);
  end;
  FileName := UTF8Encode(UnicodeString(ParamStr(First)));
  Info := ReadAudioInfo(FileName, True);
  try
    if Info.Error <> '' then
    begin
      WriteLn('FEJL: ', Info.Error);
      Halt(1);
    end;
    if Scen >= 0 then
      ApplyScenario(Info, Scen)
    else
      for I := First + 1 to ParamCount do
      begin
        Arg := UTF8Encode(UnicodeString(ParamStr(I)));
        Eq := Pos('=', Arg);
        Key := LowerCase(Copy(Arg, 1, Eq - 1));
        Found := False;
        for F := Low(TTagField) to High(TTagField) do
          if Names[F] = Key then
          begin
            Info.Fields[F] := Copy(Arg, Eq + 1, MaxInt);
            Found := True;
          end;
        if not Found then
        begin
          WriteLn('Ukendt felt: ', Key);
          Halt(2);
        end;
      end;
    try
      WriteAudioTags(Info, False);
    except
      on E: Exception do
      begin
        WriteLn('FEJL: ', E.Message);
        Halt(1);
      end;
    end;
    WriteLn('ok');
  finally
    Info.Free;
  end;
end.
