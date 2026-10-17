unit TagWriter;

{ Entry point for saving tags: picks the writer from the file extension. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, AudioTypes;

function CanWriteTags(const FileName: string): Boolean;
{ Writes Info.Fields and Info.Pictures to Info.FileName. Info must have been read with
  WantPictures = True, otherwise existing pictures would be lost. Raises on failure;
  the original file is never left half-written. }
procedure WriteAudioTags(Info: TAudioInfo; KeepTimestamp: Boolean);

type
  { Settings > Album artist: copy Artist into Album artist when saving. }
  TAlbumArtistRule = (aaNone, aaIfEmpty, aaAlways);

var
  AlbumArtistRule: TAlbumArtistRule = aaNone;

{ Info's album artist as the rule wants it (unchanged for aaNone). }
procedure ApplyAlbumArtistRule(Info: TAudioInfo);

type
  { Called with every Info before it is written, e.g. to shrink big cover pictures
    (set by the program; graphics code does not belong in this unit). }
  TPictureFilter = procedure(Info: TAudioInfo);

var
  PictureFilter: TPictureFilter = nil;

implementation

uses
  TagUtils, ID3Writer, FlacWriter, Mp4Writer, OggWriter, WavWriter, ApeTag, AsfWriter;

resourcestring
  rsInternFejlFilenErLaest = 'Intern fejl: filen er læst uden billeder';
  rsSkrivningAfDenneFiltypeUnderstoettes = 'Skrivning af denne filtype understøttes ikke endnu';


function CanWriteTags(const FileName: string): Boolean;
begin
  case LowerCase(ExtractFileExt(FileName)) of
    '.mp3', '.flac', '.m4a', '.m4b', '.mp4', '.ogg', '.oga', '.opus',
    '.wav', '.aif', '.aiff', '.aifc', '.ape', '.wv', '.mpc', '.ofr',
    '.wma', '.asf': Result := True;
  else
    Result := False;
  end;
end;

procedure ApplyAlbumArtistRule(Info: TAudioInfo);
begin
  if Info.Fields[tfArtist] = '' then Exit;
  case AlbumArtistRule of
    aaIfEmpty: if Info.Fields[tfAlbumArtist] = '' then Info.Fields[tfAlbumArtist] := Info.Fields[tfArtist];
    aaAlways: Info.Fields[tfAlbumArtist] := Info.Fields[tfArtist];
  end;
end;

procedure WriteAudioTags(Info: TAudioInfo; KeepTimestamp: Boolean);
var
  Stamp: TFileStamp;
begin
  if not Info.WantPictures then
    raise Exception.Create(rsInternFejlFilenErLaest);
  if not CanWriteTags(Info.FileName) then
    raise Exception.Create(rsSkrivningAfDenneFiltypeUnderstoettes);
  ApplyAlbumArtistRule(Info);
  if Assigned(PictureFilter) then PictureFilter(Info);
  if KeepTimestamp then
    Stamp := GetFileStamp(Info.FileName);
  case LowerCase(ExtractFileExt(Info.FileName)) of
    '.mp3': WriteMp3Tags(Info.FileName, Info);
    '.flac': WriteFlacTags(Info.FileName, Info);
    '.m4a', '.m4b', '.mp4': WriteMp4Tags(Info.FileName, Info);
    '.ogg', '.oga', '.opus': WriteOggTags(Info.FileName, Info);
    '.wav', '.aif', '.aiff', '.aifc': WriteWavAiffTags(Info.FileName, Info);
    '.ape', '.wv', '.mpc', '.ofr': WriteApeTags(Info.FileName, Info);
    '.wma', '.asf': WriteAsfTags(Info.FileName, Info);
  end;
  if KeepTimestamp then
    SetFileStamp(Info.FileName, Stamp);
end;

end.
