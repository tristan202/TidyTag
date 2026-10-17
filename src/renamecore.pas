unit RenameCore;

{ Renaming files from their tags with a mask such as '%1 - %2' or '%1\%3\%6 - %2'.
  No user interface here: plan (preview), execute and undo are plain functions. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, AudioTypes;

resourcestring
  rsUaendret = 'Uændret';
  rsHvertOrdMedStort = 'Hvert Ord Med Stort';
  rsFoersteBogstavStort = 'Første bogstav stort';
  rsSmaaBogstaver = 'små bogstaver';
  rsStoreBogstaver = 'STORE BOGSTAVER';
  rsOmdoebes = 'Omdøbes';
  rsManglerFelt = 'Mangler felt';
  rsFindesAllerede = 'Findes allerede';
  rsSammeNavnSomEnAnden = 'Samme navn som en anden fil';
  rsUgyldigtNavn = 'Ugyldigt navn';
  rsOmdoebt = 'Omdøbt';
  rsFejl = 'Fejl';
  FolderVariablesHelp = '%1 Kunstner   %3 Album   %4 År   %5 Genre   %# Disc   %aa Albumkunstner   %cp Komponist'#13#10'%f Nuværende mappenavn.  Kun værdier, der er ens for alle filer i mappen, kan bruges'#13#10'(er kunstnerne forskellige, bruges albumkunstneren).'#13#10'Brug \ for undermapper, fx  %1\%4 - %3';
  RenameVariablesHelp = '%1 Kunstner   %2 Titel   %3 Album   %4 År   %5 Genre   %6 Spor   %# Disc'#13#10'%7 Filnavn   %8 Filnummer   %9 Kommentar   %0 Bitrate   %b BPM   %t Spilletid'#13#10'%aa Albumkunstner   %cp Komponist   %co Dirigent   %lb Pladeselskab   %cat Katalognr.'#13#10'%grp Gruppering   %rb Remixet af   %md Stemning   %key Toneart   %ext Filtype   %khz Samplerate'#13#10'Brug \ for at lave mapper, fx  %1\%3\%6 - %2';
  rsForskellige = ' (forskellige)';
  rsIndeholderEnAndenValgtMappe = 'indeholder en anden valgt mappe';
  rsKanIkkeFlyttesIndI = 'kan ikke flyttes ind i sig selv';
  rsStienErForLang = 'stien er for lang';
  rsKunneIkkeOpretteMappen = 'kunne ikke oprette mappen ';
  rsFindesIkkeLaengere = ': findes ikke længere';
  rsDerLiggerAlleredeEnFil = ': der ligger allerede en fil med det navn';


type
  TCaseMode = (cmNone, cmTitle, cmSentence, cmLower, cmUpper);

  TRenameOptions = record
    CaseMode: TCaseMode;
    SpacesToUnderscores: Boolean;
    PadTrack: Boolean;          // '7/12' -> '07'
  end;

  TRenameStatus = (rsOk, rsUnchanged, rsMissing, rsExists, rsDuplicate, rsInvalid,
    rsDone, rsFailed);

  TRenamePlanItem = record
    Info: TAudioInfo;           // borrowed from the caller's list
    OldName: string;
    NewName: string;            // full path; '' when it could not be built
    Status: TRenameStatus;
    Detail: string;             // e.g. missing field names or OS error
  end;
  TRenamePlan = array of TRenamePlanItem;

  TRenameLogItem = record
    OldName, NewName: string;
  end;
  TRenameLog = array of TRenameLogItem;

  TFieldSet = set of TTagField;

  { Everything a mask can refer to. For folders only fields shared by all files are set. }
  TMaskValues = record
    Fields: array[TTagField] of string;
    Different: TFieldSet;       // fields whose value differs between the folder's files
    FileName, FileNumber, Bitrate, Duration, Ext, SampleRate, FolderName: string;
  end;

const
  CaseModeNames: array[TCaseMode] of string = (rsUaendret, rsHvertOrdMedStort,
    rsFoersteBogstavStort, rsSmaaBogstaver, rsStoreBogstaver);
  RenameStatusText: array[TRenameStatus] of string = (rsOmdoebes, rsUaendret,
    rsManglerFelt, rsFindesAllerede, rsSammeNavnSomEnAnden, rsUgyldigtNavn,
    rsOmdoebt, rsFejl);

function ApplyCase(const S: string; Mode: TCaseMode): string;
{ Makes text safe as one file/folder name component (no \ / : * ? " < > |). }
function SanitizeNamePart(const S: string): string;
{ Expands Mask for one file. Returns the new full path, or '' with Missing set to the
  captions of empty fields the mask needs. FileNumber is 1-based; Width pads it. }
function ExpandRenameMask(const Mask: string; Info: TAudioInfo; FileNumber, NumberWidth: Integer;
  const Opt: TRenameOptions; out Missing: string): string;
function PlanRename(const Items: array of TAudioInfo; const Mask: string;
  const Opt: TRenameOptions): TRenamePlan;
{ Values shared by all files of one folder (artist falls back to album artist). }
function CommonFolderValues(const Items: array of TAudioInfo; const Dir: string): TMaskValues;
{ Plans renaming the folders that contain Items (one entry per folder, Info = nil). }
function PlanFolderRename(const Items: array of TAudioInfo; const Mask: string;
  const Opt: TRenameOptions): TRenamePlan;
{ Applies a rename log to a path: exact matches and paths inside renamed folders.
  Reverse = True maps new names back to old ones (after undo). }
function MapRenamedPath(const Path: string; const Log: TRenameLog; Reverse: Boolean): string;
{ Renames all rsOk items; sets rsDone/rsFailed and updates Info.FileName.
  Returns what was done, for undo. }
function ExecuteRename(var Plan: TRenamePlan): TRenameLog;
{ Moves files back. Returns the number of files restored; problems go to Errors. }
function UndoRename(const Log: TRenameLog; Errors: TStrings): Integer;
function CountStatus(const Plan: TRenamePlan; S: TRenameStatus): Integer;

implementation

uses
  TagUtils;

function IsLetter(C: WideChar): Boolean;
begin
  Result := WideUpperCase(C) <> WideLowerCase(C);
end;

function ApplyCase(const S: string; Mode: TCaseMode): string;
const
  WordSeparators: UnicodeString = ' ([{-._"/&+';
var
  U: UnicodeString;
  I: Integer;
  StartOfWord: Boolean;
begin
  case Mode of
    cmNone: Exit(S);
    cmLower: Exit(UTF8Encode(WideLowerCase(UTF8Decode(S))));
    cmUpper: Exit(UTF8Encode(WideUpperCase(UTF8Decode(S))));
  end;
  U := WideLowerCase(UTF8Decode(S));
  if Mode = cmSentence then
  begin
    for I := 1 to Length(U) do
      if IsLetter(U[I]) then
      begin
        U[I] := WideUpperCase(U[I])[1];
        Break;
      end;
  end
  else // cmTitle
  begin
    StartOfWord := True;
    for I := 1 to Length(U) do
      if IsLetter(U[I]) then
      begin
        if StartOfWord then U[I] := WideUpperCase(U[I])[1];
        StartOfWord := False;
      end
      else if (U[I] >= '0') and (U[I] <= '9') then
        StartOfWord := False
      else
        StartOfWord := Pos(U[I], WordSeparators) > 0;
  end;
  Result := UTF8Encode(U);
end;

function SanitizeNamePart(const S: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    case C of
      '\', '/', '|': Result := Result + '-';
      ':': Result := Result + ' -';
      '*', '?': ;
      '"': Result := Result + '''';
      '<': Result := Result + '(';
      '>': Result := Result + ')';
      #0..#31: ;
    else
      Result := Result + C;
    end;
  end;
  Result := Trim(StringReplace(Result, '  ', ' ', [rfReplaceAll]));
end;

function LeadingNumber(const S: string): string;
var
  I: Integer;
begin
  I := 1;
  while (I <= Length(S)) and (S[I] in ['0'..'9']) do Inc(I);
  Result := Copy(S, 1, I - 1);
end;

{ Removes trailing dots/spaces, which Windows silently drops from names. }
function CleanComponent(const S: string): string;
begin
  Result := Trim(S);
  while (Result <> '') and (Result[Length(Result)] in ['.', ' ']) and (Result <> '..') do
    Delete(Result, Length(Result), 1);
end;

function PathExists(const Path: string): Boolean;
begin
  Result := FileExists(Path) or DirectoryExists(Path);
end;

function IsAbsoluteMaskPath(const S: string): Boolean;
begin
  Result := (Length(S) >= 3) and (S[2] = ':') and (S[3] = '\');
end;

{ Expands the variables and rebuilds a clean path text (relative or 'X:\...').
  Returns '' when a needed field is empty (Missing lists them) or a part is empty. }
function ExpandMaskPath(const Mask: string; const V: TMaskValues; const Opt: TRenameOptions;
  out Missing: string): string;
var
  I, J: Integer;
  Res, Value, Code, Why: string;
  NeedsField: Boolean;
  F: TTagField;
  Parts: TStringArray;
  Absolute: Boolean;

  procedure Need(Field: TTagField);
  begin
    F := Field;
    NeedsField := True;
    Value := V.Fields[Field];
  end;

begin
  Result := '';
  Missing := '';
  Res := '';
  I := 1;
  while I <= Length(Mask) do
  begin
    if (Mask[I] <> '%') or (I = Length(Mask)) then
    begin
      Res := Res + Mask[I];
      Inc(I);
      Continue;
    end;
    // Longest codes first: %aa %cp %ext %khz, then single characters.
    Code := '';
    for J := 3 downto 1 do
      if (Code = '') and (I + J <= Length(Mask)) then
        case LowerCase(Copy(Mask, I + 1, J)) of
          'aa', 'cp', 'co', 'lb', 'rb', 'md', 'ext', 'khz', 'key', 'grp', 'cat':
            Code := LowerCase(Copy(Mask, I + 1, J));
        end;
    if Code = '' then Code := Mask[I + 1];
    NeedsField := False;
    Value := '';
    case Code of
      '1': Need(tfArtist);
      '2': Need(tfTitle);
      '3': Need(tfAlbum);
      '4': Need(tfYear);
      '5': Need(tfGenre);
      '6': begin
             Need(tfTrack);
             if Opt.PadTrack and (LeadingNumber(Value) <> '') then
               Value := Format('%.2d', [StrToInt64Def(LeadingNumber(Value), 0)]);
           end;
      '#': begin
             Need(tfDisc);
             if LeadingNumber(Value) <> '' then Value := LeadingNumber(Value);
           end;
      '9': Need(tfComment);
      'b': Need(tfBpm);
      'aa': Need(tfAlbumArtist);
      'cp': Need(tfComposer);
      'co': Need(tfConductor);
      'lb': Need(tfPublisher);
      'rb': Need(tfRemixer);
      'md': Need(tfMood);
      'key': Need(tfInitialKey);
      'grp': Need(tfGrouping);
      'cat': Need(tfCatalogNo);
      '7': Value := V.FileName;
      '8': Value := V.FileNumber;
      '0': Value := V.Bitrate;
      't': Value := V.Duration;
      'ext': Value := V.Ext;
      'khz': Value := V.SampleRate;
      'f', 'F': Value := V.FolderName;
    else
      // Unknown code: keep it literally.
      Res := Res + '%' + Code;
      Inc(I, 1 + Length(Code));
      Continue;
    end;
    Value := SanitizeNamePart(Value);
    if NeedsField and (Value = '') then
    begin
      if Missing <> '' then Missing := Missing + ', ';
      Why := TagFieldCaptions[F];
      if F in V.Different then Why := Why + rsForskellige;
      Missing := Missing + Why;
    end;
    Res := Res + ApplyCase(Value, Opt.CaseMode);
    Inc(I, 1 + Length(Code));
  end;
  if Missing <> '' then Exit('');

  if Opt.SpacesToUnderscores then
    Res := StringReplace(Res, ' ', '_', [rfReplaceAll]);

  // Rebuild the path from cleaned components; '/' in the mask also separates folders.
  Res := StringReplace(Res, '/', '\', [rfReplaceAll]);
  Absolute := IsAbsoluteMaskPath(Res);
  Parts := Res.Split(['\']);
  Res := '';
  for I := 0 to High(Parts) do
  begin
    if Absolute and (I = 0) then
    begin
      Res := Parts[0];
      Continue;
    end;
    Value := CleanComponent(Parts[I]);
    if Value = '' then Exit('');
    if Res <> '' then Res := Res + '\';
    Res := Res + Value;
  end;
  Result := Res;
end;

function ExpandRenameMask(const Mask: string; Info: TAudioInfo; FileNumber, NumberWidth: Integer;
  const Opt: TRenameOptions; out Missing: string): string;
var
  V: TMaskValues;
  F: TTagField;
  Res: string;
begin
  for F := Low(TTagField) to High(TTagField) do V.Fields[F] := Info.Fields[F];
  V.Different := [];
  V.FileName := ChangeFileExt(ExtractFileName(Info.FileName), '');
  V.FileNumber := Format('%.*d', [NumberWidth, FileNumber]);
  if Info.Bitrate > 0 then V.Bitrate := IntToStr(Info.Bitrate) else V.Bitrate := '';
  V.Duration := StringReplace(FormatDuration(Info.Duration), ':', '.', [rfReplaceAll]);
  V.Ext := Copy(ExtractFileExt(Info.FileName), 2, MaxInt);
  if Info.SampleRate > 0 then V.SampleRate := IntToStr(Info.SampleRate) else V.SampleRate := '';
  V.FolderName := ExtractFileName(ExtractFileDir(Info.FileName));
  Res := ExpandMaskPath(Mask, V, Opt, Missing);
  if (Res = '') or (Res[Length(Res)] = ':') then Exit('');
  Res := Res + ExtractFileExt(Info.FileName);
  if not IsAbsoluteMaskPath(Res) then
    Res := IncludeTrailingPathDelimiter(ExtractFileDir(Info.FileName)) + Res;
  Result := ExpandFileName(Res);
end;

function CommonFolderValues(const Items: array of TAudioInfo; const Dir: string): TMaskValues;
var
  F: TTagField;
  First: Boolean;
  Info: TAudioInfo;
begin
  Result.Different := [];
  for F := Low(TTagField) to High(TTagField) do Result.Fields[F] := '';
  Result.FileName := '';
  Result.FileNumber := '';
  Result.Bitrate := '';
  Result.Duration := '';
  Result.Ext := '';
  Result.SampleRate := '';
  Result.FolderName := ExtractFileName(Dir);
  First := True;
  for Info in Items do
  begin
    if not SameFileName(ExtractFileDir(Info.FileName), Dir) then Continue;
    for F := Low(TTagField) to High(TTagField) do
      if First then
        Result.Fields[F] := Info.Fields[F]
      else if Info.Fields[F] <> Result.Fields[F] then
        Include(Result.Different, F);
    First := False;
  end;
  for F in Result.Different do Result.Fields[F] := '';
  // A compilation has different artists but one album artist.
  if (tfArtist in Result.Different) and (Result.Fields[tfAlbumArtist] <> '') then
  begin
    Result.Fields[tfArtist] := Result.Fields[tfAlbumArtist];
    Exclude(Result.Different, tfArtist);
  end;
end;

function IsInside(const Path, Dir: string): Boolean;
var
  D: string;
begin
  D := IncludeTrailingPathDelimiter(Dir);
  Result := SameFileName(Copy(Path, 1, Length(D)), D);
end;

function PlanFolderRename(const Items: array of TAudioInfo; const Mask: string;
  const Opt: TRenameOptions): TRenamePlan;
var
  Dirs, Seen: TStringList;
  I, J, Dummy: Integer;
  Dir, Rel, Missing: string;
  V: TMaskValues;
begin
  Result := nil;
  Dirs := TStringList.Create;
  Seen := TStringList.Create;
  try
    Dirs.Sorted := True;
    Dirs.Duplicates := dupIgnore;
    Dirs.CaseSensitive := False;
    for I := 0 to High(Items) do
      Dirs.Add(ExtractFileDir(Items[I].FileName));
    Seen.Sorted := True;
    Seen.CaseSensitive := False;
    SetLength(Result, Dirs.Count);
    for I := 0 to Dirs.Count - 1 do
    begin
      Dir := Dirs[I];
      Result[I].Info := nil;
      Result[I].OldName := Dir;
      Result[I].NewName := '';
      Result[I].Detail := '';
      // Renaming a folder that holds another chosen folder would move that one too.
      for J := 0 to Dirs.Count - 1 do
        if (J <> I) and IsInside(Dirs[J], Dir) then
        begin
          Result[I].Status := rsInvalid;
          Result[I].Detail := rsIndeholderEnAndenValgtMappe;
          Break;
        end;
      if Result[I].Detail <> '' then Continue;
      if (Trim(Mask) = '') or (ExtractFileDir(Dir) = Dir) then
      begin
        Result[I].Status := rsInvalid; // empty mask or a drive root
        Continue;
      end;
      V := CommonFolderValues(Items, Dir);
      Rel := ExpandMaskPath(Mask, V, Opt, Missing);
      if Missing <> '' then
      begin
        Result[I].Status := rsMissing;
        Result[I].Detail := Missing;
        Continue;
      end;
      if (Rel = '') or (Rel[Length(Rel)] = ':') then
      begin
        Result[I].Status := rsInvalid;
        Continue;
      end;
      if not IsAbsoluteMaskPath(Rel) then
        Rel := IncludeTrailingPathDelimiter(ExtractFileDir(Dir)) + Rel;
      Result[I].NewName := ExcludeTrailingPathDelimiter(ExpandFileName(Rel));
      if Result[I].NewName = Dir then
        Result[I].Status := rsUnchanged
      else if IsInside(Result[I].NewName, Dir) then
      begin
        Result[I].Status := rsInvalid;
        Result[I].Detail := rsKanIkkeFlyttesIndI;
      end
      else if Length(UTF8Decode(Result[I].NewName)) >= 248 then
      begin
        Result[I].Status := rsInvalid;
        Result[I].Detail := rsStienErForLang;
      end
      else if Seen.Find(Result[I].NewName, Dummy) then
        Result[I].Status := rsDuplicate
      else if PathExists(Result[I].NewName) and not SameFileName(Result[I].NewName, Dir) then
        Result[I].Status := rsExists
      else
        Result[I].Status := rsOk;
      if Result[I].NewName <> '' then Seen.Add(Result[I].NewName);
    end;
  finally
    Dirs.Free;
    Seen.Free;
  end;
end;

function MapRenamedPath(const Path: string; const Log: TRenameLog; Reverse: Boolean): string;
var
  I: Integer;
  FromName, ToName: string;
begin
  Result := Path;
  for I := 0 to High(Log) do
  begin
    if Reverse then
    begin
      FromName := Log[I].NewName;
      ToName := Log[I].OldName;
    end
    else
    begin
      FromName := Log[I].OldName;
      ToName := Log[I].NewName;
    end;
    if Result = FromName then
      Exit(ToName)
    else if IsInside(Result, FromName) then
      Exit(IncludeTrailingPathDelimiter(ToName) +
        Copy(Result, Length(IncludeTrailingPathDelimiter(FromName)) + 1, MaxInt));
  end;
end;

function PlanRename(const Items: array of TAudioInfo; const Mask: string;
  const Opt: TRenameOptions): TRenamePlan;
var
  I, Width, Dummy: Integer;
  Missing: string;
  Seen: TStringList;
begin
  Result := nil;
  SetLength(Result, Length(Items));
  Width := Length(IntToStr(Length(Items)));
  if Width < 2 then Width := 2;
  Seen := TStringList.Create;
  try
    Seen.Sorted := True;
    Seen.CaseSensitive := False;
    for I := 0 to High(Items) do
    begin
      Result[I].Info := Items[I];
      Result[I].OldName := Items[I].FileName;
      Result[I].NewName := '';
      Result[I].Detail := '';
      if Trim(Mask) = '' then
      begin
        Result[I].Status := rsInvalid;
        Continue;
      end;
      Result[I].NewName := ExpandRenameMask(Mask, Items[I], I + 1, Width, Opt, Missing);
      if Missing <> '' then
      begin
        Result[I].Status := rsMissing;
        Result[I].Detail := Missing;
      end
      else if Result[I].NewName = '' then
        Result[I].Status := rsInvalid
      else if Result[I].NewName = Result[I].OldName then
        Result[I].Status := rsUnchanged
      else if Length(UTF8Decode(Result[I].NewName)) >= 260 then
      begin
        Result[I].Status := rsInvalid;
        Result[I].Detail := rsStienErForLang;
      end
      else if Seen.Find(Result[I].NewName, Dummy) then
        Result[I].Status := rsDuplicate
      else if PathExists(Result[I].NewName) and not SameFileName(Result[I].NewName, Result[I].OldName) then
        Result[I].Status := rsExists
      else
        Result[I].Status := rsOk;
      if Result[I].NewName <> '' then
        Seen.Add(Result[I].NewName);
    end;
  finally
    Seen.Free;
  end;
end;

function ExecuteRename(var Plan: TRenamePlan): TRenameLog;
var
  I, N: Integer;
  Dir: string;
begin
  Result := nil;
  N := 0;
  SetLength(Result, Length(Plan));
  for I := 0 to High(Plan) do
  begin
    if Plan[I].Status <> rsOk then Continue;
    Dir := ExtractFileDir(Plan[I].NewName);
    if not DirectoryExists(Dir) and not ForceDirectories(Dir) then
    begin
      Plan[I].Status := rsFailed;
      Plan[I].Detail := rsKunneIkkeOpretteMappen + Dir;
      Continue;
    end;
    // A target that appeared after the preview must not be overwritten.
    if PathExists(Plan[I].NewName) and not SameFileName(Plan[I].NewName, Plan[I].OldName) then
    begin
      Plan[I].Status := rsExists;
      Continue;
    end;
    if RenameFile(Plan[I].OldName, Plan[I].NewName) then
    begin
      Plan[I].Status := rsDone;
      if Plan[I].Info <> nil then Plan[I].Info.FileName := Plan[I].NewName;
      Result[N].OldName := Plan[I].OldName;
      Result[N].NewName := Plan[I].NewName;
      Inc(N);
    end
    else
    begin
      Plan[I].Status := rsFailed;
      Plan[I].Detail := SysErrorMessage(GetLastOSError);
    end;
  end;
  SetLength(Result, N);
end;

{ Removes Dir and its parents while they are empty, stopping at StopAt. }
procedure RemoveEmptyDirs(Dir: string; const StopAt: string);
begin
  while (Dir <> '') and not SameFileName(Dir, StopAt) and
    (Length(Dir) > Length(ExtractFileDrive(Dir)) + 1) do
  begin
    if not RemoveDir(Dir) then Exit; // not empty (or in use): leave it
    Dir := ExtractFileDir(Dir);
  end;
end;

function UndoRename(const Log: TRenameLog; Errors: TStrings): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := High(Log) downto 0 do
  begin
    if not PathExists(Log[I].NewName) then
    begin
      Errors.Add(Log[I].NewName + rsFindesIkkeLaengere);
      Continue;
    end;
    if PathExists(Log[I].OldName) and not SameFileName(Log[I].OldName, Log[I].NewName) then
    begin
      Errors.Add(Log[I].OldName + rsDerLiggerAlleredeEnFil);
      Continue;
    end;
    ForceDirectories(ExtractFileDir(Log[I].OldName));
    if RenameFile(Log[I].NewName, Log[I].OldName) then
    begin
      Inc(Result);
      RemoveEmptyDirs(ExtractFileDir(Log[I].NewName), ExtractFileDir(Log[I].OldName));
    end
    else
      Errors.Add(Log[I].NewName + ': ' + SysErrorMessage(GetLastOSError));
  end;
end;

function CountStatus(const Plan: TRenamePlan; S: TRenameStatus): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Plan) do
    if Plan[I].Status = S then Inc(Result);
end;

end.
