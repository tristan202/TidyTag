unit MFDecode;

{ Decoding through Windows Media Foundation's source reader, which converts any audio
  stream it can open to 32-bit float PCM. Media Foundation is part of Windows (missing only
  on "N" editions without the Media Feature Pack), so the DLLs are loaded at run time and
  a missing DLL just gives an error text. Only the interface methods we call need correct
  parameters, but every method is declared so the vtable order is right. }

{$mode objfpc}{$H+}
{$interfaces com}

interface

uses
  AudioDecode;

function DecodeWithMediaFoundation(const FileName: string; OnFormat: TPcmFormatEvent;
  OnData: TPcmDataEvent; Cancel: PBoolean): string;
{ True when Media Foundation could be loaded and started. }
function MediaFoundationAvailable: Boolean;

implementation

uses
  Windows, SysUtils, SyncObjs;

resourcestring
  rsMediaFoundationMangler = 'Windows Media Foundation findes ikke på denne computer';
  rsKanIkkeAabnes = 'filen kan ikke afkodes af Windows (codec mangler?) – fejl %s';
  rsAfkodningsfejl = 'afkodningsfejl %s';
  rsAfbrudt2 = 'afbrudt';

const
  MF_VERSION = $00020070;
  MFSTARTUP_LITE = 1;
  MF_SOURCE_READER_ALL_STREAMS = DWORD($FFFFFFFE);
  MF_SOURCE_READER_FIRST_AUDIO_STREAM = DWORD($FFFFFFFD);
  MF_SOURCE_READERF_ERROR = $1;
  MF_SOURCE_READERF_ENDOFSTREAM = $2;
  MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED = $20;
  COINIT_MULTITHREADED = 0;

  MF_MT_MAJOR_TYPE: TGUID = '{48eba18e-f8c9-4687-bf11-0a74c9f96a8f}';
  MF_MT_SUBTYPE: TGUID = '{f7e34c9a-42e8-4714-b74b-cb29d72c35e5}';
  MF_MT_AUDIO_NUM_CHANNELS: TGUID = '{37e48bf5-645e-4c5b-89de-ada9e29b696a}';
  MF_MT_AUDIO_SAMPLES_PER_SECOND: TGUID = '{5faeeae7-0290-4c31-9e8a-c534f68d9dba}';
  MF_MT_AUDIO_BITS_PER_SAMPLE: TGUID = '{f2deb57f-40fa-4764-aa33-ed4f2d1ff669}';
  MFMediaType_Audio: TGUID = '{73647561-0000-0010-8000-00AA00389B71}';
  MFAudioFormat_Float: TGUID = '{00000003-0000-0010-8000-00AA00389B71}';

type
  IMFAttributes = interface(IUnknown)
    ['{2cd2d921-c447-44a7-a13c-4adabfc247e3}']
    function GetItem(constref guidKey: TGUID; pValue: Pointer): HRESULT; stdcall;
    function GetItemType(constref guidKey: TGUID; out pType: DWORD): HRESULT; stdcall;
    function CompareItem(constref guidKey: TGUID; Value: Pointer; out pbResult: BOOL): HRESULT; stdcall;
    function Compare(pTheirs: IMFAttributes; MatchType: DWORD; out pbResult: BOOL): HRESULT; stdcall;
    function GetUINT32(constref guidKey: TGUID; out punValue: UINT32): HRESULT; stdcall;
    function GetUINT64(constref guidKey: TGUID; out punValue: UINT64): HRESULT; stdcall;
    function GetDouble(constref guidKey: TGUID; out pfValue: Double): HRESULT; stdcall;
    function GetGUID(constref guidKey: TGUID; out pguidValue: TGUID): HRESULT; stdcall;
    function GetStringLength(constref guidKey: TGUID; out pcchLength: UINT32): HRESULT; stdcall;
    function GetString(constref guidKey: TGUID; pwszValue: PWideChar; cchBufSize: UINT32;
      pcchLength: PDWORD): HRESULT; stdcall;
    function GetAllocatedString(constref guidKey: TGUID; out ppwszValue: PWideChar;
      out pcchLength: UINT32): HRESULT; stdcall;
    function GetBlobSize(constref guidKey: TGUID; out pcbBlobSize: UINT32): HRESULT; stdcall;
    function GetBlob(constref guidKey: TGUID; pBuf: PByte; cbBufSize: UINT32;
      pcbBlobSize: PDWORD): HRESULT; stdcall;
    function GetAllocatedBlob(constref guidKey: TGUID; out ppBuf: PByte; out pcbSize: UINT32): HRESULT; stdcall;
    function GetUnknown(constref guidKey: TGUID; constref riid: TGUID; out ppv): HRESULT; stdcall;
    function SetItem(constref guidKey: TGUID; Value: Pointer): HRESULT; stdcall;
    function DeleteItem(constref guidKey: TGUID): HRESULT; stdcall;
    function DeleteAllItems: HRESULT; stdcall;
    function SetUINT32(constref guidKey: TGUID; unValue: UINT32): HRESULT; stdcall;
    function SetUINT64(constref guidKey: TGUID; unValue: UINT64): HRESULT; stdcall;
    function SetDouble(constref guidKey: TGUID; fValue: Double): HRESULT; stdcall;
    function SetGUID(constref guidKey: TGUID; constref guidValue: TGUID): HRESULT; stdcall;
    function SetString(constref guidKey: TGUID; wszValue: PWideChar): HRESULT; stdcall;
    function SetBlob(constref guidKey: TGUID; pBuf: PByte; cbBufSize: UINT32): HRESULT; stdcall;
    function SetUnknown(constref guidKey: TGUID; pUnknown: IUnknown): HRESULT; stdcall;
    function LockStore: HRESULT; stdcall;
    function UnlockStore: HRESULT; stdcall;
    function GetCount(out pcItems: UINT32): HRESULT; stdcall;
    function GetItemByIndex(unIndex: UINT32; out pguidKey: TGUID; pValue: Pointer): HRESULT; stdcall;
    function CopyAllItems(pDest: IMFAttributes): HRESULT; stdcall;
  end;

  IMFMediaType = interface(IMFAttributes)
    ['{44ae0fa8-ea31-4109-8d2e-4cae4997c555}']
    function GetMajorType(out pguidMajorType: TGUID): HRESULT; stdcall;
    function IsCompressedFormat(out pfCompressed: BOOL): HRESULT; stdcall;
    function IsEqual(pIMediaType: IMFMediaType; out pdwFlags: DWORD): HRESULT; stdcall;
    function GetRepresentation(guidRepresentation: TGUID; out ppvRepresentation: Pointer): HRESULT; stdcall;
    function FreeRepresentation(guidRepresentation: TGUID; pvRepresentation: Pointer): HRESULT; stdcall;
  end;

  IMFMediaBuffer = interface(IUnknown)
    ['{045FA593-8799-42b8-BC8D-8968C6453507}']
    function Lock(out ppbBuffer: PByte; pcbMaxLength: PDWORD; pcbCurrentLength: PDWORD): HRESULT; stdcall;
    function Unlock: HRESULT; stdcall;
    function GetCurrentLength(out pcbCurrentLength: DWORD): HRESULT; stdcall;
    function SetCurrentLength(cbCurrentLength: DWORD): HRESULT; stdcall;
    function GetMaxLength(out pcbMaxLength: DWORD): HRESULT; stdcall;
  end;

  IMFSample = interface(IMFAttributes)
    ['{c40a00f2-b93a-4d80-ae8c-5a1c634f58e4}']
    function GetSampleFlags(out pdwSampleFlags: DWORD): HRESULT; stdcall;
    function SetSampleFlags(dwSampleFlags: DWORD): HRESULT; stdcall;
    function GetSampleTime(out phnsSampleTime: Int64): HRESULT; stdcall;
    function SetSampleTime(hnsSampleTime: Int64): HRESULT; stdcall;
    function GetSampleDuration(out phnsSampleDuration: Int64): HRESULT; stdcall;
    function SetSampleDuration(hnsSampleDuration: Int64): HRESULT; stdcall;
    function GetBufferCount(out pdwBufferCount: DWORD): HRESULT; stdcall;
    function GetBufferByIndex(dwIndex: DWORD; out ppBuffer: IMFMediaBuffer): HRESULT; stdcall;
    function ConvertToContiguousBuffer(out ppBuffer: IMFMediaBuffer): HRESULT; stdcall;
    function AddBuffer(pBuffer: IMFMediaBuffer): HRESULT; stdcall;
    function RemoveBufferByIndex(dwIndex: DWORD): HRESULT; stdcall;
    function RemoveAllBuffers: HRESULT; stdcall;
    function GetTotalLength(out pcbTotalLength: DWORD): HRESULT; stdcall;
    function CopyToBuffer(pBuffer: IMFMediaBuffer): HRESULT; stdcall;
  end;

  IMFSourceReader = interface(IUnknown)
    ['{70ae66f2-c809-4e4f-8915-bdcb406b7993}']
    function GetStreamSelection(dwStreamIndex: DWORD; out pfSelected: BOOL): HRESULT; stdcall;
    function SetStreamSelection(dwStreamIndex: DWORD; fSelected: BOOL): HRESULT; stdcall;
    function GetNativeMediaType(dwStreamIndex, dwMediaTypeIndex: DWORD; out ppMediaType: IMFMediaType): HRESULT; stdcall;
    function GetCurrentMediaType(dwStreamIndex: DWORD; out ppMediaType: IMFMediaType): HRESULT; stdcall;
    function SetCurrentMediaType(dwStreamIndex: DWORD; pdwReserved: PDWORD; pMediaType: IMFMediaType): HRESULT; stdcall;
    function SetCurrentPosition(constref guidTimeFormat: TGUID; varPosition: Pointer): HRESULT; stdcall;
    function ReadSample(dwStreamIndex, dwControlFlags: DWORD; pdwActualStreamIndex, pdwStreamFlags: PDWORD;
      pllTimestamp: PInt64; out ppSample: IMFSample): HRESULT; stdcall;
    function Flush(dwStreamIndex: DWORD): HRESULT; stdcall;
    function GetServiceForStream(dwStreamIndex: DWORD; constref guidService, riid: TGUID; out ppvObject): HRESULT; stdcall;
    function GetPresentationAttribute(dwStreamIndex: DWORD; constref guidAttribute: TGUID; pvarAttribute: Pointer): HRESULT; stdcall;
  end;

  TMFStartup = function(Version: ULONG; dwFlags: DWORD): HRESULT; stdcall;
  TMFCreateMediaType = function(out ppMFType: IMFMediaType): HRESULT; stdcall;
  TMFCreateSourceReaderFromURL = function(pwszURL: PWideChar; pAttributes: IMFAttributes;
    out ppSourceReader: IMFSourceReader): HRESULT; stdcall;

function CoInitializeEx(pvReserved: Pointer; dwCoInit: DWORD): HRESULT; stdcall; external 'ole32.dll';
procedure CoUninitialize; stdcall; external 'ole32.dll';

var
  Lock: TCriticalSection;
  Tried, Ready: Boolean;
  MFCreateMediaType: TMFCreateMediaType;
  MFCreateSourceReaderFromURL: TMFCreateSourceReaderFromURL;

function MediaFoundationAvailable: Boolean;
var
  Plat, RW: HMODULE;
  Startup: TMFStartup;
begin
  Lock.Enter;
  try
    if not Tried then
    begin
      Tried := True;
      Plat := LoadLibrary('mfplat.dll');
      RW := LoadLibrary('mfreadwrite.dll');
      if (Plat <> 0) and (RW <> 0) then
      begin
        Pointer(Startup) := GetProcAddress(Plat, 'MFStartup');
        Pointer(MFCreateMediaType) := GetProcAddress(Plat, 'MFCreateMediaType');
        Pointer(MFCreateSourceReaderFromURL) := GetProcAddress(RW, 'MFCreateSourceReaderFromURL');
        // MFStartup is process wide; it is never shut down (Windows cleans up at exit)
        Ready := Assigned(Startup) and Assigned(MFCreateMediaType) and
          Assigned(MFCreateSourceReaderFromURL) and Succeeded(Startup(MF_VERSION, MFSTARTUP_LITE));
      end;
    end;
    Result := Ready;
  finally
    Lock.Leave;
  end;
end;

function DecodeWithMediaFoundation(const FileName: string; OnFormat: TPcmFormatEvent;
  OnData: TPcmDataEvent; Cancel: PBoolean): string;
var
  Reader: IMFSourceReader;
  Wanted, Current: IMFMediaType;
  Sample: IMFSample;
  Buffer: IMFMediaBuffer;
  Channels, Rate, Bits: UINT32;
  Flags, Len: DWORD;
  Data: PByte;
  HR: HRESULT;
  ComOk: Boolean;
  W: UnicodeString;

  function ReadFormat: string;
  begin
    Result := '';
    Current := nil;
    HR := Reader.GetCurrentMediaType(MF_SOURCE_READER_FIRST_AUDIO_STREAM, Current);
    if Failed(HR) then Exit(Format(rsAfkodningsfejl, [IntToHex(HR, 8)]));
    if Failed(Current.GetUINT32(MF_MT_AUDIO_NUM_CHANNELS, Channels)) or
      Failed(Current.GetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, Rate)) then
      Exit(Format(rsAfkodningsfejl, ['format']));
    if Failed(Current.GetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, Bits)) then Bits := 32;
    if Bits <> 32 then Exit(Format(rsAfkodningsfejl, ['bits ' + IntToStr(Bits)]));
    OnFormat(Rate, Channels);
  end;

begin
  if not MediaFoundationAvailable then Exit(rsMediaFoundationMangler);
  // COM per thread; S_FALSE (already initialised) also needs the matching uninitialise
  ComOk := Succeeded(CoInitializeEx(nil, COINIT_MULTITHREADED));
  try
    W := UnicodeString(FileName);
    HR := MFCreateSourceReaderFromURL(PWideChar(W), nil, Reader);
    if Failed(HR) then Exit(Format(rsKanIkkeAabnes, [IntToHex(HR, 8)]));
    Reader.SetStreamSelection(MF_SOURCE_READER_ALL_STREAMS, False);
    HR := Reader.SetStreamSelection(MF_SOURCE_READER_FIRST_AUDIO_STREAM, True);
    if Failed(HR) then Exit(Format(rsKanIkkeAabnes, [IntToHex(HR, 8)]));
    HR := MFCreateMediaType(Wanted);
    if Failed(HR) then Exit(Format(rsAfkodningsfejl, [IntToHex(HR, 8)]));
    Wanted.SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
    Wanted.SetGUID(MF_MT_SUBTYPE, MFAudioFormat_Float);
    HR := Reader.SetCurrentMediaType(MF_SOURCE_READER_FIRST_AUDIO_STREAM, nil, Wanted);
    if Failed(HR) then Exit(Format(rsKanIkkeAabnes, [IntToHex(HR, 8)]));
    Result := ReadFormat;
    if Result <> '' then Exit;
    repeat
      if (Cancel <> nil) and Cancel^ then Exit(rsAfbrudt2);
      Flags := 0;
      Sample := nil;
      HR := Reader.ReadSample(MF_SOURCE_READER_FIRST_AUDIO_STREAM, 0, nil, @Flags, nil, Sample);
      if Failed(HR) or (Flags and MF_SOURCE_READERF_ERROR <> 0) then
        Exit(Format(rsAfkodningsfejl, [IntToHex(HR, 8)]));
      if Flags and MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED <> 0 then
      begin
        Result := ReadFormat;
        if Result <> '' then Exit;
      end;
      if Sample <> nil then
      begin
        Buffer := nil;
        if Succeeded(Sample.ConvertToContiguousBuffer(Buffer)) then
        begin
          Len := 0;
          if Succeeded(Buffer.Lock(Data, nil, @Len)) then
          try
            if Len >= 4 * Channels then OnData(PSingle(Data), Len div (4 * Channels));
          finally
            Buffer.Unlock;
          end;
        end;
      end;
    until Flags and MF_SOURCE_READERF_ENDOFSTREAM <> 0;
    Result := '';
  finally
    // release the COM objects before COM itself goes
    Sample := nil;
    Buffer := nil;
    Current := nil;
    Wanted := nil;
    Reader := nil;
    if ComOk then CoUninitialize;
  end;
end;

initialization
  Lock := TCriticalSection.Create;

finalization
  Lock.Free;

end.
