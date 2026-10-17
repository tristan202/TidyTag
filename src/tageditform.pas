unit TagEditForm;

{ Single-file tag editor with cover art. Tabs: Generelt, Flere felter, Sortering,
  Sangtekst. Steps through the main file list with "Gem og forrige" / "Gem og næste". }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, ComCtrls,
  AudioTypes;

type
  { Called after a file was saved, with a freshly read TAudioInfo (caller takes ownership). }
  TFileSavedEvent = procedure(Index: Integer; NewInfo: TAudioInfo) of object;
  { Returns the file name at Index, '' if out of range. }
  TFileAtFunc = function(Index: Integer): string of object;

  { TFormTagEdit }

  TFormTagEdit = class(TForm)
    ButtonAddPicture: TButton;
    ButtonClose: TButton;
    ButtonLyricsClear: TButton;
    ButtonLyricsLoad: TButton;
    ButtonLyricsSave: TButton;
    ButtonNextPicture: TButton;
    ButtonPrevPicture: TButton;
    ButtonRemovePicture: TButton;
    ButtonSave: TButton;
    ButtonSaveNext: TButton;
    ButtonSavePicture: TButton;
    ButtonSavePrev: TButton;
    CheckKeepTimestamp: TCheckBox;
    ComboGenre: TComboBox;
    EditAlbum: TEdit;
    EditAlbumArtist: TEdit;
    EditArtist: TEdit;
    EditBpm: TEdit;
    EditComposer: TEdit;
    EditDisc: TEdit;
    EditTitle: TEdit;
    EditTrack: TEdit;
    EditYear: TEdit;
    ImageCover: TImage;
    LabelAlbum: TLabel;
    LabelAlbumArtist: TLabel;
    LabelArtist: TLabel;
    LabelBpm: TLabel;
    LabelComment: TLabel;
    LabelComposer: TLabel;
    LabelCoverInfo: TLabel;
    LabelDisc: TLabel;
    LabelFile: TLabel;
    LabelFileInfo: TLabel;
    LabelGenre: TLabel;
    LabelTitle: TLabel;
    LabelTrack: TLabel;
    LabelYear: TLabel;
    MemoComment: TMemo;
    MemoLyrics: TMemo;
    OpenPictureDialog: TOpenDialog;
    OpenTextDialog: TOpenDialog;
    PageFields: TPageControl;
    PanelCover: TPanel;
    SavePictureDialog: TSaveDialog;
    SaveTextDialog: TSaveDialog;
    TabGeneral: TTabSheet;
    TabLyrics: TTabSheet;
    TabMore: TTabSheet;
    TabSort: TTabSheet;
    procedure ButtonAddPictureClick(Sender: TObject);
    procedure ButtonCloseClick(Sender: TObject);
    procedure ButtonLyricsClearClick(Sender: TObject);
    procedure ButtonLyricsLoadClick(Sender: TObject);
    procedure ButtonLyricsSaveClick(Sender: TObject);
    procedure ButtonNextPictureClick(Sender: TObject);
    procedure ButtonPrevPictureClick(Sender: TObject);
    procedure ButtonRemovePictureClick(Sender: TObject);
    procedure ButtonSaveClick(Sender: TObject);
    procedure ButtonSaveNextClick(Sender: TObject);
    procedure ButtonSavePictureClick(Sender: TObject);
    procedure ButtonSavePrevClick(Sender: TObject);
    procedure FieldChange(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FInfo: TAudioInfo;     // the file being edited, read with pictures
    FIndex: Integer;
    FCount: Integer;
    FPicIndex: Integer;
    FLoading: Boolean;
    FModified: Boolean;
    FFileAt: TFileAtFunc;
    FOnSaved: TFileSavedEvent;
    FExtraEdits: array[TTagField] of TEdit; // fields on "Flere felter" and "Sortering"
    procedure BuildExtraFields;
    function FieldEdit(F: TTagField): TCustomEdit;
    procedure LoadFile(Index: Integer);
    procedure ShowPicture;
    function SaveCurrent: Boolean;
    procedure SetModified(Value: Boolean);
    procedure UpdateButtons;
  public
    { Opens the editor modally on file Index of a list with Count files. }
    class procedure Execute(Index, Count: Integer; FileAt: TFileAtFunc;
      OnSaved: TFileSavedEvent; var KeepTimestamp: Boolean);
  end;

implementation

{$R *.lfm}

uses
  StrUtils, LCLType, AudioTags, TagWriter, TagUtils;

{ TFormTagEdit }

class procedure TFormTagEdit.Execute(Index, Count: Integer; FileAt: TFileAtFunc;
  OnSaved: TFileSavedEvent; var KeepTimestamp: Boolean);
var
  F: TFormTagEdit;
begin
  F := TFormTagEdit.Create(Application);
  try
    F.FCount := Count;
    F.FFileAt := FileAt;
    F.FOnSaved := OnSaved;
    F.CheckKeepTimestamp.Checked := KeepTimestamp;
    F.LoadFile(Index);
    F.ShowModal;
    KeepTimestamp := F.CheckKeepTimestamp.Checked;
  finally
    F.Free;
  end;
end;

procedure TFormTagEdit.FormCreate(Sender: TObject);
var
  I: Integer;
begin
  ComboGenre.Items.BeginUpdate;
  try
    for I := 0 to ID3GenreCount - 1 do
      ComboGenre.Items.Add(ID3GenreName(I));
    ComboGenre.Sorted := True;
  finally
    ComboGenre.Items.EndUpdate;
  end;
  BuildExtraFields;
  PageFields.ActivePage := TabGeneral;
end;

{ Label + edit rows for the extra fields, in two columns on "Flere felter". }
procedure TFormTagEdit.BuildExtraFields;
const
  MoreLeft: array[0..6] of TTagField = (tfConductor, tfLyricist, tfOrigArtist, tfRemixer,
    tfPublisher, tfCatalogNo, tfIsrc);
  MoreRight: array[0..6] of TTagField = (tfCopyright, tfEncodedBy, tfUrl, tfGrouping,
    tfSubtitle, tfMood, tfInitialKey);
  SortFields: array[0..4] of TTagField = (tfSortTitle, tfSortArtist, tfSortAlbumArtist,
    tfSortAlbum, tfSortComposer);

  procedure Row(Page: TTabSheet; F: TTagField; Col, RowNo: Integer; LabelWidth, EditWidth: Integer);
  var
    L: TLabel;
    E: TEdit;
    X, Y: Integer;
  begin
    X := Scale96ToForm(8 + Col * 390);
    Y := Scale96ToForm(10 + RowNo * 32);
    L := TLabel.Create(Self);
    L.Parent := Page;
    L.Caption := TagFieldCaptions[F];
    L.Left := X;
    L.Top := Y + Scale96ToForm(3);
    E := TEdit.Create(Self);
    E.Parent := Page;
    E.Left := X + Scale96ToForm(LabelWidth);
    E.Top := Y;
    E.Width := Scale96ToForm(EditWidth);
    E.OnChange := @FieldChange;
    E.TabOrder := Col * 10 + RowNo;
    FExtraEdits[F] := E;
  end;

var
  I: Integer;
  SortHint: TLabel;
begin
  for I := 0 to High(MoreLeft) do Row(TabMore, MoreLeft[I], 0, I, 120, 250);
  for I := 0 to High(MoreRight) do Row(TabMore, MoreRight[I], 1, I, 90, 280);
  for I := 0 to High(SortFields) do Row(TabSort, SortFields[I], 0, I, 140, 400);
  SortHint := TLabel.Create(Self);
  SortHint.Parent := TabSort;
  SortHint.Left := Scale96ToForm(8);
  SortHint.Top := Scale96ToForm(10 + 5 * 32 + 8);
  SortHint.Font.Color := clGrayText;
  SortHint.Caption := 'Sorteringsfelter bestemmer, hvordan afspillere sorterer, fx "Beatles, The" ' +
    'eller "Nielsen, Carl", uden at ændre det viste navn.';
end;

procedure TFormTagEdit.FormDestroy(Sender: TObject);
begin
  FInfo.Free;
end;

function TFormTagEdit.FieldEdit(F: TTagField): TCustomEdit;
begin
  case F of
    tfTitle: Result := EditTitle;
    tfArtist: Result := EditArtist;
    tfAlbum: Result := EditAlbum;
    tfYear: Result := EditYear;
    tfTrack: Result := EditTrack;
    tfDisc: Result := EditDisc;
    tfComment: Result := MemoComment;
    tfAlbumArtist: Result := EditAlbumArtist;
    tfComposer: Result := EditComposer;
    tfBpm: Result := EditBpm;
    tfLyrics: Result := MemoLyrics;
    tfGenre: Result := nil; // genre uses the combo box
  else
    Result := FExtraEdits[F];
  end;
end;

procedure TFormTagEdit.ButtonLyricsLoadClick(Sender: TObject);
var
  L: TStringList;
begin
  if not OpenTextDialog.Execute then Exit;
  L := TStringList.Create;
  try
    L.LoadFromFile(OpenTextDialog.FileName); // UTF-8 with or without BOM
    MemoLyrics.Text := L.Text;
  finally
    L.Free;
  end;
end;

procedure TFormTagEdit.ButtonLyricsSaveClick(Sender: TObject);
begin
  SaveTextDialog.InitialDir := ExtractFileDir(FInfo.FileName);
  SaveTextDialog.FileName := ChangeFileExt(ExtractFileName(FInfo.FileName), '.txt');
  if SaveTextDialog.Execute then MemoLyrics.Lines.SaveToFile(SaveTextDialog.FileName);
end;

procedure TFormTagEdit.ButtonLyricsClearClick(Sender: TObject);
begin
  MemoLyrics.Clear;
end;

procedure TFormTagEdit.LoadFile(Index: Integer);
var
  F: TTagField;
  Info: TAudioInfo;
  FilePath: string;
begin
  FilePath := FFileAt(Index);
  if FilePath = '' then Exit;
  Info := ReadAudioInfo(FilePath, True);
  FreeAndNil(FInfo);
  FInfo := Info;
  FIndex := Index;
  FLoading := True;
  try
    for F := Low(TTagField) to High(TTagField) do
      if F = tfGenre then
        ComboGenre.Text := FInfo.Fields[F]
      else
        FieldEdit(F).Text := FInfo.Fields[F];
    LabelFile.Caption := ExtractFileName(FilePath);
    LabelFile.Hint := FilePath;
    Caption := Format('Rediger tag (%d af %d) - %s', [Index + 1, FCount, ExtractFileName(FilePath)]);
    if FInfo.Error <> '' then
      LabelFileInfo.Caption := 'Fejl ved læsning: ' + FInfo.Error
    else
      LabelFileInfo.Caption := Format('%s  ·  %s  ·  %d kbit/s  ·  %d Hz  ·  %d kanaler  ·  Tags: %s',
        [FInfo.Codec, FormatDuration(FInfo.Duration), FInfo.Bitrate, FInfo.SampleRate,
         FInfo.Channels, IfThen(FInfo.TagTypes = '', 'ingen', FInfo.TagTypes)]);
    if not CanWriteTags(FilePath) then
      LabelFileInfo.Caption := LabelFileInfo.Caption + '   (kan ikke gemme denne filtype endnu)';
    FPicIndex := 0;
    ShowPicture;
  finally
    FLoading := False;
  end;
  SetModified(False);
end;

procedure TFormTagEdit.ShowPicture;
var
  S: TBytesStream;
  W, H: Integer;
  Ext: string;
begin
  ImageCover.Picture.Clear;
  if Length(FInfo.Pictures) = 0 then
  begin
    LabelCoverInfo.Caption := 'Intet billede';
    UpdateButtons;
    Exit;
  end;
  if FPicIndex > High(FInfo.Pictures) then FPicIndex := High(FInfo.Pictures);
  if FPicIndex < 0 then FPicIndex := 0;
  with FInfo.Pictures[FPicIndex] do
  begin
    if MimeType = 'image/png' then Ext := 'png'
    else if MimeType = 'image/gif' then Ext := 'gif'
    else if MimeType = 'image/bmp' then Ext := 'bmp'
    else Ext := 'jpg';
    S := TBytesStream.Create(Data);
    try
      try
        ImageCover.Picture.LoadFromStreamWithFileExt(S, Ext);
      except
        ImageCover.Picture.Clear; // unreadable image: still shown as an entry
      end;
    finally
      S.Free;
    end;
    if not ImageDimensions(Data, W, H) then
    begin
      W := 0;
      H := 0;
    end;
    LabelCoverInfo.Caption := Format('Billede %d af %d  ·  %s  ·  %s',
      [FPicIndex + 1, Length(FInfo.Pictures), PictureTypeName(PicType), UpperCase(Ext)]);
    if W > 0 then
      LabelCoverInfo.Caption := LabelCoverInfo.Caption + Format('  ·  %dx%d', [W, H]);
    LabelCoverInfo.Caption := LabelCoverInfo.Caption + Format('  ·  %d KB', [(Length(Data) + 1023) div 1024]);
  end;
  UpdateButtons;
end;

procedure TFormTagEdit.UpdateButtons;
var
  Writable, HasPic: Boolean;
begin
  Writable := (FInfo <> nil) and (FInfo.Error = '') and CanWriteTags(FInfo.FileName);
  HasPic := (FInfo <> nil) and (Length(FInfo.Pictures) > 0);
  ButtonSave.Enabled := Writable;
  ButtonSavePrev.Enabled := Writable and (FIndex > 0);
  ButtonSaveNext.Enabled := Writable and (FIndex < FCount - 1);
  ButtonAddPicture.Enabled := Writable;
  ButtonRemovePicture.Enabled := Writable and HasPic;
  ButtonSavePicture.Enabled := HasPic;
  ButtonPrevPicture.Enabled := HasPic and (FPicIndex > 0);
  ButtonNextPicture.Enabled := HasPic and (FPicIndex < High(FInfo.Pictures));
end;

procedure TFormTagEdit.SetModified(Value: Boolean);
begin
  FModified := Value;
  if Value then
    ButtonSave.Caption := 'Gem *'
  else
    ButtonSave.Caption := 'Gem';
end;

procedure TFormTagEdit.FieldChange(Sender: TObject);
begin
  if not FLoading then SetModified(True);
end;

function TFormTagEdit.SaveCurrent: Boolean;
var
  F: TTagField;
  NewInfo: TAudioInfo;
begin
  Result := False;
  for F := Low(TTagField) to High(TTagField) do
    if F = tfGenre then
      FInfo.Fields[F] := Trim(ComboGenre.Text)
    else
      FInfo.Fields[F] := Trim(FieldEdit(F).Text);
  Screen.Cursor := crHourGlass;
  try
    try
      WriteAudioTags(FInfo, CheckKeepTimestamp.Checked);
    except
      on E: Exception do
      begin
        Screen.Cursor := crDefault;
        MessageDlg('Kunne ikke gemme', 'Tags blev ikke gemt i' + LineEnding + FInfo.FileName +
          LineEnding + LineEnding + E.Message, mtError, [mbOK], 0);
        Exit;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  SetModified(False);
  if Assigned(FOnSaved) then
  begin
    NewInfo := ReadAudioInfo(FInfo.FileName, False);
    FOnSaved(FIndex, NewInfo);
  end;
  Result := True;
end;

procedure TFormTagEdit.ButtonSaveClick(Sender: TObject);
begin
  if SaveCurrent then LoadFile(FIndex); // show what is now in the file
end;

procedure TFormTagEdit.ButtonSavePrevClick(Sender: TObject);
begin
  if SaveCurrent then LoadFile(FIndex - 1);
end;

procedure TFormTagEdit.ButtonSaveNextClick(Sender: TObject);
begin
  if SaveCurrent then LoadFile(FIndex + 1);
end;

procedure TFormTagEdit.ButtonCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TFormTagEdit.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if not FModified then Exit;
  case MessageDlg('Gem ændringer?', 'Der er ændringer, som ikke er gemt. Vil du gemme dem?',
    mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
    mrYes: CanClose := SaveCurrent;
    mrNo: CanClose := True;
  else
    CanClose := False;
  end;
end;

procedure TFormTagEdit.ButtonAddPictureClick(Sender: TObject);
var
  S: TFileStream;
  Data: TBytes;
  N: Integer;
begin
  if not OpenPictureDialog.Execute then Exit;
  S := TFileStream.Create(OpenPictureDialog.FileName, fmOpenRead or fmShareDenyWrite);
  try
    Data := ReadStreamBytes(S, S.Size);
  finally
    S.Free;
  end;
  if (DetectImageMime(Data, '') <> 'image/jpeg') and (DetectImageMime(Data, '') <> 'image/png') then
  begin
    MessageDlg('Kun JPEG- og PNG-billeder kan bruges som cover.', mtWarning, [mbOK], 0);
    Exit;
  end;
  N := Length(FInfo.Pictures);
  SetLength(FInfo.Pictures, N + 1);
  with FInfo.Pictures[N] do
  begin
    // The first picture becomes the front cover; further ones are "other".
    if N = 0 then PicType := PicTypeFrontCover else PicType := 0;
    MimeType := DetectImageMime(Data);
    Description := '';
  end;
  FInfo.Pictures[N].Data := Data;
  FPicIndex := N;
  ShowPicture;
  SetModified(True);
end;

procedure TFormTagEdit.ButtonRemovePictureClick(Sender: TObject);
begin
  if Length(FInfo.Pictures) = 0 then Exit;
  Delete(FInfo.Pictures, FPicIndex, 1);
  ShowPicture;
  SetModified(True);
end;

procedure TFormTagEdit.ButtonSavePictureClick(Sender: TObject);
var
  S: TFileStream;
begin
  if Length(FInfo.Pictures) = 0 then Exit;
  with FInfo.Pictures[FPicIndex] do
  begin
    if MimeType = 'image/png' then
    begin
      SavePictureDialog.DefaultExt := 'png';
      SavePictureDialog.Filter := 'PNG-billede|*.png';
    end
    else
    begin
      SavePictureDialog.DefaultExt := 'jpg';
      SavePictureDialog.Filter := 'JPEG-billede|*.jpg';
    end;
    SavePictureDialog.InitialDir := ExtractFileDir(FInfo.FileName);
    SavePictureDialog.FileName := 'folder.' + SavePictureDialog.DefaultExt;
    if not SavePictureDialog.Execute then Exit;
    S := TFileStream.Create(SavePictureDialog.FileName, fmCreate);
    try
      WriteBytes(S, Data);
    finally
      S.Free;
    end;
  end;
end;

procedure TFormTagEdit.ButtonPrevPictureClick(Sender: TObject);
begin
  Dec(FPicIndex);
  ShowPicture;
end;

procedure TFormTagEdit.ButtonNextPictureClick(Sender: TObject);
begin
  Inc(FPicIndex);
  ShowPicture;
end;

end.
