unit FileToTagForm;

{ "Tags fra filnavn": reads tag values out of file (and folder) names with a mask,
  shows a preview and writes the values into the files. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, ComCtrls,
  AudioTypes, RenameCore, FileNameTags;

type
  TRowStatus = (fsReady, fsUnchanged, fsNoMatch, fsNotWritable, fsSaved, fsFailed);

  TRow = record
    Info: TAudioInfo;   // borrowed from the main list
    Match: TFileNameMatch;
    Status: TRowStatus;
    Detail: string;
  end;

  { TFormFileToTag }

  TFormFileToTag = class(TForm)
    ButtonClose: TButton;
    ButtonWrite: TButton;
    CheckKeepTimestamp: TCheckBox;
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
    procedure ButtonWriteClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure OptionChange(Sender: TObject);
    procedure TimerPreviewTimer(Sender: TObject);
  private
    FAll, FSelected: TAudioInfoArray;
    FRows: array of TRow;
    FFields: TFieldSet;
    FChanged: Boolean;
    function CaseMode: TCaseMode;
    procedure UpdatePreview;
    procedure ShowRows;
    procedure SaveOptions;
    function CountRows(S: TRowStatus): Integer;
  public
    { Returns True if any file was changed (the main list should repaint). }
    { Subset = ticked or selected files, offered first when Prefer is True. }
    class function Execute(const All, Subset: TAudioInfoArray; const SubsetCaption: string;
      Prefer: Boolean; var KeepTimestamp: Boolean): Boolean;
  end;

implementation

{$R *.lfm}

uses
  IniFiles, AppSettings, AudioTags, TagWriter;

const
  HistorySection = 'FileToTagMasks';
  DefaultMasks: array[0..6] of string = ('%1 - %2', '%6 - %2', '%6 - %1 - %2', '%6. %2',
    '%6 %1 - %2', '%1\%3\%6 - %2', '%1\%4 - %3\%6 - %2');
  RowStatusText: array[TRowStatus] of string = ('Klar', 'Uændret', 'Passer ikke til masken',
    'Filtypen kan ikke gemmes endnu', 'Gemt', 'Fejl');

class function TFormFileToTag.Execute(const All, Subset: TAudioInfoArray; const SubsetCaption: string;
  Prefer: Boolean; var KeepTimestamp: Boolean): Boolean;
var
  F: TFormFileToTag;
begin
  F := TFormFileToTag.Create(Application);
  try
    F.FAll := All;
    F.FSelected := Subset;
    F.CheckKeepTimestamp.Checked := KeepTimestamp;
    F.RadioScope.Items[0] := SubsetCaption;
    F.RadioScope.Items[1] := Format('Alle filer i listen (%d)', [Length(All)]);
    if Prefer and (Length(Subset) > 0) then F.RadioScope.ItemIndex := 0 else F.RadioScope.ItemIndex := 1;
    F.UpdatePreview;
    F.ShowModal;
    KeepTimestamp := F.CheckKeepTimestamp.Checked;
    Result := F.FChanged;
  finally
    F.Free;
  end;
end;

procedure TFormFileToTag.FormCreate(Sender: TObject);
var
  M: TCaseMode;
  Ini: TIniFile;
begin
  LabelVars.Caption := FileToTagVariablesHelp;
  for M := Low(TCaseMode) to High(TCaseMode) do
    ComboCase.Items.Add(CaseModeNames[M]);
  LoadMaskHistory(HistorySection, ComboMask.Items, DefaultMasks);
  Ini := OpenSettings;
  try
    ComboMask.Text := Ini.ReadString('FileToTag', 'Mask', ComboMask.Items[0]);
    if Trim(ComboMask.Text) = '' then ComboMask.Text := ComboMask.Items[0];
    ComboCase.ItemIndex := Ini.ReadInteger('FileToTag', 'Case', 0);
    CheckUnderscores.Checked := Ini.ReadBool('FileToTag', 'Underscores', True);
  finally
    Ini.Free;
  end;
end;

procedure TFormFileToTag.SaveOptions;
var
  Ini: TIniFile;
begin
  Ini := OpenSettings;
  try
    Ini.WriteString('FileToTag', 'Mask', ComboMask.Text);
    Ini.WriteInteger('FileToTag', 'Case', ComboCase.ItemIndex);
    Ini.WriteBool('FileToTag', 'Underscores', CheckUnderscores.Checked);
  finally
    Ini.Free;
  end;
end;

function TFormFileToTag.CaseMode: TCaseMode;
begin
  if ComboCase.ItemIndex < 0 then Result := cmNone else Result := TCaseMode(ComboCase.ItemIndex);
end;

procedure TFormFileToTag.OptionChange(Sender: TObject);
begin
  TimerPreview.Enabled := False;
  TimerPreview.Enabled := True;
end;

procedure TFormFileToTag.TimerPreviewTimer(Sender: TObject);
begin
  TimerPreview.Enabled := False;
  UpdatePreview;
end;

procedure TFormFileToTag.UpdatePreview;
var
  Items: TAudioInfoArray;
  I: Integer;
  F: TTagField;
  Same: Boolean;
begin
  if (RadioScope.ItemIndex = 0) and (Length(FSelected) > 0) then Items := FSelected else Items := FAll;
  FFields := MaskFields(ComboMask.Text);
  FRows := nil;
  SetLength(FRows, Length(Items));
  for I := 0 to High(Items) do
  begin
    FRows[I].Info := Items[I];
    FRows[I].Detail := '';
    FRows[I].Match := MatchFileName(ComboMask.Text, Items[I].FileName, CheckUnderscores.Checked, CaseMode);
    if not FRows[I].Match.Ok then
      FRows[I].Status := fsNoMatch
    else if not CanWriteTags(Items[I].FileName) then
      FRows[I].Status := fsNotWritable
    else
    begin
      Same := True;
      for F in FRows[I].Match.Used do
        if FRows[I].Match.Values[F] <> Items[I].Fields[F] then Same := False;
      if Same then FRows[I].Status := fsUnchanged else FRows[I].Status := fsReady;
    end;
  end;
  ShowRows;
end;

procedure TFormFileToTag.ShowRows;
var
  I: Integer;
  F: TTagField;
  Col: TListColumn;
  Item: TListItem;
  S: string;
begin
  ListPreview.Items.BeginUpdate;
  try
    ListPreview.Items.Clear;
    // Columns: file, one per field in the mask, status
    ListPreview.Columns.BeginUpdate;
    try
      ListPreview.Columns.Clear;
      Col := ListPreview.Columns.Add;
      Col.Caption := 'Fil';
      Col.Width := 280;
      for F := Low(TTagField) to High(TTagField) do
        if F in FFields then
        begin
          Col := ListPreview.Columns.Add;
          Col.Caption := TagFieldCaptions[F];
          if F in [tfTrack, tfDisc, tfYear, tfBpm] then Col.Width := 60 else Col.Width := 170;
        end;
      Col := ListPreview.Columns.Add;
      Col.Caption := 'Status';
      Col.Width := 200;
    finally
      ListPreview.Columns.EndUpdate;
    end;
    for I := 0 to High(FRows) do
    begin
      Item := ListPreview.Items.Add;
      Item.Caption := ExtractFileName(FRows[I].Info.FileName);
      for F := Low(TTagField) to High(TTagField) do
        if F in FFields then
          Item.SubItems.Add(FRows[I].Match.Values[F]);
      S := RowStatusText[FRows[I].Status];
      if FRows[I].Detail <> '' then S := S + ': ' + FRows[I].Detail;
      Item.SubItems.Add(S);
    end;
  finally
    ListPreview.Items.EndUpdate;
  end;
  if CountRows(fsSaved) + CountRows(fsFailed) > 0 then
    LabelSummary.Caption := Format('%d filer gemt   ·   %d fejl', [CountRows(fsSaved), CountRows(fsFailed)])
  else
    LabelSummary.Caption := Format('%d klar   ·   %d uændret   ·   %d passer ikke   ·   %d kan ikke gemmes',
      [CountRows(fsReady), CountRows(fsUnchanged), CountRows(fsNoMatch), CountRows(fsNotWritable)]);
  ButtonWrite.Enabled := CountRows(fsReady) > 0;
end;

function TFormFileToTag.CountRows(S: TRowStatus): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FRows) do
    if FRows[I].Status = S then Inc(Result);
end;

procedure TFormFileToTag.ButtonWriteClick(Sender: TObject);
var
  I: Integer;
  F: TTagField;
  Full: TAudioInfo;
begin
  if MessageDlg('Skriv tags', Format('Skriv tags i %d filer?', [CountRows(fsReady)]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  AddComboMaskToHistory(HistorySection, ComboMask);
  SaveOptions;
  ButtonWrite.Enabled := False;
  Screen.Cursor := crHourGlass;
  try
    for I := 0 to High(FRows) do
    begin
      if FRows[I].Status <> fsReady then Continue;
      LabelSummary.Caption := Format('Skriver %d af %d: %s', [I + 1, Length(FRows),
        ExtractFileName(FRows[I].Info.FileName)]);
      Application.ProcessMessages;
      // Re-read with pictures so nothing but the chosen fields changes.
      Full := ReadAudioInfo(FRows[I].Info.FileName, True);
      try
        if Full.Error <> '' then
        begin
          FRows[I].Status := fsFailed;
          FRows[I].Detail := Full.Error;
          Continue;
        end;
        for F in FRows[I].Match.Used do
          Full.Fields[F] := FRows[I].Match.Values[F];
        try
          WriteAudioTags(Full, CheckKeepTimestamp.Checked);
          for F in FRows[I].Match.Used do
            FRows[I].Info.Fields[F] := FRows[I].Match.Values[F];
          FRows[I].Status := fsSaved;
          FChanged := True;
        except
          on E: Exception do
          begin
            FRows[I].Status := fsFailed;
            FRows[I].Detail := E.Message;
          end;
        end;
      finally
        Full.Free;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  ShowRows;
end;

procedure TFormFileToTag.ButtonCloseClick(Sender: TObject);
begin
  SaveOptions;
  Close;
end;

end.
