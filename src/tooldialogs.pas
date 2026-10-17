unit ToolDialogs;

{ Small dialogs built in code: choose two tag fields (swap / copy), the rename word
  lists (replacements and words that keep their spelling) and the rename actions. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, AudioTypes, AppSettings, BatchWrite, ID3Sync;

{ Returns False when cancelled. ShowCheck adds a check box (Check = its state). }
function AskFieldPair(const Title, FromCaption, ToCaption, CheckCaption: string;
  var A, B: TTagField; var Check: Boolean): Boolean;
function EditRenameWords(var Words: TRenameWords): Boolean;
function EditRenameActions(var Actions: TRenameActions; const CurrentFileMask: string): Boolean;
function AskID3Sync(var Direction: TSyncDirection; var Existing: TSyncExisting): Boolean;
{ Ticks the fields to paste; only fields with a value in Values are listed. }
function AskFieldSet(const Title, Prompt: string; const Values: TFieldValues;
  var Fields: TTagFieldSet): Boolean;

implementation

uses
  Forms, Controls, Graphics, StdCtrls, ExtCtrls, Grids, Dialogs, ButtonPanel, CheckLst;

resourcestring
  rsFra = 'Fra:';
  rsTil = 'Til:';
  rsOrdudskiftninger = 'Ordudskiftninger ved omdøbning';
  rsErstatTekst = 'Erstat tekst (skelner mellem store og små bogstaver; mellemrum tæller med):';
  rsErstat = 'Erstat';
  rsMed = 'Med';
  rsFasteOrd = 'Ord der altid skrives sådan (hele ord, et pr. linje, fx AC/DC eller ABBA):';
  rsOrdHjaelp = 'Bruges af alle omdøbninger efter versalskift. Faste ord først, så udskiftninger.';
  rsOmdoebningshandlinger = 'Omdøbningshandlinger';
  rsHandlinger = 'Handlinger:';
  rsNavn = 'Navn:';
  rsFilnavnsmaske = 'Filnavnsmaske:';
  rsMappemaske = 'Mappemaske (omdøber mapperne bagefter):';
  rsTilfoej = 'Tilføj';
  rsFjern = 'Fjern';
  rsNyHandling = 'Ny handling';
  rsHandlingHjaelp = 'En handling omdøber de afkrydsede (eller markerede) filer med filnavnsmasken og ' +
    'derefter deres mapper med mappemasken. Versaler og ordudskiftninger følger indstillingerne ' +
    'i fanebladet Omdøb filer. Handlingerne findes i menuen Værktøjer.';
  rsGivHandlingenEtNavn = 'Giv handlingen et navn og mindst én maske.';
  rsMpTagSynkronisering = 'Mp3-tag-synkronisering';
  rsRetning = 'Retning';
  rsIdV1TilIdV2 = 'Kopiér fra ID3v1 til ID3v2';
  rsIdV2TilIdV1 = 'Kopiér fra ID3v2 til ID3v1 (opretter ID3v1 om nødvendigt)';
  rsHvisTagFindes = 'Hvis måltagget allerede findes';
  rsSkrivIkke = 'Skriv ikke tagget';
  rsKunTommeFelter = 'Udfyld kun tomme felter';
  rsOverskrivFelter = 'Overskriv felterne';
  rsSyncHjaelp = 'Felter: titel, kunstner, album, år, kommentar, spor og genre. ID3v1 kan kun rumme ' +
    '30 tegn pr. felt og kun vesteuropæiske bogstaver.';
  rsAlle = 'Alle';
  rsIngen = 'Ingen';

function NewDialog(const Title: string; W, H: Integer): TForm;
begin
  Result := TForm.CreateNew(Application);
  Result.Caption := Title;
  Result.BorderStyle := bsDialog;
  Result.Position := poMainFormCenter;
  Result.ClientWidth := Result.Scale96ToForm(W);
  Result.ClientHeight := Result.Scale96ToForm(H);
end;

function AddButtons(F: TForm): TButtonPanel;
begin
  Result := TButtonPanel.Create(F);
  Result.Parent := F;
  Result.ShowButtons := [pbOK, pbCancel];
end;

function AddLabel(F: TWinControl; const Caption: string; X, Y: Integer): TLabel;
begin
  Result := TLabel.Create(F);
  Result.Parent := F;
  Result.Caption := Caption;
  Result.Left := F.Scale96ToForm(X);
  Result.Top := F.Scale96ToForm(Y);
end;

function FieldCombo(F: TForm; X, Y: Integer; Sel: TTagField): TComboBox;
var
  T: TTagField;
begin
  Result := TComboBox.Create(F);
  Result.Parent := F;
  Result.Style := csDropDownList;
  Result.Left := F.Scale96ToForm(X);
  Result.Top := F.Scale96ToForm(Y);
  Result.Width := F.Scale96ToForm(220);
  Result.DropDownCount := 20;
  for T := Low(TTagField) to High(TTagField) do Result.Items.Add(TagFieldCaptions[T]);
  Result.ItemIndex := Ord(Sel);
end;

function AskFieldPair(const Title, FromCaption, ToCaption, CheckCaption: string;
  var A, B: TTagField; var Check: Boolean): Boolean;
var
  F: TForm;
  CA, CB: TComboBox;
  CK: TCheckBox;
begin
  F := NewDialog(Title, 340, 150);
  try
    AddLabel(F, FromCaption, 12, 18);
    CA := FieldCombo(F, 100, 14, A);
    AddLabel(F, ToCaption, 12, 52);
    CB := FieldCombo(F, 100, 48, B);
    CK := nil;
    if CheckCaption <> '' then
    begin
      CK := TCheckBox.Create(F);
      CK.Parent := F;
      CK.Caption := CheckCaption;
      CK.Checked := Check;
      CK.Left := F.Scale96ToForm(100);
      CK.Top := F.Scale96ToForm(80);
    end;
    AddButtons(F);
    Result := (F.ShowModal = mrOK) and (CA.ItemIndex <> CB.ItemIndex);
    if Result then
    begin
      A := TTagField(CA.ItemIndex);
      B := TTagField(CB.ItemIndex);
      if CK <> nil then Check := CK.Checked;
    end;
  finally
    F.Free;
  end;
end;

function EditRenameWords(var Words: TRenameWords): Boolean;
var
  F: TForm;
  Grid: TStringGrid;
  Memo: TMemo;
  I, N: Integer;
begin
  F := NewDialog(rsOrdudskiftninger, 520, 470);
  try
    AddLabel(F, rsErstatTekst, 12, 10);
    Grid := TStringGrid.Create(F);
    Grid.Parent := F;
    Grid.SetBounds(F.Scale96ToForm(12), F.Scale96ToForm(30), F.Scale96ToForm(496), F.Scale96ToForm(180));
    Grid.ColCount := 2;
    Grid.FixedCols := 0;
    Grid.FixedRows := 1;
    Grid.Options := Grid.Options + [goEditing, goTabs, goAlwaysShowEditor] - [goRangeSelect];
    Grid.Cells[0, 0] := rsErstat;
    Grid.Cells[1, 0] := rsMed;
    Grid.ColWidths[0] := F.Scale96ToForm(235);
    Grid.ColWidths[1] := F.Scale96ToForm(235);
    Grid.RowCount := Length(Words.ReplaceFrom) + 11; // room for new rows
    for I := 0 to High(Words.ReplaceFrom) do
    begin
      Grid.Cells[0, I + 1] := Words.ReplaceFrom[I];
      Grid.Cells[1, I + 1] := Words.ReplaceTo[I];
    end;
    AddLabel(F, rsFasteOrd, 12, 222);
    Memo := TMemo.Create(F);
    Memo.Parent := F;
    Memo.SetBounds(F.Scale96ToForm(12), F.Scale96ToForm(242), F.Scale96ToForm(496), F.Scale96ToForm(130));
    Memo.ScrollBars := ssAutoVertical;
    Memo.Lines.AddStrings(Words.KeepCase);
    with AddLabel(F, rsOrdHjaelp, 12, 380) do
    begin
      WordWrap := True;
      AutoSize := False;
      Width := F.Scale96ToForm(496);
      Height := F.Scale96ToForm(36);
    end;
    AddButtons(F);
    Result := F.ShowModal = mrOK;
    if not Result then Exit;
    Words.ReplaceFrom := nil;
    Words.ReplaceTo := nil;
    for I := 1 to Grid.RowCount - 1 do
      if Grid.Cells[0, I] <> '' then
      begin
        N := Length(Words.ReplaceFrom);
        SetLength(Words.ReplaceFrom, N + 1);
        SetLength(Words.ReplaceTo, N + 1);
        Words.ReplaceFrom[N] := Grid.Cells[0, I];
        Words.ReplaceTo[N] := Grid.Cells[1, I];
      end;
    Words.KeepCase := nil;
    for I := 0 to Memo.Lines.Count - 1 do
      if Trim(Memo.Lines[I]) <> '' then
      begin
        N := Length(Words.KeepCase);
        SetLength(Words.KeepCase, N + 1);
        Words.KeepCase[N] := Trim(Memo.Lines[I]);
      end;
  finally
    F.Free;
  end;
end;

type
  { Keeps the edit fields and the list of the actions dialog in step. }
  TActionsEditor = class
    List: TListBox;
    EditName: TEdit;
    CheckFile, CheckFolder: TCheckBox;
    EditFile, EditFolder: TEdit;
    Items: TRenameActions;
    Current: Integer;
    Loading: Boolean;
    procedure Store;
    procedure Load;
    procedure ListClick(Sender: TObject);
    procedure FieldChange(Sender: TObject);
    procedure AddClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
  end;

procedure TActionsEditor.Store;
begin
  if (Current < 0) or (Current > High(Items)) then Exit;
  Items[Current].Name := Trim(EditName.Text);
  if CheckFile.Checked then Items[Current].FileMask := Trim(EditFile.Text) else Items[Current].FileMask := '';
  if CheckFolder.Checked then Items[Current].FolderMask := Trim(EditFolder.Text) else Items[Current].FolderMask := '';
  if Items[Current].Name <> '' then List.Items[Current] := Items[Current].Name;
end;

procedure TActionsEditor.Load;
var
  On: Boolean;
begin
  Loading := True;
  try
    On := (Current >= 0) and (Current <= High(Items));
    EditName.Enabled := On;
    CheckFile.Enabled := On;
    CheckFolder.Enabled := On;
    if On then
    begin
      EditName.Text := Items[Current].Name;
      CheckFile.Checked := Items[Current].FileMask <> '';
      EditFile.Text := Items[Current].FileMask;
      CheckFolder.Checked := Items[Current].FolderMask <> '';
      EditFolder.Text := Items[Current].FolderMask;
    end
    else
    begin
      EditName.Text := '';
      EditFile.Text := '';
      EditFolder.Text := '';
    end;
    EditFile.Enabled := On and CheckFile.Checked;
    EditFolder.Enabled := On and CheckFolder.Checked;
  finally
    Loading := False;
  end;
end;

procedure TActionsEditor.ListClick(Sender: TObject);
begin
  Store;
  Current := List.ItemIndex;
  Load;
end;

procedure TActionsEditor.FieldChange(Sender: TObject);
begin
  if Loading then Exit;
  EditFile.Enabled := CheckFile.Checked;
  EditFolder.Enabled := CheckFolder.Checked;
  Store;
end;

procedure TActionsEditor.AddClick(Sender: TObject);
var
  N: Integer;
begin
  Store;
  N := Length(Items);
  SetLength(Items, N + 1);
  Items[N].Name := rsNyHandling;
  Items[N].FileMask := EditFile.Hint; // the current mask of the main window
  Items[N].FolderMask := '';
  List.Items.Add(Items[N].Name);
  List.ItemIndex := N;
  Current := N;
  Load;
  EditName.SetFocus;
  EditName.SelectAll;
end;

procedure TActionsEditor.RemoveClick(Sender: TObject);
var
  I: Integer;
begin
  if (Current < 0) or (Current > High(Items)) then Exit;
  for I := Current to High(Items) - 1 do Items[I] := Items[I + 1];
  SetLength(Items, Length(Items) - 1);
  List.Items.Delete(Current);
  if Current > High(Items) then Current := High(Items);
  List.ItemIndex := Current;
  Load;
end;

function EditRenameActions(var Actions: TRenameActions; const CurrentFileMask: string): Boolean;
var
  F: TForm;
  E: TActionsEditor;
  B: TButton;
  I: Integer;
  Ok: Boolean;
begin
  F := NewDialog(rsOmdoebningshandlinger, 600, 370);
  E := TActionsEditor.Create;
  try
    E.Items := Copy(Actions);
    AddLabel(F, rsHandlinger, 12, 10);
    E.List := TListBox.Create(F);
    E.List.Parent := F;
    E.List.SetBounds(F.Scale96ToForm(12), F.Scale96ToForm(30), F.Scale96ToForm(190), F.Scale96ToForm(190));
    for I := 0 to High(E.Items) do E.List.Items.Add(E.Items[I].Name);
    E.List.OnClick := @E.ListClick;
    B := TButton.Create(F);
    B.Parent := F;
    B.Caption := rsTilfoej;
    B.SetBounds(F.Scale96ToForm(12), F.Scale96ToForm(226), F.Scale96ToForm(92), F.Scale96ToForm(26));
    B.OnClick := @E.AddClick;
    B := TButton.Create(F);
    B.Parent := F;
    B.Caption := rsFjern;
    B.SetBounds(F.Scale96ToForm(110), F.Scale96ToForm(226), F.Scale96ToForm(92), F.Scale96ToForm(26));
    B.OnClick := @E.RemoveClick;

    AddLabel(F, rsNavn, 216, 34);
    E.EditName := TEdit.Create(F);
    E.EditName.Parent := F;
    E.EditName.SetBounds(F.Scale96ToForm(216), F.Scale96ToForm(52), F.Scale96ToForm(372), F.Scale96ToForm(23));
    E.EditName.OnChange := @E.FieldChange;
    E.CheckFile := TCheckBox.Create(F);
    E.CheckFile.Parent := F;
    E.CheckFile.Caption := rsFilnavnsmaske;
    E.CheckFile.SetBounds(F.Scale96ToForm(216), F.Scale96ToForm(86), F.Scale96ToForm(372), F.Scale96ToForm(19));
    E.CheckFile.OnClick := @E.FieldChange;
    E.EditFile := TEdit.Create(F);
    E.EditFile.Parent := F;
    E.EditFile.SetBounds(F.Scale96ToForm(216), F.Scale96ToForm(108), F.Scale96ToForm(372), F.Scale96ToForm(23));
    E.EditFile.OnChange := @E.FieldChange;
    E.EditFile.Hint := CurrentFileMask;
    E.CheckFolder := TCheckBox.Create(F);
    E.CheckFolder.Parent := F;
    E.CheckFolder.Caption := rsMappemaske;
    E.CheckFolder.SetBounds(F.Scale96ToForm(216), F.Scale96ToForm(142), F.Scale96ToForm(372), F.Scale96ToForm(19));
    E.CheckFolder.OnClick := @E.FieldChange;
    E.EditFolder := TEdit.Create(F);
    E.EditFolder.Parent := F;
    E.EditFolder.SetBounds(F.Scale96ToForm(216), F.Scale96ToForm(164), F.Scale96ToForm(372), F.Scale96ToForm(23));
    E.EditFolder.OnChange := @E.FieldChange;
    with AddLabel(F, rsHandlingHjaelp, 216, 196) do
    begin
      WordWrap := True;
      AutoSize := False;
      Width := F.Scale96ToForm(372);
      Height := F.Scale96ToForm(124);
      Font.Color := clGrayText;
    end;
    AddButtons(F);
    E.Current := -1;
    if Length(E.Items) > 0 then
    begin
      E.List.ItemIndex := 0;
      E.Current := 0;
    end;
    E.Load;
    repeat
      Result := F.ShowModal = mrOK;
      if not Result then Exit;
      E.Store;
      Ok := True;
      for I := 0 to High(E.Items) do
        if (E.Items[I].Name = '') or ((E.Items[I].FileMask = '') and (E.Items[I].FolderMask = '')) then
        begin
          Ok := False;
          E.List.ItemIndex := I;
          E.Current := I;
          E.Load;
          MessageDlg(rsGivHandlingenEtNavn, mtInformation, [mbOK], 0);
          Break;
        end;
    until Ok;
    Actions := E.Items;
  finally
    E.Free;
    F.Free;
  end;
end;

function AskID3Sync(var Direction: TSyncDirection; var Existing: TSyncExisting): Boolean;
var
  F: TForm;
  RD, RE: TRadioGroup;
begin
  F := NewDialog(rsMpTagSynkronisering, 440, 300);
  try
    RD := TRadioGroup.Create(F);
    RD.Parent := F;
    RD.Caption := rsRetning;
    RD.SetBounds(F.Scale96ToForm(12), F.Scale96ToForm(10), F.Scale96ToForm(416), F.Scale96ToForm(70));
    RD.Items.Add(rsIdV1TilIdV2);
    RD.Items.Add(rsIdV2TilIdV1);
    RD.ItemIndex := Ord(Direction);
    RE := TRadioGroup.Create(F);
    RE.Parent := F;
    RE.Caption := rsHvisTagFindes;
    RE.SetBounds(F.Scale96ToForm(12), F.Scale96ToForm(88), F.Scale96ToForm(416), F.Scale96ToForm(90));
    RE.Items.Add(rsSkrivIkke);
    RE.Items.Add(rsKunTommeFelter);
    RE.Items.Add(rsOverskrivFelter);
    RE.ItemIndex := Ord(Existing);
    with AddLabel(F, rsSyncHjaelp, 12, 186) do
    begin
      WordWrap := True;
      AutoSize := False;
      Width := F.Scale96ToForm(416);
      Height := F.Scale96ToForm(56);
      Font.Color := clGrayText;
    end;
    AddButtons(F);
    Result := F.ShowModal = mrOK;
    if Result then
    begin
      Direction := TSyncDirection(RD.ItemIndex);
      Existing := TSyncExisting(RE.ItemIndex);
    end;
  finally
    F.Free;
  end;
end;

type
  TCheckAll = class
    List: TCheckListBox;
    procedure AllClick(Sender: TObject);
    procedure NoneClick(Sender: TObject);
  end;

procedure TCheckAll.AllClick(Sender: TObject);
begin
  List.CheckAll(cbChecked);
end;

procedure TCheckAll.NoneClick(Sender: TObject);
begin
  List.CheckAll(cbUnchecked);
end;

function AskFieldSet(const Title, Prompt: string; const Values: TFieldValues;
  var Fields: TTagFieldSet): Boolean;
var
  F: TForm;
  H: TCheckAll;
  B: TButton;
  T: TTagField;
  Map: array of TTagField;
  I: Integer;
  V: string;
begin
  F := NewDialog(Title, 460, 420);
  H := TCheckAll.Create;
  try
    AddLabel(F, Prompt, 12, 10);
    H.List := TCheckListBox.Create(F);
    H.List.Parent := F;
    H.List.SetBounds(F.Scale96ToForm(12), F.Scale96ToForm(30), F.Scale96ToForm(436), F.Scale96ToForm(300));
    Map := nil;
    for T := Low(TTagField) to High(TTagField) do
      if Values[T] <> '' then
      begin
        V := StringReplace(Values[T], LineEnding, ' / ', [rfReplaceAll]);
        if Length(V) > 60 then V := Copy(V, 1, 57) + '...';
        H.List.Items.Add(TagFieldCaptions[T] + ':  ' + V);
        H.List.Checked[H.List.Count - 1] := T in Fields;
        SetLength(Map, Length(Map) + 1);
        Map[High(Map)] := T;
      end;
    B := TButton.Create(F);
    B.Parent := F;
    B.Caption := rsAlle;
    B.SetBounds(F.Scale96ToForm(12), F.Scale96ToForm(336), F.Scale96ToForm(90), F.Scale96ToForm(26));
    B.OnClick := @H.AllClick;
    B := TButton.Create(F);
    B.Parent := F;
    B.Caption := rsIngen;
    B.SetBounds(F.Scale96ToForm(108), F.Scale96ToForm(336), F.Scale96ToForm(90), F.Scale96ToForm(26));
    B.OnClick := @H.NoneClick;
    AddButtons(F);
    Result := F.ShowModal = mrOK;
    if Result then
    begin
      // fields without a value keep their previous choice
      for I := 0 to High(Map) do
        if H.List.Checked[I] then Include(Fields, Map[I]) else Exclude(Fields, Map[I]);
    end;
  finally
    H.Free;
    F.Free;
  end;
end;

end.
