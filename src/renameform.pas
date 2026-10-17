unit RenameForm;

{ "Omdøb filer" / "Omdøb mapper": mask with live preview. Renames can be undone from
  the main window, which receives the log. In folder mode the folders that contain the
  files are renamed, using the tag values shared by all files in each folder. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, ComCtrls,
  AudioTypes, RenameCore;

type
  { TFormRename }

  TFormRename = class(TForm)
    ButtonClose: TButton;
    ButtonRename: TButton;
    CheckPadTrack: TCheckBox;
    CheckUnderscores: TCheckBox;
    ComboCase: TComboBox;
    ComboMask: TComboBox;
    LabelCase: TLabel;
    LabelMask: TLabel;
    LabelSummary: TLabel;
    LabelVars: TLabel;
    ListPreview: TListView;
    RadioScope: TRadioGroup;
    TimerPreview: TTimer;
    procedure ButtonCloseClick(Sender: TObject);
    procedure ButtonRenameClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure OptionChange(Sender: TObject);
    procedure TimerPreviewTimer(Sender: TObject);
  private
    FAll, FSelected: TAudioInfoArray;
    FPlan: TRenamePlan;
    FLog: TRenameLog;
    FFolderMode: Boolean;
    function Section: string;
    procedure LoadOptions;
    function Options: TRenameOptions;
    function ScopeItems: TAudioInfoArray;
    procedure UpdatePreview;
    procedure ShowPlan;
    procedure SaveOptions;
  public
    { Shows the dialog. Returns the renames that were done (empty if none). }
    { Subset = ticked or selected files, offered first when Prefer is True. }
    class function Execute(const All, Subset: TAudioInfoArray; const SubsetCaption: string;
      Prefer: Boolean; FolderMode: Boolean = False): TRenameLog;
  end;

implementation

{$R *.lfm}

uses
  IniFiles, AppSettings;

resourcestring
  rsOmdoebMapperUdFraTags = 'Omdøb mapper ud fra tags';
  rsNuvaerendeMappe = 'Nuværende mappe';
  rsNyMappe = 'Ny mappe';
  rsOmdoebMapper = 'Omdøb mapper';
  rsSDMapper = '%s - %d mapper';
  rsAlleFilerIListenD = 'Alle filer i listen - %d mapper';
  rsAlleFilerIListenD2 = 'Alle filer i listen (%d)';
  rsDOmdoebesDUaendretD = '%d omdøbes   ·   %d uændret   ·   %d springes over';
  rsDOmdoebtDFejlKan = '%d omdøbt   ·   %d fejl   ·   kan fortrydes fra hovedvinduet';
  rsOmdoebDMapper = 'Omdøb %d mapper?';
  rsOmdoebFiler = 'Omdøb filer';
  rsOmdoebDFiler = 'Omdøb %d filer?';


const
  DefaultMasks: array[0..5] of string = ('%1 - %2', '%6 - %2', '%6 - %1 - %2',
    '%1 - %3 - %6 - %2', '%1\%3\%6 - %2', '%aa\%4 - %3\%6 - %2');
  DefaultFolderMasks: array[0..4] of string = ('%1 - %3', '%1 - %4 - %3', '%4 - %3',
    '%1\%4 - %3', '%aa\%3');

function FolderCount(const Items: TAudioInfoArray): Integer;
var
  L: TStringList;
  Info: TAudioInfo;
begin
  L := TStringList.Create;
  try
    L.Sorted := True;
    L.Duplicates := dupIgnore;
    L.CaseSensitive := False;
    for Info in Items do L.Add(ExtractFileDir(Info.FileName));
    Result := L.Count;
  finally
    L.Free;
  end;
end;

class function TFormRename.Execute(const All, Subset: TAudioInfoArray; const SubsetCaption: string;
  Prefer: Boolean; FolderMode: Boolean): TRenameLog;
var
  F: TFormRename;
begin
  F := TFormRename.Create(Application);
  try
    F.FAll := All;
    F.FSelected := Subset;
    F.FFolderMode := FolderMode;
    if FolderMode then
    begin
      F.Caption := rsOmdoebMapperUdFraTags;
      F.LabelMask.Caption := 'Mappemaske:';
      F.LabelVars.Caption := FolderVariablesHelp;
      F.CheckPadTrack.Visible := False;
      F.ListPreview.Column[0].Caption := rsNuvaerendeMappe;
      F.ListPreview.Column[1].Caption := rsNyMappe;
      F.ButtonRename.Caption := rsOmdoebMapper;
      F.RadioScope.Items[0] := Format(rsSDMapper, [SubsetCaption, FolderCount(Subset)]);
      F.RadioScope.Items[1] := Format(rsAlleFilerIListenD, [FolderCount(All)]);
    end
    else
    begin
      F.RadioScope.Items[0] := SubsetCaption;
      F.RadioScope.Items[1] := Format(rsAlleFilerIListenD2, [Length(All)]);
    end;
    F.LoadOptions;
    if Prefer and (Length(Subset) > 0) then F.RadioScope.ItemIndex := 0 else F.RadioScope.ItemIndex := 1;
    F.UpdatePreview;
    F.ShowModal;
    Result := F.FLog;
  finally
    F.Free;
  end;
end;

procedure TFormRename.FormCreate(Sender: TObject);
var
  M: TCaseMode;
begin
  LabelVars.Caption := RenameVariablesHelp;
  for M := Low(TCaseMode) to High(TCaseMode) do
    ComboCase.Items.Add(CaseModeNames[M]);
end;

function TFormRename.Section: string;
begin
  if FFolderMode then Result := 'RenameFolder' else Result := 'Rename';
end;

procedure TFormRename.LoadOptions;
var
  Ini: TIniFile;
begin
  if FFolderMode then
    LoadMaskHistory('FolderMasks', ComboMask.Items, DefaultFolderMasks)
  else
    LoadMaskHistory('RenameMasks', ComboMask.Items, DefaultMasks);
  Ini := OpenSettings;
  try
    ComboMask.Text := Ini.ReadString(Section, 'Mask', ComboMask.Items[0]);
    if Trim(ComboMask.Text) = '' then ComboMask.Text := ComboMask.Items[0];
    ComboCase.ItemIndex := Ini.ReadInteger(Section, 'Case', 0);
    CheckUnderscores.Checked := Ini.ReadBool(Section, 'Underscores', False);
    CheckPadTrack.Checked := Ini.ReadBool(Section, 'PadTrack', True);
  finally
    Ini.Free;
  end;
end;

procedure TFormRename.SaveOptions;
var
  Ini: TIniFile;
begin
  Ini := OpenSettings;
  try
    Ini.WriteString(Section, 'Mask', ComboMask.Text);
    Ini.WriteInteger(Section, 'Case', ComboCase.ItemIndex);
    Ini.WriteBool(Section, 'Underscores', CheckUnderscores.Checked);
    Ini.WriteBool(Section, 'PadTrack', CheckPadTrack.Checked);
  finally
    Ini.Free;
  end;
end;

function TFormRename.Options: TRenameOptions;
begin
  if ComboCase.ItemIndex < 0 then
    Result.CaseMode := cmNone
  else
    Result.CaseMode := TCaseMode(ComboCase.ItemIndex);
  Result.SpacesToUnderscores := CheckUnderscores.Checked;
  Result.PadTrack := CheckPadTrack.Checked;
  ApplyRenameWords(Result);
end;

function TFormRename.ScopeItems: TAudioInfoArray;
begin
  if (RadioScope.ItemIndex = 0) and (Length(FSelected) > 0) then
    Result := FSelected
  else
    Result := FAll;
end;

procedure TFormRename.OptionChange(Sender: TObject);
begin
  TimerPreview.Enabled := False;
  TimerPreview.Enabled := True;
end;

procedure TFormRename.TimerPreviewTimer(Sender: TObject);
begin
  TimerPreview.Enabled := False;
  UpdatePreview;
end;

procedure TFormRename.UpdatePreview;
begin
  if FFolderMode then
    FPlan := PlanFolderRename(ScopeItems, ComboMask.Text, Options)
  else
    FPlan := PlanRename(ScopeItems, ComboMask.Text, Options);
  ShowPlan;
end;

{ New name relative to the file's current folder when it stays below it. }
function DisplayName(const OldName, NewName: string): string;
var
  Dir: string;
begin
  Dir := IncludeTrailingPathDelimiter(ExtractFileDir(OldName));
  if SameFileName(Copy(NewName, 1, Length(Dir)), Dir) then
    Result := Copy(NewName, Length(Dir) + 1, MaxInt)
  else
    Result := NewName;
end;

procedure TFormRename.ShowPlan;
var
  I: Integer;
  Item: TListItem;
  StatusText: string;
begin
  ListPreview.Items.BeginUpdate;
  try
    ListPreview.Items.Clear;
    for I := 0 to High(FPlan) do
    begin
      Item := ListPreview.Items.Add;
      Item.Caption := ExtractFileName(FPlan[I].OldName);
      if FPlan[I].NewName <> '' then
        Item.SubItems.Add(DisplayName(FPlan[I].OldName, FPlan[I].NewName))
      else
        Item.SubItems.Add('');
      StatusText := RenameStatusText[FPlan[I].Status];
      if FPlan[I].Detail <> '' then StatusText := StatusText + ': ' + FPlan[I].Detail;
      Item.SubItems.Add(StatusText);
    end;
  finally
    ListPreview.Items.EndUpdate;
  end;
  LabelSummary.Caption := Format(rsDOmdoebesDUaendretD,
    [CountStatus(FPlan, rsOk), CountStatus(FPlan, rsUnchanged),
     Length(FPlan) - CountStatus(FPlan, rsOk) - CountStatus(FPlan, rsUnchanged) -
     CountStatus(FPlan, rsDone)]);
  if CountStatus(FPlan, rsDone) > 0 then
    LabelSummary.Caption := Format(rsDOmdoebtDFejlKan,
      [CountStatus(FPlan, rsDone), CountStatus(FPlan, rsFailed)]);
  ButtonRename.Enabled := CountStatus(FPlan, rsOk) > 0;
end;

procedure TFormRename.ButtonRenameClick(Sender: TObject);
var
  Log: TRenameLog;
  I, N: Integer;
begin
  UpdatePreview; // the files on disk may have changed since the last preview
  if CountStatus(FPlan, rsOk) = 0 then Exit;
  if FFolderMode then
  begin
    if MessageDlg(rsOmdoebMapper, Format(rsOmdoebDMapper, [CountStatus(FPlan, rsOk)]),
      mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
    AddComboMaskToHistory('FolderMasks', ComboMask);
  end
  else
  begin
    if MessageDlg(rsOmdoebFiler, Format(rsOmdoebDFiler, [CountStatus(FPlan, rsOk)]),
      mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
    AddComboMaskToHistory('RenameMasks', ComboMask);
  end;
  SaveOptions;
  Screen.Cursor := crHourGlass;
  try
    Log := ExecuteRename(FPlan);
  finally
    Screen.Cursor := crDefault;
  end;
  N := Length(FLog);
  SetLength(FLog, N + Length(Log));
  for I := 0 to High(Log) do FLog[N + I] := Log[I];
  ShowPlan;
end;

procedure TFormRename.ButtonCloseClick(Sender: TObject);
begin
  SaveOptions;
  Close;
end;

end.
