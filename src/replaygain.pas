unit ReplayGain;

{ Measures many files for ReplayGain 2.0 on several threads. Each file keeps its block
  energies, so album values can be computed afterwards from any group of files. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Loudness;

type
  TRGMeasure = record
    FileName: string;
    Blocks: TDoubleArray;
    Peak: Double;
    Loudness: Double;  // LUFS; -Infinity for silence
    Error: string;     // '' = measured
  end;
  TRGMeasures = array of TRGMeasure;

  { Start it, poll Done/Finished (e.g. from a timer), read Results when finished. }
  TRGBatch = class
  private
    FFiles: TStringArray;
    FNext, FDone, FRunning: LongInt;
    FThreads: TList;
  public
    Results: TRGMeasures;
    Cancelled: Boolean;
    constructor Create(const Files: TStringArray);
    destructor Destroy; override;
    procedure Start(ThreadCount: Integer = 0);
    procedure Cancel;
    function Finished: Boolean;
    property Done: LongInt read FDone;
    function Count: Integer;
  end;

{ Measures one file (also used by the tests). }
function MeasureFile(const FileName: string; Cancel: PBoolean): TRGMeasure;
{ Gain for the given loudness ('' for silence) and the album values of several measures. }
function TrackGainText(const M: TRGMeasure): string;
procedure AlbumValues(const Ms: array of TRGMeasure; out Gain, Peak: string);

implementation

uses
  Math, AudioDecode, AudioTypes;

resourcestring
  rsIngenLyd = 'ingen lyd';
  rsIkkeMaalt = 'ikke målt';

type
  TSink = class
    Meter: TLoudnessMeter;
    procedure Format(Rate, Channels: Integer);
    procedure Data(Samples: PSingle; Frames: Integer);
  end;

  TRGThread = class(TThread)
  private
    FBatch: TRGBatch;
  protected
    procedure Execute; override;
  public
    constructor Create(Batch: TRGBatch);
  end;

procedure TSink.Format(Rate, Channels: Integer);
begin
  Meter.SetFormat(Rate, Channels);
end;

procedure TSink.Data(Samples: PSingle; Frames: Integer);
begin
  Meter.AddFrames(Samples, Frames);
end;

function MeasureFile(const FileName: string; Cancel: PBoolean): TRGMeasure;
var
  Sink: TSink;
begin
  Result.FileName := FileName;
  Result.Blocks := nil;
  Result.Peak := 0;
  Result.Loudness := NegInfinity;
  Result.Error := '';
  Sink := TSink.Create;
  Sink.Meter := TLoudnessMeter.Create;
  try
    try
      Result.Error := DecodeAudio(FileName, @Sink.Format, @Sink.Data, Cancel);
    except
      on E: Exception do Result.Error := E.Message;
    end;
    if (Result.Error = '') and (Sink.Meter.Frames = 0) then Result.Error := rsIngenLyd;
    if Result.Error = '' then
    begin
      Result.Blocks := Sink.Meter.Blocks;
      Result.Peak := Sink.Meter.Peak;
      Result.Loudness := GatedLoudness(Result.Blocks);
    end;
  finally
    Sink.Meter.Free;
    Sink.Free;
  end;
end;

function TrackGainText(const M: TRGMeasure): string;
begin
  if IsInfinite(M.Loudness) or IsNan(M.Loudness) then Exit('');
  Result := RGGainText(RG2Reference - M.Loudness);
end;

procedure AlbumValues(const Ms: array of TRGMeasure; out Gain, Peak: string);
var
  All: TDoubleArray;
  I, N: Integer;
  P, L: Double;
begin
  All := nil;
  N := 0;
  P := 0;
  for I := 0 to High(Ms) do
  begin
    SetLength(All, N + Length(Ms[I].Blocks));
    if Length(Ms[I].Blocks) > 0 then
      Move(Ms[I].Blocks[0], All[N], Length(Ms[I].Blocks) * SizeOf(Double));
    Inc(N, Length(Ms[I].Blocks));
    P := Max(P, Ms[I].Peak);
  end;
  L := GatedLoudness(All);
  if IsInfinite(L) then Gain := '' else Gain := RGGainText(RG2Reference - L);
  Peak := RGPeakText(P);
end;

{ TRGThread }

constructor TRGThread.Create(Batch: TRGBatch);
begin
  FBatch := Batch;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TRGThread.Execute;
var
  I: LongInt;
begin
  try
    repeat
      I := InterLockedIncrement(FBatch.FNext) - 1;
      if (I >= Length(FBatch.FFiles)) or FBatch.Cancelled then Break;
      FBatch.Results[I] := MeasureFile(FBatch.FFiles[I], @FBatch.Cancelled);
      InterLockedIncrement(FBatch.FDone);
    until False;
  finally
    InterLockedDecrement(FBatch.FRunning);
  end;
end;

{ TRGBatch }

constructor TRGBatch.Create(const Files: TStringArray);
var
  I: Integer;
begin
  inherited Create;
  FFiles := Copy(Files);
  SetLength(Results, Length(Files));
  for I := 0 to High(Results) do
  begin
    Results[I].FileName := Files[I];
    Results[I].Error := rsIkkeMaalt;
    Results[I].Loudness := NegInfinity;
  end;
  FThreads := TList.Create;
end;

destructor TRGBatch.Destroy;
var
  I: Integer;
begin
  Cancelled := True;
  for I := 0 to FThreads.Count - 1 do
  begin
    TRGThread(FThreads[I]).WaitFor;
    TRGThread(FThreads[I]).Free;
  end;
  FThreads.Free;
  inherited Destroy;
end;

procedure TRGBatch.Start(ThreadCount: Integer);
var
  I: Integer;
begin
  if ThreadCount <= 0 then ThreadCount := Max(1, Min(TThread.ProcessorCount, 8));
  ThreadCount := Max(1, Min(ThreadCount, Length(FFiles)));
  FRunning := ThreadCount;
  for I := 1 to ThreadCount do FThreads.Add(TRGThread.Create(Self));
end;

procedure TRGBatch.Cancel;
begin
  Cancelled := True;
end;

function TRGBatch.Finished: Boolean;
begin
  Result := FRunning <= 0;
end;

function TRGBatch.Count: Integer;
begin
  Result := Length(FFiles);
end;

end.
