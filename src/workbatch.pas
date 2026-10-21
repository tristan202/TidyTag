unit WorkBatch;

{ Runs one job per file on several threads (ReplayGain, tempo and key analysis).
  Start it, poll Done/Finished (e.g. from a timer), read the results when finished. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TWorkBatch = class
  private
    FNext, FDone, FRunning: LongInt;
    FThreads: TList;
  protected
    FFiles: TStringArray;
    { Works on FFiles[Index]; runs on a worker thread, may poll Cancelled. }
    procedure Process(Index: Integer); virtual; abstract;
  public
    Cancelled: Boolean;
    constructor Create(const Files: TStringArray);
    destructor Destroy; override;
    procedure Start(ThreadCount: Integer = 0);
    procedure Cancel;
    function Finished: Boolean;
    function Count: Integer;
    property Done: LongInt read FDone;
  end;

implementation

uses
  Math;

type
  TWorkThread = class(TThread)
  private
    FBatch: TWorkBatch;
  protected
    procedure Execute; override;
  public
    constructor Create(Batch: TWorkBatch);
  end;

constructor TWorkThread.Create(Batch: TWorkBatch);
begin
  FBatch := Batch;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TWorkThread.Execute;
var
  I: LongInt;
begin
  try
    repeat
      I := InterLockedIncrement(FBatch.FNext) - 1;
      if (I >= Length(FBatch.FFiles)) or FBatch.Cancelled then Break;
      FBatch.Process(I);
      InterLockedIncrement(FBatch.FDone);
    until False;
  finally
    InterLockedDecrement(FBatch.FRunning);
  end;
end;

constructor TWorkBatch.Create(const Files: TStringArray);
begin
  inherited Create;
  FFiles := Copy(Files);
  FThreads := TList.Create;
end;

destructor TWorkBatch.Destroy;
var
  I: Integer;
begin
  Cancelled := True;
  for I := 0 to FThreads.Count - 1 do
  begin
    TWorkThread(FThreads[I]).WaitFor;
    TWorkThread(FThreads[I]).Free;
  end;
  FThreads.Free;
  inherited Destroy;
end;

procedure TWorkBatch.Start(ThreadCount: Integer);
var
  I: Integer;
begin
  if ThreadCount <= 0 then ThreadCount := Max(1, Min(TThread.ProcessorCount, 8));
  ThreadCount := Max(1, Min(ThreadCount, Length(FFiles)));
  FRunning := ThreadCount;
  for I := 1 to ThreadCount do FThreads.Add(TWorkThread.Create(Self));
end;

procedure TWorkBatch.Cancel;
begin
  Cancelled := True;
end;

function TWorkBatch.Finished: Boolean;
begin
  Result := FRunning <= 0;
end;

function TWorkBatch.Count: Integer;
begin
  Result := Length(FFiles);
end;

end.
