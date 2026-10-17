unit Mp4Writer;

{ Writes the editable fields and cover art into an MP4/M4A file's iTunes metadata
  (moov/udta/meta/ilst). Items we do not edit are kept.

  Growing or shrinking 'moov' moves the audio data when 'moov' sits before 'mdat'; the
  chunk offset tables (stco/co64) are then corrected. A 'free' atom right after 'moov'
  is used as slack first, so most edits only touch the start of the file. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, AudioTypes;

procedure WriteMp4Tags(const FileName: string; Info: TAudioInfo);

implementation

uses
  Contnrs, TagUtils;

resourcestring
  rsMetadataAtomErForStor = 'Metadata-atom er for stor';
  rsUgyldigAtomStrukturIMoov = 'Ugyldig atom-struktur i moov';
  rsUgyldigStcoTabel = 'Ugyldig stco-tabel';
  rsFilenBliverForStorTil = 'Filen bliver for stor til 32-bit chunk-offsets';
  rsUgyldigCoTabel = 'Ugyldig co64-tabel';
  rsUgyldigMpStruktur = 'Ugyldig MP4-struktur';
  rsFragmenteredeMpFilerUnderstoettesIkke = 'Fragmenterede MP4-filer understøttes ikke';
  rsIngenMoovAtomIkkeEn = 'Ingen moov-atom - ikke en gyldig MP4-fil';


const
  NewFreeSpace = 2048;

type
  TAtom = class
    Name: Cardinal;      // four-character code, big endian
    Prefix: TBytes;      // version/flags of full boxes we descend into ('meta')
    Data: TBytes;        // payload of leaf atoms
    Children: TObjectList;
    constructor Create(AName: Cardinal);
    destructor Destroy; override;
    function IsContainer: Boolean;
    function Find(AName: Cardinal): TAtom;
    function Add(AAtom: TAtom): TAtom;
    function TotalSize: Int64;
    procedure WriteTo(S: TStream);
  end;

function FourCC(const S: string): Cardinal;
var
  I: Integer;
  C: Byte;
begin
  Result := 0;
  for I := 1 to 4 do
  begin
    if S[I] = '@' then C := $A9 else C := Ord(S[I]);
    Result := (Result shl 8) or C;
  end;
end;

const
  ContainerNames: array[0..7] of string = ('moov', 'trak', 'mdia', 'minf', 'stbl', 'udta', 'meta', 'ilst');

constructor TAtom.Create(AName: Cardinal);
begin
  Name := AName;
  Children := TObjectList.Create(True);
end;

destructor TAtom.Destroy;
begin
  Children.Free;
  inherited Destroy;
end;

function TAtom.IsContainer: Boolean;
var
  N: string;
begin
  for N in ContainerNames do
    if FourCC(N) = Name then Exit(True);
  Result := False;
end;

function TAtom.Find(AName: Cardinal): TAtom;
var
  I: Integer;
begin
  for I := 0 to Children.Count - 1 do
    if TAtom(Children[I]).Name = AName then Exit(TAtom(Children[I]));
  Result := nil;
end;

function TAtom.Add(AAtom: TAtom): TAtom;
begin
  Children.Add(AAtom);
  Result := AAtom;
end;

function TAtom.TotalSize: Int64;
var
  I: Integer;
begin
  Result := 8 + Length(Prefix);
  if IsContainer then
    for I := 0 to Children.Count - 1 do
      Inc(Result, TAtom(Children[I]).TotalSize)
  else
    Inc(Result, Length(Data));
end;

procedure TAtom.WriteTo(S: TStream);
var
  I: Integer;
  Size: Int64;
begin
  Size := TotalSize;
  if Size > $FFFFFFFF then
    raise Exception.Create(rsMetadataAtomErForStor);
  WriteBE32(S, Size);
  WriteBE32(S, Name);
  WriteBytes(S, Prefix);
  if IsContainer then
    for I := 0 to Children.Count - 1 do
      TAtom(Children[I]).WriteTo(S)
  else
    WriteBytes(S, Data);
end;

{ Parses the atoms in B[P..Limit) into Parent. }
procedure ParseChildren(Parent: TAtom; const B: TBytes; P, Limit: SizeInt);
var
  Size, Hdr: Int64;
  A: TAtom;
  Body: SizeInt;
begin
  while P + 8 <= Limit do
  begin
    Size := BE32(B, P);
    Hdr := 8;
    if Size = 1 then
    begin
      Size := Int64(BE64(B, P + 8));
      Hdr := 16;
    end
    else if Size = 0 then
      Size := Limit - P;
    if (Size < Hdr) or (P + Size > Limit) then
      raise Exception.Create(rsUgyldigAtomStrukturIMoov);
    A := Parent.Add(TAtom.Create(BE32(B, P + 4)));
    Body := P + Hdr;
    if A.IsContainer then
    begin
      if A.Name = FourCC('meta') then
      begin
        // Normally a full box; QuickTime-style 'meta' has no version/flags.
        if not BytesAre(B, Body + 4, 'hdlr') then
        begin
          A.Prefix := Copy(B, Body, 4);
          Inc(Body, 4);
        end;
      end;
      ParseChildren(A, B, Body, P + Size);
    end
    else
      A.Data := Copy(B, Body, P + Size - Body);
    Inc(P, Size);
  end;
end;

function DataAtom(TypeCode: Cardinal; const Payload: TBytes): TAtom;
var
  S: TBytesStream;
begin
  Result := TAtom.Create(FourCC('data'));
  S := TBytesStream.Create;
  try
    WriteBE32(S, TypeCode);
    WriteBE32(S, 0); // locale
    WriteBytes(S, Payload);
    Result.Data := StreamBytes(S);
  finally
    S.Free;
  end;
end;

{ ilst items are containers of 'data' atoms; we build them as leafs with ready bytes. }
function ItemAtom(const Name: string; DataItems: array of TAtom): TAtom;
var
  S: TBytesStream;
  D: TAtom;
begin
  Result := TAtom.Create(FourCC(Name));
  S := TBytesStream.Create;
  try
    for D in DataItems do
    begin
      D.WriteTo(S);
      D.Free;
    end;
    Result.Data := StreamBytes(S);
  finally
    S.Free;
  end;
end;

procedure AddText(Ilst: TAtom; const Name, Value: string);
begin
  if Value <> '' then
    Ilst.Add(ItemAtom(Name, [DataAtom(1, UTF8Bytes(Value))]));
end;

procedure AddNumberPair(Ilst: TAtom; const Name, Value: string; ExtraZero: Boolean);
var
  Num, Total, Slash: Integer;
  S: TBytesStream;
begin
  if Value = '' then Exit;
  Slash := Pos('/', Value);
  if Slash > 0 then
  begin
    Num := StrToIntDef(Trim(Copy(Value, 1, Slash - 1)), 0);
    Total := StrToIntDef(Trim(Copy(Value, Slash + 1, MaxInt)), 0);
  end
  else
  begin
    Num := StrToIntDef(Trim(Value), 0);
    Total := 0;
  end;
  if (Num <= 0) or (Num > $FFFF) or (Total < 0) or (Total > $FFFF) then Exit;
  S := TBytesStream.Create;
  try
    WriteBE16(S, 0);
    WriteBE16(S, Num);
    WriteBE16(S, Total);
    if ExtraZero then WriteBE16(S, 0); // trkn has 8 bytes, disk 6
    Ilst.Add(ItemAtom(Name, [DataAtom(0, StreamBytes(S))]));
  finally
    S.Free;
  end;
end;

function IsManagedItem(Name: Cardinal): Boolean;
const
  Managed: array[0..22] of string = ('@nam', '@ART', '@alb', '@day', '@gen', 'gnre',
    '@cmt', 'aART', '@wrt', 'trkn', 'disk', 'tmpo', 'covr', '@lyr', 'cprt', '@grp',
    'sonm', 'soar', 'soaa', 'soal', 'soco', 'cpil', 'pcst');
var
  N: string;
begin
  for N in Managed do
    if FourCC(N) = Name then Exit(True);
  Result := False;
end;

const
  // Freeform names (----:com.apple.iTunes:NAME) we edit; others are kept.
  ManagedFreeform: array[0..17] of string = ('CONDUCTOR', 'LYRICIST', 'ORIGINALARTIST',
    'ORIGINAL ARTIST', 'REMIXER', 'LABEL', 'PUBLISHER', 'CATALOGNUMBER', 'ISRC', 'ENCODEDBY',
    'URL', 'SUBTITLE', 'MOOD', 'INITIALKEY', 'REPLAYGAIN_TRACK_GAIN', 'REPLAYGAIN_TRACK_PEAK',
    'REPLAYGAIN_ALBUM_GAIN', 'REPLAYGAIN_ALBUM_PEAK');

{ The 'name' of a freeform item, upper case; '' if it has none. }
function FreeformName(Item: TAtom): string;
var
  P: SizeInt;
  Size: Cardinal;
begin
  Result := '';
  P := 0;
  while P + 8 <= Length(Item.Data) do
  begin
    Size := BE32(Item.Data, P);
    if (Size < 8) or (P + Size > Length(Item.Data)) then Exit;
    if BytesAre(Item.Data, P + 4, 'name') and (Size > 12) then
      Exit(UpperCase(RawUTF8(Item.Data, P + 12, Size - 12)));
    Inc(P, Size);
  end;
end;

function IsManagedFreeform(Item: TAtom): Boolean;
var
  N, M: string;
begin
  Result := False;
  if Item.Name <> FourCC('----') then Exit;
  N := FreeformName(Item);
  for M in ManagedFreeform do
    if M = N then Exit(True);
end;

function PrefixedAtom(const Name, Text: string): TAtom;
var
  S: TBytesStream;
begin
  Result := TAtom.Create(FourCC(Name));
  S := TBytesStream.Create;
  try
    WriteBE32(S, 0); // version/flags
    WriteBytes(S, UTF8Bytes(Text));
    Result.Data := StreamBytes(S);
  finally
    S.Free;
  end;
end;

procedure AddFreeform(Ilst: TAtom; const Name, Value: string);
begin
  if Value <> '' then
    Ilst.Add(ItemAtom('----', [PrefixedAtom('mean', 'com.apple.iTunes'), PrefixedAtom('name', Name),
      DataAtom(1, UTF8Bytes(Value))]));
end;

function NewHdlr: TAtom;
var
  S: TBytesStream;
begin
  Result := TAtom.Create(FourCC('hdlr'));
  S := TBytesStream.Create;
  try
    WriteBE32(S, 0);       // version/flags
    WriteBE32(S, 0);       // pre-defined
    WriteAscii(S, 'mdir');
    WriteAscii(S, 'appl');
    WriteBE32(S, 0);
    WriteBE32(S, 0);
    S.WriteByte(0);        // empty name
    Result.Data := StreamBytes(S);
  finally
    S.Free;
  end;
end;

procedure UpdateIlst(Moov: TAtom; Info: TAudioInfo);
var
  Udta, Meta, Ilst: TAtom;
  I, Bpm: Integer;
  Covers: array of TAtom;
  S: TBytesStream;
  TypeCode: Cardinal;
begin
  Udta := Moov.Find(FourCC('udta'));
  if Udta = nil then Udta := Moov.Add(TAtom.Create(FourCC('udta')));
  Meta := Udta.Find(FourCC('meta'));
  if Meta = nil then
  begin
    Meta := Udta.Add(TAtom.Create(FourCC('meta')));
    SetLength(Meta.Prefix, 4);
    FillChar(Meta.Prefix[0], 4, 0);
    Meta.Add(NewHdlr);
  end;
  Ilst := Meta.Find(FourCC('ilst'));
  if Ilst = nil then Ilst := Meta.Add(TAtom.Create(FourCC('ilst')));

  // ilst children were parsed as containers of 'data' atoms; keep the ones we do not edit.
  for I := Ilst.Children.Count - 1 downto 0 do
    if IsManagedItem(TAtom(Ilst.Children[I]).Name) or IsManagedFreeform(TAtom(Ilst.Children[I])) then
      Ilst.Children.Delete(I);

  AddText(Ilst, '@nam', Info.Fields[tfTitle]);
  AddText(Ilst, '@ART', Info.Fields[tfArtist]);
  AddText(Ilst, '@alb', Info.Fields[tfAlbum]);
  AddText(Ilst, 'aART', Info.Fields[tfAlbumArtist]);
  AddText(Ilst, '@day', Info.Fields[tfYear]);
  AddNumberPair(Ilst, 'trkn', Info.Fields[tfTrack], True);
  AddNumberPair(Ilst, 'disk', Info.Fields[tfDisc], False);
  AddText(Ilst, '@gen', Info.Fields[tfGenre]);
  AddText(Ilst, '@wrt', Info.Fields[tfComposer]);
  AddText(Ilst, '@cmt', Info.Fields[tfComment]);
  AddText(Ilst, '@lyr', Info.Fields[tfLyrics]);
  AddText(Ilst, 'cprt', Info.Fields[tfCopyright]);
  AddText(Ilst, '@grp', Info.Fields[tfGrouping]);
  AddText(Ilst, 'sonm', Info.Fields[tfSortTitle]);
  AddText(Ilst, 'soar', Info.Fields[tfSortArtist]);
  AddText(Ilst, 'soaa', Info.Fields[tfSortAlbumArtist]);
  AddText(Ilst, 'soal', Info.Fields[tfSortAlbum]);
  AddText(Ilst, 'soco', Info.Fields[tfSortComposer]);
  AddFreeform(Ilst, 'CONDUCTOR', Info.Fields[tfConductor]);
  AddFreeform(Ilst, 'LYRICIST', Info.Fields[tfLyricist]);
  AddFreeform(Ilst, 'ORIGINALARTIST', Info.Fields[tfOrigArtist]);
  AddFreeform(Ilst, 'REMIXER', Info.Fields[tfRemixer]);
  AddFreeform(Ilst, 'LABEL', Info.Fields[tfPublisher]);
  AddFreeform(Ilst, 'CATALOGNUMBER', Info.Fields[tfCatalogNo]);
  AddFreeform(Ilst, 'ISRC', Info.Fields[tfIsrc]);
  AddFreeform(Ilst, 'ENCODEDBY', Info.Fields[tfEncodedBy]);
  AddFreeform(Ilst, 'URL', Info.Fields[tfUrl]);
  AddFreeform(Ilst, 'SUBTITLE', Info.Fields[tfSubtitle]);
  AddFreeform(Ilst, 'MOOD', Info.Fields[tfMood]);
  AddFreeform(Ilst, 'initialkey', Info.Fields[tfInitialKey]);
  Bpm := StrToIntDef(Trim(Info.Fields[tfBpm]), 0);
  if (Bpm > 0) and (Bpm <= $FFFF) then
  begin
    S := TBytesStream.Create;
    try
      WriteBE16(S, Bpm);
      Ilst.Add(ItemAtom('tmpo', [DataAtom(21, StreamBytes(S))]));
    finally
      S.Free;
    end;
  end;
  AddFreeform(Ilst, 'replaygain_track_gain', Info.Fields[tfRGTrackGain]);
  AddFreeform(Ilst, 'replaygain_track_peak', Info.Fields[tfRGTrackPeak]);
  AddFreeform(Ilst, 'replaygain_album_gain', Info.Fields[tfRGAlbumGain]);
  AddFreeform(Ilst, 'replaygain_album_peak', Info.Fields[tfRGAlbumPeak]);
  // flags: one byte, data type 21 (integer)
  if IsTrueFlag(Info.Fields[tfCompilation]) then Ilst.Add(ItemAtom('cpil', [DataAtom(21, TBytes.Create(1))]));
  if IsTrueFlag(Info.Fields[tfPodcast]) then Ilst.Add(ItemAtom('pcst', [DataAtom(21, TBytes.Create(1))]));
  if Length(Info.Pictures) > 0 then
  begin
    Covers := nil;
    SetLength(Covers, Length(Info.Pictures));
    for I := 0 to High(Info.Pictures) do
    begin
      if Info.Pictures[I].MimeType = 'image/png' then TypeCode := 14 else TypeCode := 13;
      Covers[I] := DataAtom(TypeCode, Info.Pictures[I].Data);
    end;
    Ilst.Add(ItemAtom('covr', Covers));
  end;
end;

{ Adds Delta to every chunk offset >= Threshold in all stco/co64 tables below A. }
procedure ShiftChunkOffsets(A: TAtom; Delta, Threshold: Int64);
var
  I: Integer;
  N, J: Cardinal;
  C: TAtom;
begin
  for I := 0 to A.Children.Count - 1 do
  begin
    C := TAtom(A.Children[I]);
    if C.IsContainer then
      ShiftChunkOffsets(C, Delta, Threshold)
    else if C.Name = FourCC('stco') then
    begin
      N := BE32(C.Data, 4);
      if 8 + Int64(N) * 4 > Length(C.Data) then raise Exception.Create(rsUgyldigStcoTabel);
      for J := 0 to N - 1 do
      begin
        if BE32(C.Data, 8 + J * 4) < Threshold then Continue;
        if Int64(BE32(C.Data, 8 + J * 4)) + Delta > $FFFFFFFF then
          raise Exception.Create(rsFilenBliverForStorTil);
        PutBE32(C.Data, 8 + J * 4, Int64(BE32(C.Data, 8 + J * 4)) + Delta);
      end;
    end
    else if C.Name = FourCC('co64') then
    begin
      N := BE32(C.Data, 4);
      if 8 + Int64(N) * 8 > Length(C.Data) then raise Exception.Create(rsUgyldigCoTabel);
      for J := 0 to N - 1 do
        if Int64(BE64(C.Data, 8 + J * 8)) >= Threshold then
          PutBE64(C.Data, 8 + J * 8, Int64(BE64(C.Data, 8 + J * 8)) + Delta);
    end;
  end;
end;

type
  TTopAtom = record
    Name: Cardinal;
    Pos, Size: Int64;
  end;

procedure WriteMp4Tags(const FileName: string; Info: TAudioInfo);
var
  Src, Dst: TFileStream;
  Top: array of TTopAtom;
  H, MoovBytes: TBytes;
  Pos, Size, Hdr, Delta, NewFree: Int64;
  MoovIdx, I: Integer;
  Root, Moov: TAtom;
  NewMoov: TBytesStream;
  Temp: string;
  FreeFollows: Boolean;
begin
  Root := TAtom.Create(FourCC('moov'));
  NewMoov := TBytesStream.Create;
  Src := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    // Top-level atom list
    Top := nil;
    Pos := 0;
    while Pos + 8 <= Src.Size do
    begin
      Src.Position := Pos;
      H := ReadStreamBytes(Src, 16);
      Size := BE32(H, 0);
      Hdr := 8;
      if Size = 1 then begin Size := Int64(BE64(H, 8)); Hdr := 16; end
      else if Size = 0 then Size := Src.Size - Pos;
      if (Size < Hdr) or (Pos + Size > Src.Size) then
        raise Exception.Create(rsUgyldigMpStruktur);
      SetLength(Top, Length(Top) + 1);
      Top[High(Top)].Name := BE32(H, 4);
      Top[High(Top)].Pos := Pos;
      Top[High(Top)].Size := Size;
      Inc(Pos, Size);
    end;

    MoovIdx := -1;
    for I := 0 to High(Top) do
    begin
      if (Top[I].Name = FourCC('moov')) and (MoovIdx < 0) then MoovIdx := I;
      if Top[I].Name = FourCC('moof') then
        raise Exception.Create(rsFragmenteredeMpFilerUnderstoettesIkke);
    end;
    if MoovIdx < 0 then raise Exception.Create(rsIngenMoovAtomIkkeEn);

    Src.Position := Top[MoovIdx].Pos;
    H := ReadStreamBytes(Src, 16);
    if BE32(H, 0) = 1 then Hdr := 16 else Hdr := 8;
    Src.Position := Top[MoovIdx].Pos + Hdr;
    MoovBytes := ReadStreamBytes(Src, Top[MoovIdx].Size - Hdr);
    ParseChildren(Root, MoovBytes, 0, Length(MoovBytes));
    Moov := Root; // Root stands in for 'moov' itself

    UpdateIlst(Moov, Info);
    Delta := Moov.TotalSize - Top[MoovIdx].Size;

    // Use a following 'free' atom as slack, so nothing behind it moves.
    FreeFollows := (MoovIdx < High(Top)) and (Top[MoovIdx + 1].Name = FourCC('free'));
    NewFree := -1;
    if FreeFollows then
    begin
      NewFree := Top[MoovIdx + 1].Size - Delta;
      if (NewFree <> 0) and (NewFree < 8) then NewFree := -1; // does not fit
    end;

    if (Delta = 0) or (NewFree >= 0) or (MoovIdx = High(Top)) then
    begin
      // In place: moov (+ shrunk/grown free) occupy exactly the old space, or moov is last.
      Moov.WriteTo(NewMoov);
      if (Delta <> 0) and (NewFree > 0) then
      begin
        WriteBE32(NewMoov, NewFree);
        WriteAscii(NewMoov, 'free');
        WriteZeros(NewMoov, NewFree - 8);
      end;
      FreeAndNil(Src);
      Dst := TFileStream.Create(FileName, fmOpenReadWrite or fmShareDenyWrite);
      try
        Dst.Position := Top[MoovIdx].Pos;
        Dst.WriteBuffer(NewMoov.Bytes[0], NewMoov.Size);
        if (MoovIdx = High(Top)) and (Delta <> 0) and (NewFree < 0) then
          Dst.Size := Top[MoovIdx].Pos + NewMoov.Size; // moov was last: shrink/grow file
      finally
        Dst.Free;
      end;
    end
    else
    begin
      // Rewrite: moov + fresh free space; shift chunk offsets if the audio moves.
      Delta := Delta + 8 + NewFreeSpace;
      if FreeFollows then Dec(Delta, Top[MoovIdx + 1].Size); // old free is dropped
      // Only data stored after the old moov moves.
      ShiftChunkOffsets(Moov, Delta, Top[MoovIdx].Pos);
      Moov.WriteTo(NewMoov);
      WriteBE32(NewMoov, 8 + NewFreeSpace);
      WriteAscii(NewMoov, 'free');
      WriteZeros(NewMoov, NewFreeSpace);

      Temp := TempFileFor(FileName);
      try
        Dst := TFileStream.Create(Temp, fmCreate);
        try
          for I := 0 to High(Top) do
            if I = MoovIdx then
              Dst.WriteBuffer(NewMoov.Bytes[0], NewMoov.Size)
            else if FreeFollows and (I = MoovIdx + 1) then
              Continue
            else
              CopyStreamRange(Src, Dst, Top[I].Pos, Top[I].Size);
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
    NewMoov.Free;
    Root.Free;
  end;
end;

end.
