program bpmtest;

{ Tempo and key checks: synthetic WAV files with a known tempo and key are written to the
  work folder and analysed; then any given files (or folders) are analysed and compared
  with the BPM and key already in their tags. Given files are only read.
  Usage: bpmtest <work folder> [<audio file or folder> ...] [-min=<bpm>] }

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, Math, StrUtils, MusicAnalysis, AudioTypes, AudioTags;

var
  Failures: Integer = 0;
  Checks: Integer = 0;
  MinBpm: Double = DefaultMinBpm;
  CsvName: string;
  Csv: TStringList = nil; // -csv=<file>: tag values and chroma per file, for tuning the key step

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

procedure WriteLE(S: TStream; V: Cardinal; Bytes: Integer);
var
  I: Integer;
begin
  for I := 0 to Bytes - 1 do S.WriteByte((V shr (8 * I)) and $FF);
end;

{ 16-bit mono WAV. }
procedure SaveWav(const FileName: string; const X: array of Single; Rate: Integer);
var
  S: TFileStream;
  I: Integer;
begin
  S := TFileStream.Create(FileName, fmCreate);
  try
    S.WriteBuffer('RIFF', 4);
    WriteLE(S, 36 + Length(X) * 2, 4);
    S.WriteBuffer('WAVEfmt ', 8);
    WriteLE(S, 16, 4);
    WriteLE(S, 1, 2);
    WriteLE(S, 1, 2);
    WriteLE(S, Rate, 4);
    WriteLE(S, Rate * 2, 4);
    WriteLE(S, 2, 2);
    WriteLE(S, 16, 2);
    S.WriteBuffer('data', 4);
    WriteLE(S, Length(X) * 2, 4);
    for I := 0 to High(X) do WriteLE(S, Word(SmallInt(Round(EnsureRange(X[I], -1, 1) * 32000))), 2);
  finally
    S.Free;
  end;
end;

function NoteHz(Midi: Double): Double;
begin
  Result := 440 * Power(2, (Midi - 69) / 12);
end;

{ A dance-like loop: kick on every beat, hi-hat between, a bass note and a chord per bar.
  Chords are MIDI note lists; Detune shifts everything by cents (tuning test). }
procedure MakeTrack(const FileName: string; Bpm, Seconds: Double; const Chords: array of string;
  Detune: Double; Drums: Boolean);
const
  Rate = 44100;
var
  X: array of Single;
  N, I, Beat, Bar, J: Integer;
  T, BeatLen, InBeat, V, Ph: Double;
  Notes: TStringArray;
begin
  N := Round(Seconds * Rate);
  SetLength(X, N);
  BeatLen := 60 / Bpm;
  for I := 0 to N - 1 do
  begin
    T := I / Rate;
    Beat := Floor(T / BeatLen);
    InBeat := T - Beat * BeatLen;
    V := 0;
    if Drums then
    begin
      // kick: falling sine with a fast decay
      if InBeat < 0.15 then V := V + 0.6 * Sin(2 * Pi * (50 + 100 * Exp(-InBeat * 40)) * InBeat) * Exp(-InBeat * 20);
      // hi-hat on the off-beat: noise burst
      Ph := InBeat - BeatLen / 2;
      if (Ph >= 0) and (Ph < 0.04) then V := V + 0.15 * (Random * 2 - 1) * Exp(-Ph * 80);
    end;
    if Length(Chords) > 0 then
    begin
      Bar := (Beat div 4) mod Length(Chords);
      Notes := Chords[Bar].Split([' ']);
      for J := 0 to High(Notes) do
        V := V + 0.06 * Sin(2 * Pi * NoteHz(StrToInt(Notes[J]) + Detune / 100) * T)
          + 0.02 * Sin(4 * Pi * NoteHz(StrToInt(Notes[J]) + Detune / 100) * T);
    end;
    X[I] := V;
  end;
  SaveWav(FileName, X, Rate);
end;

function Analyze(const FileName: string): TAnalysisResult;
var
  Opt: TAnalysisOptions;
begin
  Opt.DoBpm := True;
  Opt.DoKey := True;
  Opt.MinBpm := MinBpm;
  Result := AnalyzeFile(FileName, Opt, nil);
end;

procedure TestNames;
begin
  WriteLn('== notation');
  Check(KeyName(21, knMusical) = 'Am', 'Am');
  Check(KeyName(21, knCamelot) = '8A', 'Am = 8A');
  Check(KeyName(21, knOpenKey) = '1m', 'Am = 1m');
  Check(KeyName(0, knCamelot) = '8B', 'C = 8B');
  Check(KeyName(6, knMusical) = 'F#', 'F#');
  Check(KeyName(6, knCamelot) = '2B', 'F# = 2B');
  Check(KeyName(5, knOpenKey) = '12d', 'F = 12d');
  Check(KeyName(13, knCamelot) = '12A', 'C#m = 12A');
  Check(ParseKey('8A') = 21, 'parse 8A');
  Check(ParseKey('12B') = 4, 'parse 12B = E');
  Check(ParseKey('1d') = 0, 'parse 1d = C');
  Check(ParseKey('6m') = 12 + 8, 'parse 6m = G#m');
  Check(ParseKey('Bbm') = 22, 'parse Bbm');
  Check(ParseKey('F# minor') = 18, 'parse F# minor');
  Check(ParseKey('Db') = 1, 'parse Db');
  Check(ParseKey('x') = -1, 'parse x');
  Check(BpmText(127.996, 0) = '128', 'BPM 128');
  Check(BpmText(127.996, 2) = '128.00', 'BPM 128.00');
end;

procedure TestSynthetic(const Dir: string);
const
  // Am, Dm, E, Am: harmonic minor (G#) so A minor is clear
  AMinor: array[0..3] of string = ('45 57 60 64', '50 57 62 65', '52 56 59 64', '45 57 60 64');
  // D, G, A, D
  DMajor: array[0..3] of string = ('38 54 57 62', '43 55 59 62', '45 57 61 64', '38 54 57 62');
var
  R: TAnalysisResult;
  F: string;

  procedure One(const Name: string; Bpm: Double; const Chords: array of string; Key: Integer;
    Detune: Double; Seconds: Double = 60);
  begin
    F := Dir + Name + '.wav';
    MakeTrack(F, Bpm, Seconds, Chords, Detune, True);
    R := Analyze(F);
    WriteLn(Format('  %-14s bpm %.2f steady %s key %s (%.2f)',
      [Name, R.Bpm, BoolToStr(R.BpmSteady, True), KeyName(R.Key, knMusical), R.KeyClarity]));
    Check(Abs(R.Bpm - Bpm) < 0.1, Format('%s: %.2f BPM', [Name, Bpm]));
    if Key >= 0 then Check(R.Key = Key, Name + ': ' + KeyName(Key, knMusical));
  end;

begin
  WriteLn('== synthetic');
  RandSeed := 1;
  One('am-128', 128, AMinor, 21, 0);
  One('d-174', 87, DMajor, 2, 0);      // 174 is out of the 85-170 range: 87 expected
  One('am-122.5', 122.5, AMinor, 21, 0);
  One('d-96-detuned', 96, DMajor, 2, 35); // 35 cents sharp
  // 20 seconds of pure sine chords are too little to tell Am from A with profiles measured
  // on real tracks; the tempo must still be right
  One('am-140-short', 140, AMinor, -1, 0, 20);
end;

procedure Compare(const FileName: string; const R: TAnalysisResult;
  var BpmOk, KeyOk, BpmTagged, KeyTagged: Integer);
var
  Info: TAudioInfo;
  TagBpm: Double;
  TagKey: Integer;
  BpmMark, KeyMark: string;
  FS: TFormatSettings;
  I: Integer;
begin
  Info := ReadAudioInfo(FileName, False);
  try
    FS := DefaultFormatSettings;
    FS.DecimalSeparator := '.';
    TagBpm := StrToFloatDef(StringReplace(Trim(Info.Fields[tfBpm]), ',', '.', []), 0, FS);
    TagKey := ParseKey(Info.Fields[tfInitialKey]);
  finally
    Info.Free;
  end;
  if Csv <> nil then
  begin
    BpmMark := ExtractFileName(FileName) + #9 + IntToStr(TagKey) + #9 + FloatToStr(TagBpm, FS) + #9 + IntToStr(R.Key);
    for I := 0 to 11 do BpmMark := BpmMark + #9 + FloatToStr(R.Chroma[I], FS);
    for I := 0 to 11 do BpmMark := BpmMark + #9 + FloatToStr(R.BassChroma[I], FS);
    Csv.Add(BpmMark);
  end;
  BpmMark := '';
  KeyMark := '';
  if TagBpm > 0 then
  begin
    Inc(BpmTagged);
    // the tag may be in another octave than our range
    while TagBpm < MinBpm - 0.5 do TagBpm := TagBpm * 2;
    while TagBpm >= 2 * MinBpm + 0.5 do TagBpm := TagBpm / 2;
    if Abs(R.Bpm - TagBpm) <= 0.6 then begin Inc(BpmOk); BpmMark := 'ok' end else BpmMark := '<>';
  end;
  if TagKey >= 0 then
  begin
    Inc(KeyTagged);
    if TagKey = R.Key then begin Inc(KeyOk); KeyMark := 'ok' end else KeyMark := '<>';
  end;
  WriteLn(Format('  %6.2f %-5s %2s tag %6.2f | %-4s %-3s %2s tag %-4s | %s', [R.Bpm,
    IfThen(R.BpmSteady, '', 'vary'), BpmMark, TagBpm, KeyName(R.Key, knMusical),
    KeyName(R.Key, knCamelot), KeyMark, KeyName(TagKey, knMusical),
    ExtractFileName(FileName) + IfThen(R.Error <> '', ' !! ' + R.Error, '')]));
end;

procedure Walk(const Path: string; Files: TStrings);
var
  SR: TSearchRec;
begin
  if FileExists(Path) then
  begin
    if IsReadableAudioFile(Path) then Files.Add(Path);
    Exit;
  end;
  if FindFirst(IncludeTrailingPathDelimiter(Path) + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then Continue;
      Walk(IncludeTrailingPathDelimiter(Path) + SR.Name, Files);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

{ All given files on several threads, then the comparison with the tags. }
procedure CompareAll(Files: TStringList);
var
  Opt: TAnalysisOptions;
  Batch: TAnalysisBatch;
  Arr: TStringArray;
  I, BpmOk, KeyOk, BpmTagged, KeyTagged: Integer;
begin
  Opt.DoBpm := True;
  Opt.DoKey := True;
  Opt.MinBpm := MinBpm;
  Arr := Files.ToStringArray;
  Batch := TAnalysisBatch.Create(Arr, Opt);
  try
    Batch.Start;
    while not Batch.Finished do Sleep(200);
    WriteLn('== given files (analysed | tag)');
    BpmOk := 0; KeyOk := 0; BpmTagged := 0; KeyTagged := 0;
    for I := 0 to High(Arr) do Compare(Arr[I], Batch.Results[I], BpmOk, KeyOk, BpmTagged, KeyTagged);
    WriteLn(Format('%d files; BPM like the tag: %d of %d; key like the tag: %d of %d',
      [Length(Arr), BpmOk, BpmTagged, KeyOk, KeyTagged]));
    if Csv <> nil then Csv.SaveToFile(CsvName);
  finally
    Batch.Free;
  end;
end;

var
  Dir, A: string;
  I: Integer;
  Files: TStringList;
begin
  if ParamCount < 1 then
  begin
    WriteLn('bpmtest <work folder> [<audio file or folder> ...] [-min=<bpm>] [-csv=<file>]');
    Halt(2);
  end;
  for I := 2 to ParamCount do
  begin
    if Copy(ParamStr(I), 1, 5) = '-min=' then MinBpm := StrToFloat(Copy(ParamStr(I), 6, 10));
    if Copy(ParamStr(I), 1, 5) = '-csv=' then
    begin
      CsvName := Copy(ParamStr(I), 6, MaxInt);
      Csv := TStringList.Create;
    end;
  end;
  Dir := IncludeTrailingPathDelimiter(UTF8Encode(UnicodeString(ParamStr(1))));
  ForceDirectories(Dir);
  Files := TStringList.Create;
  try
    for I := 2 to ParamCount do
    begin
      A := UTF8Encode(UnicodeString(ParamStr(I)));
      if Copy(A, 1, 1) <> '-' then Walk(A, Files);
    end;
    if Files.Count > 0 then
    begin
      CompareAll(Files);
      Exit;
    end;
  finally
    Files.Free;
  end;
  TestNames;
  TestSynthetic(Dir);
  WriteLn(Format('%d checks, %d failures', [Checks, Failures]));
  if Failures > 0 then Halt(1);
end.
