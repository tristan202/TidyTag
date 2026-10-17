program rgtest;

{ ReplayGain checks: EBU Tech 3341 style test signals written as WAV/AIFF (known loudness),
  read natively and through Media Foundation, plus a measurement of any files given.
  Usage: rgtest <work folder> [<audio file> ...]   (only reads the given files) }

{$mode objfpc}{$H+}

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  Classes, SysUtils, Math, Loudness, AudioDecode, MFDecode, ReplayGain, AudioTypes, AudioTags;

var
  Failures: Integer = 0;
  Checks: Integer = 0;

procedure Check(Ok: Boolean; const What: string);
begin
  Inc(Checks);
  if Ok then WriteLn('   ok   ', What)
  else
  begin
    Inc(Failures);
    WriteLn('   FEJL ', What);
  end;
end;

type
  TSegment = record
    Seconds: Double;
    DBFS: Double;  // per channel sine level; -999 = silence
  end;

procedure WriteLE(S: TStream; V: Cardinal; Bytes: Integer);
var
  I: Integer;
begin
  for I := 0 to Bytes - 1 do S.WriteByte((V shr (8 * I)) and $FF);
end;

procedure WriteBE(S: TStream; V: Cardinal; Bytes: Integer);
var
  I: Integer;
begin
  for I := Bytes - 1 downto 0 do S.WriteByte((V shr (8 * I)) and $FF);
end;

{ Sine at 1 kHz on every channel; Bits 16/24 integer or 32 = float (WAV) / int (AIFF). }
procedure WriteTestFile(const FileName: string; Rate, Channels, Bits: Integer; Float, Aiff: Boolean;
  const Segs: array of TSegment);
var
  S: TFileStream;
  Frames, I, C, N: Int64;
  K: Integer;
  Amp, X: Double;
  V: LongInt;
  F32: Single;
  DataLen: Int64;
  Ph: Double;
begin
  Frames := 0;
  for K := 0 to High(Segs) do Inc(Frames, Round(Segs[K].Seconds * Rate));
  DataLen := Frames * Channels * (Bits div 8);
  S := TFileStream.Create(FileName, fmCreate);
  try
    if not Aiff then
    begin
      S.WriteBuffer(PChar('RIFF')^, 4); WriteLE(S, 36 + DataLen, 4);
      S.WriteBuffer(PChar('WAVE')^, 4);
      S.WriteBuffer(PChar('fmt ')^, 4); WriteLE(S, 16, 4);
      if Float then WriteLE(S, 3, 2) else WriteLE(S, 1, 2);
      WriteLE(S, Channels, 2); WriteLE(S, Rate, 4);
      WriteLE(S, Rate * Channels * (Bits div 8), 4); WriteLE(S, Channels * (Bits div 8), 2);
      WriteLE(S, Bits, 2);
      S.WriteBuffer(PChar('data')^, 4); WriteLE(S, DataLen, 4);
    end
    else
    begin
      S.WriteBuffer(PChar('FORM')^, 4); WriteBE(S, 4 + 26 + 16 + DataLen, 4);
      S.WriteBuffer(PChar('AIFF')^, 4);
      S.WriteBuffer(PChar('COMM')^, 4); WriteBE(S, 18, 4);
      WriteBE(S, Channels, 2); WriteBE(S, Frames, 4); WriteBE(S, Bits, 2);
      // 80-bit extended sample rate
      N := Rate; K := 0;
      while N >= 2 do begin N := N shr 1; Inc(K); end;
      WriteBE(S, 16383 + K, 2);
      WriteBE(S, Cardinal((QWord(Rate) shl (63 - K)) shr 32), 4);
      WriteBE(S, Cardinal(QWord(Rate) shl (63 - K)), 4);
      S.WriteBuffer(PChar('SSND')^, 4); WriteBE(S, 8 + DataLen, 4);
      WriteBE(S, 0, 4); WriteBE(S, 0, 4);
    end;
    Ph := 0;
    for K := 0 to High(Segs) do
    begin
      if Segs[K].DBFS < -900 then Amp := 0 else Amp := Power(10, Segs[K].DBFS / 20);
      for I := 1 to Round(Segs[K].Seconds * Rate) do
      begin
        X := Amp * Sin(Ph);
        Ph := Ph + 2 * Pi * 1000 / Rate;
        if Ph > 2 * Pi then Ph := Ph - 2 * Pi;
        for C := 1 to Channels do
          if Float then
          begin
            F32 := X;
            S.WriteBuffer(F32, 4);
          end
          else
          begin
            V := Round(X * (Int64(1) shl (Bits - 1)));
            if V >= Int64(1) shl (Bits - 1) then V := (Int64(1) shl (Bits - 1)) - 1;
            if Aiff then WriteBE(S, Cardinal(V), Bits div 8) else WriteLE(S, Cardinal(V), Bits div 8);
          end;
      end;
    end;
  finally
    S.Free;
  end;
end;

function Seg(Sec, DB: Double): TSegment;
begin
  Result.Seconds := Sec;
  Result.DBFS := DB;
end;

type
  TSink = class
    Meter: TLoudnessMeter;
    procedure Fmt(Rate, Channels: Integer);
    procedure Dat(Samples: PSingle; Frames: Integer);
  end;

procedure TSink.Fmt(Rate, Channels: Integer);
begin
  Meter.SetFormat(Rate, Channels);
end;

procedure TSink.Dat(Samples: PSingle; Frames: Integer);
begin
  Meter.AddFrames(Samples, Frames);
end;

function LoudnessVia(const FileName: string; UseMF: Boolean; out Err: string): Double;
var
  Sink: TSink;
  NotPcm: Boolean;
begin
  Result := NaN;
  Sink := TSink.Create;
  Sink.Meter := TLoudnessMeter.Create;
  try
    if UseMF then Err := DecodeWithMediaFoundation(FileName, @Sink.Fmt, @Sink.Dat, nil)
    else Err := DecodePcmFile(FileName, @Sink.Fmt, @Sink.Dat, nil, NotPcm);
    if Err = '' then Result := GatedLoudness(Sink.Meter.Blocks);
  finally
    Sink.Meter.Free;
    Sink.Free;
  end;
end;

procedure Known(const Dir, Name: string; Rate, Channels, Bits: Integer; Float, Aiff: Boolean;
  const Segs: array of TSegment; Expected: Double);
var
  F, Err: string;
  L, LM: Double;
begin
  F := Dir + Name;
  WriteTestFile(F, Rate, Channels, Bits, Float, Aiff, Segs);
  L := LoudnessVia(F, False, Err);
  Check((Err = '') and (Abs(L - Expected) <= 0.1),
    Format('%s: %.2f LUFS (forventet %.1f) %s', [Name, L, Expected, Err]));
  if not Aiff then
  begin
    LM := LoudnessVia(F, True, Err);
    Check((Err = '') and (Abs(LM - L) <= 0.01),
      Format('%s via Media Foundation: %.3f LUFS (direkte %.3f) %s', [Name, LM, L, Err]));
  end;
end;

procedure MeasureGiven(const FileName: string);
var
  M: TRGMeasure;
  Info: TAudioInfo;
  T0: QWord;
begin
  T0 := GetTickCount64;
  M := MeasureFile(FileName, nil);
  Info := ReadAudioInfo(FileName, False);
  try
    if M.Error <> '' then
      WriteLn(Format('  %-40s  FEJL: %s', [ExtractFileName(FileName), M.Error]))
    else
      WriteLn(Format('  %-40s  %7.2f LUFS  gain %-10s peak %s  (%d ms)  tag: %s / %s',
        [ExtractFileName(FileName), M.Loudness, TrackGainText(M), RGPeakText(M.Peak),
        GetTickCount64 - T0, Info.Fields[tfRGTrackGain], Info.Fields[tfRGTrackPeak]]));
  finally
    Info.Free;
  end;
end;

var
  Dir: string;
  I: Integer;
  G, P: string;
  GD: Double;
  Ms: array of TRGMeasure;
begin
  SetMultiByteConversionCodePage(CP_UTF8);
  SetMultiByteFileSystemCodePage(CP_UTF8);
  {$IFDEF WINDOWS}SetConsoleOutputCP(CP_UTF8);{$ENDIF}
  SetTextCodePage(Output, CP_UTF8);
  if ParamCount < 1 then
  begin
    WriteLn('Brug: rgtest <arbejdsmappe> [<lydfil> ...]');
    Halt(2);
  end;
  Dir := IncludeTrailingPathDelimiter(ParamStr(1));
  ForceDirectories(Dir);
  WriteLn('Media Foundation: ', MediaFoundationAvailable);
  WriteLn('== Kendte testsignaler (EBU Tech 3341)');
  // test 1 and 2: stereo 1 kHz sine at -23 and -33 dBFS
  Known(Dir, 't1_48k_16.wav', 48000, 2, 16, False, False, [Seg(20, -23)], -23);
  Known(Dir, 't2_48k_16.wav', 48000, 2, 16, False, False, [Seg(20, -33)], -33);
  // test 3 and 4: the gates
  Known(Dir, 't3_gate.wav', 48000, 2, 16, False, False, [Seg(10, -36), Seg(60, -23), Seg(10, -36)], -23);
  Known(Dir, 't4_gate.wav', 48000, 2, 16, False, False,
    [Seg(10, -72), Seg(10, -36), Seg(60, -23), Seg(10, -36), Seg(10, -72)], -23);
  // other rates and sample formats
  Known(Dir, 't1_44k_24.wav', 44100, 2, 24, False, False, [Seg(20, -23)], -23);
  Known(Dir, 't1_96k_float.wav', 96000, 2, 32, True, False, [Seg(20, -23)], -23);
  Known(Dir, 't1_44k_16.aif', 44100, 2, 16, False, True, [Seg(20, -23)], -23);
  // mono counts as dual mono: same loudness as the sine on both stereo channels
  Known(Dir, 't1_mono.wav', 44100, 1, 16, False, False, [Seg(20, -23)], -23.0);
  // silence: no gain
  WriteTestFile(Dir + 'stille.wav', 44100, 2, 16, False, False, [Seg(5, -999)]);
  Check(TrackGainText(MeasureFile(Dir + 'stille.wav', nil)) = '', 'stilhed giver ingen gain');
  // ReplayGain text
  Check(RGGainText(-18 - (-23)) = '5.00 dB', 'gain-tekst ' + RGGainText(5));
  Check(RGToR128('-6.52 dB') = '-2949', 'R128 ' + RGToR128('-6.52 dB'));
  Check(R128ToRG('-2949') = '-6.52 dB', 'fra R128 ' + R128ToRG('-2949'));
  // album: -23 and -33 files of equal length: both pass the gates, so the album is the
  // energy mean: -23 + 10*log10((1 + 0.1) / 2) = -25.60 LUFS
  SetLength(Ms, 2);
  Ms[0] := MeasureFile(Dir + 't1_48k_16.wav', nil);
  Ms[1] := MeasureFile(Dir + 't2_48k_16.wav', nil);
  AlbumValues(Ms, G, P);
  WriteLn('  album af -23 og -33: gain ', G, ' peak ', P);
  Check(ParseRGGain(G, GD) and (Abs(GD - 7.60) <= 0.02), 'album-gain er energigennemsnittet');
  if ParamCount > 1 then
  begin
    WriteLn('== Givne filer');
    for I := 2 to ParamCount do MeasureGiven(ParamStr(I));
  end;
  WriteLn;
  WriteLn(Checks, ' tjek, ', Failures, ' fejl');
  if Failures = 0 then WriteLn('ALLE TESTS OK') else Halt(1);
end.
