unit TrackToolsForm;

{ "Spornumre": reformat existing track numbers or number the files in list order,
  with a preview, then write only the Track field. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, ComCtrls, Spin,
  AudioTypes, TrackCore;

type
  TTrackRowStatus = (trChange, trUnchanged, trNotWritable, trSaved, trFailed);

  { TFormTrackTools }

  TFormTrackTools = class(TForm)
    ButtonClose: TButton;
    ButtonWrite: TButton;
    CheckKeepTimestamp: TCheckBox;
    CheckPerFolder: TCheckBox;
    ComboFormat: TComboBox;
    LabelFormat: TLabel;
    LabelStart: TLabel;
    LabelSummary: TLabel;
    ListPreview: TListView;
    RadioMode: TRadioGroup;
    RadioScope: TRadioGroup;
    SpinStart: TSpinEdit;
    procedure ButtonCloseClick(Sender: TObject);
    procedure ButtonWriteClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure OptionChange(Sender: TObject);
  private
    FAll, FSubset, FItems: TAudioInfoArray;
    FNew: TStringArray;
    FStatus: array of TTrackRowStatus;
    FDetail: TStringArray;
    FLoading: Boolean;
    procedure UpdatePreview;
    procedure ShowRows;
    function Count(S: TTrackRowStatus): Integer;
    procedure SaveOptions;
  public
    class procedure Execute(const All, Subset: TAudioInfoArray; const SubsetCaption: string;
      Prefer: Boolean; var KeepTimestamp: Boolean);
  end;

implementation

{$R *.lfm}

uses
  IniFiles, AppSettings, AudioTags, TagWriter;

const
  StatusText: array[TTrackRowStatus] of string = ('Ændres', 'Uændret',
    'Filtypen kan ikke gemmes endnu', 'Gemt', 'Fejl');

class procedure TFormTrackTools.Execute(const All, Subset: TAudioInfoArray;
  const SubsetCaption: string; Prefer: Boolean; var KeepTimestamp: Boolean);
var
  F: TFormTrackTools;
begin
  F := TFormTrackTools.Create(Application);
  try
    F.FAll := All;
    F.FSubset := Subset;
    F.CheckKeepTimestamp.Checked := KeepTimestamp;
    F.FLoading := True;
    F.RadioScope.Items[0] := SubsetCaption;
    F.RadioScope.Items[1] := Format('Alle filer i listen (%d)', [Length(All)]);
    if Prefer and (Length(Subset) > 0) then F.RadioScope.ItemIndex := 0 else F.RadioScope.ItemIndex := 1;
    F.FLoading := False;
    F.UpdatePreview;
    F.ShowModal;
    KeepTimestamp := F.CheckKeepTimestamp.Checked;
  finally
    F.Free;
  end;
end;

procedure TFormTrackTools.FormCreate(Sender: TObject);
var
  Fmt: TTrackFormat;
  Ini: TIniFile;
begin
  FLoading := True;
  try
    for Fmt := Low(TTrackFormat) to High(TTrackFormat) do
      ComboFormat.Items.Add(TrackFormatNames[Fmt]);
    Ini := OpenSettings;
    try
      RadioMode.ItemIndex := Ini.ReadInteger('Tracks', 'Mode', 0);
      ComboFormat.ItemIndex := Ini.ReadInteger('Tracks', 'Format', Ord(nfTwoDigits));
      SpinStart.Value := Ini.ReadInteger('Tracks', 'Start', 1);
      CheckPerFolder.Checked := Ini.ReadBool('Tracks', 'PerFolder', True);
    finally
      Ini.Free;
    end;
  finally
    FLoading := False;
  end;
end;

procedure TFormTrackTools.SaveOptions;
var
  Ini: TIniFile;
begin
  Ini := OpenSettings;
  try
    Ini.WriteInteger('Tracks', 'Mode', RadioMode.ItemIndex);
    Ini.WriteInteger('Tracks', 'Format', ComboFormat.ItemIndex);
    Ini.WriteInteger('Tracks', 'Start', SpinStart.Value);
    Ini.WriteBool('Tracks', 'PerFolder', CheckPerFolder.Checked);
  finally
    Ini.Free;
  end;
end;

procedure TFormTrackTools.OptionChange(Sender: TObject);
begin
  if not FLoading then UpdatePreview;
end;

procedure TFormTrackTools.UpdatePreview;
var
  I: Integer;
  Mode: TTrackMode;
  Fmt: TTrackFormat;
begin
  if (RadioScope.ItemIndex = 0) and (Length(FSubset) > 0) then FItems := FSubset else FItems := FAll;
  if RadioMode.ItemIndex = 1 then Mode := tmNumber else Mode := tmFormat;
  if ComboFormat.ItemIndex < 0 then Fmt := nfTwoDigits else Fmt := TTrackFormat(ComboFormat.ItemIndex);
  SpinStart.Enabled := Mode = tmNumber;
  LabelStart.Enabled := Mode = tmNumber;
  CheckPerFolder.Enabled := Mode = tmNumber;
  FNew := PlanTrackNumbers(FItems, Mode, Fmt, SpinStart.Value, CheckPerFolder.Checked);
  FStatus := nil;
  SetLength(FStatus, Length(FItems));
  FDetail := nil;
  SetLength(FDetail, Length(FItems));
  for I := 0 to High(FItems) do
    if FNew[I] = FItems[I].Fields[tfTrack] then
      FStatus[I] := trUnchanged
    else if not CanWriteTags(FItems[I].FileName) then
      FStatus[I] := trNotWritable
    else
      FStatus[I] := trChange;
  ShowRows;
end;

procedure TFormTrackTools.ShowRows;
var
  I: Integer;
  Item: TListItem;
  S: string;
begin
  ListPreview.Items.BeginUpdate;
  try
    ListPreview.Items.Clear;
    for I := 0 to High(FItems) do
    begin
      Item := ListPreview.Items.Add;
      Item.Caption := ExtractFileName(FItems[I].FileName);
      Item.SubItems.Add(FItems[I].Fields[tfTrack]);
      Item.SubItems.Add(FNew[I]);
      S := StatusText[FStatus[I]];
      if FDetail[I] <> '' then S := S + ': ' + FDetail[I];
      Item.SubItems.Add(S);
      Item.SubItems.Add(ExtractFileName(ExtractFileDir(FItems[I].FileName)));
    end;
  finally
    ListPreview.Items.EndUpdate;
  end;
  if Count(trSaved) + Count(trFailed) > 0 then
    LabelSummary.Caption := Format('%d filer gemt   ·   %d fejl', [Count(trSaved), Count(trFailed)])
  else
    LabelSummary.Caption := Format('%d ændres   ·   %d uændret   ·   %d kan ikke gemmes',
      [Count(trChange), Count(trUnchanged), Count(trNotWritable)]);
  ButtonWrite.Enabled := Count(trChange) > 0;
end;

function TFormTrackTools.Count(S: TTrackRowStatus): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FStatus) do
    if FStatus[I] = S then Inc(Result);
end;

procedure TFormTrackTools.ButtonWriteClick(Sender: TObject);
var
  I: Integer;
  Full: TAudioInfo;
begin
  if MessageDlg('Gem spornumre', Format('Gem nye spornumre i %d filer?', [Count(trChange)]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  SaveOptions;
  ButtonWrite.Enabled := False;
  Screen.Cursor := crHourGlass;
  try
    for I := 0 to High(FItems) do
    begin
      if FStatus[I] <> trChange then Continue;
      LabelSummary.Caption := Format('Gemmer %d af %d: %s', [I + 1, Length(FItems),
        ExtractFileName(FItems[I].FileName)]);
      Application.ProcessMessages;
      // Re-read with pictures so only the track number changes.
      Full := ReadAudioInfo(FItems[I].FileName, True);
      try
        if Full.Error <> '' then
        begin
          FStatus[I] := trFailed;
          FDetail[I] := Full.Error;
          Continue;
        end;
        Full.Fields[tfTrack] := FNew[I];
        try
          WriteAudioTags(Full, CheckKeepTimestamp.Checked);
          FItems[I].Fields[tfTrack] := FNew[I];
          FStatus[I] := trSaved;
        except
          on E: Exception do
          begin
            FStatus[I] := trFailed;
            FDetail[I] := E.Message;
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

procedure TFormTrackTools.ButtonCloseClick(Sender: TObject);
begin
  SaveOptions;
  Close;
end;

end.
