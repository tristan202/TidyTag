unit ExportImportForm;

{ "Eksportér/importér tags": export the list to CSV/TXT/HTML/XML with chosen columns,
  or import tag values from CSV/XLSX with a preview before writing. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, ComCtrls,
  CheckLst, AudioTypes, ExportImport;

type

  { TFormExportImport }

  TFormExportImport = class(TForm)
    ButtonBrowse: TButton;
    ButtonClose: TButton;
    ButtonColsAll: TButton;
    ButtonColsDefault: TButton;
    ButtonColsNone: TButton;
    ButtonExport: TButton;
    ButtonImportWrite: TButton;
    CheckEmptyClears: TCheckBox;
    CheckListColumns: TCheckListBox;
    CheckOpenAfter: TCheckBox;
    EditImportFile: TEdit;
    LabelColumns: TLabel;
    LabelImportFile: TLabel;
    LabelImportInfo: TLabel;
    LabelImportSummary: TLabel;
    ListImport: TListView;
    OpenTableDialog: TOpenDialog;
    PageMain: TPageControl;
    RadioFormat: TRadioGroup;
    RadioScope: TRadioGroup;
    SaveExportDialog: TSaveDialog;
    TabExport: TTabSheet;
    TabImport: TTabSheet;
    procedure ButtonBrowseClick(Sender: TObject);
    procedure ButtonCloseClick(Sender: TObject);
    procedure ButtonColsAllClick(Sender: TObject);
    procedure ButtonColsDefaultClick(Sender: TObject);
    procedure ButtonColsNoneClick(Sender: TObject);
    procedure ButtonExportClick(Sender: TObject);
    procedure ButtonImportWriteClick(Sender: TObject);
    procedure CheckEmptyClearsChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    FAll, FSubset: TAudioInfoArray;
    FCols: TExportColumns;
    FTable: TTable;
    FPlan: TImportRows;
    FKeepTimestamp: Boolean;
    FChanged: Boolean;
    procedure LoadOptions;
    procedure SaveOptions;
    procedure UpdateImportPreview;
    procedure ShowImportRows;
  public
    class function Execute(const All, Subset: TAudioInfoArray; const SubsetCaption: string;
      Prefer: Boolean; var KeepTimestamp: Boolean; StartWithImport: Boolean = False): Boolean;
  end;

implementation

{$R *.lfm}

uses
  IniFiles, LCLIntf, AppSettings, BatchWrite;

const
  DefaultCols: array[0..11] of string = ('filename', 'path', 'title', 'artist', 'album', 'year',
    'track', 'disc', 'genre', 'albumartist', 'comment', 'duration');

class function TFormExportImport.Execute(const All, Subset: TAudioInfoArray;
  const SubsetCaption: string; Prefer: Boolean; var KeepTimestamp: Boolean;
  StartWithImport: Boolean): Boolean;
var
  F: TFormExportImport;
begin
  F := TFormExportImport.Create(Application);
  try
    F.FAll := All;
    F.FSubset := Subset;
    F.FKeepTimestamp := KeepTimestamp;
    F.RadioScope.Items[0] := SubsetCaption;
    F.RadioScope.Items[1] := Format('Alle filer i listen (%d)', [Length(All)]);
    if Prefer and (Length(Subset) > 0) then F.RadioScope.ItemIndex := 0 else F.RadioScope.ItemIndex := 1;
    if StartWithImport then F.PageMain.ActivePage := F.TabImport else F.PageMain.ActivePage := F.TabExport;
    F.ShowModal;
    Result := F.FChanged;
  finally
    F.Free;
  end;
end;

procedure TFormExportImport.FormCreate(Sender: TObject);
var
  Fmt: TExportFormat;
  I: Integer;
begin
  for Fmt := Low(TExportFormat) to High(TExportFormat) do
    RadioFormat.Items.Add(ExportFormatNames[Fmt]);
  RadioFormat.ItemIndex := 0;
  FCols := AllExportColumns;
  for I := 0 to High(FCols) do CheckListColumns.Items.Add(FCols[I].Caption);
  LoadOptions;
end;

procedure TFormExportImport.LoadOptions;
var
  Ini: TIniFile;
  Saved: string;
  I, J: Integer;
begin
  Ini := OpenSettings;
  try
    RadioFormat.ItemIndex := Ini.ReadInteger('Export', 'Format', 0);
    CheckOpenAfter.Checked := Ini.ReadBool('Export', 'OpenAfter', True);
    Saved := Ini.ReadString('Export', 'Columns', '');
    CheckEmptyClears.Checked := Ini.ReadBool('Import', 'EmptyClears', False);
  finally
    Ini.Free;
  end;
  if Saved = '' then
    ButtonColsDefaultClick(nil)
  else
    for I := 0 to High(FCols) do
      CheckListColumns.Checked[I] := Pos(',' + FCols[I].Key + ',', ',' + Saved + ',') > 0;
  J := 0;
  for I := 0 to CheckListColumns.Count - 1 do if CheckListColumns.Checked[I] then Inc(J);
  if J = 0 then ButtonColsDefaultClick(nil);
end;

procedure TFormExportImport.SaveOptions;
var
  Ini: TIniFile;
  Saved: string;
  I: Integer;
begin
  Saved := '';
  for I := 0 to High(FCols) do
    if CheckListColumns.Checked[I] then Saved := Saved + FCols[I].Key + ',';
  Ini := OpenSettings;
  try
    Ini.WriteInteger('Export', 'Format', RadioFormat.ItemIndex);
    Ini.WriteBool('Export', 'OpenAfter', CheckOpenAfter.Checked);
    Ini.WriteString('Export', 'Columns', Saved);
    Ini.WriteBool('Import', 'EmptyClears', CheckEmptyClears.Checked);
  finally
    Ini.Free;
  end;
end;

procedure TFormExportImport.ButtonColsAllClick(Sender: TObject);
begin
  CheckListColumns.CheckAll(cbChecked);
end;

procedure TFormExportImport.ButtonColsNoneClick(Sender: TObject);
begin
  CheckListColumns.CheckAll(cbUnchecked);
end;

procedure TFormExportImport.ButtonColsDefaultClick(Sender: TObject);
var
  I: Integer;
  K: string;
begin
  for I := 0 to High(FCols) do
  begin
    CheckListColumns.Checked[I] := False;
    for K in DefaultCols do
      if FCols[I].Key = K then CheckListColumns.Checked[I] := True;
  end;
end;

procedure TFormExportImport.ButtonExportClick(Sender: TObject);
var
  Cols: TExportColumns;
  Items: TAudioInfoArray;
  I: Integer;
  Fmt: TExportFormat;
begin
  Cols := nil;
  for I := 0 to High(FCols) do
    if CheckListColumns.Checked[I] then
    begin
      SetLength(Cols, Length(Cols) + 1);
      Cols[High(Cols)] := FCols[I];
    end;
  if Length(Cols) = 0 then
  begin
    MessageDlg('Vælg mindst én kolonne.', mtInformation, [mbOK], 0);
    Exit;
  end;
  if (RadioScope.ItemIndex = 0) and (Length(FSubset) > 0) then Items := FSubset else Items := FAll;
  if Length(Items) = 0 then Exit;
  Fmt := TExportFormat(RadioFormat.ItemIndex);
  SaveExportDialog.DefaultExt := ExportFormatExt[Fmt];
  SaveExportDialog.Filter := ExportFormatNames[Fmt] + '|*.' + ExportFormatExt[Fmt];
  SaveExportDialog.InitialDir := ExtractFileDir(Items[0].FileName);
  SaveExportDialog.FileName := ExtractFileName(ExtractFileDir(Items[0].FileName)) + '.' + ExportFormatExt[Fmt];
  if not SaveExportDialog.Execute then Exit;
  SaveOptions;
  try
    ExportFiles(SaveExportDialog.FileName, Items, Cols, Fmt);
  except
    on E: Exception do
    begin
      MessageDlg('Eksporten mislykkedes:' + LineEnding + E.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;
  if CheckOpenAfter.Checked then OpenDocument(SaveExportDialog.FileName)
  else MessageDlg(Format('%d filer eksporteret til' + LineEnding + '%s',
    [Length(Items), SaveExportDialog.FileName]), mtInformation, [mbOK], 0);
end;

procedure TFormExportImport.ButtonBrowseClick(Sender: TObject);
begin
  if not OpenTableDialog.Execute then Exit;
  EditImportFile.Text := OpenTableDialog.FileName;
  try
    FTable := ReadTableFile(OpenTableDialog.FileName);
  except
    on E: Exception do
    begin
      FTable := nil;
      FPlan := nil;
      ShowImportRows;
      LabelImportInfo.Caption := 'Filen kunne ikke læses: ' + E.Message;
      Exit;
    end;
  end;
  UpdateImportPreview;
end;

procedure TFormExportImport.CheckEmptyClearsChange(Sender: TObject);
begin
  if FTable <> nil then UpdateImportPreview;
end;

procedure TFormExportImport.UpdateImportPreview;
var
  Info: string;
begin
  FPlan := PlanImport(FTable, FAll, CheckEmptyClears.Checked, Info);
  LabelImportInfo.Caption := Info;
  ShowImportRows;
end;

function ChangeText(const R: TImportRow): string;
var
  F: TTagField;
  Old, New: string;
begin
  Result := '';
  if R.Info = nil then Exit;
  for F in R.Fields do
  begin
    Old := StringReplace(R.Info.Fields[F], #13#10, ' / ', [rfReplaceAll]);
    New := StringReplace(R.Values[F], #13#10, ' / ', [rfReplaceAll]);
    if Length(Old) > 30 then Old := Copy(Old, 1, 28) + '…';
    if Length(New) > 30 then New := Copy(New, 1, 28) + '…';
    if Result <> '' then Result := Result + ';  ';
    if Old = '' then Old := '(tom)';
    if New = '' then New := '(tom)';
    Result := Result + TagFieldCaptions[F] + ': ' + Old + ' → ' + New;
  end;
end;

procedure TFormExportImport.ShowImportRows;
var
  I, Ready: Integer;
  Item: TListItem;
  S: string;
  Count: array[TImportStatus] of Integer;
  St: TImportStatus;
begin
  for St := Low(TImportStatus) to High(TImportStatus) do Count[St] := 0;
  ListImport.Items.BeginUpdate;
  try
    ListImport.Items.Clear;
    for I := 0 to High(FPlan) do
    begin
      Inc(Count[FPlan[I].Status]);
      Item := ListImport.Items.Add;
      Item.Caption := IntToStr(FPlan[I].RowNo);
      if FPlan[I].Info <> nil then Item.SubItems.Add(ExtractFileName(FPlan[I].Info.FileName))
      else Item.SubItems.Add(FPlan[I].Detail);
      Item.SubItems.Add(ChangeText(FPlan[I]));
      S := ImportStatusText[FPlan[I].Status];
      if (FPlan[I].Info <> nil) and (FPlan[I].Detail <> '') then S := S + ': ' + FPlan[I].Detail;
      Item.SubItems.Add(S);
    end;
  finally
    ListImport.Items.EndUpdate;
  end;
  Ready := Count[isChange];
  if Count[isSaved] + Count[isFailed] > 0 then
    LabelImportSummary.Caption := Format('%d filer gemt   ·   %d fejl', [Count[isSaved], Count[isFailed]])
  else
    LabelImportSummary.Caption := Format('%d ændres   ·   %d uændret   ·   %d uden fil   ·   %d tvetydige   ·   %d kan ikke gemmes',
      [Ready, Count[isUnchanged], Count[isNoMatch], Count[isAmbiguous], Count[isNotWritable]]);
  ButtonImportWrite.Enabled := Ready > 0;
end;

procedure TFormExportImport.ButtonImportWriteClick(Sender: TObject);
var
  I, Ready: Integer;
  Err: string;
  Skip: Boolean;
begin
  Ready := 0;
  for I := 0 to High(FPlan) do if FPlan[I].Status = isChange then Inc(Ready);
  if MessageDlg('Importér tags', Format('Skriv de importerede værdier i %d filer?', [Ready]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  SaveOptions;
  ButtonImportWrite.Enabled := False;
  Screen.Cursor := crHourGlass;
  try
    for I := 0 to High(FPlan) do
    begin
      if FPlan[I].Status <> isChange then Continue;
      LabelImportSummary.Caption := Format('Skriver %s...', [ExtractFileName(FPlan[I].Info.FileName)]);
      Application.ProcessMessages;
      if UpdateFileTags(FPlan[I].Info, FPlan[I].Values, FPlan[I].Fields, nil, FKeepTimestamp, Err, Skip) then
      begin
        FPlan[I].Status := isSaved;
        FChanged := True;
      end
      else
      begin
        FPlan[I].Status := isFailed;
        FPlan[I].Detail := Err;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  ShowImportRows;
end;

procedure TFormExportImport.ButtonCloseClick(Sender: TObject);
begin
  SaveOptions;
  Close;
end;

end.
