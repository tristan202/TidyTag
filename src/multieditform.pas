unit MultiEditForm;

{ Edits the same fields in many files at once. Each field has an "apply" box; only
  ticked fields are written. Values shared by all files are shown, differing ones are
  left empty with a hint. Cover art can be replaced or removed in all files. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, ComCtrls,
  AudioTypes;

type
  TFieldRow = record
    Field: TTagField;
    Check: TCheckBox;
    Edit: TCustomComboBox; // nil for plain edits
    TextEdit: TEdit;       // nil for the genre combo
  end;

  { TFormMultiEdit }

  TFormMultiEdit = class(TForm)
    ButtonApply: TButton;
    ButtonChooseCover: TButton;
    ButtonClose: TButton;
    CheckKeepTimestamp: TCheckBox;
    CheckRemoveCovers: TCheckBox;
    CheckReplaceCover: TCheckBox;
    GroupCover: TGroupBox;
    ImageCover: TImage;
    LabelCoverFile: TLabel;
    LabelInfo: TLabel;
    LabelStatus: TLabel;
    OpenPictureDialog: TOpenDialog;
    PanelFields: TScrollBox;
    ProgressBar: TProgressBar;
    procedure ButtonApplyClick(Sender: TObject);
    procedure ButtonChooseCoverClick(Sender: TObject);
    procedure ButtonCloseClick(Sender: TObject);
    procedure CheckRemoveCoversChange(Sender: TObject);
    procedure CheckReplaceCoverChange(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  private
    FItems: TAudioInfoArray;
    FRows: array of TFieldRow;
    FLoading: Boolean;
    FRunning: Boolean;
    FCancel: Boolean;
    FChanged: Boolean;
    FCoverData: TBytes;
    procedure BuildRows;
    procedure FillCommonValues;
    procedure ValueChange(Sender: TObject);
    function RowText(const R: TFieldRow): string;
  public
    class function Execute(const Items: TAudioInfoArray; const ScopeCaption: string;
      var KeepTimestamp: Boolean): Boolean;
  end;

implementation

{$R *.lfm}

uses
  AudioTags, TagWriter, TagUtils, ProgOptions;

resourcestring
  rsForskelligeVaerdier = '(forskellige værdier)';
  rsRedigerFlereFiler = 'Rediger flere filer - ';
  rsAendringerneGemmesIDFiler = 'Ændringerne gemmes i %d filer. Kun felter med flueben ændres; et tomt felt med flueben bliver ryddet.';
  rsGemIDFiler = 'Gem i %d filer';
  rsSaetFluebenForAtGemme = 'Sæt flueben for at gemme dette felt';
  rsKunJpegOgPngBilleder = 'Kun JPEG- og PNG-billeder kan bruges som cover.';
  rsDKb = '  (%d KB)';
  rsSaetFluebenVedDeFelter = 'Sæt flueben ved de felter, der skal gemmes.';
  rsRydFelter = 'Ryd felter';
  rsFelterneSErTommeOg = 'Felterne %s er tomme og bliver ryddet i %d filer. Fortsæt?';
  rsGem = 'Gem';
  rsGemAendringerneIDFiler = 'Gem ændringerne i %d filer?';
  rsAnnuller = 'Annuller';
  rsGemmerDAfDS = 'Gemmer %d af %d: %s';
  rsGemtIDFilerD = 'Gemt i %d filer   ·   %d sprunget over (filtypen kan ikke gemmes endnu)   ·   %d fejl';
  rsAfbrudt = 'Afbrudt.  ';
  rsNogleFilerBlevIkkeGemt = 'Nogle filer blev ikke gemt';
  rsLuk = 'Luk';


const
  EditFields: array[0..14] of TTagField = (tfArtist, tfAlbum, tfAlbumArtist, tfComposer,
    tfYear, tfDisc, tfGenre, tfBpm, tfComment, tfPublisher, tfCatalogNo, tfGrouping,
    tfConductor, tfCopyright, tfMood);


class function TFormMultiEdit.Execute(const Items: TAudioInfoArray; const ScopeCaption: string;
  var KeepTimestamp: Boolean): Boolean;
var
  F: TFormMultiEdit;
begin
  F := TFormMultiEdit.Create(Application);
  try
    F.FItems := Items;
    F.Caption := rsRedigerFlereFiler + ScopeCaption;
    F.LabelInfo.Caption := Format(rsAendringerneGemmesIDFiler, [Length(Items)]);
    F.ButtonApply.Caption := Format(rsGemIDFiler, [Length(Items)]);
    F.CheckKeepTimestamp.Checked := KeepTimestamp;
    F.BuildRows;
    F.FillCommonValues;
    F.ShowModal;
    KeepTimestamp := F.CheckKeepTimestamp.Checked;
    Result := F.FChanged;
  finally
    F.Free;
  end;
end;

procedure TFormMultiEdit.BuildRows;
var
  I: Integer;
  GName: string;
  Combo: TComboBox;
  RowTop: Integer;
begin
  SetLength(FRows, Length(EditFields));
  for I := 0 to High(EditFields) do
  begin
    RowTop := Scale96ToForm(8 + I * 31);
    FRows[I].Field := EditFields[I];
    FRows[I].Check := TCheckBox.Create(Self);
    with FRows[I].Check do
    begin
      Parent := PanelFields;
      Left := Scale96ToForm(8);
      Top := RowTop + Scale96ToForm(2);
      Caption := TagFieldCaptions[EditFields[I]];
      Hint := rsSaetFluebenForAtGemme;
      ShowHint := True;
      TabOrder := I * 2;
    end;
    if EditFields[I] = tfGenre then
    begin
      Combo := TComboBox.Create(Self);
      Combo.Parent := PanelFields;
      Combo.Left := Scale96ToForm(160);
      Combo.Top := RowTop;
      Combo.Width := Scale96ToForm(300);
      Combo.Sorted := True;
      for GName in GenreList do Combo.Items.Add(GName);
      Combo.OnChange := @ValueChange;
      Combo.TabOrder := I * 2 + 1;
      FRows[I].Edit := Combo;
      FRows[I].TextEdit := nil;
    end
    else
    begin
      FRows[I].Edit := nil;
      FRows[I].TextEdit := TEdit.Create(Self);
      with FRows[I].TextEdit do
      begin
        Parent := PanelFields;
        Left := Scale96ToForm(160);
        Top := RowTop;
        if EditFields[I] in [tfYear, tfDisc, tfBpm] then
          Width := Scale96ToForm(170)
        else
        begin
          Width := PanelFields.ClientWidth - Scale96ToForm(190); // room for the scroll bar
          Anchors := [akTop, akLeft, akRight];
        end;
        OnChange := @ValueChange;
        TabOrder := I * 2 + 1;
      end;
    end;
  end;
end;

procedure TFormMultiEdit.FillCommonValues;
var
  I, J: Integer;
  Common: string;
  Same: Boolean;
begin
  FLoading := True;
  try
    for I := 0 to High(FRows) do
    begin
      Common := FItems[0].Fields[FRows[I].Field];
      Same := True;
      for J := 1 to High(FItems) do
        if FItems[J].Fields[FRows[I].Field] <> Common then
        begin
          Same := False;
          Break;
        end;
      if not Same then Common := '';
      if FRows[I].TextEdit <> nil then
      begin
        FRows[I].TextEdit.Text := Common;
        if not Same then FRows[I].TextEdit.TextHint := rsForskelligeVaerdier;
      end
      else
      begin
        FRows[I].Edit.Text := Common;
        if not Same then FRows[I].Edit.TextHint := rsForskelligeVaerdier;
      end;
    end;
  finally
    FLoading := False;
  end;
end;

procedure TFormMultiEdit.ValueChange(Sender: TObject);
var
  I: Integer;
begin
  if FLoading then Exit;
  for I := 0 to High(FRows) do
    if (Sender = FRows[I].TextEdit) or (Sender = FRows[I].Edit) then
      FRows[I].Check.Checked := True;
end;

function TFormMultiEdit.RowText(const R: TFieldRow): string;
begin
  if R.TextEdit <> nil then Result := Trim(R.TextEdit.Text) else Result := Trim(R.Edit.Text);
end;

procedure TFormMultiEdit.ButtonChooseCoverClick(Sender: TObject);
var
  S: TFileStream;
  Data: TBytes;
  Mime: string;
  B: TBytesStream;
begin
  if not OpenPictureDialog.Execute then Exit;
  S := TFileStream.Create(OpenPictureDialog.FileName, fmOpenRead or fmShareDenyWrite);
  try
    Data := ReadStreamBytes(S, S.Size);
  finally
    S.Free;
  end;
  Mime := DetectImageMime(Data, '');
  if (Mime <> 'image/jpeg') and (Mime <> 'image/png') then
  begin
    MessageDlg(rsKunJpegOgPngBilleder, mtWarning, [mbOK], 0);
    Exit;
  end;
  FCoverData := Data;
  LabelCoverFile.Caption := ExtractFileName(OpenPictureDialog.FileName) +
    Format(rsDKb, [(Length(Data) + 1023) div 1024]);
  B := TBytesStream.Create(Data);
  try
    try
      if Mime = 'image/png' then
        ImageCover.Picture.LoadFromStreamWithFileExt(B, 'png')
      else
        ImageCover.Picture.LoadFromStreamWithFileExt(B, 'jpg');
    except
      ImageCover.Picture.Clear;
    end;
  finally
    B.Free;
  end;
  CheckReplaceCover.Checked := True;
end;

procedure TFormMultiEdit.CheckReplaceCoverChange(Sender: TObject);
begin
  if CheckReplaceCover.Checked then
  begin
    CheckRemoveCovers.Checked := False;
    if FCoverData = nil then ButtonChooseCoverClick(nil);
    if FCoverData = nil then CheckReplaceCover.Checked := False;
  end;
end;

procedure TFormMultiEdit.CheckRemoveCoversChange(Sender: TObject);
begin
  if CheckRemoveCovers.Checked then CheckReplaceCover.Checked := False;
end;

procedure TFormMultiEdit.ButtonApplyClick(Sender: TObject);
var
  I, J, Saved, Skipped, Failed: Integer;
  Cleared: string;
  Any: Boolean;
  Full: TAudioInfo;
  Errors: TStringList;
begin
  Any := CheckReplaceCover.Checked or CheckRemoveCovers.Checked;
  Cleared := '';
  for I := 0 to High(FRows) do
    if FRows[I].Check.Checked then
    begin
      Any := True;
      if RowText(FRows[I]) = '' then
      begin
        if Cleared <> '' then Cleared := Cleared + ', ';
        Cleared := Cleared + TagFieldCaptions[FRows[I].Field];
      end;
    end;
  if not Any then
  begin
    MessageDlg(rsSaetFluebenVedDeFelter, mtInformation, [mbOK], 0);
    Exit;
  end;
  if Cleared <> '' then
  begin
    if MessageDlg(rsRydFelter, Format(rsFelterneSErTommeOg,
      [Cleared, Length(FItems)]), mtWarning, [mbYes, mbNo], 0) <> mrYes then Exit;
  end
  else if MessageDlg(rsGem, Format(rsGemAendringerneIDFiler, [Length(FItems)]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;

  Saved := 0;
  Skipped := 0;
  Failed := 0;
  FCancel := False;
  FRunning := True;
  ButtonApply.Enabled := False;
  PanelFields.Enabled := False;
  GroupCover.Enabled := False;
  ButtonClose.Caption := rsAnnuller;
  ProgressBar.Max := Length(FItems);
  ProgressBar.Position := 0;
  Errors := TStringList.Create;
  try
    for I := 0 to High(FItems) do
    begin
      if FCancel then Break;
      LabelStatus.Caption := Format(rsGemmerDAfDS, [I + 1, Length(FItems),
        ExtractFileName(FItems[I].FileName)]);
      ProgressBar.Position := I;
      Application.ProcessMessages;
      if not CanWriteTags(FItems[I].FileName) then
      begin
        Inc(Skipped);
        Continue;
      end;
      // Re-read with pictures so only the ticked fields change.
      Full := ReadAudioInfo(FItems[I].FileName, True);
      try
        if Full.Error <> '' then
        begin
          Inc(Failed);
          Errors.Add(ExtractFileName(FItems[I].FileName) + ': ' + Full.Error);
          Continue;
        end;
        for J := 0 to High(FRows) do
          if FRows[J].Check.Checked then
            Full.Fields[FRows[J].Field] := RowText(FRows[J]);
        if CheckRemoveCovers.Checked then
          Full.Pictures := nil
        else if CheckReplaceCover.Checked and (FCoverData <> nil) then
        begin
          SetLength(Full.Pictures, 1);
          Full.Pictures[0].PicType := PicTypeFrontCover;
          Full.Pictures[0].MimeType := DetectImageMime(FCoverData);
          Full.Pictures[0].Description := '';
          Full.Pictures[0].Data := FCoverData;
        end;
        try
          WriteAudioTags(Full, CheckKeepTimestamp.Checked);
          for J := 0 to High(FRows) do
            if FRows[J].Check.Checked then
              FItems[I].Fields[FRows[J].Field] := RowText(FRows[J]);
          FItems[I].HasCover := Length(Full.Pictures) > 0;
          Inc(Saved);
          FChanged := True;
        except
          on E: Exception do
          begin
            Inc(Failed);
            Errors.Add(ExtractFileName(FItems[I].FileName) + ': ' + E.Message);
          end;
        end;
      finally
        Full.Free;
      end;
    end;
    ProgressBar.Position := ProgressBar.Max;
    LabelStatus.Caption := Format(rsGemtIDFilerD,
      [Saved, Skipped, Failed]);
    if FCancel then LabelStatus.Caption := rsAfbrudt + LabelStatus.Caption;
    if Errors.Count > 0 then
    begin
      while Errors.Count > 20 do Errors.Delete(Errors.Count - 1);
      MessageDlg(rsNogleFilerBlevIkkeGemt, Errors.Text, mtWarning, [mbOK], 0);
    end;
  finally
    Errors.Free;
    FRunning := False;
    ButtonClose.Caption := rsLuk;
    PanelFields.Enabled := True;
    GroupCover.Enabled := True;
    ButtonApply.Enabled := True;
  end;
end;

procedure TFormMultiEdit.ButtonCloseClick(Sender: TObject);
begin
  if FRunning then
    FCancel := True
  else
    Close;
end;

procedure TFormMultiEdit.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  // Never close in the middle of a file; stop after the current one instead.
  if FRunning then
  begin
    FCancel := True;
    CanClose := False;
  end;
end;

end.
