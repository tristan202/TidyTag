unit AudioDecode;

{ Decodes an audio file to float samples for the loudness meter. WAV and AIFF are read
  directly; everything else goes through Windows Media Foundation (part of Windows: MP3,
  AAC/ALAC in MP4, WMA, FLAC and whatever codecs are installed). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TPcmFormatEvent = procedure(Rate, Channels: Integer) of object;
  TPcmDataEvent = procedure(Data: PSingle; Frames: Integer) of object;

{ Returns '' on success or an error text. Cancel (may be nil) is polled between buffers. }
function DecodeAudio(const FileName: string; OnFormat: TPcmFormatEvent; OnData: TPcmDataEvent;
  Cancel: PBoolean): string;
{ Native WAV/AIFF reader only (exposed for the tests). NotPcm = the file is WAV/AIFF but
  compressed or otherwise unsupported, so another decoder may try. }
function DecodePcmFile(const FileName: string; OnFormat: TPcmFormatEvent; OnData: TPcmDataEvent;
  Cancel: PBoolean; out NotPcm: Boolean): string;

implementation

uses
  Math, MFDecode;

resourcestring
  rsAfbrudt = 'afbrudt';
  rsUkendtLydformat = 'ukendt lydformat';
  rsIngenLyddata = 'ingen lyddata';

type
  TSampleKind = (skUInt8, skInt, skFloat);

function ReadLE16(const B: array of Byte; P: Integer): Word;
begin
  Result := B[P] or (B[P + 1] shl 8);
end;

function ReadLE32(const B: array of Byte; P: Integer): Cardinal;
begin
  Result := B[P] or (B[P + 1] shl 8) or (B[P + 2] shl 16) or (Cardinal(B[P + 3]) shl 24);
end;

function ReadBE16(const B: array of Byte; P: Integer): Word;
begin
  Result := (B[P] shl 8) or B[P + 1];
end;

function ReadBE32(const B: array of Byte; P: Integer): Cardinal;
begin
  Result := (Cardinal(B[P]) shl 24) or (B[P + 1] shl 16) or (B[P + 2] shl 8) or B[P + 3];
end;

function Power2(E: Integer): Double;
begin
  Result := 1;
  while E > 0 do begin Result := Result * 2; Dec(E); end;
  while E < 0 do begin Result := Result / 2; Inc(E); end;
end;

{ 80-bit IEEE extended (AIFF sample rate). }
function Extended80(const B: array of Byte; P: Integer): Double;
var
  Expo: Integer;
  Mant: QWord;
  I: Integer;
begin
  Expo := ((B[P] and $7F) shl 8) or B[P + 1];
  Mant := 0;
  for I := 0 to 7 do Mant := (Mant shl 8) or B[P + 2 + I];
  if (Expo = 0) and (Mant = 0) then Exit(0);
  Result := Mant * Power2(Expo - 16383 - 63);
  if B[P] and $80 <> 0 then Result := -Result;
end;

function DecodePcmFile(const FileName: string; OnFormat: TPcmFormatEvent; OnData: TPcmDataEvent;
  Cancel: PBoolean; out NotPcm: Boolean): string;
const
  ChunkFrames = 32768;
var
  S: TFileStream;
  H: array[0..11] of Byte;
  C: array[0..7] of Byte;
  Fmt: TBytes;
  IsAiff, BigEndian, HaveFmt: Boolean;
  Kind: TSampleKind;
  Channels, Bits, BytesPer, Rate, Tag: Integer;
  DataPos, DataLen, ChunkLen, Left: Int64;
  Raw: TBytes;
  Buf: array of Single;
  Frames, I, N, P: Integer;
  V: LongInt;
  Q: QWord;
  Comp: string;
begin
  Result := '';
  NotPcm := False;
  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    if S.Read(H, 12) <> 12 then Exit(rsUkendtLydformat);
    IsAiff := (Chr(H[0]) + Chr(H[1]) + Chr(H[2]) + Chr(H[3]) = 'FORM');
    if IsAiff then
    begin
      Comp := Chr(H[8]) + Chr(H[9]) + Chr(H[10]) + Chr(H[11]);
      if (Comp <> 'AIFF') and (Comp <> 'AIFC') then Exit(rsUkendtLydformat);
    end
    else if not ((Chr(H[0]) + Chr(H[1]) + Chr(H[2]) + Chr(H[3]) = 'RIFF') and
      (Chr(H[8]) + Chr(H[9]) + Chr(H[10]) + Chr(H[11]) = 'WAVE')) then
    begin
      NotPcm := True;
      Exit(rsUkendtLydformat);
    end;
    HaveFmt := False;
    DataPos := -1;
    DataLen := 0;
    Channels := 0; Bits := 0; Rate := 0;
    Kind := skInt;
    BigEndian := IsAiff;
    while S.Position + 8 <= S.Size do
    begin
      S.ReadBuffer(C, 8);
      if IsAiff then ChunkLen := ReadBE32(C, 4) else ChunkLen := ReadLE32(C, 4);
      Comp := Chr(C[0]) + Chr(C[1]) + Chr(C[2]) + Chr(C[3]);
      if (Comp = 'fmt ') or (Comp = 'COMM') then
      begin
        SetLength(Fmt, Min(ChunkLen, 64));
        if Length(Fmt) > 0 then S.ReadBuffer(Fmt[0], Length(Fmt));
        S.Position := S.Position + ChunkLen - Length(Fmt);
        if not IsAiff then
        begin
          if Length(Fmt) < 16 then Exit(rsUkendtLydformat);
          Tag := ReadLE16(Fmt, 0);
          Channels := ReadLE16(Fmt, 2);
          Rate := ReadLE32(Fmt, 4);
          Bits := ReadLE16(Fmt, 14);
          if (Tag = $FFFE) and (Length(Fmt) >= 26) then Tag := ReadLE16(Fmt, 24);
          if Tag = 3 then Kind := skFloat
          else if Tag = 1 then
          begin
            if Bits = 8 then Kind := skUInt8 else Kind := skInt;
          end
          else
          begin
            NotPcm := True;
            Exit(rsUkendtLydformat);
          end;
        end
        else
        begin
          if Length(Fmt) < 18 then Exit(rsUkendtLydformat);
          Channels := ReadBE16(Fmt, 0);
          Bits := ReadBE16(Fmt, 6);
          Rate := Round(Extended80(Fmt, 8));
          if Length(Fmt) >= 22 then
          begin
            Comp := Chr(Fmt[18]) + Chr(Fmt[19]) + Chr(Fmt[20]) + Chr(Fmt[21]);
            if Comp = 'sowt' then BigEndian := False
            else if (Comp = 'fl32') or (Comp = 'FL32') then begin Kind := skFloat; Bits := 32; end
            else if (Comp = 'fl64') or (Comp = 'FL64') then begin Kind := skFloat; Bits := 64; end
            else if Comp <> 'NONE' then
            begin
              NotPcm := True;
              Exit(rsUkendtLydformat);
            end;
          end;
        end;
        HaveFmt := True;
      end
      else if (Comp = 'data') or (Comp = 'SSND') then
      begin
        DataPos := S.Position;
        DataLen := ChunkLen;
        if Comp = 'SSND' then
        begin
          S.ReadBuffer(C, 8);
          DataPos := S.Position + ReadBE32(C, 0);
          DataLen := ChunkLen - 8 - ReadBE32(C, 0);
        end;
        if (DataLen < 0) or (DataPos + DataLen > S.Size) then DataLen := S.Size - DataPos;
        if HaveFmt then Break;
        S.Position := DataPos + DataLen;
      end
      else
        S.Position := S.Position + ChunkLen;
      if Odd(ChunkLen) then S.Position := S.Position + 1;
    end;
    if not HaveFmt or (Channels <= 0) or (Rate <= 0) then Exit(rsUkendtLydformat);
    if (DataPos < 0) or (DataLen <= 0) then Exit(rsIngenLyddata);
    if not (Bits in [8, 16, 24, 32, 64]) or ((Kind = skFloat) and not (Bits in [32, 64])) or
      ((Kind <> skFloat) and (Bits = 64)) then
    begin
      NotPcm := True;
      Exit(rsUkendtLydformat);
    end;
    BytesPer := Bits div 8;
    OnFormat(Rate, Channels);
    S.Position := DataPos;
    Left := DataLen div (BytesPer * Channels);
    SetLength(Raw, ChunkFrames * BytesPer * Channels);
    SetLength(Buf, ChunkFrames * Channels);
    while Left > 0 do
    begin
      if (Cancel <> nil) and Cancel^ then Exit(rsAfbrudt);
      Frames := Min(Left, ChunkFrames);
      N := S.Read(Raw[0], Frames * BytesPer * Channels) div (BytesPer * Channels);
      if N <= 0 then Break;
      P := 0;
      for I := 0 to N * Channels - 1 do
      begin
        case Bits of
          8:
            if Kind = skUInt8 then Buf[I] := (Raw[P] - 128) / 128
            else Buf[I] := ShortInt(Raw[P]) / 128;
          16:
            if BigEndian then Buf[I] := SmallInt((Raw[P] shl 8) or Raw[P + 1]) / 32768
            else Buf[I] := SmallInt(Raw[P] or (Raw[P + 1] shl 8)) / 32768;
          24:
            begin
              if BigEndian then V := (Raw[P] shl 24) or (Raw[P + 1] shl 16) or (Raw[P + 2] shl 8)
              else V := (Raw[P + 2] shl 24) or (Raw[P + 1] shl 16) or (Raw[P] shl 8);
              Buf[I] := V / 2147483648.0;
            end;
          32:
            begin
              if BigEndian then V := LongInt(ReadBE32(Raw, P)) else V := LongInt(ReadLE32(Raw, P));
              if Kind = skFloat then Buf[I] := PSingle(@V)^ else Buf[I] := V / 2147483648.0;
            end;
          64:
            begin
              if BigEndian then Q := (QWord(ReadBE32(Raw, P)) shl 32) or ReadBE32(Raw, P + 4)
              else Q := (QWord(ReadLE32(Raw, P + 4)) shl 32) or ReadLE32(Raw, P);
              Buf[I] := PDouble(@Q)^;
            end;
        end;
        Inc(P, BytesPer);
      end;
      OnData(@Buf[0], N);
      Dec(Left, N);
    end;
  finally
    S.Free;
  end;
end;

function DecodeAudio(const FileName: string; OnFormat: TPcmFormatEvent; OnData: TPcmDataEvent;
  Cancel: PBoolean): string;
var
  Ext: string;
  NotPcm: Boolean;
begin
  Ext := LowerCase(ExtractFileExt(FileName));
  if (Ext = '.wav') or (Ext = '.aif') or (Ext = '.aiff') or (Ext = '.aifc') then
  begin
    Result := DecodePcmFile(FileName, OnFormat, OnData, Cancel, NotPcm);
    if (Result = '') or not NotPcm then Exit;
  end;
  Result := DecodeWithMediaFoundation(FileName, OnFormat, OnData, Cancel);
end;

end.
