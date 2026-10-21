unit MusicAnalysis;

{ Tempo (BPM) and key detection, both from one decoding pass. The audio is mixed to mono,
  low-pass filtered and decimated to about 11 kHz.
  Tempo: an onset envelope (spectral flux) is autocorrelated over the whole track; the
  candidate within the chosen one-octave range whose multiples are strongest wins, and it
  is refined by folding the envelope over the beat period (the exact period lines the
  beats of the whole track up).
  Key: spectral peaks between C2 and C7 are collected as pitch classes in 10-cent steps,
  the tuning offset is taken out, and the 12 pitch classes (plus those of the bass alone)
  are correlated with major and minor key profiles. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, WorkBatch;

type
  TKeyNotation = (knMusical, knCamelot, knOpenKey);

  TAnalysisOptions = record
    DoBpm, DoKey: Boolean;
    MinBpm: Double;  // tempo range MinBpm .. 2 * MinBpm
  end;

  TAnalysisResult = record
    FileName: string;
    Bpm: Double;         // 0 = no tempo found
    BpmSteady: Boolean;  // the tempo holds through the track
    Key: Integer;        // 0..11 major, 12..23 minor (pitch class + 12); -1 = unknown
    KeyClarity: Double;  // distance to the second best key, 0..1
    Error: string;       // '' = analysed
    Chroma, BassChroma: array[0..11] of Double; // pitch class energy from C (all / below 260 Hz)
  end;

  TSingleArray = array of Single;
  TDoubleArray12 = array[0..11] of Double;

  TAnalysisBatch = class(TWorkBatch)
  private
    FOpt: TAnalysisOptions;
  protected
    procedure Process(Index: Integer); override;
  public
    Results: array of TAnalysisResult;
    constructor Create(const Files: TStringArray; const Opt: TAnalysisOptions);
  end;

const
  DefaultMinBpm = 85;

function AnalyzeFile(const FileName: string; const Opt: TAnalysisOptions; Cancel: PBoolean): TAnalysisResult;
{ 'Am', 'F#' / '8A', '2B' / '1m', '7d'; '' for -1. }
function KeyName(Key: Integer; Notation: TKeyNotation): string;
{ Reads a key in any of the three notations (also 'A minor', 'Bbm', 'D#', '08A'); -1 if unknown. }
function ParseKey(const S: string): Integer;
{ '128', '128.5', '128.50' with '.' as separator. }
function BpmText(Bpm: Double; Decimals: Integer): string;

{ The steps on their own, for the tests. Env is the onset envelope at FrameRate. }
function EstimateBpm(const Env: TSingleArray; FrameRate, MinBpm: Double; out Steady: Boolean): Double;
function EstimateKey(const Chroma, BassChroma: TDoubleArray12; out Clarity: Double): Integer;

implementation

uses
  Math, AudioDecode;

resourcestring
  rsIngenLydAnalyse = 'ingen lyd';
  rsForKortTilTempo = 'for kort til tempo';
  rsIkkeAnalyseret = 'ikke analyseret';

const
  TargetRate = 11025;
  OnsetSize = 1024;   // FFT size for the onset envelope
  OnsetHop = 128;
  ChromaSize = 8192;  // FFT size for pitch (1.35 Hz per bin at 11025 Hz)
  ChromaHop = 2048;
  CentSteps = 120;    // pitch classes in 10-cent steps
  MinPitchHz = 63;    // a little below C2
  MaxPitchHz = 2100;  // about C7

  // spelled as in the key signature: Db major (5 flats) rather than C# major (7 sharps)
  MajorNames: array[0..11] of string = ('C', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B');
  MinorNames: array[0..11] of string = ('Cm', 'C#m', 'Dm', 'Ebm', 'Em', 'Fm', 'F#m', 'Gm', 'G#m', 'Am', 'Bbm', 'Bm');

  { Key profiles from C, measured with this analysis on 1125 dance/pop tracks whose key tags
    came from DJ software (average pitch-class profile per key, after the square root
    compression below). They matched the tags in 75 % of the tracks in cross-validation;
    the classic Krumhansl/Temperley/Aarden profiles reached 50-58 % on the same tracks. }
  MajorProfile: TDoubleArray12 = (0.1097, 0.0725, 0.0869, 0.0718, 0.0934, 0.0799, 0.0717, 0.1043, 0.0711, 0.0810, 0.0764, 0.0814);
  MinorProfile: TDoubleArray12 = (0.1099, 0.0739, 0.0861, 0.0872, 0.0769, 0.0804, 0.0710, 0.1054, 0.0749, 0.0720, 0.0870, 0.0753);
  BassMajorProfile: TDoubleArray12 = (0.1000, 0.0795, 0.0816, 0.0785, 0.0854, 0.0805, 0.0787, 0.0934, 0.0779, 0.0808, 0.0798, 0.0838);
  BassMinorProfile: TDoubleArray12 = (0.1008, 0.0808, 0.0813, 0.0832, 0.0801, 0.0805, 0.0786, 0.0923, 0.0803, 0.0777, 0.0824, 0.0820);
  BassWeight = 0.25;

type
  TDoubleArray = array of Double;
  TComplexArray = array of record Re, Im: Double; end;

{ In-place radix-2 FFT; Length(A) must be a power of two. }
procedure FFT(var A: TComplexArray);
var
  N, I, J, K, M, Half: Integer;
  TRe, TIm, WRe, WIm, UR, UI, Ang, CS, SN: Double;
begin
  N := Length(A);
  J := 0;
  for I := 0 to N - 2 do
  begin
    if I < J then
    begin
      TRe := A[I].Re; A[I].Re := A[J].Re; A[J].Re := TRe;
      TIm := A[I].Im; A[I].Im := A[J].Im; A[J].Im := TIm;
    end;
    K := N shr 1;
    while K <= J do
    begin
      Dec(J, K);
      K := K shr 1;
    end;
    Inc(J, K);
  end;
  M := 2;
  while M <= N do
  begin
    Half := M shr 1;
    Ang := -2 * Pi / M;
    CS := Cos(Ang);
    SN := Sin(Ang);
    I := 0;
    while I < N do
    begin
      WRe := 1;
      WIm := 0;
      for K := 0 to Half - 1 do
      begin
        UR := A[I + K + Half].Re * WRe - A[I + K + Half].Im * WIm;
        UI := A[I + K + Half].Re * WIm + A[I + K + Half].Im * WRe;
        A[I + K + Half].Re := A[I + K].Re - UR;
        A[I + K + Half].Im := A[I + K].Im - UI;
        A[I + K].Re := A[I + K].Re + UR;
        A[I + K].Im := A[I + K].Im + UI;
        TRe := WRe * CS - WIm * SN;
        WIm := WRe * SN + WIm * CS;
        WRe := TRe;
      end;
      Inc(I, M);
    end;
    M := M shl 1;
  end;
end;

function HannWindow(N: Integer): TSingleArray;
var
  I: Integer;
begin
  SetLength(Result, N);
  for I := 0 to N - 1 do Result[I] := 0.5 - 0.5 * Cos(2 * Pi * I / N);
end;

{ Tempo }

{ Linear interpolation into A at a fractional index; 0 outside. }
function At(const A: array of Double; X: Double): Double;
var
  I: Integer;
  F: Double;
begin
  I := Floor(X);
  if (I < 0) or (I + 1 > High(A)) then Exit(0);
  F := X - I;
  Result := A[I] * (1 - F) + A[I + 1] * F;
end;

{ Autocorrelation of X (lags 0..MaxLag) through the FFT. }
function AutoCorr(const X: array of Double; MaxLag: Integer): TDoubleArray;
var
  N, I: Integer;
  C: TComplexArray;
  R: Double;
begin
  N := 1;
  while N < 2 * Length(X) do N := N shl 1;
  SetLength(C, N);
  for I := 0 to N - 1 do
  begin
    if I < Length(X) then C[I].Re := X[I] else C[I].Re := 0;
    C[I].Im := 0;
  end;
  FFT(C);
  for I := 0 to N - 1 do
  begin
    C[I].Re := Sqr(C[I].Re) + Sqr(C[I].Im);
    C[I].Im := 0;
  end;
  FFT(C); // the power spectrum is real and even, so a forward FFT gives the same as the inverse
  SetLength(Result, Min(MaxLag, Length(X) - 1) + 1);
  for I := 0 to High(Result) do
  begin
    R := C[I].Re / N;
    Result[I] := R / (Length(X) - I); // unbiased
  end;
end;

{ Best tempo of the envelope part by the strength of the beat period and its multiples. }
function CoarseBpm(const O: array of Double; FrameRate, MinBpm: Double): Double;
var
  AC: TDoubleArray;
  B, L, S, Best: Double;
  K: Integer;
begin
  Result := 0;
  AC := AutoCorr(O, Ceil(4 * 60 * FrameRate / MinBpm) + 2);
  Best := -MaxDouble;
  B := MinBpm;
  while B < 2 * MinBpm do
  begin
    L := 60 * FrameRate / B;
    S := 0;
    for K := 1 to 4 do S := S + At(AC, K * L) / Sqrt(K);
    if S > Best then
    begin
      Best := S;
      Result := B;
    end;
    B := B + 0.1;
  end;
end;

{ How sharply the envelope lines up when folded over the period of Bpm. }
function FoldSharpness(const O: array of Double; FrameRate, Bpm: Double): Double;
const
  Bins = 48;
var
  H: array[0..Bins - 1] of Double;
  P, Total, S: Double;
  I, Bin: Integer;
begin
  P := 60 * FrameRate / Bpm;
  FillChar(H, SizeOf(H), 0);
  Total := 0;
  for I := 0 to High(O) do
  begin
    Bin := Trunc(Frac(I / P) * Bins) mod Bins;
    H[Bin] := H[Bin] + O[I];
    Total := Total + O[I];
  end;
  if Total <= 0 then Exit(0);
  Result := 0;
  for I := 0 to Bins - 1 do
  begin
    S := H[(I + Bins - 1) mod Bins] + H[I] + H[(I + 1) mod Bins];
    if S > Result then Result := S;
  end;
  Result := Result / Total;
end;

{ Envelope with the slow level taken out and negative values cut. }
function PrepareEnvelope(const Env: TSingleArray; FrameRate: Double): TDoubleArray;
var
  W, I: Integer;
  Sum: Double;
  Prefix: TDoubleArray;
begin
  SetLength(Prefix, Length(Env) + 1);
  Prefix[0] := 0;
  for I := 0 to High(Env) do Prefix[I + 1] := Prefix[I] + Env[I];
  W := Max(1, Round(FrameRate * 0.5));
  SetLength(Result, Length(Env));
  for I := 0 to High(Env) do
  begin
    Sum := Prefix[Min(Length(Env), I + W + 1)] - Prefix[Max(0, I - W)];
    Result[I] := Max(0, Env[I] - Sum / (Min(Length(Env), I + W + 1) - Max(0, I - W)));
  end;
end;

function EstimateBpm(const Env: TSingleArray; FrameRate, MinBpm: Double; out Steady: Boolean): Double;
var
  O, Part: TDoubleArray;
  B0, B, Best, S, Energy, Median: Double;
  SegLen, NSeg, I, Agree, Counted: Integer;
  SegBpm, SegEnergy, Sorted: TDoubleArray;
begin
  Steady := False;
  Result := 0;
  if Length(Env) < FrameRate * 8 then Exit; // under 8 seconds
  O := PrepareEnvelope(Env, FrameRate);
  B0 := CoarseBpm(O, FrameRate, MinBpm);
  if B0 = 0 then Exit;
  // refine: the exact period makes the beats of the whole track fall on the same phase;
  // first in 0.02 steps (a wrong period smears the beats quickly) around the estimate,
  // then in 0.005 steps
  Best := -1;
  Result := B0;
  B := B0 - 2;
  while B <= B0 + 2 do
  begin
    S := FoldSharpness(O, FrameRate, B);
    if S > Best then
    begin
      Best := S;
      Result := B;
    end;
    B := B + 0.02;
  end;
  B0 := Result;
  B := B0 - 0.02;
  while B <= B0 + 0.02 do
  begin
    S := FoldSharpness(O, FrameRate, B);
    if S > Best then
    begin
      Best := S;
      Result := B;
    end;
    B := B + 0.005;
  end;
  // steady: the parts with drums (enough onset energy) agree with the whole
  SegLen := Round(20 * FrameRate);
  NSeg := Length(O) div SegLen;
  if NSeg < 3 then
  begin
    Steady := True;
    Exit;
  end;
  SetLength(SegBpm, NSeg);
  SetLength(SegEnergy, NSeg);
  for I := 0 to NSeg - 1 do
  begin
    Part := Copy(O, I * SegLen, SegLen);
    Energy := 0;
    for S in Part do Energy := Energy + S;
    SegEnergy[I] := Energy;
    SegBpm[I] := CoarseBpm(Part, FrameRate, MinBpm);
  end;
  Sorted := Copy(SegEnergy);
  for I := 1 to High(Sorted) do  // insertion sort, few items
  begin
    S := Sorted[I];
    Agree := I - 1;
    while (Agree >= 0) and (Sorted[Agree] > S) do
    begin
      Sorted[Agree + 1] := Sorted[Agree];
      Dec(Agree);
    end;
    Sorted[Agree + 1] := S;
  end;
  Median := Sorted[NSeg div 2];
  Agree := 0;
  Counted := 0;
  for I := 0 to NSeg - 1 do
    if SegEnergy[I] >= 0.5 * Median then
    begin
      Inc(Counted);
      if Abs(SegBpm[I] - Result) <= 0.02 * Result then Inc(Agree);
    end;
  Steady := (Counted > 0) and (Agree >= 0.75 * Counted);
end;

{ Key }

function KeyName(Key: Integer; Notation: TKeyNotation): string;
var
  PC, Major, N: Integer;
  Minor: Boolean;
begin
  if (Key < 0) or (Key > 23) then Exit('');
  Minor := Key >= 12;
  PC := Key mod 12;
  if Minor then Major := (PC + 3) mod 12 else Major := PC; // a minor key shares the relative major's number
  case Notation of
    knMusical:
      if Minor then Result := MinorNames[PC] else Result := MajorNames[PC];
    knCamelot:
      begin
        N := (7 * Major + 8) mod 12;
        if N = 0 then N := 12;
        if Minor then Result := IntToStr(N) + 'A' else Result := IntToStr(N) + 'B';
      end;
    knOpenKey:
      begin
        N := (7 * Major) mod 12 + 1;
        if Minor then Result := IntToStr(N) + 'm' else Result := IntToStr(N) + 'd';
      end;
  end;
end;

function ParseKey(const S: string): Integer;
var
  T, Letter: string;
  N, PC, I: Integer;
  Minor: Boolean;
const
  Letters = 'C D EF G A B'; // pitch class of each letter: its position
begin
  Result := -1;
  T := LowerCase(Trim(S));
  T := StringReplace(T, '♯', '#', [rfReplaceAll]);
  T := StringReplace(T, '♭', 'b', [rfReplaceAll]);
  if T = '' then Exit;
  // Camelot (8A/8B) and Open Key (1m/1d)
  I := 1;
  while (I <= Length(T)) and (T[I] in ['0'..'9']) do Inc(I);
  if (I > 1) and (I = Length(T)) and TryStrToInt(Copy(T, 1, I - 1), N) and (N >= 1) and (N <= 12) then
  begin
    case T[I] of
      'a', 'b':
        begin
          PC := ((N - 8 + 12) * 7) mod 12;  // inverse of (7 * p + 8) mod 12
          if T[I] = 'b' then Exit(PC) else Exit(12 + (PC + 9) mod 12);
        end;
      'd', 'm':
        begin
          PC := ((N - 1) * 7) mod 12;
          if T[I] = 'd' then Exit(PC) else Exit(12 + (PC + 9) mod 12);
        end;
    end;
    Exit;
  end;
  // musical: letter, accidental, then 'm', 'min', 'minor', 'maj', 'major' or nothing
  Letter := UpperCase(T[1]);
  PC := Pos(Letter, Letters) - 1;
  if (PC < 0) or (Letter = ' ') then Exit;
  I := 2;
  if (I <= Length(T)) and (T[I] = '#') then begin Inc(PC); Inc(I); end
  else if (I <= Length(T)) and (T[I] = 'b') then begin Dec(PC); Inc(I); end;
  PC := (PC + 12) mod 12;
  T := Trim(Copy(T, I, MaxInt));
  if (T = '') or (T = 'maj') or (T = 'major') or (T = 'dur') then Minor := False
  else if (T = 'm') or (T = 'min') or (T = 'minor') or (T = 'moll') then Minor := True
  else Exit;
  if Minor then Result := 12 + PC else Result := PC;
end;

function Correlation(const A, B: TDoubleArray12; Shift: Integer): Double;
var
  I: Integer;
  MA, MB, SA, SB, SAB, DA, DB: Double;
begin
  MA := 0;
  MB := 0;
  for I := 0 to 11 do
  begin
    MA := MA + A[I];
    MB := MB + B[I];
  end;
  MA := MA / 12;
  MB := MB / 12;
  SA := 0;
  SB := 0;
  SAB := 0;
  for I := 0 to 11 do
  begin
    DA := A[(I + Shift) mod 12] - MA;
    DB := B[I] - MB;
    SAB := SAB + DA * DB;
    SA := SA + DA * DA;
    SB := SB + DB * DB;
  end;
  if (SA = 0) or (SB = 0) then Exit(0);
  Result := SAB / Sqrt(SA * SB);
end;

{ Sum 1, square root (so a few loud notes do not decide), sum 1 again. }
function Compressed(const V: TDoubleArray12): TDoubleArray12;
var
  I: Integer;
  S: Double;
begin
  S := 0;
  for I := 0 to 11 do S := S + V[I];
  for I := 0 to 11 do
    if S > 0 then Result[I] := Sqrt(V[I] / S) else Result[I] := 1;
  S := 0;
  for I := 0 to 11 do S := S + Result[I];
  for I := 0 to 11 do Result[I] := Result[I] / S;
end;

function EstimateKey(const Chroma, BassChroma: TDoubleArray12; out Clarity: Double): Integer;
var
  K: Integer;
  R, Best, Second: Double;
  C, B: TDoubleArray12;
begin
  C := Compressed(Chroma);
  B := Compressed(BassChroma);
  Result := -1;
  Clarity := 0;
  Best := -2;
  Second := -2;
  for K := 0 to 23 do
  begin
    if K < 12 then
      R := Correlation(C, MajorProfile, K) + BassWeight * Correlation(B, BassMajorProfile, K)
    else
      R := Correlation(C, MinorProfile, K - 12) + BassWeight * Correlation(B, BassMinorProfile, K - 12);
    if R > Best then
    begin
      Second := Best;
      Best := R;
      Result := K;
    end
    else if R > Second then Second := R;
  end;
  if Best <= 0 then Exit(-1);
  Clarity := Max(0, Best - Second);
end;

function BpmText(Bpm: Double; Decimals: Integer): string;
var
  FS: TFormatSettings;
begin
  if Bpm <= 0 then Exit('');
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  if Decimals <= 0 then Result := IntToStr(Round(Bpm))
  else Result := FloatToStrF(Bpm, ffFixed, 15, Decimals, FS);
end;

{ Collecting }

type
  TBiquad = record
    B0, B1, B2, A1, A2, Z1, Z2: Double;
  end;

  TAnalyzer = class
  private
    FOpt: TAnalysisOptions;
    FChannels, FDecim, FPhase: Integer;
    FRate: Double;               // after decimation
    FLow: array[0..1] of TBiquad;
    FBuf: TSingleArray;          // decimated mono samples not yet consumed
    FBufLen: Integer;
    FBufStart: Int64;            // sample number of FBuf[0]
    FNextOnset, FNextChroma: Int64;
    FOnsetWin, FChromaWin: TSingleArray;
    FPrevLog: TSingleArray;
    FFFT: TComplexArray;
    FTotal: Int64;
  public
    Env: TSingleArray;
    EnvLen: Integer;
    Pitch, BassPitch: array[0..CentSteps - 1] of Double;
    constructor Create(const Opt: TAnalysisOptions);
    procedure Format(Rate, Channels: Integer);
    procedure Data(Samples: PSingle; Frames: Integer);
    procedure Flush;
    function FrameRate: Double;
    function Chroma(out Tuning: Double): TDoubleArray12;
    function BassChroma(Tuning: Double): TDoubleArray12;
    property Total: Int64 read FTotal;
  end;

procedure LowPass(var F: TBiquad; Cutoff, Rate, Q: Double);
var
  W, Alpha, CosW, A0: Double;
begin
  W := 2 * Pi * Cutoff / Rate;
  CosW := Cos(W);
  Alpha := Sin(W) / (2 * Q);
  A0 := 1 + Alpha;
  F.B0 := (1 - CosW) / 2 / A0;
  F.B1 := (1 - CosW) / A0;
  F.B2 := F.B0;
  F.A1 := -2 * CosW / A0;
  F.A2 := (1 - Alpha) / A0;
  F.Z1 := 0;
  F.Z2 := 0;
end;

function Run(var F: TBiquad; X: Double): Double; inline;
begin
  Result := F.B0 * X + F.Z1;
  F.Z1 := F.B1 * X - F.A1 * Result + F.Z2;
  F.Z2 := F.B2 * X - F.A2 * Result;
end;

constructor TAnalyzer.Create(const Opt: TAnalysisOptions);
begin
  inherited Create;
  FOpt := Opt;
  FOnsetWin := HannWindow(OnsetSize);
  FChromaWin := HannWindow(ChromaSize);
  SetLength(FPrevLog, OnsetSize div 2);
  FillChar(Pitch, SizeOf(Pitch), 0);
  FillChar(BassPitch, SizeOf(BassPitch), 0);
end;

procedure TAnalyzer.Format(Rate, Channels: Integer);
var
  Cut: Double;
begin
  FChannels := Max(1, Channels);
  FDecim := Max(1, Round(Rate / TargetRate));
  FRate := Rate / FDecim;
  // 4th order Butterworth well below the new Nyquist frequency
  Cut := Min(0.4 * FRate, 0.45 * Rate);
  LowPass(FLow[0], Cut, Rate, 0.5412);
  LowPass(FLow[1], Cut, Rate, 1.3066);
  FPhase := 0;
end;

function TAnalyzer.FrameRate: Double;
begin
  Result := FRate / OnsetHop;
end;

procedure TAnalyzer.Data(Samples: PSingle; Frames: Integer);
var
  I, C, Bin, K, Lo, Hi: Integer;
  X, M, L, Flux, Freq, Note, A, B, G, P: Double;
  Pos: Int64;
  Mag: TDoubleArray;
begin
  if FChannels = 0 then raise Exception.Create('no audio format');
  for I := 0 to Frames - 1 do
  begin
    X := 0;
    for C := 0 to FChannels - 1 do
    begin
      X := X + Samples^;
      Inc(Samples);
    end;
    X := Run(FLow[1], Run(FLow[0], X / FChannels));
    Inc(FPhase);
    if FPhase < FDecim then Continue;
    FPhase := 0;
    if FBufLen = Length(FBuf) then SetLength(FBuf, Max(65536, 2 * Length(FBuf)));
    FBuf[FBufLen] := X;
    Inc(FBufLen);
    Inc(FTotal);
  end;

  // onset envelope: positive change of the log spectrum
  if FOpt.DoBpm then
    while FNextOnset + OnsetSize <= FBufStart + FBufLen do
    begin
      SetLength(FFFT, OnsetSize);
      Pos := FNextOnset - FBufStart;
      for K := 0 to OnsetSize - 1 do
      begin
        FFFT[K].Re := FBuf[Pos + K] * FOnsetWin[K];
        FFFT[K].Im := 0;
      end;
      FFT(FFFT);
      Flux := 0;
      for Bin := 1 to OnsetSize div 2 - 1 do
      begin
        L := Ln(1 + 100 * Sqrt(Sqr(FFFT[Bin].Re) + Sqr(FFFT[Bin].Im)));
        if L > FPrevLog[Bin] then Flux := Flux + L - FPrevLog[Bin];
        FPrevLog[Bin] := L;
      end;
      if EnvLen = Length(Env) then SetLength(Env, Max(4096, 2 * Length(Env)));
      Env[EnvLen] := Flux;
      Inc(EnvLen);
      Inc(FNextOnset, OnsetHop);
    end;

  // pitch: spectral peaks as pitch classes, each frame weighted equally
  if FOpt.DoKey then
    while FNextChroma + ChromaSize <= FBufStart + FBufLen do
    begin
      SetLength(FFFT, ChromaSize);
      Pos := FNextChroma - FBufStart;
      for K := 0 to ChromaSize - 1 do
      begin
        FFFT[K].Re := FBuf[Pos + K] * FChromaWin[K];
        FFFT[K].Im := 0;
      end;
      FFT(FFFT);
      Lo := Max(2, Floor(MinPitchHz * ChromaSize / FRate));
      Hi := Min(ChromaSize div 2 - 2, Ceil(MaxPitchHz * ChromaSize / FRate));
      SetLength(Mag, Hi + 2);
      for Bin := Lo - 1 to Hi + 1 do Mag[Bin] := Sqrt(Sqr(FFFT[Bin].Re) + Sqr(FFFT[Bin].Im));
      M := 0;
      for Bin := Lo to Hi do M := M + Mag[Bin];
      if M > 1e-6 then
        for Bin := Lo to Hi do
          if (Mag[Bin] > Mag[Bin - 1]) and (Mag[Bin] >= Mag[Bin + 1]) and (Mag[Bin] > 2 * M / (Hi - Lo + 1)) then
          begin
            // parabolic interpolation of the peak position
            A := Mag[Bin - 1];
            B := Mag[Bin];
            G := Mag[Bin + 1];
            P := 0;
            if A - 2 * B + G <> 0 then P := 0.5 * (A - G) / (A - 2 * B + G);
            Freq := (Bin + P) * FRate / ChromaSize;
            if Freq <= 0 then Continue;
            Note := 12 * Log2(Freq / 440) + 69 + 1200; // positive; C = multiple of 12
            K := Round(Frac(Note / 12) * CentSteps) mod CentSteps;
            Pitch[K] := Pitch[K] + Sqrt(B / M);
            if Freq < 260 then BassPitch[K] := BassPitch[K] + Sqrt(B / M);
          end;
      Inc(FNextChroma, ChromaHop);
    end;

  // drop what both analyses are done with
  Pos := FBufLen;
  if FOpt.DoBpm then Pos := Min(Pos, FNextOnset - FBufStart);
  if FOpt.DoKey then Pos := Min(Pos, FNextChroma - FBufStart);
  if Pos > 32768 then
  begin
    Move(FBuf[Pos], FBuf[0], (FBufLen - Pos) * SizeOf(Single));
    Dec(FBufLen, Pos);
    Inc(FBufStart, Pos);
  end;
end;

procedure TAnalyzer.Flush;
begin
  SetLength(Env, EnvLen);
end;

function TAnalyzer.Chroma(out Tuning: Double): TDoubleArray12;
var
  I, PC: Integer;
  SRe, SIm, Ang, Pos: Double;
begin
  // tuning: circular mean of the distance to the nearest semitone (10 steps per semitone)
  SRe := 0;
  SIm := 0;
  for I := 0 to CentSteps - 1 do
  begin
    Ang := 2 * Pi * (I mod 10) / 10;
    SRe := SRe + Pitch[I] * Cos(Ang);
    SIm := SIm + Pitch[I] * Sin(Ang);
  end;
  Tuning := ArcTan2(SIm, SRe) / (2 * Pi) * 10; // in steps of 10 cents, -5..5
  for PC := 0 to 11 do Result[PC] := 0;
  for I := 0 to CentSteps - 1 do
  begin
    Pos := (I - Tuning) / 10; // semitones from C after taking out the tuning
    PC := (Round(Pos) + 12) mod 12;
    Result[PC] := Result[PC] + Pitch[I];
  end;
end;

function TAnalyzer.BassChroma(Tuning: Double): TDoubleArray12;
var
  I, PC: Integer;
begin
  for PC := 0 to 11 do Result[PC] := 0;
  for I := 0 to CentSteps - 1 do
  begin
    PC := (Round((I - Tuning) / 10) + 12) mod 12;
    Result[PC] := Result[PC] + BassPitch[I];
  end;
end;

type
  TSink = class
    A: TAnalyzer;
    procedure Format(Rate, Channels: Integer);
    procedure Data(Samples: PSingle; Frames: Integer);
  end;

procedure TSink.Format(Rate, Channels: Integer);
begin
  A.Format(Rate, Channels);
end;

procedure TSink.Data(Samples: PSingle; Frames: Integer);
begin
  A.Data(Samples, Frames);
end;

function AnalyzeFile(const FileName: string; const Opt: TAnalysisOptions; Cancel: PBoolean): TAnalysisResult;
var
  Sink: TSink;
  Ch, Bass: TDoubleArray12;
  Tuning: Double;
begin
  Result.FileName := FileName;
  Result.Bpm := 0;
  Result.BpmSteady := False;
  Result.Key := -1;
  Result.KeyClarity := 0;
  Result.Error := '';
  FillChar(Result.Chroma, SizeOf(Result.Chroma), 0);
  FillChar(Result.BassChroma, SizeOf(Result.BassChroma), 0);
  Sink := TSink.Create;
  Sink.A := TAnalyzer.Create(Opt);
  try
    try
      Result.Error := DecodeAudio(FileName, @Sink.Format, @Sink.Data, Cancel);
    except
      on E: Exception do Result.Error := E.Message;
    end;
    if (Result.Error = '') and (Sink.A.Total = 0) then Result.Error := rsIngenLydAnalyse;
    if Result.Error <> '' then Exit;
    Sink.A.Flush;
    if Opt.DoBpm then
    begin
      Result.Bpm := EstimateBpm(Sink.A.Env, Sink.A.FrameRate, Opt.MinBpm, Result.BpmSteady);
      if Result.Bpm = 0 then Result.Error := rsForKortTilTempo;
    end;
    if Opt.DoKey then
    begin
      Ch := Sink.A.Chroma(Tuning);
      Bass := Sink.A.BassChroma(Tuning);
      Result.Key := EstimateKey(Ch, Bass, Result.KeyClarity);
      Move(Ch, Result.Chroma, SizeOf(Ch));
      Move(Bass, Result.BassChroma, SizeOf(Bass));
    end;
  finally
    Sink.A.Free;
    Sink.Free;
  end;
end;

{ TAnalysisBatch }

constructor TAnalysisBatch.Create(const Files: TStringArray; const Opt: TAnalysisOptions);
var
  I: Integer;
begin
  inherited Create(Files);
  FOpt := Opt;
  SetLength(Results, Length(Files));
  for I := 0 to High(Results) do
  begin
    Results[I].FileName := Files[I];
    Results[I].Bpm := 0;
    Results[I].Key := -1;
    Results[I].Error := rsIkkeAnalyseret;
  end;
end;

procedure TAnalysisBatch.Process(Index: Integer);
begin
  Results[Index] := AnalyzeFile(FFiles[Index], FOpt, @Cancelled);
end;

end.
