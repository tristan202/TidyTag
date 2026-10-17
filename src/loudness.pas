unit Loudness;

{ Loudness measurement for ReplayGain 2.0: ITU-R BS.1770-4 / EBU R128 integrated loudness
  (K-weighting, 400 ms blocks with 75 % overlap, absolute gate -70 LUFS and relative gate
  -10 LU) plus the sample peak. ReplayGain 2.0 uses -18 LUFS as reference level.

  The meter keeps the mean square of every block, so album loudness is computed by gating
  the blocks of all tracks together, as BS.1770 describes for a programme made of parts. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math;

type
  TDoubleArray = array of Double;

  TBiquad = record
    B0, B1, B2, A1, A2: Double;
  end;

  TLoudnessMeter = class
  private
    FRate, FChannels: Integer;
    FPre, FRlb: TBiquad;
    // filter state per channel: two delay elements per stage (transposed direct form II)
    FZ: array of array[0..3] of Double;
    FWeight: array of Double;
    FSubLen, FSubPos: Integer;   // 100 ms sub-blocks
    FSubSum: Double;
    FSubs: array[0..3] of Double; // last four sub-block sums (ring)
    FSubCount: Int64;
    FBlocks: TDoubleArray;
    FBlockCount: Integer;
    FPeak: Double;
    FTotalSum: Double;            // for files shorter than one block
    FTotalFrames: Int64;
    procedure AddBlock(E: Double);
  public
    constructor Create;
    { Called before the first samples and again if the stream format changes. }
    procedure SetFormat(Rate, Channels: Integer);
    { Interleaved float samples, 1.0 = full scale. }
    procedure AddFrames(Data: PSingle; Frames: Integer);
    { Mean square of each 400 ms block (gating input); for a very short file the whole file. }
    function Blocks: TDoubleArray;
    property Peak: Double read FPeak;
    property Rate: Integer read FRate;
    property Channels: Integer read FChannels;
    property Frames: Int64 read FTotalFrames;
  end;

const
  RG2Reference = -18.0; // LUFS
  SilenceLoudness = -70.0;

{ Gated loudness in LUFS of the given blocks; -Infinity when everything is below -70 LUFS. }
function GatedLoudness(const Blocks: TDoubleArray): Double;
{ The K-weighting filter for a sample rate (exposed for the tests). }
procedure KWeighting(Rate: Integer; out Pre, Rlb: TBiquad);

implementation

procedure KWeighting(Rate: Integer; out Pre, Rlb: TBiquad);
var
  F0, G, Q, K, Vh, Vb, A0: Double;
begin
  // stage 1: high shelf (head effects), coefficients derived for any sample rate
  F0 := 1681.974450955533;
  G := 3.999843853973347;
  Q := 0.7071752369554196;
  K := Tan(Pi * F0 / Rate);
  Vh := Power(10, G / 20);
  Vb := Power(Vh, 0.4996667741545416);
  A0 := 1 + K / Q + K * K;
  Pre.B0 := (Vh + Vb * K / Q + K * K) / A0;
  Pre.B1 := 2 * (K * K - Vh) / A0;
  Pre.B2 := (Vh - Vb * K / Q + K * K) / A0;
  Pre.A1 := 2 * (K * K - 1) / A0;
  Pre.A2 := (1 - K / Q + K * K) / A0;
  // stage 2: RLB high pass
  F0 := 38.13547087602444;
  Q := 0.5003270373238773;
  K := Tan(Pi * F0 / Rate);
  A0 := 1 + K / Q + K * K;
  Rlb.B0 := 1;
  Rlb.B1 := -2;
  Rlb.B2 := 1;
  Rlb.A1 := 2 * (K * K - 1) / A0;
  Rlb.A2 := (1 - K / Q + K * K) / A0;
end;

constructor TLoudnessMeter.Create;
begin
  inherited Create;
  FBlocks := nil;
end;

procedure TLoudnessMeter.SetFormat(Rate, Channels: Integer);
var
  C: Integer;
begin
  if (Rate = FRate) and (Channels = FChannels) then Exit;
  if (Rate <= 0) or (Channels <= 0) then raise Exception.Create('invalid audio format');
  FRate := Rate;
  FChannels := Channels;
  KWeighting(Rate, FPre, FRlb);
  SetLength(FZ, Channels);
  for C := 0 to Channels - 1 do FillChar(FZ[C], SizeOf(FZ[C]), 0);
  // channel weights: surround channels count 1.41, LFE not at all (WAVE/MF 5.1 order)
  SetLength(FWeight, Channels);
  for C := 0 to Channels - 1 do FWeight[C] := 1;
  // mono is played on both speakers: counted as dual mono (EBU Tech 3343, as rsgain/foobar2000)
  if Channels = 1 then FWeight[0] := 2
  else if Channels = 5 then
  begin
    FWeight[3] := 1.41;
    FWeight[4] := 1.41;
  end
  else if Channels >= 6 then
  begin
    FWeight[3] := 0;
    FWeight[4] := 1.41;
    FWeight[5] := 1.41;
  end;
  FSubLen := Max(1, Round(Rate / 10));
  FSubPos := 0;
  FSubSum := 0;
  FSubCount := 0;
end;

procedure TLoudnessMeter.AddBlock(E: Double);
begin
  if FBlockCount = Length(FBlocks) then SetLength(FBlocks, Max(64, FBlockCount * 2));
  FBlocks[FBlockCount] := E;
  Inc(FBlockCount);
end;

procedure TLoudnessMeter.AddFrames(Data: PSingle; Frames: Integer);
var
  I, C: Integer;
  X, Y, S, A: Double;
  Z: ^Double;
begin
  if FChannels = 0 then raise Exception.Create('no audio format');
  for I := 0 to Frames - 1 do
  begin
    S := 0;
    for C := 0 to FChannels - 1 do
    begin
      X := Data^;
      Inc(Data);
      A := Abs(X);
      if A > FPeak then FPeak := A;
      if FWeight[C] = 0 then Continue;
      Z := @FZ[C][0];
      // stage 1
      Y := FPre.B0 * X + Z[0];
      Z[0] := FPre.B1 * X - FPre.A1 * Y + Z[1];
      Z[1] := FPre.B2 * X - FPre.A2 * Y;
      X := Y;
      // stage 2
      Y := FRlb.B0 * X + Z[2];
      Z[2] := FRlb.B1 * X - FRlb.A1 * Y + Z[3];
      Z[3] := FRlb.B2 * X - FRlb.A2 * Y;
      S := S + FWeight[C] * Y * Y;
    end;
    FSubSum := FSubSum + S;
    FTotalSum := FTotalSum + S;
    Inc(FTotalFrames);
    Inc(FSubPos);
    if FSubPos = FSubLen then
    begin
      FSubs[FSubCount mod 4] := FSubSum;
      Inc(FSubCount);
      FSubSum := 0;
      FSubPos := 0;
      if FSubCount >= 4 then
        AddBlock((FSubs[0] + FSubs[1] + FSubs[2] + FSubs[3]) / (4.0 * FSubLen));
    end;
  end;
end;

function TLoudnessMeter.Blocks: TDoubleArray;
begin
  if (FBlockCount = 0) and (FTotalFrames > 0) then
  begin
    SetLength(Result, 1);
    Result[0] := FTotalSum / FTotalFrames;
    Exit;
  end;
  Result := Copy(FBlocks, 0, FBlockCount);
end;

function BlockLoudness(E: Double): Double;
begin
  if E <= 0 then Exit(NegInfinity);
  Result := -0.691 + 10 * Log10(E);
end;

function GatedLoudness(const Blocks: TDoubleArray): Double;
var
  AbsGate, RelGate, Sum: Double;
  I, N: Integer;
begin
  Result := NegInfinity;
  // absolute gate: -70 LUFS
  AbsGate := Power(10, (SilenceLoudness + 0.691) / 10);
  Sum := 0;
  N := 0;
  for I := 0 to High(Blocks) do
    if Blocks[I] >= AbsGate then
    begin
      Sum := Sum + Blocks[I];
      Inc(N);
    end;
  if N = 0 then Exit;
  // relative gate: 10 LU below the loudness of the blocks that passed
  RelGate := Sum / N * 0.1;
  Sum := 0;
  N := 0;
  for I := 0 to High(Blocks) do
    if (Blocks[I] >= AbsGate) and (Blocks[I] >= RelGate) then
    begin
      Sum := Sum + Blocks[I];
      Inc(N);
    end;
  if N = 0 then Exit;
  Result := BlockLoudness(Sum / N);
end;

end.
