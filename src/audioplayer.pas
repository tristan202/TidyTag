unit AudioPlayer;

{ Playback through Windows Media Foundation's MFPlay (mfplay.dll, part of Windows): plays
  every format Windows can decode, with seeking and volume. The DLL is loaded at run time;
  without it Available is False. Every interface method is declared so the vtable order
  is right; only the ones we call need exact parameters. No LCL. }

{$mode objfpc}{$H+}
{$interfaces com}

interface

uses
  Windows, SysUtils;

type
  TPlayerState = (psEmpty, psStopped, psPlaying, psPaused);

  TAudioPlayer = class
  private
    FPlayer: IUnknown;
    FFileName: string;
    FVolume: Single;
    function Player: Pointer;
  public
    constructor Create;
    destructor Destroy; override;
    { Starts playing the file; '' on success or an error text. }
    function Play(const FileName: string): string;
    procedure Pause;
    procedure Resume;
    procedure Stop;
    function State: TPlayerState;
    function Position: Double;   // seconds
    function Duration: Double;   // seconds; 0 while unknown
    procedure Seek(Seconds: Double);
    procedure SetVolume(V: Single); // 0..1
    property Volume: Single read FVolume;
    property FileName: string read FFileName;
  end;

function PlayerAvailable: Boolean;

implementation

resourcestring
  rsAfspillerMangler = 'Windows Media Foundation findes ikke på denne computer';
  rsKanIkkeAfspilles = 'filen kan ikke afspilles af Windows (codec mangler?) – fejl %s';

const
  MFP_MEDIAPLAYER_STATE_EMPTY = 0;
  MFP_MEDIAPLAYER_STATE_STOPPED = 1;
  MFP_MEDIAPLAYER_STATE_PLAYING = 2;
  MFP_MEDIAPLAYER_STATE_PAUSED = 3;
  VT_I8 = 20;
  VT_UI8 = 21;
  MFP_POSITIONTYPE_100NS: TGUID = '{00000000-0000-0000-0000-000000000000}';

type
  TPropVariant = record
    vt: Word;
    Reserved1, Reserved2, Reserved3: Word;
    Value: Int64;
    Pad: Int64; // PROPVARIANT is 24 bytes on 64-bit
  end;
  PPropVariant = ^TPropVariant;

  IMFPMediaPlayer = interface(IUnknown)
    ['{A714590A-58AF-430a-85BF-44F5EC838D85}']
    function Play: HRESULT; stdcall;
    function Pause: HRESULT; stdcall;
    function Stop: HRESULT; stdcall;
    function FrameStep: HRESULT; stdcall;
    function SetPosition(constref guidPositionType: TGUID; constref pvPositionValue: TPropVariant): HRESULT; stdcall;
    function GetPosition(constref guidPositionType: TGUID; out pvPositionValue: TPropVariant): HRESULT; stdcall;
    function GetDuration(constref guidPositionType: TGUID; out pvDurationValue: TPropVariant): HRESULT; stdcall;
    function SetRate(flRate: Single): HRESULT; stdcall;
    function GetRate(out pflRate: Single): HRESULT; stdcall;
    function GetSupportedRates(fForwardDirection: BOOL; out pflSlowestRate, pflFastestRate: Single): HRESULT; stdcall;
    function GetState(out peState: DWORD): HRESULT; stdcall;
    function CreateMediaItemFromURL(pwszURL: PWideChar; fSync: BOOL; dwUserData: PtrUInt; out ppMediaItem: IUnknown): HRESULT; stdcall;
    function CreateMediaItemFromObject(pIUnknownObj: IUnknown; fSync: BOOL; dwUserData: PtrUInt; out ppMediaItem: IUnknown): HRESULT; stdcall;
    function SetMediaItem(pIMFPMediaItem: IUnknown): HRESULT; stdcall;
    function ClearMediaItem: HRESULT; stdcall;
    function GetMediaItem(out ppIMFPMediaItem: IUnknown): HRESULT; stdcall;
    function GetVolume(out pflVolume: Single): HRESULT; stdcall;
    function SetVolume(flVolume: Single): HRESULT; stdcall;
    function GetBalance(out pflBalance: Single): HRESULT; stdcall;
    function SetBalance(flBalance: Single): HRESULT; stdcall;
    function GetMute(out pfMute: BOOL): HRESULT; stdcall;
    function SetMute(fMute: BOOL): HRESULT; stdcall;
    function GetNativeVideoSize(pszVideo, pszARVideo: Pointer): HRESULT; stdcall;
    function GetIdealVideoSize(pszMin, pszMax: Pointer): HRESULT; stdcall;
    function SetVideoSourceRect(pnrcSource: Pointer): HRESULT; stdcall;
    function GetVideoSourceRect(pnrcSource: Pointer): HRESULT; stdcall;
    function SetAspectRatioMode(dwAspectRatioMode: DWORD): HRESULT; stdcall;
    function GetAspectRatioMode(out pdwAspectRatioMode: DWORD): HRESULT; stdcall;
    function GetVideoWindow(out phwndVideo: HWND): HRESULT; stdcall;
    function UpdateVideo: HRESULT; stdcall;
    function SetBorderColor(Clr: COLORREF): HRESULT; stdcall;
    function GetBorderColor(out pClr: COLORREF): HRESULT; stdcall;
    function InsertEffect(pEffect: IUnknown; fOptional: BOOL): HRESULT; stdcall;
    function RemoveEffect(pEffect: IUnknown): HRESULT; stdcall;
    function RemoveAllEffects: HRESULT; stdcall;
    function Shutdown: HRESULT; stdcall;
  end;

  TMFPCreateMediaPlayer = function(pwszURL: PWideChar; fStartPlayback: BOOL; creationOptions: DWORD;
    pCallback: Pointer; hWnd: HWND; out ppMediaPlayer: IMFPMediaPlayer): HRESULT; stdcall;

var
  Lib: HMODULE = 0;
  Tried: Boolean = False;
  CreatePlayer: TMFPCreateMediaPlayer = nil;

function CoInitializeEx(pvReserved: Pointer; dwCoInit: DWORD): HRESULT; stdcall; external 'ole32.dll';

function PlayerAvailable: Boolean;
begin
  if not Tried then
  begin
    Tried := True;
    Lib := LoadLibrary('mfplay.dll');
    if Lib <> 0 then Pointer(CreatePlayer) := GetProcAddress(Lib, 'MFPCreateMediaPlayer');
  end;
  Result := Assigned(CreatePlayer);
end;

constructor TAudioPlayer.Create;
begin
  inherited Create;
  FVolume := 1;
end;

destructor TAudioPlayer.Destroy;
begin
  Stop;
  inherited Destroy;
end;

function TAudioPlayer.Player: Pointer;
begin
  Result := Pointer(FPlayer);
end;

function TAudioPlayer.Play(const FileName: string): string;
var
  P: IMFPMediaPlayer;
  HR: HRESULT;
  W: UnicodeString;
begin
  Result := '';
  Stop;
  if not PlayerAvailable then Exit(rsAfspillerMangler);
  CoInitializeEx(nil, 2); // apartment threaded; fine if COM is set up already
  W := UTF8Decode(FileName);
  HR := CreatePlayer(PWideChar(W), True, 0, nil, 0, P);
  if Failed(HR) or (P = nil) then Exit(Format(rsKanIkkeAfspilles, [IntToHex(DWORD(HR), 8)]));
  P.SetVolume(FVolume);
  FPlayer := P;
  FFileName := FileName;
end;

procedure TAudioPlayer.Pause;
begin
  if FPlayer <> nil then IMFPMediaPlayer(Player).Pause;
end;

procedure TAudioPlayer.Resume;
begin
  if FPlayer <> nil then IMFPMediaPlayer(Player).Play;
end;

procedure TAudioPlayer.Stop;
begin
  if FPlayer = nil then Exit;
  IMFPMediaPlayer(Player).Stop;
  IMFPMediaPlayer(Player).Shutdown;
  FPlayer := nil;
  FFileName := '';
end;

function TAudioPlayer.State: TPlayerState;
var
  S: DWORD;
begin
  Result := psEmpty;
  if (FPlayer = nil) or Failed(IMFPMediaPlayer(Player).GetState(S)) then Exit;
  case S of
    MFP_MEDIAPLAYER_STATE_STOPPED: Result := psStopped;
    MFP_MEDIAPLAYER_STATE_PLAYING: Result := psPlaying;
    MFP_MEDIAPLAYER_STATE_PAUSED: Result := psPaused;
  end;
end;

function TAudioPlayer.Position: Double;
var
  V: TPropVariant;
begin
  Result := 0;
  if FPlayer = nil then Exit;
  FillChar(V, SizeOf(V), 0);
  if Succeeded(IMFPMediaPlayer(Player).GetPosition(MFP_POSITIONTYPE_100NS, V)) and (V.vt in [VT_I8, VT_UI8]) then
    Result := V.Value / 1E7;
end;

function TAudioPlayer.Duration: Double;
var
  V: TPropVariant;
begin
  Result := 0;
  if FPlayer = nil then Exit;
  FillChar(V, SizeOf(V), 0);
  if Succeeded(IMFPMediaPlayer(Player).GetDuration(MFP_POSITIONTYPE_100NS, V)) and (V.vt in [VT_I8, VT_UI8]) then
    Result := V.Value / 1E7;
end;

procedure TAudioPlayer.Seek(Seconds: Double);
var
  V: TPropVariant;
begin
  if FPlayer = nil then Exit;
  FillChar(V, SizeOf(V), 0);
  V.vt := VT_I8;
  V.Value := Round(Seconds * 1E7);
  IMFPMediaPlayer(Player).SetPosition(MFP_POSITIONTYPE_100NS, V);
end;

procedure TAudioPlayer.SetVolume(V: Single);
begin
  if V < 0 then V := 0;
  if V > 1 then V := 1;
  FVolume := V;
  if FPlayer <> nil then IMFPMediaPlayer(Player).SetVolume(V);
end;

end.
