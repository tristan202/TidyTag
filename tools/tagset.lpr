program TagSet;

{ Developer tool: sets tag fields from the command line.
    tagset <file> artist="Kim Larsen" album="Midt om natten" track=1 ...
  Field names: title artist album year track disc genre comment albumartist composer bpm }

{$mode objfpc}{$H+}

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  Classes, SysUtils, AudioTypes, AudioTags, TagWriter;

const
  Names: array[TTagField] of string = ('title', 'artist', 'album', 'year', 'track', 'disc',
    'genre', 'comment', 'albumartist', 'composer', 'bpm');

var
  Info: TAudioInfo;
  I, Eq: Integer;
  Arg, Key: string;
  F: TTagField;
  Found: Boolean;
begin
  SetMultiByteConversionCodePage(CP_UTF8);
  SetMultiByteFileSystemCodePage(CP_UTF8);
  {$IFDEF WINDOWS}SetConsoleOutputCP(CP_UTF8);{$ENDIF}
  SetTextCodePage(Output, CP_UTF8);
  if ParamCount < 2 then
  begin
    WriteLn('Brug: tagset <fil> felt=værdi ...');
    Halt(2);
  end;
  Info := ReadAudioInfo(UTF8Encode(UnicodeString(ParamStr(1))), True);
  try
    if Info.Error <> '' then
    begin
      WriteLn('FEJL: ', Info.Error);
      Halt(1);
    end;
    for I := 2 to ParamCount do
    begin
      Arg := UTF8Encode(UnicodeString(ParamStr(I)));
      Eq := Pos('=', Arg);
      Key := LowerCase(Copy(Arg, 1, Eq - 1));
      Found := False;
      for F := Low(TTagField) to High(TTagField) do
        if Names[F] = Key then
        begin
          Info.Fields[F] := Copy(Arg, Eq + 1, MaxInt);
          Found := True;
        end;
      if not Found then
      begin
        WriteLn('Ukendt felt: ', Key);
        Halt(2);
      end;
    end;
    WriteAudioTags(Info, False);
    WriteLn('ok');
  finally
    Info.Free;
  end;
end.
