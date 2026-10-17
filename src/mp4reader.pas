unit Mp4Reader;

{ MP4/M4A/M4B: iTunes-style metadata (moov/udta/meta/ilst) and audio properties. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, AudioTypes;

procedure ReadMp4(S: TStream; Info: TAudioInfo);

implementation

uses
  TagUtils;

const
  MaxMoovSize = 64 * 1024 * 1024;

{ Atom names in source use '@' for the copyright sign (byte $A9), e.g. '@nam'. }
function AtomIs(const B: TBytes; P: SizeInt; const Name: string): Boolean;
var
  I: Integer;
  C: Byte;
begin
  if (P < 0) or (P + 4 > Length(B)) then Exit(False);
  for I := 1 to 4 do
  begin
    if Name[I] = '@' then C := $A9 else C := Ord(Name[I]);
    if B[P + I - 1] <> C then Exit(False);
  end;
  Result := True;
end;

{ Reads one atom header at P inside [P, Limit). Returns False if it is malformed. }
function AtomHeader(const B: TBytes; P, Limit: SizeInt; out Size, HdrLen: Int64): Boolean;
begin
  Result := False;
  if P + 8 > Limit then Exit;
  Size := BE32(B, P);
  HdrLen := 8;
  if Size = 1 then
  begin
    if P + 16 > Limit then Exit;
    Size := Int64(BE64(B, P + 8));
    HdrLen := 16;
  end
  else if Size = 0 then
    Size := Limit - P;
  Result := (Size >= HdrLen) and (P + Size <= Limit);
end;

{ Payload of the first 'data' child of an ilst item. }
function FindData(const B: TBytes; P, Limit: SizeInt; out DataP, DataLen: SizeInt; out DataType: Cardinal): Boolean;
var
  Size, Hdr: Int64;
begin
  Result := False;
  while AtomHeader(B, P, Limit, Size, Hdr) do
  begin
    if AtomIs(B, P + 4, 'data') and (Size >= Hdr + 8) then
    begin
      DataType := BE32(B, P + Hdr) and $FFFFFF;
      DataP := P + Hdr + 8; // skip type indicator + locale
      DataLen := Size - Hdr - 8;
      Exit(True);
    end;
    Inc(P, Size);
  end;
end;

{ 'covr' may hold several 'data' children, one per image (13 = JPEG, 14 = PNG). }
procedure ReadCovers(const B: TBytes; P, Limit: SizeInt; Info: TAudioInfo);
var
  Size, Hdr: Int64;
  Mime: string;
begin
  while AtomHeader(B, P, Limit, Size, Hdr) do
  begin
    if AtomIs(B, P + 4, 'data') and (Size > Hdr + 8) then
    begin
      case BE32(B, P + Hdr) and $FFFFFF of
        13: Mime := 'image/jpeg';
        14: Mime := 'image/png';
      else
        Mime := '';
      end;
      Info.AddPicture(PicTypeFrontCover, Mime, '', Copy(B, P + Hdr + 8, Size - Hdr - 8));
    end;
    Inc(P, Size);
  end;
end;

{ iTunes freeform item '----': children 'mean' (com.apple.iTunes), 'name' and 'data'. }
procedure ReadFreeform(const B: TBytes; P, Limit: SizeInt; Info: TAudioInfo);
var
  Size, Hdr: Int64;
  Name, Value: string;
begin
  Name := '';
  Value := '';
  while AtomHeader(B, P, Limit, Size, Hdr) do
  begin
    if AtomIs(B, P + 4, 'name') and (Size > Hdr + 4) then
      Name := UpperCase(RawUTF8(B, P + Hdr + 4, Size - Hdr - 4))
    else if AtomIs(B, P + 4, 'data') and (Value = '') and (Size > Hdr + 8) then
      Value := CleanTagText(RawUTF8(B, P + Hdr + 8, Size - Hdr - 8));
    Inc(P, Size);
  end;
  if Value = '' then Exit;
  if Name = 'CONDUCTOR' then Info.SetField(tfConductor, Value)
  else if Name = 'LYRICIST' then Info.SetField(tfLyricist, Value)
  else if (Name = 'ORIGINALARTIST') or (Name = 'ORIGINAL ARTIST') then Info.SetField(tfOrigArtist, Value)
  else if Name = 'REMIXER' then Info.SetField(tfRemixer, Value)
  else if (Name = 'LABEL') or (Name = 'PUBLISHER') then Info.SetField(tfPublisher, Value)
  else if Name = 'CATALOGNUMBER' then Info.SetField(tfCatalogNo, Value)
  else if Name = 'ISRC' then Info.SetField(tfIsrc, Value)
  else if Name = 'ENCODEDBY' then Info.SetField(tfEncodedBy, Value)
  else if Name = 'URL' then Info.SetField(tfUrl, Value)
  else if Name = 'SUBTITLE' then Info.SetField(tfSubtitle, Value)
  else if Name = 'MOOD' then Info.SetField(tfMood, Value)
  else if (Name = 'INITIALKEY') or (Name = 'KEY') then Info.SetField(tfInitialKey, Value);
end;

procedure ParseIlstItem(const B: TBytes; P, Limit: SizeInt; ItemP: SizeInt; Info: TAudioInfo);
var
  DP, DL: SizeInt;
  DT: Cardinal;
  Txt: string;
  N, T: Word;

  function NumPair: string;
  begin
    N := BE16(B, DP + 2);
    T := BE16(B, DP + 4);
    if N = 0 then Exit('');
    Result := IntToStr(N);
    if T > 0 then Result := Result + '/' + IntToStr(T);
  end;

begin
  if AtomIs(B, ItemP, 'covr') then
  begin
    ReadCovers(B, P, Limit, Info);
    Exit;
  end;
  if AtomIs(B, ItemP, '----') then
  begin
    ReadFreeform(B, P, Limit, Info);
    Exit;
  end;
  if not FindData(B, P, Limit, DP, DL, DT) then Exit;
  if AtomIs(B, ItemP, 'trkn') then
    Info.SetField(tfTrack, NumPair)
  else if AtomIs(B, ItemP, 'disk') then
    Info.SetField(tfDisc, NumPair)
  else if AtomIs(B, ItemP, 'gnre') then
    Info.SetField(tfGenre, ID3GenreName(BE16(B, DP) - 1), False)
  else if AtomIs(B, ItemP, 'tmpo') then
  begin
    if BE16(B, DP) > 0 then Info.SetField(tfBpm, IntToStr(BE16(B, DP)));
  end
  else
  begin
    Txt := CleanTagText(RawUTF8(B, DP, DL));
    if AtomIs(B, ItemP, '@nam') then Info.SetField(tfTitle, Txt)
    else if AtomIs(B, ItemP, '@ART') then Info.SetField(tfArtist, Txt)
    else if AtomIs(B, ItemP, '@alb') then Info.SetField(tfAlbum, Txt)
    else if AtomIs(B, ItemP, '@day') then Info.SetField(tfYear, Txt)
    else if AtomIs(B, ItemP, '@gen') then Info.SetField(tfGenre, Txt)
    else if AtomIs(B, ItemP, '@cmt') then Info.SetField(tfComment, Txt)
    else if AtomIs(B, ItemP, 'aART') then Info.SetField(tfAlbumArtist, Txt)
    else if AtomIs(B, ItemP, '@wrt') then Info.SetField(tfComposer, Txt)
    else if AtomIs(B, ItemP, '@lyr') then Info.SetField(tfLyrics, Txt)
    else if AtomIs(B, ItemP, 'cprt') then Info.SetField(tfCopyright, Txt)
    else if AtomIs(B, ItemP, '@grp') then Info.SetField(tfGrouping, Txt)
    else if AtomIs(B, ItemP, 'sonm') then Info.SetField(tfSortTitle, Txt)
    else if AtomIs(B, ItemP, 'soar') then Info.SetField(tfSortArtist, Txt)
    else if AtomIs(B, ItemP, 'soaa') then Info.SetField(tfSortAlbumArtist, Txt)
    else if AtomIs(B, ItemP, 'soal') then Info.SetField(tfSortAlbum, Txt)
    else if AtomIs(B, ItemP, 'soco') then Info.SetField(tfSortComposer, Txt);
  end;
end;

procedure ParseAtoms(const B: TBytes; P, Limit: SizeInt; InIlst: Boolean; Info: TAudioInfo);
var
  Size, Hdr: Int64;
  Body, E: SizeInt;
  Ver: Byte;
  TimeScale: Cardinal;
  Dur: QWord;
begin
  while AtomHeader(B, P, Limit, Size, Hdr) do
  begin
    Body := P + Hdr;
    if InIlst then
      ParseIlstItem(B, Body, P + Size, P + 4, Info)
    else if AtomIs(B, P + 4, 'trak') or AtomIs(B, P + 4, 'mdia') or AtomIs(B, P + 4, 'minf') or
      AtomIs(B, P + 4, 'stbl') or AtomIs(B, P + 4, 'udta') then
      ParseAtoms(B, Body, P + Size, False, Info)
    else if AtomIs(B, P + 4, 'meta') then
    begin
      // Normally a full box (4 bytes version/flags); QuickTime style has no such prefix.
      if AtomIs(B, Body + 4, 'hdlr') then
        ParseAtoms(B, Body, P + Size, False, Info)
      else
        ParseAtoms(B, Body + 4, P + Size, False, Info);
    end
    else if AtomIs(B, P + 4, 'ilst') then
    begin
      Info.AddTagType('MP4');
      ParseAtoms(B, Body, P + Size, True, Info);
    end
    else if AtomIs(B, P + 4, 'mvhd') then
    begin
      Ver := B[Body];
      if Ver = 1 then
      begin
        TimeScale := BE32(B, Body + 20);
        Dur := BE64(B, Body + 24);
      end
      else
      begin
        TimeScale := BE32(B, Body + 12);
        Dur := BE32(B, Body + 16);
      end;
      if TimeScale > 0 then Info.Duration := Dur / TimeScale;
    end
    else if AtomIs(B, P + 4, 'stsd') and (Info.Codec = '') then
    begin
      // version/flags (4), entry count (4), first sample entry
      E := Body + 8;
      if AtomIs(B, E + 4, 'mp4a') then Info.Codec := 'AAC'
      else if AtomIs(B, E + 4, 'alac') then Info.Codec := 'ALAC'
      else if AtomIs(B, E + 4, 'ac-3') then Info.Codec := 'AC-3'
      else if AtomIs(B, E + 4, 'Opus') then Info.Codec := 'Opus'
      else if AtomIs(B, E + 4, 'fLaC') then Info.Codec := 'FLAC';
      if Info.Codec <> '' then
      begin
        // audio sample entry: 8 header + 8 reserved/dataref + 8 version/vendor
        Info.Channels := BE16(B, E + 24);
        Info.SampleRate := BE32(B, E + 32) shr 16;
      end;
    end;
    Inc(P, Size);
  end;
end;

procedure ReadMp4(S: TStream; Info: TAudioInfo);
var
  H, Moov: TBytes;
  Pos, Size, Hdr, MdatSize: Int64;
begin
  Info.Supported := True;
  Moov := nil;
  MdatSize := 0;
  Pos := 0;
  while Pos + 8 <= S.Size do
  begin
    S.Position := Pos;
    H := ReadStreamBytes(S, 16);
    if Length(H) < 8 then Break;
    Size := BE32(H, 0);
    Hdr := 8;
    if Size = 1 then
    begin
      Size := Int64(BE64(H, 8));
      Hdr := 16;
    end
    else if Size = 0 then
      Size := S.Size - Pos;
    if Size < Hdr then Break;
    if AtomIs(H, 4, 'moov') then
    begin
      if Size - Hdr > MaxMoovSize then
        raise Exception.Create('moov-atom er for stor');
      S.Position := Pos + Hdr;
      Moov := ReadStreamBytes(S, Size - Hdr);
    end
    else if AtomIs(H, 4, 'mdat') then
      Inc(MdatSize, Size - Hdr);
    Inc(Pos, Size);
  end;
  if Moov = nil then
    raise Exception.Create('Ingen moov-atom - ikke en gyldig MP4-fil');
  ParseAtoms(Moov, 0, Length(Moov), False, Info);
  if Info.Duration > 0 then
  begin
    if MdatSize = 0 then MdatSize := S.Size;
    Info.Bitrate := Round(MdatSize * 8 / Info.Duration / 1000);
  end;
end;

end.
