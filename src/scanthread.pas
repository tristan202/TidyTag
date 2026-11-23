unit ScanThread;

{ Background thread: finds audio files in a folder and reads their tags.
  The GUI polls TakeResults from a timer, so the thread never blocks on the main thread
  and can always be stopped with Terminate + WaitFor. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs, AudioTypes;

type
  TScanThread = class(TThread)
  private
    FFolder: string;
    FRecursive: Boolean;
    FLock: TCriticalSection;
    FPending: TFPList;
    FTotal: Integer;
    FDone: Integer;
    FError: string;
    procedure CollectFiles(const Dir: string; Files: TStrings);
  protected
    procedure Execute; override;
  public
    constructor Create(const AFolder: string; ARecursive: Boolean);
    destructor Destroy; override;
    { Moves finished TAudioInfo objects into Dest (Dest takes ownership). }
    procedure TakeResults(Dest: TFPList);
    function Progress(out Done, Total: Integer): Boolean;
    { Why the scan stopped early ('' when it did not), e.g. a phone that went away;
      the tracks read until then are kept. }
    function ErrorText: string;
  end;

implementation

uses
  AudioTags, FileLayer, PhoneClient;

const
  PrefetchChunk = 50; // phone files whose tag parts are fetched in one request

constructor TScanThread.Create(const AFolder: string; ARecursive: Boolean);
begin
  FFolder := IncludeTrailingPathDelimiter(AFolder);
  FRecursive := ARecursive;
  FLock := TCriticalSection.Create;
  FPending := TFPList.Create;
  FTotal := -1;
  inherited Create(False);
end;

destructor TScanThread.Destroy;
var
  I: Integer;
begin
  for I := 0 to FPending.Count - 1 do
    TAudioInfo(FPending[I]).Free;
  FPending.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TScanThread.CollectFiles(const Dir: string; Files: TStrings);
var
  SR: TSearchRec;
  E: TPhoneEntry;
  Subdirs: TStringList;
  I: Integer;
begin
  Subdirs := TStringList.Create;
  try
    if IsPhonePath(Dir) then
    begin
      for E in ListDirL(Dir) do
        if E.IsDir then
        begin
          if FRecursive then Subdirs.Add(Dir + E.Name + PathDelim);
        end
        else if IsAudioFile(E.Name) then
          Files.Add(Dir + E.Name);
    end
    else if FindFirst(Dir + '*', faAnyFile, SR) = 0 then
    try
      repeat
        if Terminated then Exit;
        if (SR.Name = '.') or (SR.Name = '..') then Continue;
        if SR.Attr and faDirectory <> 0 then
        begin
          if FRecursive then Subdirs.Add(Dir + SR.Name + PathDelim);
        end
        else if IsAudioFile(SR.Name) then
          Files.Add(Dir + SR.Name);
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
    Subdirs.Sort;
    for I := 0 to Subdirs.Count - 1 do
      CollectFiles(Subdirs[I], Files);
  finally
    Subdirs.Free;
  end;
end;

procedure TScanThread.Execute;
var
  Files: TStringList;
  I: Integer;
  Info: TAudioInfo;
begin
  Files := TStringList.Create;
  try
    try
    CollectFiles(FFolder, Files);
    FLock.Enter;
    FTotal := Files.Count;
    FLock.Leave;
    for I := 0 to Files.Count - 1 do
    begin
      if Terminated then Exit;
      if IsPhonePath(Files[I]) and (I mod PrefetchChunk = 0) then
        PrefetchTags(Copy(Files.ToStringArray, I, PrefetchChunk));
      Info := ReadAudioInfo(Files[I]);
      FLock.Enter;
      try
        FPending.Add(Info);
        FDone := I + 1;
      finally
        FLock.Leave;
      end;
    end;
    except
      on E: Exception do
      begin
        FLock.Enter;
        FError := E.Message;
        FLock.Leave;
      end;
    end;
  finally
    Files.Free;
  end;
end;

function TScanThread.ErrorText: string;
begin
  FLock.Enter;
  try
    Result := FError;
  finally
    FLock.Leave;
  end;
end;

procedure TScanThread.TakeResults(Dest: TFPList);
var
  I: Integer;
begin
  FLock.Enter;
  try
    for I := 0 to FPending.Count - 1 do
      Dest.Add(FPending[I]);
    FPending.Clear;
  finally
    FLock.Leave;
  end;
end;

function TScanThread.Progress(out Done, Total: Integer): Boolean;
begin
  FLock.Enter;
  try
    Done := FDone;
    Total := FTotal;
    Result := FTotal >= 0;
  finally
    FLock.Leave;
  end;
end;

end.
