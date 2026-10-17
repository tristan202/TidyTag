unit FlacWriter;

{ Writes the editable fields and pictures into a FLAC file's metadata blocks.
  STREAMINFO, SEEKTABLE, CUESHEET, APPLICATION blocks and all Vorbis comments we do not
  edit (ReplayGain, MusicBrainz IDs, ...) are kept. If the new metadata fits in the old
  space (incl. padding) the file is updated in place; otherwise it is rewritten. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, AudioTypes;

procedure WriteFlacTags(const FileName: string; Info: TAudioInfo);
{ Vorbis comment body (vendor + entries) shared with a future Ogg writer. }
function BuildVorbisComment(const OldBody: TBytes; OldStart: SizeInt; Info: TAudioInfo;
  WithPictures: Boolean): TBytes;
function BuildFlacPicture(const Pic: TTagPicture): TBytes;

implementation

uses
  base64, TagUtils, Mp3Reader;

resourcestring
  rsMetadataBlokkenErForStor = 'Metadata-blokken er for stor (billedet er over 16 MB)';
  rsIkkeEnGyldigFlacFil = 'Ikke en gyldig FLAC-fil';
  rsFlacMetadataErAfkortet = 'FLAC-metadata er afkortet';
  rsUgyldigFlacMetadatablok = 'Ugyldig FLAC-metadatablok';
  rsFlacFilenManglerStreaminfo = 'FLAC-filen mangler STREAMINFO';


const
  NewPadding = 4096;
  MaxBlockLen = $FFFFFF;

type
  TBlock = record
    BlockType: Byte;
    Data: TBytes;
  end;

function IsManagedKey(const Key: string): Boolean;
begin
  case UpperCase(Key) of
    'TITLE', 'ARTIST', 'ALBUM', 'DATE', 'YEAR', 'TRACKNUMBER', 'TRACKTOTAL', 'TOTALTRACKS',
    'DISCNUMBER', 'DISCTOTAL', 'TOTALDISCS', 'GENRE', 'COMMENT', 'DESCRIPTION',
    'ALBUMARTIST', 'ALBUM ARTIST', 'ALBUM_ARTIST', 'COMPOSER', 'BPM',
    'METADATA_BLOCK_PICTURE', 'COVERART', 'COVERARTMIME',
    'LYRICS', 'UNSYNCEDLYRICS', 'CONDUCTOR', 'LYRICIST', 'ORIGINALARTIST', 'ORIGARTIST',
    'REMIXER', 'LABEL', 'ORGANIZATION', 'PUBLISHER', 'CATALOGNUMBER', 'ISRC', 'COPYRIGHT',
    'ENCODEDBY', 'ENCODED-BY', 'WEBSITE', 'URL', 'GROUPING', 'SUBTITLE', 'MOOD', 'KEY',
    'INITIALKEY', 'TITLESORT', 'ARTISTSORT', 'ALBUMARTISTSORT', 'ALBUMSORT', 'COMPOSERSORT',
    'COMPILATION', 'PODCAST':
      Result := True;
  else
    Result := False;
  end;
end;

function BuildFlacPicture(const Pic: TTagPicture): TBytes;
var
  B: TBytesStream;
  Mime, Desc: TBytes;
  W, H: Integer;
begin
  B := TBytesStream.Create;
  try
    Mime := UTF8Bytes(Pic.MimeType);
    Desc := UTF8Bytes(Pic.Description);
    ImageDimensions(Pic.Data, W, H);
    WriteBE32(B, Pic.PicType);
    WriteBE32(B, Length(Mime));
    WriteBytes(B, Mime);
    WriteBE32(B, Length(Desc));
    WriteBytes(B, Desc);
    WriteBE32(B, W);
    WriteBE32(B, H);
    WriteBE32(B, 24); // colour depth: typical value, informational only
    WriteBE32(B, 0);  // not an indexed-colour image
    WriteBE32(B, Length(Pic.Data));
    WriteBytes(B, Pic.Data);
    Result := StreamBytes(B);
  finally
    B.Free;
  end;
end;

function BuildVorbisComment(const OldBody: TBytes; OldStart: SizeInt; Info: TAudioInfo;
  WithPictures: Boolean): TBytes;
var
  Entries: TStringList;
  Vendor: string;
  P: SizeInt;
  VendorLen, Count, Len, I: Cardinal;
  Entry, Raw: string;
  Dest: TBytesStream;
  Pic: TBytes;
  K: Integer;

  procedure AddMulti(const Key, Value: string);
  var
    Parts: TStringArray;
    Part: string;
  begin
    if Value = '' then Exit;
    // The reader joins repeated keys with '; ' - split them again.
    Parts := Value.Split(['; ']);
    for Part in Parts do
      if Trim(Part) <> '' then Entries.Add(Key + '=' + Trim(Part));
  end;

  procedure AddOne(const Key, Value: string);
  begin
    if Value <> '' then Entries.Add(Key + '=' + Value);
  end;

  procedure AddNumberPair(const NumKey, TotalKey, Value: string);
  var
    Slash: Integer;
  begin
    if Value = '' then Exit;
    Slash := Pos('/', Value);
    if Slash > 0 then
    begin
      Entries.Add(NumKey + '=' + Trim(Copy(Value, 1, Slash - 1)));
      if Trim(Copy(Value, Slash + 1, MaxInt)) <> '' then
        Entries.Add(TotalKey + '=' + Trim(Copy(Value, Slash + 1, MaxInt)));
    end
    else
      Entries.Add(NumKey + '=' + Value);
  end;

begin
  Entries := TStringList.Create;
  Dest := TBytesStream.Create;
  try
    Vendor := 'TagKlon';
    if OldBody <> nil then
    begin
      P := OldStart;
      VendorLen := LE32(OldBody, P);
      Vendor := RawUTF8(OldBody, P + 4, VendorLen);
      Inc(P, 4 + Int64(VendorLen));
      Count := LE32(OldBody, P);
      Inc(P, 4);
      for I := 1 to Count do
      begin
        if P + 4 > Length(OldBody) then Break;
        Len := LE32(OldBody, P);
        Inc(P, 4);
        if P + Int64(Len) > Length(OldBody) then Break;
        Entry := RawUTF8(OldBody, P, Len);
        Inc(P, Len);
        if (Pos('=', Entry) > 1) and not IsManagedKey(Copy(Entry, 1, Pos('=', Entry) - 1)) then
          Entries.Add(Entry);
      end;
    end;
    AddMulti('TITLE', Info.Fields[tfTitle]);
    AddMulti('ARTIST', Info.Fields[tfArtist]);
    AddMulti('ALBUM', Info.Fields[tfAlbum]);
    AddMulti('ALBUMARTIST', Info.Fields[tfAlbumArtist]);
    if Info.Fields[tfYear] <> '' then Entries.Add('DATE=' + Info.Fields[tfYear]);
    AddNumberPair('TRACKNUMBER', 'TRACKTOTAL', Info.Fields[tfTrack]);
    AddNumberPair('DISCNUMBER', 'DISCTOTAL', Info.Fields[tfDisc]);
    AddMulti('GENRE', Info.Fields[tfGenre]);
    AddMulti('COMPOSER', Info.Fields[tfComposer]);
    if Info.Fields[tfBpm] <> '' then Entries.Add('BPM=' + Info.Fields[tfBpm]);
    if Info.Fields[tfComment] <> '' then Entries.Add('COMMENT=' + Info.Fields[tfComment]);
    AddMulti('CONDUCTOR', Info.Fields[tfConductor]);
    AddMulti('LYRICIST', Info.Fields[tfLyricist]);
    AddMulti('ORIGINALARTIST', Info.Fields[tfOrigArtist]);
    AddMulti('REMIXER', Info.Fields[tfRemixer]);
    AddMulti('LABEL', Info.Fields[tfPublisher]);
    AddOne('CATALOGNUMBER', Info.Fields[tfCatalogNo]);
    AddOne('ISRC', Info.Fields[tfIsrc]);
    AddOne('COPYRIGHT', Info.Fields[tfCopyright]);
    AddOne('ENCODEDBY', Info.Fields[tfEncodedBy]);
    AddOne('WEBSITE', Info.Fields[tfUrl]);
    AddOne('GROUPING', Info.Fields[tfGrouping]);
    AddOne('SUBTITLE', Info.Fields[tfSubtitle]);
    AddOne('MOOD', Info.Fields[tfMood]);
    AddOne('KEY', Info.Fields[tfInitialKey]);
    AddOne('TITLESORT', Info.Fields[tfSortTitle]);
    AddOne('ARTISTSORT', Info.Fields[tfSortArtist]);
    AddOne('ALBUMARTISTSORT', Info.Fields[tfSortAlbumArtist]);
    AddOne('ALBUMSORT', Info.Fields[tfSortAlbum]);
    AddOne('COMPOSERSORT', Info.Fields[tfSortComposer]);
    AddOne('COMPILATION', FlagValue(Info.Fields[tfCompilation]));
    AddOne('PODCAST', FlagValue(Info.Fields[tfPodcast]));
    AddOne('LYRICS', Info.Fields[tfLyrics]);
    if WithPictures then
      for K := 0 to High(Info.Pictures) do
      begin
        Pic := BuildFlacPicture(Info.Pictures[K]);
        SetLength(Raw, Length(Pic));
        if Length(Pic) > 0 then Move(Pic[0], Raw[1], Length(Pic));
        Entries.Add('METADATA_BLOCK_PICTURE=' + EncodeStringBase64(Raw));
      end;

    WriteLE32(Dest, Length(UTF8Bytes(Vendor)));
    WriteBytes(Dest, UTF8Bytes(Vendor));
    WriteLE32(Dest, Entries.Count);
    for I := 0 to Entries.Count - 1 do
    begin
      WriteLE32(Dest, Length(UTF8Bytes(Entries[I])));
      WriteBytes(Dest, UTF8Bytes(Entries[I]));
    end;
    Result := StreamBytes(Dest);
  finally
    Dest.Free;
    Entries.Free;
  end;
end;

procedure WriteBlock(Dest: TStream; BlockType: Byte; Last: Boolean; const Data: TBytes);
var
  N: Cardinal;
begin
  if Length(Data) > MaxBlockLen then
    raise Exception.Create(rsMetadataBlokkenErForStor);
  N := Length(Data);
  if Last then Dest.WriteByte(BlockType or $80) else Dest.WriteByte(BlockType);
  Dest.WriteByte(N shr 16);
  Dest.WriteByte((N shr 8) and $FF);
  Dest.WriteByte(N and $FF);
  WriteBytes(Dest, Data);
end;

procedure WriteFlacTags(const FileName: string; Info: TAudioInfo);
var
  Src, Dst: TFileStream;
  Prefix: Int64;
  H, CommentBody: TBytes;
  Blocks: array of TBlock;
  Last: Boolean;
  BlockType: Byte;
  Len: Cardinal;
  AudioStart, OldMetaLen, Needed, PadLen: Int64;
  Meta: TBytesStream;
  Kept: array of TBlock;
  I, N: Integer;
  Temp: string;
  Dummy: TID3Frames;
  DummyVer: Byte;
begin
  Meta := TBytesStream.Create;
  Src := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    ParseID3v2(Src, DummyVer, Dummy, Prefix); // keep an ID3v2 prefix as it is
    Src.Position := Prefix;
    H := ReadStreamBytes(Src, 4);
    if not BytesAre(H, 0, 'fLaC') then
      raise Exception.Create(rsIkkeEnGyldigFlacFil);

    Blocks := nil;
    CommentBody := nil;
    repeat
      H := ReadStreamBytes(Src, 4);
      if Length(H) < 4 then raise Exception.Create(rsFlacMetadataErAfkortet);
      Last := H[0] and $80 <> 0;
      BlockType := H[0] and $7F;
      Len := BE24(H, 1);
      if BlockType = 127 then raise Exception.Create(rsUgyldigFlacMetadatablok);
      N := Length(Blocks);
      SetLength(Blocks, N + 1);
      Blocks[N].BlockType := BlockType;
      Blocks[N].Data := ReadStreamBytes(Src, Len);
      if Length(Blocks[N].Data) <> Len then raise Exception.Create(rsFlacMetadataErAfkortet);
      if (BlockType = 4) and (CommentBody = nil) then CommentBody := Blocks[N].Data;
    until Last;
    AudioStart := Src.Position;
    OldMetaLen := AudioStart - (Prefix + 4);
    if (Length(Blocks) = 0) or (Blocks[0].BlockType <> 0) then
      raise Exception.Create(rsFlacFilenManglerStreaminfo);

    // New block order: STREAMINFO, other kept blocks, comments, pictures (padding last).
    Kept := nil;
    for I := 0 to High(Blocks) do
      if not (Blocks[I].BlockType in [1, 4, 6]) then
      begin
        SetLength(Kept, Length(Kept) + 1);
        Kept[High(Kept)] := Blocks[I];
      end;
    SetLength(Kept, Length(Kept) + 1);
    Kept[High(Kept)].BlockType := 4;
    Kept[High(Kept)].Data := BuildVorbisComment(CommentBody, 0, Info, False);
    for I := 0 to High(Info.Pictures) do
    begin
      SetLength(Kept, Length(Kept) + 1);
      Kept[High(Kept)].BlockType := 6;
      Kept[High(Kept)].Data := BuildFlacPicture(Info.Pictures[I]);
    end;

    Needed := 0;
    for I := 0 to High(Kept) do Inc(Needed, 4 + Length(Kept[I].Data));

    if (Needed = OldMetaLen) or (Needed + 4 <= OldMetaLen) then
      PadLen := OldMetaLen - Needed - 4  // -4 = no padding block at all
    else
      PadLen := NewPadding;

    for I := 0 to High(Kept) do
      WriteBlock(Meta, Kept[I].BlockType, (I = High(Kept)) and (PadLen < 0), Kept[I].Data);
    if PadLen >= 0 then
    begin
      Meta.WriteByte(1 or $80);
      Meta.WriteByte(PadLen shr 16);
      Meta.WriteByte((PadLen shr 8) and $FF);
      Meta.WriteByte(PadLen and $FF);
      WriteZeros(Meta, PadLen);
    end;

    if Meta.Size = OldMetaLen then
    begin
      FreeAndNil(Src);
      Dst := TFileStream.Create(FileName, fmOpenReadWrite or fmShareDenyWrite);
      try
        Dst.Position := Prefix + 4;
        Dst.WriteBuffer(Meta.Bytes[0], Meta.Size);
      finally
        Dst.Free;
      end;
    end
    else
    begin
      Temp := TempFileFor(FileName);
      try
        Dst := TFileStream.Create(Temp, fmCreate);
        try
          CopyStreamRange(Src, Dst, 0, Prefix + 4); // ID3v2 prefix + 'fLaC'
          Dst.WriteBuffer(Meta.Bytes[0], Meta.Size);
          CopyStreamRange(Src, Dst, AudioStart, Src.Size - AudioStart);
        finally
          Dst.Free;
        end;
        FreeAndNil(Src);
        ReplaceFileWith(Temp, FileName);
      except
        DeleteFile(Temp);
        raise;
      end;
    end;
  finally
    Src.Free;
    Meta.Free;
  end;
end;

end.
