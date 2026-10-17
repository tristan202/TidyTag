unit ApeReader;

{ Monkey's Audio (.ape), WavPack (.wv), Musepack (.mpc, SV7/SV8) and OptimFROG (.ofr):
  audio properties from the stream header, tags from APEv2 with ID3v2 (at the start) and
  ID3v1 as fallback. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, AudioTypes;

procedure ReadApeFamily(S: TStream; Info: TAudioInfo);

implementation

uses
  TagUtils, Mp3Reader, ApeTag;

resourcestring
  rsFilenErForKort = 'Filen er for kort';
  rsUkendtLydformat = 'Ukendt lydformat';


procedure SetLength_(Info: TAudioInfo; Samples: Double; AudioBytes: Int64);
begin
  if Info.SampleRate <= 0 then Exit;
  Info.Duration := Samples / Info.SampleRate;
  if Info.Duration > 0 then
    Info.Bitrate := Round(AudioBytes * 8 / Info.Duration / 1000);
end;

procedure ReadMonkeys(const B: TBytes; Info: TAudioInfo; AudioBytes: Int64);
var
  Ver, Flags, Compression: Integer;
  Desc: Cardinal;
  BlocksPerFrame, FinalBlocks, Frames: Cardinal;
  Bits: Integer;
begin
  Ver := LE16(B, 4);
  if Ver >= 3980 then
  begin
    Desc := LE32(B, 8);
    if Length(B) < Desc + 24 then Exit;
    Compression := LE16(B, Desc);
    BlocksPerFrame := LE32(B, Desc + 4);
    FinalBlocks := LE32(B, Desc + 8);
    Frames := LE32(B, Desc + 12);
    Bits := LE16(B, Desc + 16);
    Info.Channels := LE16(B, Desc + 18);
    Info.SampleRate := LE32(B, Desc + 20);
  end
  else
  begin
    Compression := LE16(B, 6);
    Flags := LE16(B, 8);
    Info.Channels := LE16(B, 10);
    Info.SampleRate := LE32(B, 12);
    Frames := LE32(B, 24);
    FinalBlocks := LE32(B, 28);
    if Ver >= 3950 then BlocksPerFrame := 73728 * 4
    else if (Ver >= 3900) or ((Ver >= 3800) and (Compression = 4000)) then BlocksPerFrame := 73728
    else BlocksPerFrame := 9216;
    if Flags and 1 <> 0 then Bits := 8
    else if Flags and 8 <> 0 then Bits := 24
    else Bits := 16;
  end;
  Info.Codec := Format('Monkey''s Audio %d.%.2d (%d-bit)', [Ver div 1000, (Ver mod 1000) div 10, Bits]);
  if Frames > 0 then
    SetLength_(Info, (Int64(Frames) - 1) * BlocksPerFrame + FinalBlocks, AudioBytes);
end;

procedure ReadWavPack(const B: TBytes; Info: TAudioInfo; AudioBytes: Int64);
const
  Rates: array[0..14] of Integer = (6000, 8000, 9600, 11025, 12000, 16000, 22050, 24000,
    32000, 44100, 48000, 64000, 88200, 96000, 192000);
var
  Flags, Total: Cardinal;
  Idx: Integer;
  Samples: Int64;
begin
  Flags := LE32(B, 24);
  Idx := (Flags shr 23) and $F;
  if Idx < 15 then Info.SampleRate := Rates[Idx] else Info.SampleRate := 0;
  if Flags and 4 <> 0 then Info.Channels := 1 else Info.Channels := 2;
  Info.Codec := Format('WavPack %d-bit', [((Flags and 3) + 1) * 8]);
  if Flags and 8 <> 0 then Info.Codec := Info.Codec + ' (hybrid)';
  Total := LE32(B, 12);
  if Total <> $FFFFFFFF then
  begin
    Samples := Int64(Total) + Int64(B[11]) shl 32;
    SetLength_(Info, Samples, AudioBytes);
  end;
end;

function ReadVarint(const B: TBytes; var P: SizeInt): QWord;
var
  C: Byte;
begin
  Result := 0;
  repeat
    if P >= Length(B) then Exit;
    C := B[P];
    Inc(P);
    Result := (Result shl 7) or (C and $7F);
  until C and $80 = 0;
end;

procedure ReadMusepack(const B: TBytes; Info: TAudioInfo; AudioBytes: Int64);
const
  Rates: array[0..3] of Integer = (44100, 48000, 37800, 32000);
var
  P, Start: SizeInt;
  Size, Samples, Silence: QWord;
  Ver: Integer;
begin
  if BytesAre(B, 0, 'MPCK') then
  begin
    P := 4;
    while P + 2 < Length(B) do
    begin
      Start := P;
      Inc(P, 2);
      Size := ReadVarint(B, P);
      if BytesAre(B, Start, 'SH') then
      begin
        Inc(P, 4); // CRC
        Ver := B[P];
        Inc(P);
        Samples := ReadVarint(B, P);
        Silence := ReadVarint(B, P);
        if P + 1 >= Length(B) then Exit;
        Info.SampleRate := Rates[B[P] shr 5];
        Info.Channels := (B[P + 1] shr 4) + 1;
        Info.Codec := Format('Musepack SV%d', [Ver]);
        SetLength_(Info, Samples - Silence, AudioBytes);
        Exit;
      end;
      if Size < 3 then Exit;
      P := Start + SizeInt(Size);
    end;
  end
  else if BytesAre(B, 0, 'MP+') then
  begin
    Ver := B[3] and $0F;
    Info.Codec := Format('Musepack SV%d', [Ver]);
    Info.Channels := 2;
    if Ver >= 7 then
    begin
      Info.SampleRate := Rates[(LE32(B, 8) shr 16) and 3];
      SetLength_(Info, Int64(LE32(B, 4)) * 1152, AudioBytes);
    end;
  end
  else
    Info.Codec := 'Musepack';
end;

procedure ReadOptimFrog(const B: TBytes; Info: TAudioInfo; AudioBytes: Int64);
const
  Bits: array[0..6] of Integer = (8, 8, 16, 16, 24, 24, 32);
var
  Samples: Int64;
  SampleType: Byte;
begin
  // 'OFR ', header size, total samples (48-bit), sample type, channel config, rate
  Samples := Int64(LE32(B, 8)) + Int64(LE16(B, 12)) shl 32;
  SampleType := B[14];
  Info.Channels := B[15] + 1;
  Info.SampleRate := LE32(B, 16);
  if SampleType <= High(Bits) then
    Info.Codec := Format('OptimFROG %d-bit', [Bits[SampleType]])
  else
    Info.Codec := 'OptimFROG';
  if Info.Channels > 0 then
    SetLength_(Info, Samples / Info.Channels, AudioBytes);
end;

procedure ReadApeFamily(S: TStream; Info: TAudioInfo);
var
  TagSize, AudioEnd: Int64;
  B: TBytes;
  Loc: TApeLocation;
  HasApe: Boolean;
  Ext: string;
  Ver: Byte;
  Frames: TID3Frames;
begin
  Info.Supported := True;
  HasApe := ReadApeTag(S, Info);
  // ID3v2 at the start (seen on some .mpc/.ape files) and ID3v1 are only used when there
  // is no APE tag: the APE writer leaves the ID3v2 tag alone, so it must not shadow it.
  S.Position := 0;
  if HasApe then
    ParseID3v2(S, Ver, Frames, TagSize)
  else
    ReadID3v2(S, Info, TagSize);
  Loc := FindApeTag(S);
  AudioEnd := Loc.AudioEnd;
  if not HasApe then ReadID3v1(S, Info);
  if TagSize < 0 then TagSize := 0;
  S.Position := TagSize;
  B := ReadStreamBytes(S, 4096);
  if Length(B) < 32 then raise Exception.Create(rsFilenErForKort);
  Ext := LowerCase(ExtractFileExt(Info.FileName));
  if BytesAre(B, 0, 'MAC ') then
    ReadMonkeys(B, Info, AudioEnd - TagSize)
  else if BytesAre(B, 0, 'wvpk') then
    ReadWavPack(B, Info, AudioEnd - TagSize)
  else if BytesAre(B, 0, 'MPCK') or BytesAre(B, 0, 'MP+') then
    ReadMusepack(B, Info, AudioEnd - TagSize)
  else if BytesAre(B, 0, 'OFR ') then
    ReadOptimFrog(B, Info, AudioEnd - TagSize)
  else if Ext = '.mpc' then
    Info.Codec := 'Musepack'
  else
    raise Exception.Create(rsUkendtLydformat);
end;

end.
