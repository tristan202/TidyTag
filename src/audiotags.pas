unit AudioTags;

{ Entry point: picks the right reader from the file extension. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, AudioTypes;

{ Extensions whose tags we can read. }
function IsReadableAudioFile(const FileName: string): Boolean;
{ Readable plus formats that are listed but not read yet. }
function IsAudioFile(const FileName: string): Boolean;
{ Never raises: read problems end up in Result.Error.
  WantPictures keeps cover image data (needed before saving). }
function ReadAudioInfo(const FileName: string; WantPictures: Boolean = False): TAudioInfo;

implementation

uses
  Mp3Reader, VorbisReader, Mp4Reader;

const
  ReadableExts: array[0..7] of string = ('.mp3', '.flac', '.ogg', '.oga', '.opus', '.m4a', '.m4b', '.mp4');
  OtherExts: array[0..9] of string = ('.wma', '.asf', '.ape', '.wv', '.mpc', '.ofr', '.wav', '.aif', '.aiff', '.dsf');

function ExtIn(const FileName: string; const Exts: array of string): Boolean;
var
  Ext, E: string;
begin
  Ext := LowerCase(ExtractFileExt(FileName));
  for E in Exts do
    if E = Ext then Exit(True);
  Result := False;
end;

function IsReadableAudioFile(const FileName: string): Boolean;
begin
  Result := ExtIn(FileName, ReadableExts);
end;

function IsAudioFile(const FileName: string): Boolean;
begin
  Result := ExtIn(FileName, ReadableExts) or ExtIn(FileName, OtherExts);
end;

function ReadAudioInfo(const FileName: string; WantPictures: Boolean): TAudioInfo;
var
  S: TFileStream;
begin
  Result := TAudioInfo.Create;
  Result.FileName := FileName;
  Result.WantPictures := WantPictures;
  try
    S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    try
      Result.FileSize := S.Size;
      case LowerCase(ExtractFileExt(FileName)) of
        '.mp3': ReadMp3(S, Result);
        '.flac': ReadFlac(S, Result);
        '.ogg', '.oga', '.opus': ReadOgg(S, Result);
        '.m4a', '.m4b', '.mp4': ReadMp4(S, Result);
      else
        Result.Supported := False;
      end;
    finally
      S.Free;
    end;
  except
    on E: Exception do
      Result.Error := E.Message;
  end;
end;

end.
