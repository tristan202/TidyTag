unit AsfWriter;

{ Writes tags into WMA/ASF files. The header object is rebuilt: Content Description and
  Extended Content Description are replaced, managed records are removed from the
  Metadata (Library) objects, values over 64 KB (big pictures, long lyrics) go into the
  Metadata Library. Unknown attributes and all other objects are kept unchanged.
  If the new header fits into the old one the rest is padded and the file is written in
  place; otherwise header + the unchanged data/index objects go to a temporary file and
  the file size in the File Properties object is updated. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, AudioTypes;

procedure WriteAsfTags(const FileName: string; Info: TAudioInfo);

implementation

uses
  TagUtils, AsfReader;

const
  RewritePadding = 4096;
  MaxInPlacePadding = 64 * 1024;

procedure WriteLE16(S: TStream; V: Word);
begin
  S.WriteByte(V and $FF);
  S.WriteByte(V shr 8);
end;

procedure WriteLE64(S: TStream; V: QWord);
begin
  WriteLE32(S, V and $FFFFFFFF);
  WriteLE32(S, V shr 32);
end;

procedure PutLE64(var B: TBytes; P: SizeInt; V: QWord);
var
  I: Integer;
begin
  for I := 0 to 7 do B[P + I] := (V shr (8 * I)) and $FF;
end;

procedure WriteObject(Dest: TStream; const Guid: string; const Body: TBytes);
begin
  WriteBytes(Dest, GuidBytes(Guid));
  WriteLE64(Dest, 24 + Length(Body));
  WriteBytes(Dest, Body);
end;

function PictureBlob(const Pic: TTagPicture): TBytes;
var
  B: TBytesStream;
  Mime: string;
begin
  B := TBytesStream.Create;
  try
    B.WriteByte(Pic.PicType);
    WriteLE32(B, Length(Pic.Data));
    Mime := Pic.MimeType;
    if Mime = '' then Mime := DetectImageMime(Pic.Data);
    WriteBytes(B, Utf16z(Mime));
    WriteBytes(B, Utf16z(Pic.Description));
    WriteBytes(B, Pic.Data);
    Result := StreamBytes(B);
  finally
    B.Free;
  end;
end;

type
  TAttr = record
    Name: string;
    DataType: Word;
    Value: TBytes;
  end;
  TAttrList = array of TAttr;

procedure AddAttr(var L: TAttrList; const Name: string; DataType: Word; const Value: TBytes);
var
  N: Integer;
begin
  N := Length(L);
  SetLength(L, N + 1);
  L[N].Name := Name;
  L[N].DataType := DataType;
  L[N].Value := Value;
end;

{ Kept (unknown) attributes of an Extended Content Description body. }
procedure KeepExtAttrs(const B: TBytes; P, Limit: SizeInt; var L: TAttrList);
var
  Count, I: Integer;
  NameLen, DataType, ValLen: Word;
  Name: string;
begin
  if P + 2 > Limit then Exit;
  Count := LE16(B, P);
  Inc(P, 2);
  for I := 1 to Count do
  begin
    if P + 2 > Limit then Exit;
    NameLen := LE16(B, P);
    if P + 6 + NameLen > Limit then Exit;
    Name := UTF16ToUTF8(B, P + 2, NameLen - 2 * Ord(NameLen >= 2), False);
    DataType := LE16(B, P + 2 + NameLen);
    ValLen := LE16(B, P + 4 + NameLen);
    if P + 6 + NameLen + ValLen > Limit then Exit;
    if not IsManagedAttr(Name) then
      AddAttr(L, Name, DataType, Copy(B, P + 6 + NameLen, ValLen));
    P := P + 6 + NameLen + ValLen;
  end;
end;

{ Metadata / Metadata Library body without the managed file-wide records, plus Extra
  (always for the library; Extra is nil for the Metadata object). }
function FilterMetadata(const B: TBytes; P, Limit: SizeInt; const Extra: TAttrList): TBytes;
var
  Dest: TBytesStream;
  Count, Kept, I: Integer;
  NameLen: Word;
  DataLen: Cardinal;
  Start: SizeInt;
  Name: string;
  Rec: TBytes;
begin
  Dest := TBytesStream.Create;
  try
    WriteLE16(Dest, 0); // count, patched below
    Kept := 0;
    if P + 2 <= Limit then
    begin
      Count := LE16(B, P);
      Inc(P, 2);
      for I := 1 to Count do
      begin
        if P + 12 > Limit then Break;
        Start := P;
        NameLen := LE16(B, P + 4);
        DataLen := LE32(B, P + 8);
        if P + 12 + NameLen + Int64(DataLen) > Limit then Break;
        Name := UTF16ToUTF8(B, P + 12, NameLen - 2 * Ord(NameLen >= 2), False);
        P := P + 12 + NameLen + DataLen;
        if (LE16(B, Start + 2) = 0) and IsManagedAttr(Name) then Continue;
        WriteBytes(Dest, Copy(B, Start, P - Start));
        Inc(Kept);
      end;
    end;
    for I := 0 to High(Extra) do
    begin
      Rec := Utf16z(Extra[I].Name);
      WriteLE16(Dest, 0); // language list index
      WriteLE16(Dest, 0); // stream 0 = whole file
      WriteLE16(Dest, Length(Rec));
      WriteLE16(Dest, Extra[I].DataType);
      WriteLE32(Dest, Length(Extra[I].Value));
      WriteBytes(Dest, Rec);
      WriteBytes(Dest, Extra[I].Value);
      Inc(Kept);
    end;
    Result := StreamBytes(Dest);
    Result[0] := Kept and $FF;
    Result[1] := Kept shr 8;
  finally
    Dest.Free;
  end;
end;

function ContentDescBody(Info: TAudioInfo): TBytes;
var
  Dest: TBytesStream;
  Texts: array[0..4] of TBytes;
  I: Integer;
begin
  Texts[0] := nil; Texts[1] := nil; Texts[2] := nil; Texts[3] := nil; Texts[4] := nil;
  if Info.Fields[tfTitle] <> '' then Texts[0] := Utf16z(Info.Fields[tfTitle]);
  if Info.Fields[tfArtist] <> '' then Texts[1] := Utf16z(Info.Fields[tfArtist]);
  if Info.Fields[tfCopyright] <> '' then Texts[2] := Utf16z(Info.Fields[tfCopyright]);
  if Info.Fields[tfComment] <> '' then Texts[3] := Utf16z(Info.Fields[tfComment]);
  for I := 0 to 3 do
    if Length(Texts[I]) > $FFFF then SetLength(Texts[I], 0); // cannot be stored here
  Dest := TBytesStream.Create;
  try
    for I := 0 to 4 do WriteLE16(Dest, Length(Texts[I]));
    for I := 0 to 4 do WriteBytes(Dest, Texts[I]);
    Result := StreamBytes(Dest);
  finally
    Dest.Free;
  end;
end;

function ExtContentBody(const L: TAttrList): TBytes;
var
  Dest: TBytesStream;
  I: Integer;
  Name: TBytes;
begin
  Dest := TBytesStream.Create;
  try
    WriteLE16(Dest, Length(L));
    for I := 0 to High(L) do
    begin
      Name := Utf16z(L[I].Name);
      WriteLE16(Dest, Length(Name));
      WriteBytes(Dest, Name);
      WriteLE16(Dest, L[I].DataType);
      WriteLE16(Dest, Length(L[I].Value));
      WriteBytes(Dest, L[I].Value);
    end;
    Result := StreamBytes(Dest);
  finally
    Dest.Free;
  end;
end;

{ Our attributes; values that do not fit a WORD length go to Big (Metadata Library). }
procedure BuildAttrs(Info: TAudioInfo; var Small, Big: TAttrList);
var
  F: TTagField;
  V, Num, Total: string;
  Slash, I: Integer;
  Data: TBytes;

  procedure Put(const Name: string; DataType: Word; const Value: TBytes);
  begin
    if Length(Value) > $FFFF then AddAttr(Big, Name, DataType, Value)
    else AddAttr(Small, Name, DataType, Value);
  end;

begin
  for F := Low(TTagField) to High(TTagField) do
  begin
    V := Info.Fields[F];
    if (V = '') or (WmNames[F] = '') then Continue;
    if F = tfTrack then
    begin
      Slash := Pos('/', V);
      if Slash > 0 then
      begin
        Num := Trim(Copy(V, 1, Slash - 1));
        Total := Trim(Copy(V, Slash + 1, MaxInt));
      end
      else
      begin
        Num := V;
        Total := '';
      end;
      if Num <> '' then Put('WM/TrackNumber', AsfString, Utf16z(Num));
      if Total <> '' then Put('TotalTracks', AsfString, Utf16z(Total));
    end
    else
      Put(WmNames[F], AsfString, Utf16z(V));
  end;
  for I := 0 to High(Info.Pictures) do
  begin
    Data := PictureBlob(Info.Pictures[I]);
    Put('WM/Picture', AsfBytes, Data);
  end;
end;

procedure WriteAsfTags(const FileName: string; Info: TAudioInfo);
var
  S, Dst: TFileStream;
  B, Body, NewHeader: TBytes;
  HeaderSize, P, Q, Size, ExtEnd, FilePropsPos, NewFileSize, Pad: Int64;
  Kept, Small, Big, NoAttrs: TAttrList;
  Objects: TBytesStream;
  Count: Integer;
  HaveExt, HaveLibrary: Boolean;
  ExtInner: TBytesStream;
  Temp: string;

  procedure CopyObject(From, Len: Int64);
  begin
    WriteBytes(Objects, Copy(B, From, Len));
    Inc(Count);
  end;

begin
  Kept := nil;
  Small := nil;
  Big := nil;
  NoAttrs := nil;
  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    B := ReadStreamBytes(S, 30);
    if (Length(B) < 30) or not IsGuid(B, 0, GuidHeader) then
      raise Exception.Create('Ikke en WMA/ASF-fil');
    HeaderSize := LE64(B, 16);
    if (HeaderSize < 30) or (HeaderSize > S.Size) then raise Exception.Create('Ugyldig ASF-header');
    S.Position := 0;
    B := ReadStreamBytes(S, HeaderSize);

    // pass 1: unknown attributes of the old Extended Content Description
    P := 30;
    while P + 24 <= HeaderSize do
    begin
      Size := LE64(B, P + 16);
      if (Size < 24) or (P + Size > HeaderSize) then raise Exception.Create('Ugyldigt ASF-objekt');
      if IsGuid(B, P, GuidExtContentDesc) then KeepExtAttrs(B, P + 24, P + Size, Kept);
      Inc(P, Size);
    end;
    BuildAttrs(Info, Small, Big);
    Small := Concat(Kept, Small);

    // pass 2: assemble the new header objects
    Objects := TBytesStream.Create;
    try
      Count := 0;
      FilePropsPos := -1;
      HaveExt := False;
      P := 30;
      while P + 24 <= HeaderSize do
      begin
        Size := LE64(B, P + 16);
        if IsGuid(B, P, GuidContentDesc) or IsGuid(B, P, GuidExtContentDesc) or
          IsGuid(B, P, GuidPadding) then
        begin
          // replaced / dropped
        end
        else if IsGuid(B, P, GuidHeaderExt) and (Size >= 46) then
        begin
          HaveExt := True;
          HaveLibrary := False;
          ExtInner := TBytesStream.Create;
          try
            Q := P + 46;
            ExtEnd := P + Size;
            while Q + 24 <= ExtEnd do
            begin
              Size := LE64(B, Q + 16);
              if (Size < 24) or (Q + Size > ExtEnd) then Break;
              if IsGuid(B, Q, GuidMetadataLibrary) then
              begin
                HaveLibrary := True;
                WriteObject(ExtInner, GuidMetadataLibrary, FilterMetadata(B, Q + 24, Q + Size, Big));
              end
              else if IsGuid(B, Q, GuidMetadata) then
                WriteObject(ExtInner, GuidMetadata, FilterMetadata(B, Q + 24, Q + Size, NoAttrs))
              else if not IsGuid(B, Q, GuidPadding) then
                WriteBytes(ExtInner, Copy(B, Q, Size));
              Inc(Q, Size);
            end;
            if not HaveLibrary and (Big <> nil) then
              WriteObject(ExtInner, GuidMetadataLibrary, FilterMetadata(nil, 0, 0, Big));
            // reserved GUID + reserved WORD as stored, then the new inner data size
            Body := Copy(B, P + 24, 22);
            Body[18] := ExtInner.Size and $FF;
            Body[19] := (ExtInner.Size shr 8) and $FF;
            Body[20] := (ExtInner.Size shr 16) and $FF;
            Body[21] := (ExtInner.Size shr 24) and $FF;
            Body := Concat(Body, StreamBytes(ExtInner));
            WriteObject(Objects, GuidHeaderExt, Body);
            Inc(Count);
          finally
            ExtInner.Free;
          end;
          Size := ExtEnd - P;
        end
        else
        begin
          if IsGuid(B, P, GuidFileProps) then FilePropsPos := 30 + Objects.Size;
          CopyObject(P, Size);
        end;
        Inc(P, Size);
      end;
      if FilePropsPos < 0 then raise Exception.Create('ASF-filen mangler File Properties');
      if not HaveExt and (Big <> nil) then
      begin
        ExtInner := TBytesStream.Create;
        try
          WriteObject(ExtInner, GuidMetadataLibrary, FilterMetadata(nil, 0, 0, Big));
          Body := GuidBytes(GuidHeaderExtReserved);
          SetLength(Body, 22);
          Body[16] := 6;
          Body[17] := 0;
          Body[18] := ExtInner.Size and $FF;
          Body[19] := (ExtInner.Size shr 8) and $FF;
          Body[20] := (ExtInner.Size shr 16) and $FF;
          Body[21] := (ExtInner.Size shr 24) and $FF;
          Body := Concat(Body, StreamBytes(ExtInner));
          WriteObject(Objects, GuidHeaderExt, Body);
          Inc(Count);
        finally
          ExtInner.Free;
        end;
      end;
      WriteObject(Objects, GuidContentDesc, ContentDescBody(Info));
      Inc(Count);
      if Small <> nil then
      begin
        WriteObject(Objects, GuidExtContentDesc, ExtContentBody(Small));
        Inc(Count);
      end;

      // in place if it fits with room for a padding object (or exactly)
      Pad := HeaderSize - 30 - Objects.Size;
      // (a lot of free space, e.g. after removing a big picture, is given back by a rewrite)
      if (Pad = 0) or ((Pad >= 24) and (Pad <= MaxInPlacePadding)) then
      begin
        if Pad > 0 then
        begin
          WriteBytes(Objects, GuidBytes(GuidPadding));
          WriteLE64(Objects, Pad);
          WriteZeros(Objects, Pad - 24);
          Inc(Count);
        end;
        NewFileSize := S.Size;
      end
      else
      begin
        WriteBytes(Objects, GuidBytes(GuidPadding));
        WriteLE64(Objects, RewritePadding);
        WriteZeros(Objects, RewritePadding - 24);
        Inc(Count);
        NewFileSize := S.Size - HeaderSize + 30 + Objects.Size;
      end;
      NewHeader := Concat(Copy(B, 0, 30), StreamBytes(Objects));
    finally
      Objects.Free;
    end;
    PutLE64(NewHeader, 16, Length(NewHeader));
    NewHeader[24] := Count and $FF;
    NewHeader[25] := (Count shr 8) and $FF;
    NewHeader[26] := (Count shr 16) and $FF;
    NewHeader[27] := (Count shr 24) and $FF;
    PutLE64(NewHeader, FilePropsPos + 24 + 16, NewFileSize);

    if Length(NewHeader) <> HeaderSize then
    begin
      Temp := TempFileFor(FileName);
      try
        Dst := TFileStream.Create(Temp, fmCreate);
        try
          WriteBytes(Dst, NewHeader);
          CopyStreamRange(S, Dst, HeaderSize, S.Size - HeaderSize);
        finally
          Dst.Free;
        end;
        FreeAndNil(S);
        ReplaceFileWith(Temp, FileName);
      except
        DeleteFile(Temp);
        raise;
      end;
      Exit;
    end;
  finally
    S.Free;
  end;

  S := TFileStream.Create(FileName, fmOpenReadWrite or fmShareExclusive);
  try
    S.Position := 0;
    WriteBytes(S, NewHeader);
  finally
    S.Free;
  end;
end;

end.
