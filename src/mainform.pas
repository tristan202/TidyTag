unit MainForm;

{ Main window: menu and toolbar (built from one action table), a tools panel with the
  three everyday functions (rename, multi-file tag editor, tags from file name) plus
  folder/file cover panels, address and filter bars, folder tree and the file list. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ComCtrls, ExtCtrls,
  StdCtrls, ShellCtrls, Menus, ActnList, IniFiles, AudioTypes, ScanThread, RenameCore,
  BatchWrite;

type
  TColumnKind = (ckCheck, ckFileName, ckField, ckDuration, ckBitrate, ckSampleRate,
    ckCodec, ckTagTypes, ckCover, ckSize, ckFolder);

  TColumnDef = record
    Caption: string;
    Width: Integer;
    Kind: TColumnKind;
    Field: TTagField;
    Numeric: Boolean;
  end;

  { TFormMain }

  TFormMain = class(TForm)
    ButtonF2TPreview: TButton;
    ButtonF2TVars: TButton;
    ButtonF2TWrite: TButton;
    ButtonFilterApply: TButton;
    ButtonHideSelected: TButton;
    ButtonMultiAll: TButton;
    ButtonMultiCopy: TButton;
    ButtonMultiSave: TButton;
    ButtonRenameDo: TButton;
    ButtonRenamePreview: TButton;
    ButtonRenameUndo: TButton;
    ButtonRenameVars: TButton;
    ButtonShowAll: TButton;
    CheckF2TCase: TCheckBox;
    CheckF2TUnderscores: TCheckBox;
    CheckMultiAlbum: TCheckBox;
    CheckMultiAlbumArtist: TCheckBox;
    CheckMultiArtist: TCheckBox;
    CheckMultiComment: TCheckBox;
    CheckMultiGenre: TCheckBox;
    CheckMultiYear: TCheckBox;
    CheckRenameCase: TCheckBox;
    CheckRenamePadTrack: TCheckBox;
    CheckRenameUnderscores: TCheckBox;
    ComboAddress: TComboBox;
    ComboF2TMask: TComboBox;
    ComboFilterField: TComboBox;
    ComboMultiGenre: TComboBox;
    ComboRenameMask: TComboBox;
    EditFilter: TEdit;
    EditMultiAlbum: TEdit;
    EditMultiAlbumArtist: TEdit;
    EditMultiArtist: TEdit;
    EditMultiComment: TEdit;
    EditMultiYear: TEdit;
    FileList: TListView;
    ImageFileCover: TImage;
    ImageFolderCover: TImage;
    ImagesMain: TImageList;
    LabelAddress: TLabel;
    LabelF2THelp: TLabel;
    LabelF2TMask: TLabel;
    LabelF2TPreview: TLabel;
    LabelF2TResult: TLabel;
    LabelFileCover: TLabel;
    LabelFileCoverInfo: TLabel;
    LabelFilter: TLabel;
    LabelFolderCover: TLabel;
    LabelFolderCoverInfo: TLabel;
    LabelFolders: TLabel;
    LabelMultiHelp: TLabel;
    LabelRenameHelp: TLabel;
    LabelRenameMask: TLabel;
    LabelRenamePreview: TLabel;
    LabelRenameResult: TLabel;
    MainMenu: TMainMenu;
    PageTools: TPageControl;
    PanelAddress: TPanel;
    PanelF2TCase: TPanel;
    PanelF2TPreview: TPanel;
    PanelFileCover: TPanel;
    PanelFilter: TPanel;
    PanelFolderCover: TPanel;
    PanelFolders: TPanel;
    PanelFoldersHeader: TPanel;
    PanelRenameCase: TPanel;
    PanelRenamePreview: TPanel;
    PanelTools: TPanel;
    PopupFavorites: TPopupMenu;
    PopupFileList: TPopupMenu;
    PopupVars: TPopupMenu;
    RadioF2TLower: TRadioButton;
    RadioF2TSentence: TRadioButton;
    RadioF2TTitle: TRadioButton;
    RadioF2TUpper: TRadioButton;
    RadioRenameLower: TRadioButton;
    RadioRenameSentence: TRadioButton;
    RadioRenameTitle: TRadioButton;
    RadioRenameUpper: TRadioButton;
    ShellTree: TShellTreeView;
    Splitter1: TSplitter;
    StatusBar: TStatusBar;
    TabFileToTag: TTabSheet;
    TabMulti: TTabSheet;
    TabRename: TTabSheet;
    TimerDebounce: TTimer;
    TimerPoll: TTimer;
    TimerSelection: TTimer;
    ToolBarFolders: TToolBar;
    ToolBarMain: TToolBar;
    procedure ActMultiEditExecute(Sender: TObject);
    procedure ActUndoExecute(Sender: TObject);
    procedure ButtonF2TPreviewClick(Sender: TObject);
    procedure ButtonF2TWriteClick(Sender: TObject);
    procedure ButtonFilterApplyClick(Sender: TObject);
    procedure ButtonHideSelectedClick(Sender: TObject);
    procedure ButtonMultiCopyClick(Sender: TObject);
    procedure ButtonMultiSaveClick(Sender: TObject);
    procedure ButtonRenameDoClick(Sender: TObject);
    procedure ButtonRenamePreviewClick(Sender: TObject);
    procedure ButtonShowAllClick(Sender: TObject);
    procedure ButtonVarsClick(Sender: TObject);
    procedure ComboAddressKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ComboAddressSelect(Sender: TObject);
    procedure EditFilterKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FileListColumnClick(Sender: TObject; Column: TListColumn);
    procedure FileListData(Sender: TObject; Item: TListItem);
    procedure FileListDblClick(Sender: TObject);
    procedure FileListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FileListMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure FileListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure InlineOptionChange(Sender: TObject);
    procedure MultiValueChange(Sender: TObject);
    procedure ShellTreeChange(Sender: TObject; Node: TTreeNode);
    procedure TimerDebounceTimer(Sender: TObject);
    procedure TimerPollTimer(Sender: TObject);
    procedure TimerSelectionTimer(Sender: TObject);
  private
    FItems: TFPList;        // owned TAudioInfo objects, in sort order
    FView: TFPList;         // the visible subset of FItems (filter, hidden files)
    FScanner: TScanThread;
    FFolder: string;
    FSortColumn: Integer;
    FSortDescending: Boolean;
    FKeepTimestamp: Boolean;
    FUndoLog: TRenameLog;
    FFilterText: string;
    FFilterField: Integer;
    FLoading: Boolean;
    FVarsTarget: TComboBox;
    FClip: TFieldValues;
    FHasClip: Boolean;
    FCoverFile: string;     // file whose embedded cover is shown
    FFolderCoverDir: string;
    FActions: TActionList;
    FActUndo, FActSubfolders, FActToolsPanel, FActFolders, FActAddress, FActFilter,
      FActKeepDate, FActPaste: TAction;
    FFavorites: TStringList;
    // actions
    procedure ActOpenFolderExecute(Sender: TObject);
    procedure ActRefreshExecute(Sender: TObject);
    procedure ActEditTagExecute(Sender: TObject);
    procedure ActRenameFolderExecute(Sender: TObject);
    procedure ActPlayExecute(Sender: TObject);
    procedure ActShowInExplorerExecute(Sender: TObject);
    procedure ActExitExecute(Sender: TObject);
    procedure ActSelectAllExecute(Sender: TObject);
    procedure ActSelectNoneExecute(Sender: TObject);
    procedure ActCheckSelectedExecute(Sender: TObject);
    procedure ActUncheckSelectedExecute(Sender: TObject);
    procedure ActCheckAllExecute(Sender: TObject);
    procedure ActUncheckAllExecute(Sender: TObject);
    procedure ActInvertChecksExecute(Sender: TObject);
    procedure ActCopyTagExecute(Sender: TObject);
    procedure ActPasteTagExecute(Sender: TObject);
    procedure ActFindExecute(Sender: TObject);
    procedure ActToolsPanelExecute(Sender: TObject);
    procedure ActFoldersExecute(Sender: TObject);
    procedure ActAddressExecute(Sender: TObject);
    procedure ActFilterBarExecute(Sender: TObject);
    procedure ActSubfoldersExecute(Sender: TObject);
    procedure ActPlaylistCheckedExecute(Sender: TObject);
    procedure ActPlaylistAllExecute(Sender: TObject);
    procedure ActTabRenameExecute(Sender: TObject);
    procedure ActTabMultiExecute(Sender: TObject);
    procedure ActTabFileToTagExecute(Sender: TObject);
    procedure ActRenameDialogExecute(Sender: TObject);
    procedure ActFileToTagDialogExecute(Sender: TObject);
    procedure ActTracksExecute(Sender: TObject);
    procedure ActWebExecute(Sender: TObject);
    procedure ActKeepDateExecute(Sender: TObject);
    procedure ActDiscogsTokenExecute(Sender: TObject);
    procedure ActShortcutsExecute(Sender: TObject);
    procedure ActAboutExecute(Sender: TObject);
    procedure ActFolderUpExecute(Sender: TObject);
    procedure ActFavoritesExecute(Sender: TObject);
    procedure ActNewFolderExecute(Sender: TObject);
    procedure ActRefreshTreeExecute(Sender: TObject);
    procedure FavoriteClick(Sender: TObject);
    procedure FavoriteAddClick(Sender: TObject);
    procedure FavoriteRemoveClick(Sender: TObject);
    procedure VarItemClick(Sender: TObject);
    // building
    procedure LoadIcons;
    function NewAction(const ACaption, AHint: string; AShortCut: TShortCut; AImage: Integer;
      AHandler: TNotifyEvent): TAction;
    procedure BuildActionsAndMenus;
    procedure SetupColumns;
    // list
    function Item(Index: Integer): TAudioInfo;
    function FocusedInfo: TAudioInfo;
    procedure RebuildView;
    function MatchesFilter(Info: TAudioInfo): Boolean;
    function CanStartBatch: Boolean;
    function AllItems: TAudioInfoArray;
    function SelectedItems: TAudioInfoArray;
    function CheckedItems: TAudioInfoArray;
    { Ticked files if any, else the selected ones. }
    function TargetItems(out ScopeCaption: string; out Prefer: Boolean): TAudioInfoArray;
    function RequireTargets(out Items: TAudioInfoArray): Boolean;
    procedure SetChecked(Items: TAudioInfoArray; Value: Boolean);
    procedure ChecksChanged;
    procedure SelectionChanged;
    { Follows renamed files/folders in the list, the open folder and the tree. }
    procedure ApplyRenameLog(const Log: TRenameLog; Reverse: Boolean);
    procedure SetUndoLog(const Log: TRenameLog; const What: string);
    procedure EditSelected;
    function FileAt(Index: Integer): string;
    procedure FileSaved(Index: Integer; NewInfo: TAudioInfo);
    procedure StopScan;
    procedure StartScan;
    procedure Navigate(const Dir: string);
    procedure AddAddressHistory(const Dir: string);
    procedure ClearItems;
    procedure SortItems;
    procedure UpdateStatus;
    procedure SetMessage(const S: string);
    function CellText(Info: TAudioInfo; Col: Integer): string;
    // tools panel
    procedure ShowTool(Index: Integer);
    function RenameOptions: TRenameOptions;
    function F2TCaseMode: TCaseMode;
    procedure SetCaseControls(Mode: TCaseMode; Check: TCheckBox; Lower, Upper, Title, Sentence: TRadioButton);
    function CaseFromControls(Check: TCheckBox; Lower, Upper, Title, Sentence: TRadioButton): TCaseMode;
    procedure UpdateInlinePreviews;
    procedure LoadInlineOptions;
    procedure SaveInlineOptions;
    procedure WriteFieldsBatch(const Items: TAudioInfoArray; const PerItem: array of TFieldValues;
      const PerItemFields: array of TTagFieldSet; const Cover: TBytes; const What: string);
    // covers
    procedure UpdateCovers;
    procedure ShowImageBytes(Image: TImage; const Data: TBytes);
    function FindFolderCover(const Dir: string): string;
    // settings
    procedure LoadSettings;
    procedure SaveSettings;
  end;

var
  FormMain: TFormMain;

implementation

{$R *.lfm}

uses
  StrUtils, LazUTF8, LCLType, LCLIntf, TagUtils, AudioTags, TagWriter, TagEditForm, RenameForm,
  FileToTagForm, FileNameTags, MultiEditForm, TrackToolsForm, WebLookupForm, AppSettings;

const
  CheckOn = '☑';
  CheckOff = '☐';

  IconNames: array[0..29] of string = ('open', 'refresh', 'search', 'subfolders', 'edit',
    'multiedit', 'renamefiles', 'renamefolder', 'filetotag', 'tracks', 'web', 'play', 'undo',
    'checkall', 'uncheck', 'help', 'info', 'favorites', 'settings', 'preview', 'save', 'filter',
    'copy', 'paste', 'folderup', 'newfolder', 'close', 'exit', 'picture', 'delete');
  icoOpen = 0; icoRefresh = 1; icoSearch = 2; icoSubfolders = 3; icoEdit = 4; icoMultiEdit = 5;
  icoRenameFiles = 6; icoRenameFolder = 7; icoFileToTag = 8; icoTracks = 9; icoWeb = 10;
  icoPlay = 11; icoUndo = 12; icoCheckAll = 13; icoUncheck = 14; icoHelp = 15; icoInfo = 16;
  icoFavorites = 17; icoSettings = 18; icoPreview = 19; icoSave = 20; icoFilter = 21;
  icoCopy = 22; icoPaste = 23; icoFolderUp = 24; icoNewFolder = 25; icoClose = 26;
  icoExit = 27; icoPicture = 28;

  DefaultRenameMasks: array[0..5] of string = ('%1 - %2', '%6 - %2', '%6 - %1 - %2',
    '%1 - %3 - %6 - %2', '%1\%3\%6 - %2', '%aa\%4 - %3\%6 - %2');
  DefaultF2TMasks: array[0..6] of string = ('%1 - %2', '%6 - %2', '%6 - %1 - %2', '%6. %2',
    '%6 %1 - %2', '%1\%3\%6 - %2', '%1\%4 - %3\%6 - %2');

  RenameVars: array[0..21] of string = (
    '%1|Kunstner', '%2|Titel', '%3|Album', '%4|År', '%5|Genre', '%6|Spor', '%#|Disc',
    '%7|Filnavn', '%8|Filnummer', '%9|Kommentar', '%0|Bitrate', '%b|BPM', '%t|Spilletid',
    '%aa|Albumkunstner', '%cp|Komponist', '%ext|Filtype', '%khz|Samplerate', '-|',
    ' - |" - " (bindestreg)', '\|\ (ny mappe)', '%6 - %1 - %2|Eksempel: spor - kunstner - titel',
    '%1\%3\%6 - %2|Eksempel: mapper pr. kunstner og album');
  F2TVars: array[0..15] of string = (
    '%1|Kunstner', '%2|Titel', '%3|Album', '%4|År', '%5|Genre', '%6|Spor', '%#|Disc',
    '%9|Kommentar', '%b|BPM', '%aa|Albumkunstner', '%cp|Komponist', '%d|Spring over',
    '-|', ' - |" - " (bindestreg)', '\|\ (mappeniveau)', '%6 - %1 - %2|Eksempel: spor - kunstner - titel');

  FilterFieldNames: array[0..7] of string = ('Filnavn', 'Titel', 'Kunstner', 'Album', 'År',
    'Genre', 'Kommentar', 'Alle felter');

var
  Columns: array of TColumnDef;
  // TFPList.Sort takes a plain function, so the active sort order lives here.
  SortForm: TFormMain;

procedure AddColumn(const ACaption: string; AWidth: Integer; AKind: TColumnKind;
  AField: TTagField = tfTitle; ANumeric: Boolean = False);
begin
  SetLength(Columns, Length(Columns) + 1);
  with Columns[High(Columns)] do
  begin
    Caption := ACaption;
    Width := AWidth;
    Kind := AKind;
    Field := AField;
    Numeric := ANumeric;
  end;
end;

procedure DefineColumns;
begin
  Columns := nil;
  AddColumn('✓', 30, ckCheck, tfTitle, True);
  AddColumn('Filnavn', 260, ckFileName);
  AddColumn(TagFieldCaptions[tfArtist], 160, ckField, tfArtist);
  AddColumn(TagFieldCaptions[tfAlbum], 180, ckField, tfAlbum);
  AddColumn(TagFieldCaptions[tfTitle], 220, ckField, tfTitle);
  AddColumn(TagFieldCaptions[tfYear], 70, ckField, tfYear);
  AddColumn(TagFieldCaptions[tfGenre], 110, ckField, tfGenre);
  AddColumn(TagFieldCaptions[tfTrack], 55, ckField, tfTrack, True);
  AddColumn('Bitrate', 60, ckBitrate, tfTitle, True);
  AddColumn('Tid', 60, ckDuration, tfTitle, True);
  AddColumn('Cover', 50, ckCover);
  AddColumn(TagFieldCaptions[tfDisc], 45, ckField, tfDisc, True);
  AddColumn(TagFieldCaptions[tfAlbumArtist], 140, ckField, tfAlbumArtist);
  AddColumn(TagFieldCaptions[tfComposer], 120, ckField, tfComposer);
  AddColumn(TagFieldCaptions[tfComment], 160, ckField, tfComment);
  AddColumn(TagFieldCaptions[tfBpm], 45, ckField, tfBpm, True);
  AddColumn('Samplerate', 75, ckSampleRate, tfTitle, True);
  AddColumn('Codec', 70, ckCodec);
  AddColumn('Tag-typer', 120, ckTagTypes);
  AddColumn('Størrelse', 75, ckSize, tfTitle, True);
  AddColumn('Mappe', 300, ckFolder);
end;

{ Leading integer of '7/12', '07', etc.; -1 if none. }
function LeadingNumber(const S: string): Int64;
var
  I: Integer;
begin
  I := 1;
  while (I <= Length(S)) and (S[I] in ['0'..'9']) do Inc(I);
  if (I = 1) or not TryStrToInt64(Copy(S, 1, I - 1), Result) then
    Result := -1;
end;

function NumericValue(Info: TAudioInfo; const C: TColumnDef): Double;
begin
  case C.Kind of
    ckCheck: Result := Ord(Info.Checked);
    ckField: Result := LeadingNumber(Info.Fields[C.Field]);
    ckDuration: Result := Info.Duration;
    ckBitrate: Result := Info.Bitrate;
    ckSampleRate: Result := Info.SampleRate;
    ckSize: Result := Info.FileSize;
  else
    Result := 0;
  end;
end;

function CompareInfos(Item1, Item2: Pointer): Integer;
var
  A, B: TAudioInfo;
  C: TColumnDef;
  NA, NB: Double;
begin
  A := TAudioInfo(Item1);
  B := TAudioInfo(Item2);
  C := Columns[SortForm.FSortColumn];
  if C.Numeric then
  begin
    NA := NumericValue(A, C);
    NB := NumericValue(B, C);
    if NA < NB then Result := -1
    else if NA > NB then Result := 1
    else Result := 0;
  end
  else
    Result := UTF8CompareText(SortForm.CellText(A, SortForm.FSortColumn),
      SortForm.CellText(B, SortForm.FSortColumn));
  if Result = 0 then // stable, predictable order: folder, then file name
    Result := UTF8CompareText(A.FileName, B.FileName)
  else if SortForm.FSortDescending then
    Result := -Result;
end;

function FormatSize(Bytes: Int64): string;
begin
  if Bytes >= 1024 * 1024 then
    Result := FormatFloat('0.0', Bytes / (1024 * 1024)) + ' MB'
  else
    Result := IntToStr((Bytes + 1023) div 1024) + ' KB';
end;

function ReadFileBytes(const FileName: string): TBytes;
var
  S: TFileStream;
begin
  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    Result := ReadStreamBytes(S, S.Size);
  finally
    S.Free;
  end;
end;

function IsImageFile(const FileName: string): Boolean;
begin
  case LowerCase(ExtractFileExt(FileName)) of
    '.jpg', '.jpeg', '.png': Result := True;
  else
    Result := False;
  end;
end;

{ TFormMain - setup }

procedure TFormMain.FormCreate(Sender: TObject);
var
  S: string;
  I: Integer;
begin
  FItems := TFPList.Create;
  FView := TFPList.Create;
  FFavorites := TStringList.Create;
  FSortColumn := 1; // file name
  FLoading := True;
  try
    LoadIcons;
    BuildActionsAndMenus;
    DefineColumns;
    SetupColumns;
    for S in FilterFieldNames do ComboFilterField.Items.Add(S);
    ComboFilterField.ItemIndex := 0;
    ComboMultiGenre.Items.BeginUpdate;
    try
      for I := 0 to ID3GenreCount - 1 do
        ComboMultiGenre.Items.Add(ID3GenreName(I));
    finally
      ComboMultiGenre.Items.EndUpdate;
    end;
    FFilterField := 0;
    LabelRenameHelp.Caption :=
      '%1 Kunstner   %2 Titel   %3 Album   %4 År   %5 Genre   %6 Spor' + LineEnding +
      '%# Disc   %7 Filnavn   %8 Filnummer   %9 Kommentar   %0 Bitrate' + LineEnding +
      '%b BPM   %t Spilletid   %aa Albumkunstner   %cp Komponist' + LineEnding +
      '%ext Filtype   %khz Samplerate.   \ laver mapper, fx  %1\%3\%6 - %2' + LineEnding +
      'Gælder de afkrydsede filer (ellers de markerede).';
    LabelMultiHelp.Caption :=
      '1. Kun felter med flueben bliver ændret (et felt får flueben, når du skriver i det).' + LineEnding +
      '2. Tags gemmes i de afkrydsede filer (ellers de markerede).' + LineEnding +
      '3. Et tomt felt med flueben bliver ryddet.' + LineEnding +
      '4. "Alle felter..." redigerer flere felter og cover på én gang.';
    LabelF2THelp.Caption :=
      '%1 Kunstner   %2 Titel   %3 Album   %4 År   %5 Genre   %6 Spor' + LineEnding +
      '%# Disc   %9 Kommentar   %b BPM   %aa Albumkunstner   %cp Komponist' + LineEnding +
      '%d Spring en del over.   Filtypen fjernes automatisk.' + LineEnding +
      '\ bruger mappenavne, fx  %1\%3\%6 - %2' + LineEnding +
      'Gælder de afkrydsede filer (ellers de markerede).';
    LoadInlineOptions;
  finally
    FLoading := False;
  end;
  LoadSettings;
end;

procedure TFormMain.FormDestroy(Sender: TObject);
begin
  StopScan;
  SaveSettings;
  SaveInlineOptions;
  ClearItems;
  FItems.Free;
  FView.Free;
  FFavorites.Free;
end;

procedure TFormMain.LoadIcons;
var
  I, J: Integer;
  Pngs: array[0..2] of TCustomBitmap;
const
  Sizes: array[0..2] of Integer = (16, 24, 32);
begin
  ImagesMain.Width := 16;
  ImagesMain.Height := 16;
  for I := 0 to High(IconNames) do
  begin
    for J := 0 to 2 do
    begin
      Pngs[J] := TPortableNetworkGraphic.Create;
      Pngs[J].LoadFromResourceName(HInstance, Format('ICON_%s_%d', [UpperCase(IconNames[I]), Sizes[J]]));
    end;
    try
      ImagesMain.AddMultipleResolutions([Pngs[0], Pngs[1], Pngs[2]]);
    finally
      for J := 0 to 2 do Pngs[J].Free;
    end;
  end;
  MainMenu.Images := ImagesMain;
  PopupFileList.Images := ImagesMain;
  PopupFavorites.Images := ImagesMain;
  ToolBarMain.Images := ImagesMain;
  ToolBarFolders.Images := ImagesMain;
end;

function TFormMain.NewAction(const ACaption, AHint: string; AShortCut: TShortCut; AImage: Integer;
  AHandler: TNotifyEvent): TAction;
begin
  Result := TAction.Create(FActions);
  Result.ActionList := FActions;
  Result.Caption := ACaption;
  if AHint <> '' then Result.Hint := AHint else Result.Hint := StringReplace(ACaption, '&', '', [rfReplaceAll]);
  Result.ShortCut := AShortCut;
  Result.ImageIndex := AImage;
  Result.OnExecute := AHandler;
end;

procedure TFormMain.BuildActionsAndMenus;
var
  aOpen, aRefresh, aEdit, aMulti, aRenameFolder, aPlay, aExplorer, aExit,
    aSelAll, aSelNone, aChkSel, aUnchkSel, aChkAll, aUnchkAll, aInvert, aCopy, aFind,
    aPlChecked, aPlAll, aTabRename, aTabMulti, aTabF2T, aRenameDlg, aF2TDlg, aTracks, aWeb,
    aToken, aKeys, aAbout, aUp, aFav, aNewFolder, aTreeRefresh, aCloseFolders: TAction;
  TopMenu: TMenuItem;
  X: Integer;

  function Menu(const Caption: string): TMenuItem;
  begin
    Result := TMenuItem.Create(MainMenu);
    Result.Caption := Caption;
    MainMenu.Items.Add(Result);
  end;

  procedure Add(Parent: TMenuItem; A: TAction);
  var
    M: TMenuItem;
  begin
    M := TMenuItem.Create(Parent);
    if A = nil then M.Caption := '-' else M.Action := A;
    Parent.Add(M);
  end;

  procedure AddPopup(A: TAction);
  var
    M: TMenuItem;
  begin
    M := TMenuItem.Create(PopupFileList);
    if A = nil then M.Caption := '-' else M.Action := A;
    PopupFileList.Items.Add(M);
  end;

  procedure Btn(Bar: TToolBar; A: TAction; Style: TToolButtonStyle = tbsButton);
  var
    B: TToolButton;
  begin
    B := TToolButton.Create(Bar);
    B.Left := X; // appended to the right in creation order
    Inc(X, 100);
    if A = nil then B.Style := tbsSeparator
    else
    begin
      B.Style := Style;
      B.Action := A;
    end;
    B.Parent := Bar;
  end;

begin
  FActions := TActionList.Create(Self);
  FActions.Images := ImagesMain;

  aOpen := NewAction('Åbn mappe...', 'Åbn en mappe', ShortCut(VK_O, [ssCtrl]), icoOpen, @ActOpenFolderExecute);
  aRefresh := NewAction('Opdater fillisten', 'Læs mappen igen (F5)', ShortCut(VK_F5, []), icoRefresh, @ActRefreshExecute);
  aEdit := NewAction('Rediger tag...', 'Rediger tag for den markerede fil (Enter)', 0, icoEdit, @ActEditTagExecute);
  aMulti := NewAction('Rediger flere filer...', 'Ret felter og cover i alle afkrydsede (eller markerede) filer',
    ShortCut(VK_E, [ssCtrl]), icoMultiEdit, @ActMultiEditExecute);
  aRenameFolder := NewAction('Omdøb mapper...', 'Omdøb mapperne ud fra filernes tags', 0, icoRenameFolder, @ActRenameFolderExecute);
  aPlay := NewAction('Afspil fil', 'Afspil den markerede fil', ShortCut(VK_P, [ssCtrl]), icoPlay, @ActPlayExecute);
  aExplorer := NewAction('Vis i Stifinder', '', 0, icoOpen, @ActShowInExplorerExecute);
  aExit := NewAction('Afslut', '', ShortCut(VK_F4, [ssAlt]), icoExit, @ActExitExecute);
  aSelAll := NewAction('Markér alle', '', ShortCut(VK_A, [ssCtrl]), -1, @ActSelectAllExecute);
  aSelNone := NewAction('Fjern markering', '', 0, -1, @ActSelectNoneExecute);
  aChkSel := NewAction('Afkryds markerede filer' + #9 + 'Mellemrum', 'Afkryds de markerede filer', 0, icoCheckAll, @ActCheckSelectedExecute);
  aUnchkSel := NewAction('Fjern afkrydsning fra markerede filer', '', 0, -1, @ActUncheckSelectedExecute);
  aChkAll := NewAction('Afkryds alle filer', 'Afkryds alle filer i listen', 0, icoCheckAll, @ActCheckAllExecute);
  aUnchkAll := NewAction('Fjern alle afkrydsninger', '', 0, icoUncheck, @ActUncheckAllExecute);
  aInvert := NewAction('Inverter afkrydsning', '', 0, -1, @ActInvertChecksExecute);
  aCopy := NewAction('Kopiér tag', 'Kopiér tag fra den markerede fil', ShortCut(VK_C, [ssCtrl, ssShift]), icoCopy, @ActCopyTagExecute);
  FActPaste := NewAction('Indsæt tag', 'Indsæt det kopierede tag (undtagen titel og spor) i de afkrydsede/markerede filer',
    ShortCut(VK_V, [ssCtrl, ssShift]), icoPaste, @ActPasteTagExecute);
  FActPaste.Enabled := False;
  aFind := NewAction('Find / filtrér...', 'Filtrér fillisten', ShortCut(VK_F, [ssCtrl]), icoSearch, @ActFindExecute);
  FActToolsPanel := NewAction('Værktøjspanel', 'Vis/skjul værktøjspanelet (F8)', ShortCut(VK_F8, []), -1, @ActToolsPanelExecute);
  FActFolders := NewAction('Mappepanel', '', 0, -1, @ActFoldersExecute);
  FActAddress := NewAction('Adresselinje', '', 0, -1, @ActAddressExecute);
  FActFilter := NewAction('Filterlinje', '', 0, -1, @ActFilterBarExecute);
  FActSubfolders := NewAction('Søg i undermapper', 'Medtag filer i undermapper', 0, icoSubfolders, @ActSubfoldersExecute);
  aPlChecked := NewAction('Gem afkrydsede/markerede filer som playliste...', '', 0, icoSave, @ActPlaylistCheckedExecute);
  aPlAll := NewAction('Gem alle filer som playliste...', '', 0, icoSave, @ActPlaylistAllExecute);
  aTabRename := NewAction('Omdøb filer', 'Vis fanebladet Omdøb filer', ShortCut(VK_F4, []), icoRenameFiles, @ActTabRenameExecute);
  aTabMulti := NewAction('Multi-fil-tag-editor', 'Vis fanebladet Multi-fil-tag-editor', ShortCut(VK_F4, [ssCtrl]), icoMultiEdit, @ActTabMultiExecute);
  aTabF2T := NewAction('Tags fra filnavn', 'Vis fanebladet Tags fra filnavn', ShortCut(VK_F4, [ssShift]), icoFileToTag, @ActTabFileToTagExecute);
  aRenameDlg := NewAction('Omdøb filer med forhåndsvisning...', '', 0, icoPreview, @ActRenameDialogExecute);
  aF2TDlg := NewAction('Tags fra filnavn med forhåndsvisning...', '', 0, icoPreview, @ActFileToTagDialogExecute);
  aTracks := NewAction('Spornumre...', 'Formatér eller nummerér spornumre', ShortCut(VK_T, [ssCtrl]), icoTracks, @ActTracksExecute);
  aWeb := NewAction('Web-opslag (MusicBrainz/Discogs)...', 'Hent titler, spornumre og cover fra MusicBrainz eller Discogs',
    ShortCut(VK_W, [ssCtrl]), icoWeb, @ActWebExecute);
  FActUndo := NewAction('Fortryd omdøbning', 'Giv de senest omdøbte filer/mapper deres gamle navne igen',
    ShortCut(VK_Z, [ssCtrl]), icoUndo, @ActUndoExecute);
  FActUndo.Enabled := False;
  FActKeepDate := NewAction('Bevar filernes dato ved gem', '', 0, -1, @ActKeepDateExecute);
  aToken := NewAction('Discogs-token...', '', 0, icoSettings, @ActDiscogsTokenExecute);
  aKeys := NewAction('Tastaturgenveje', '', ShortCut(VK_F1, []), icoHelp, @ActShortcutsExecute);
  aAbout := NewAction('Om TagKlon...', '', 0, icoInfo, @ActAboutExecute);
  aUp := NewAction('Op', 'Gå en mappe op', ShortCut(VK_BACK, [ssAlt]), icoFolderUp, @ActFolderUpExecute);
  aFav := NewAction('Favoritter', 'Favoritmapper', 0, icoFavorites, @ActFavoritesExecute);
  aNewFolder := NewAction('Ny mappe...', 'Opret en undermappe i den åbne mappe', 0, icoNewFolder, @ActNewFolderExecute);
  aTreeRefresh := NewAction('Opdater mappetræet', '', 0, icoRefresh, @ActRefreshTreeExecute);
  aCloseFolders := NewAction('Skjul mappepanelet', '', 0, icoClose, @ActFoldersExecute);
  FActToolsPanel.AutoCheck := True;
  FActFolders.AutoCheck := True;
  FActAddress.AutoCheck := True;
  FActFilter.AutoCheck := True;
  FActSubfolders.AutoCheck := True;
  FActKeepDate.AutoCheck := True;

  // ---- main menu
  TopMenu := Menu('&Filer');
  Add(TopMenu, aOpen); Add(TopMenu, aRefresh); Add(TopMenu, nil);
  Add(TopMenu, aEdit); Add(TopMenu, aMulti); Add(TopMenu, aRenameFolder); Add(TopMenu, nil);
  Add(TopMenu, aPlay); Add(TopMenu, aExplorer); Add(TopMenu, nil); Add(TopMenu, aExit);
  TopMenu := Menu('&Rediger');
  Add(TopMenu, aSelAll); Add(TopMenu, aSelNone); Add(TopMenu, nil);
  Add(TopMenu, aChkSel); Add(TopMenu, aUnchkSel); Add(TopMenu, aChkAll); Add(TopMenu, aUnchkAll); Add(TopMenu, aInvert);
  Add(TopMenu, nil); Add(TopMenu, aCopy); Add(TopMenu, FActPaste); Add(TopMenu, nil); Add(TopMenu, aFind);
  TopMenu := Menu('&Vis');
  Add(TopMenu, FActToolsPanel); Add(TopMenu, FActFolders); Add(TopMenu, FActAddress); Add(TopMenu, FActFilter);
  Add(TopMenu, nil); Add(TopMenu, FActSubfolders); Add(TopMenu, nil); Add(TopMenu, aRefresh);
  TopMenu := Menu('&Playliste');
  Add(TopMenu, aPlChecked); Add(TopMenu, aPlAll);
  TopMenu := Menu('Vær&ktøjer');
  Add(TopMenu, aTabRename); Add(TopMenu, aTabMulti); Add(TopMenu, aTabF2T); Add(TopMenu, nil);
  Add(TopMenu, aRenameDlg); Add(TopMenu, aF2TDlg); Add(TopMenu, aRenameFolder); Add(TopMenu, aTracks); Add(TopMenu, aWeb);
  Add(TopMenu, nil); Add(TopMenu, FActUndo);
  TopMenu := Menu('&Indstillinger');
  Add(TopMenu, FActKeepDate); Add(TopMenu, aToken);
  TopMenu := Menu('&Hjælp');
  Add(TopMenu, aKeys); Add(TopMenu, aAbout);

  // ---- file list popup
  AddPopup(aEdit); AddPopup(aMulti); AddPopup(nil);
  AddPopup(aChkSel); AddPopup(aUnchkSel); AddPopup(aChkAll); AddPopup(aUnchkAll); AddPopup(aInvert);
  AddPopup(nil); AddPopup(aCopy); AddPopup(FActPaste); AddPopup(nil); AddPopup(aPlay); AddPopup(aExplorer);

  // ---- toolbars
  X := 0;
  Btn(ToolBarMain, aOpen); Btn(ToolBarMain, aRefresh); Btn(ToolBarMain, aFind); Btn(ToolBarMain, nil);
  Btn(ToolBarMain, FActSubfolders, tbsCheck); Btn(ToolBarMain, nil);
  Btn(ToolBarMain, aEdit); Btn(ToolBarMain, aMulti); Btn(ToolBarMain, aRenameDlg);
  Btn(ToolBarMain, aRenameFolder); Btn(ToolBarMain, aF2TDlg); Btn(ToolBarMain, nil);
  Btn(ToolBarMain, aCopy); Btn(ToolBarMain, FActPaste); Btn(ToolBarMain, nil);
  Btn(ToolBarMain, aPlay); Btn(ToolBarMain, nil);
  Btn(ToolBarMain, aTracks); Btn(ToolBarMain, aWeb); Btn(ToolBarMain, nil);
  Btn(ToolBarMain, aChkAll); Btn(ToolBarMain, aUnchkAll); Btn(ToolBarMain, nil);
  Btn(ToolBarMain, FActUndo); Btn(ToolBarMain, nil);
  Btn(ToolBarMain, aKeys); Btn(ToolBarMain, aAbout);
  X := 0;
  Btn(ToolBarFolders, aUp); Btn(ToolBarFolders, aFav); Btn(ToolBarFolders, aNewFolder);
  Btn(ToolBarFolders, aTreeRefresh); Btn(ToolBarFolders, aCloseFolders);
end;

procedure TFormMain.SetupColumns;
var
  I: Integer;
  Col: TListColumn;
begin
  FileList.Columns.BeginUpdate;
  try
    FileList.Columns.Clear;
    for I := 0 to High(Columns) do
    begin
      Col := FileList.Columns.Add;
      Col.Caption := Columns[I].Caption;
      Col.Width := Columns[I].Width;
      if Columns[I].Kind = ckCheck then Col.Alignment := taCenter
      else if Columns[I].Numeric then Col.Alignment := taRightJustify;
    end;
  finally
    FileList.Columns.EndUpdate;
  end;
end;

{ TFormMain - list }

function TFormMain.Item(Index: Integer): TAudioInfo;
begin
  Result := TAudioInfo(FView[Index]);
end;

function TFormMain.FocusedInfo: TAudioInfo;
var
  I: Integer;
begin
  Result := nil;
  I := FileList.ItemIndex;
  if (I >= 0) and (I < FView.Count) then Result := Item(I);
end;

function TFormMain.MatchesFilter(Info: TAudioInfo): Boolean;
var
  Hay: string;
  F: TTagField;
begin
  if FFilterText = '' then Exit(True);
  case FFilterField of
    0: Hay := ExtractFileName(Info.FileName);
    1: Hay := Info.Fields[tfTitle];
    2: Hay := Info.Fields[tfArtist];
    3: Hay := Info.Fields[tfAlbum];
    4: Hay := Info.Fields[tfYear];
    5: Hay := Info.Fields[tfGenre];
    6: Hay := Info.Fields[tfComment];
  else
    Hay := ExtractFileName(Info.FileName);
    for F := Low(TTagField) to High(TTagField) do Hay := Hay + #1 + Info.Fields[F];
  end;
  Result := Pos(FFilterText, UTF8LowerCase(Hay)) > 0;
end;

procedure TFormMain.RebuildView;
var
  I: Integer;
  Info: TAudioInfo;
begin
  FView.Clear;
  for I := 0 to FItems.Count - 1 do
  begin
    Info := TAudioInfo(FItems[I]);
    if not Info.Hidden and MatchesFilter(Info) then FView.Add(Info);
  end;
  if FileList.Items.Count <> FView.Count then
    FileList.Items.Count := FView.Count;
  FileList.Invalidate;
  UpdateStatus;
end;

function TFormMain.CellText(Info: TAudioInfo; Col: Integer): string;
begin
  case Columns[Col].Kind of
    ckCheck: if Info.Checked then Result := CheckOn else Result := CheckOff;
    ckFileName: Result := ExtractFileName(Info.FileName);
    ckField: Result := Info.Fields[Columns[Col].Field];
    ckDuration: Result := FormatDuration(Info.Duration);
    ckBitrate: if Info.Bitrate > 0 then Result := IntToStr(Info.Bitrate) else Result := '';
    ckSampleRate: if Info.SampleRate > 0 then Result := IntToStr(Info.SampleRate) else Result := '';
    ckCodec: Result := Info.Codec;
    ckTagTypes:
      if Info.Error <> '' then Result := 'Fejl: ' + Info.Error
      else if not Info.Supported then Result := '(ikke understøttet endnu)'
      else Result := Info.TagTypes;
    ckCover: if Info.HasCover then Result := 'Ja' else Result := '';
    ckSize: Result := FormatSize(Info.FileSize);
    ckFolder: Result := ExtractFileDir(Info.FileName);
  else
    Result := '';
  end;
end;

procedure TFormMain.FileListData(Sender: TObject; Item: TListItem);
var
  Info: TAudioInfo;
  I: Integer;
begin
  if (Item.Index < 0) or (Item.Index >= FView.Count) then Exit;
  Info := TAudioInfo(FView[Item.Index]);
  Item.Caption := CellText(Info, 0);
  for I := 1 to High(Columns) do
    Item.SubItems.Add(CellText(Info, I));
end;

procedure TFormMain.FileListColumnClick(Sender: TObject; Column: TListColumn);
begin
  if Column.Index = FSortColumn then
    FSortDescending := not FSortDescending
  else
  begin
    FSortColumn := Column.Index;
    FSortDescending := False;
  end;
  SortItems;
end;

procedure TFormMain.SortItems;
begin
  SortForm := Self;
  FItems.Sort(@CompareInfos);
  RebuildView;
end;

procedure TFormMain.FileListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  SelectionChanged;
end;

procedure TFormMain.SelectionChanged;
begin
  // Selecting many rows fires once per row; react once things settle.
  TimerSelection.Enabled := False;
  TimerSelection.Enabled := True;
end;

procedure TFormMain.TimerSelectionTimer(Sender: TObject);
begin
  TimerSelection.Enabled := False;
  UpdateStatus;
  UpdateInlinePreviews;
  UpdateCovers;
end;

procedure TFormMain.FileListDblClick(Sender: TObject);
begin
  EditSelected;
end;

procedure TFormMain.FileListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  Sel: TAudioInfoArray;
begin
  if Key = VK_RETURN then
  begin
    Key := 0;
    EditSelected;
  end
  else if Key = VK_SPACE then
  begin
    // Space ticks/unticks all selected files together (following the first one).
    Key := 0;
    Sel := SelectedItems;
    if Length(Sel) > 0 then SetChecked(Sel, not Sel[0].Checked);
  end;
end;

procedure TFormMain.FileListMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  LI: TListItem;
  Info: TAudioInfo;
begin
  if Button <> mbLeft then Exit;
  // Only clicks inside the tick column toggle; the column may be scrolled sideways.
  if X + GetScrollPos(FileList.Handle, SB_HORZ) >= FileList.Column[0].Width then Exit;
  LI := FileList.GetItemAt(X, Y);
  if (LI = nil) or (LI.Index < 0) or (LI.Index >= FView.Count) then Exit;
  Info := Item(LI.Index);
  Info.Checked := not Info.Checked;
  ChecksChanged;
end;

procedure TFormMain.SetChecked(Items: TAudioInfoArray; Value: Boolean);
var
  Info: TAudioInfo;
begin
  for Info in Items do Info.Checked := Value;
  ChecksChanged;
end;

procedure TFormMain.ChecksChanged;
begin
  FileList.Invalidate;
  UpdateStatus;
  UpdateInlinePreviews;
end;

function TFormMain.CanStartBatch: Boolean;
begin
  Result := FScanner = nil;
  if not Result then
    MessageDlg('Vent venligst, til alle tags er læst.', mtInformation, [mbOK], 0);
end;

function TFormMain.AllItems: TAudioInfoArray;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, FView.Count);
  for I := 0 to FView.Count - 1 do
    Result[I] := Item(I);
end;

function TFormMain.SelectedItems: TAudioInfoArray;
var
  I, N: Integer;
begin
  Result := nil;
  SetLength(Result, FileList.SelCount);
  N := 0;
  for I := 0 to FView.Count - 1 do
    if (N < Length(Result)) and FileList.Items[I].Selected then
    begin
      Result[N] := Item(I);
      Inc(N);
    end;
  SetLength(Result, N);
end;

function TFormMain.CheckedItems: TAudioInfoArray;
var
  I, N: Integer;
begin
  Result := nil;
  SetLength(Result, FView.Count);
  N := 0;
  for I := 0 to FView.Count - 1 do
    if Item(I).Checked then
    begin
      Result[N] := Item(I);
      Inc(N);
    end;
  SetLength(Result, N);
end;

function TFormMain.TargetItems(out ScopeCaption: string; out Prefer: Boolean): TAudioInfoArray;
begin
  Result := CheckedItems;
  if Length(Result) > 0 then
  begin
    ScopeCaption := Format('Afkrydsede filer (%d)', [Length(Result)]);
    Prefer := True;
  end
  else
  begin
    Result := SelectedItems;
    ScopeCaption := Format('Markerede filer (%d)', [Length(Result)]);
    Prefer := Length(Result) > 1;
  end;
end;

function TFormMain.RequireTargets(out Items: TAudioInfoArray): Boolean;
var
  ScopeCaption: string;
  Prefer: Boolean;
begin
  Result := False;
  Items := nil;
  if not CanStartBatch then Exit;
  Items := TargetItems(ScopeCaption, Prefer);
  Result := Length(Items) > 0;
  if not Result then
    MessageDlg('Afkryds (☑) eller markér de filer, det skal gælde.', mtInformation, [mbOK], 0);
end;

{ TFormMain - folders, scanning }

procedure TFormMain.ShellTreeChange(Sender: TObject; Node: TTreeNode);
begin
  // Wait briefly so arrowing through the tree does not start a scan per folder.
  TimerDebounce.Enabled := False;
  TimerDebounce.Enabled := True;
end;

procedure TFormMain.TimerDebounceTimer(Sender: TObject);
var
  NewFolder: string;
begin
  TimerDebounce.Enabled := False;
  try
    NewFolder := ShellTree.Path;
  except
    NewFolder := '';
  end;
  if (NewFolder = '') or not DirectoryExists(NewFolder) then Exit;
  NewFolder := ExcludeTrailingPathDelimiter(NewFolder);
  if SameFileName(NewFolder, FFolder) then Exit; // use "Opdater" to re-read
  FFolder := NewFolder;
  AddAddressHistory(FFolder);
  StartScan;
end;

procedure TFormMain.Navigate(const Dir: string);
var
  D: string;
begin
  D := ExcludeTrailingPathDelimiter(Trim(Dir));
  if (D = '') or not DirectoryExists(D) then
  begin
    MessageDlg('Mappen findes ikke:' + LineEnding + Dir, mtWarning, [mbOK], 0);
    Exit;
  end;
  FFolder := D;
  try
    ShellTree.Path := D;
  except
    // the list still works when the tree cannot show the folder
  end;
  AddAddressHistory(D);
  StartScan;
end;

procedure TFormMain.AddAddressHistory(const Dir: string);
var
  I: Integer;
begin
  I := ComboAddress.Items.IndexOf(Dir);
  if I >= 0 then ComboAddress.Items.Delete(I);
  ComboAddress.Items.Insert(0, Dir);
  while ComboAddress.Items.Count > 20 do ComboAddress.Items.Delete(ComboAddress.Items.Count - 1);
  ComboAddress.Text := Dir;
end;

procedure TFormMain.ComboAddressKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    Key := 0;
    Navigate(ComboAddress.Text);
  end;
end;

procedure TFormMain.ComboAddressSelect(Sender: TObject);
begin
  if ComboAddress.ItemIndex >= 0 then
    Navigate(ComboAddress.Items[ComboAddress.ItemIndex]);
end;

procedure TFormMain.ClearItems;
var
  I: Integer;
begin
  for I := 0 to FItems.Count - 1 do
    TAudioInfo(FItems[I]).Free;
  FItems.Clear;
  FView.Clear;
end;

procedure TFormMain.StopScan;
begin
  TimerPoll.Enabled := False;
  if FScanner = nil then Exit;
  FScanner.Terminate;
  FScanner.WaitFor;
  FreeAndNil(FScanner);
end;

procedure TFormMain.StartScan;
begin
  StopScan;
  FileList.Items.Count := 0;
  ClearItems;
  ComboAddress.Text := FFolder;
  Caption := 'TagKlon - ' + FFolder;
  FCoverFile := '';
  FFolderCoverDir := '';
  FScanner := TScanThread.Create(FFolder, FActSubfolders.Checked);
  TimerPoll.Enabled := True;
  UpdateStatus;
end;

procedure TFormMain.TimerPollTimer(Sender: TObject);
var
  Finished: Boolean;
begin
  if FScanner = nil then
  begin
    TimerPoll.Enabled := False;
    Exit;
  end;
  Finished := FScanner.Finished;
  FScanner.TakeResults(FItems);
  if Finished then
  begin
    FScanner.TakeResults(FItems); // anything added after the Finished check
    FreeAndNil(FScanner);
    TimerPoll.Enabled := False;
    SortItems;
    SelectionChanged;
  end
  else
    RebuildView;
end;

procedure TFormMain.SetMessage(const S: string);
begin
  StatusBar.Panels[5].Text := S;
end;

procedure TFormMain.UpdateStatus;
var
  Done, Total, I, Checked, Hidden: Integer;
  TotalSec, SelSec: Double;
  Sel: TAudioInfoArray;
begin
  if FScanner <> nil then
  begin
    if FScanner.Progress(Done, Total) then
      SetMessage(Format('Læser tags: %d af %d filer...', [Done, Total]))
    else
      SetMessage('Søger efter filer...');
  end
  else if Pos('Læser tags', StatusBar.Panels[5].Text) + Pos('Søger efter', StatusBar.Panels[5].Text) > 0 then
    SetMessage('');
  TotalSec := 0;
  Checked := 0;
  for I := 0 to FView.Count - 1 do
  begin
    TotalSec := TotalSec + Item(I).Duration;
    if Item(I).Checked then Inc(Checked);
  end;
  Hidden := FItems.Count - FView.Count;
  Sel := SelectedItems;
  SelSec := 0;
  for I := 0 to High(Sel) do SelSec := SelSec + Sel[I].Duration;
  if Hidden > 0 then
    StatusBar.Panels[0].Text := Format('Filer: %d (+%d skjult)', [FView.Count, Hidden])
  else
    StatusBar.Panels[0].Text := Format('Filer i alt: %d', [FView.Count]);
  StatusBar.Panels[1].Text := Format('Markerede: %d', [Length(Sel)]);
  StatusBar.Panels[2].Text := 'Samlet tid: ' + IfThen(TotalSec > 0, FormatDuration(TotalSec), '0:00');
  StatusBar.Panels[3].Text := 'Markeret tid: ' + IfThen(SelSec > 0, FormatDuration(SelSec), '0:00');
  StatusBar.Panels[4].Text := Format('Afkrydset: %d', [Checked]);
end;

{ TFormMain - rename log / undo }

procedure TFormMain.SetUndoLog(const Log: TRenameLog; const What: string);
begin
  FUndoLog := Log;
  FActUndo.Enabled := True;
  ButtonRenameUndo.Enabled := True;
  FActUndo.Hint := Format('Fortryd omdøbning af %d %s', [Length(Log), What]);
end;

procedure TFormMain.ApplyRenameLog(const Log: TRenameLog; Reverse: Boolean);
var
  I: Integer;
  Info: TAudioInfo;
  NewPath, NewFolder: string;
begin
  for I := 0 to FItems.Count - 1 do
  begin
    Info := TAudioInfo(FItems[I]);
    NewPath := MapRenamedPath(Info.FileName, Log, Reverse);
    if (NewPath <> Info.FileName) and FileExists(NewPath) then
      Info.FileName := NewPath;
  end;
  NewFolder := MapRenamedPath(FFolder, Log, Reverse);
  if (NewFolder <> FFolder) and DirectoryExists(NewFolder) then
  begin
    FFolder := NewFolder;
    ComboAddress.Text := FFolder;
    Caption := 'TagKlon - ' + FFolder;
  end;
  try
    ShellTree.UpdateView(FFolder); // show the new folder names, keep the open folder selected
  except
    // the tree is only a view; the list is already up to date
  end;
  FileList.Invalidate;
end;

procedure TFormMain.ActUndoExecute(Sender: TObject);
var
  Errors: TStringList;
  Restored: Integer;
begin
  if Length(FUndoLog) = 0 then Exit;
  if MessageDlg('Fortryd omdøbning', Format('Giv %d filer/mapper deres tidligere navn igen?',
    [Length(FUndoLog)]), mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  Errors := TStringList.Create;
  try
    Restored := UndoRename(FUndoLog, Errors);
    ApplyRenameLog(FUndoLog, True);
    FUndoLog := nil;
    FActUndo.Enabled := False;
    ButtonRenameUndo.Enabled := False;
    SetMessage(Format('%d filer/mapper fik deres gamle navn igen', [Restored]));
    SelectionChanged;
    if Errors.Count > 0 then
      MessageDlg('Fortryd omdøbning', Format('%d filer/mapper fik deres gamle navn igen. Problemer:',
        [Restored]) + LineEnding + Errors.Text, mtWarning, [mbOK], 0);
  finally
    Errors.Free;
  end;
end;

{ TFormMain - single file editor }

procedure TFormMain.EditSelected;
var
  Index: Integer;
begin
  if not CanStartBatch then Exit;
  Index := FileList.ItemIndex;
  if (Index < 0) or (Index >= FView.Count) then
  begin
    if FView.Count = 0 then Exit;
    Index := 0;
  end;
  TFormTagEdit.Execute(Index, FView.Count, @FileAt, @FileSaved, FKeepTimestamp);
  FActKeepDate.Checked := FKeepTimestamp;
  FCoverFile := '';
  FileList.Invalidate;
  SelectionChanged;
end;

function TFormMain.FileAt(Index: Integer): string;
begin
  if (Index >= 0) and (Index < FView.Count) then
    Result := Item(Index).FileName
  else
    Result := '';
end;

procedure TFormMain.FileSaved(Index: Integer; NewInfo: TAudioInfo);
var
  Old: TAudioInfo;
  J: Integer;
begin
  if (Index < 0) or (Index >= FView.Count) then
  begin
    NewInfo.Free;
    Exit;
  end;
  Old := Item(Index);
  NewInfo.Checked := Old.Checked;
  NewInfo.Hidden := Old.Hidden;
  J := FItems.IndexOf(Old);
  if J >= 0 then FItems[J] := NewInfo;
  FView[Index] := NewInfo;
  Old.Free;
  FileList.Invalidate;
end;

{ TFormMain - tools panel }

procedure TFormMain.ShowTool(Index: Integer);
begin
  PanelTools.Visible := True;
  FActToolsPanel.Checked := True;
  PageTools.ActivePageIndex := Index;
  case Index of
    0: ActiveControl := ComboRenameMask;
    1: ActiveControl := EditMultiArtist;
    2: ActiveControl := ComboF2TMask;
  end;
end;

procedure TFormMain.SetCaseControls(Mode: TCaseMode; Check: TCheckBox; Lower, Upper, Title,
  Sentence: TRadioButton);
begin
  Check.Checked := Mode <> cmNone;
  case Mode of
    cmLower: Lower.Checked := True;
    cmUpper: Upper.Checked := True;
    cmSentence: Sentence.Checked := True;
  else
    Title.Checked := True;
  end;
end;

function TFormMain.CaseFromControls(Check: TCheckBox; Lower, Upper, Title, Sentence: TRadioButton): TCaseMode;
begin
  if not Check.Checked then Exit(cmNone);
  if Lower.Checked then Result := cmLower
  else if Upper.Checked then Result := cmUpper
  else if Sentence.Checked then Result := cmSentence
  else Result := cmTitle;
end;

function TFormMain.RenameOptions: TRenameOptions;
begin
  Result.CaseMode := CaseFromControls(CheckRenameCase, RadioRenameLower, RadioRenameUpper,
    RadioRenameTitle, RadioRenameSentence);
  Result.SpacesToUnderscores := CheckRenameUnderscores.Checked;
  Result.PadTrack := CheckRenamePadTrack.Checked;
end;

function TFormMain.F2TCaseMode: TCaseMode;
begin
  Result := CaseFromControls(CheckF2TCase, RadioF2TLower, RadioF2TUpper, RadioF2TTitle, RadioF2TSentence);
end;

procedure TFormMain.LoadInlineOptions;
var
  Ini: TIniFile;
begin
  LoadMaskHistory('RenameMasks', ComboRenameMask.Items, DefaultRenameMasks);
  LoadMaskHistory('FileToTagMasks', ComboF2TMask.Items, DefaultF2TMasks);
  Ini := OpenSettings;
  try
    ComboRenameMask.Text := Ini.ReadString('Rename', 'Mask', ComboRenameMask.Items[0]);
    SetCaseControls(TCaseMode(Ini.ReadInteger('Rename', 'Case', 0)), CheckRenameCase,
      RadioRenameLower, RadioRenameUpper, RadioRenameTitle, RadioRenameSentence);
    CheckRenameUnderscores.Checked := Ini.ReadBool('Rename', 'Underscores', False);
    CheckRenamePadTrack.Checked := Ini.ReadBool('Rename', 'PadTrack', True);
    ComboF2TMask.Text := Ini.ReadString('FileToTag', 'Mask', ComboF2TMask.Items[0]);
    SetCaseControls(TCaseMode(Ini.ReadInteger('FileToTag', 'Case', 0)), CheckF2TCase,
      RadioF2TLower, RadioF2TUpper, RadioF2TTitle, RadioF2TSentence);
    CheckF2TUnderscores.Checked := Ini.ReadBool('FileToTag', 'Underscores', True);
  finally
    Ini.Free;
  end;
end;

{ The dialogs read the same settings, so "Forhåndsvis..." opens with the inline mask. }
procedure TFormMain.SaveInlineOptions;
var
  Ini: TIniFile;
begin
  Ini := OpenSettings;
  try
    Ini.WriteString('Rename', 'Mask', ComboRenameMask.Text);
    Ini.WriteInteger('Rename', 'Case', Ord(RenameOptions.CaseMode));
    Ini.WriteBool('Rename', 'Underscores', CheckRenameUnderscores.Checked);
    Ini.WriteBool('Rename', 'PadTrack', CheckRenamePadTrack.Checked);
    Ini.WriteString('FileToTag', 'Mask', ComboF2TMask.Text);
    Ini.WriteInteger('FileToTag', 'Case', Ord(F2TCaseMode));
    Ini.WriteBool('FileToTag', 'Underscores', CheckF2TUnderscores.Checked);
  finally
    Ini.Free;
  end;
end;

procedure TFormMain.InlineOptionChange(Sender: TObject);
begin
  if FLoading then Exit;
  PanelRenameCase.Enabled := CheckRenameCase.Checked;
  PanelF2TCase.Enabled := CheckF2TCase.Checked;
  UpdateInlinePreviews;
end;

procedure TFormMain.UpdateInlinePreviews;
var
  Info: TAudioInfo;
  NewName, Missing, S: string;
  M: TFileNameMatch;
  F: TTagField;
begin
  PanelRenameCase.Enabled := CheckRenameCase.Checked;
  PanelF2TCase.Enabled := CheckF2TCase.Checked;
  Info := FocusedInfo;
  if (Info = nil) and (FView.Count > 0) then Info := Item(0);
  if Info = nil then
  begin
    LabelRenamePreview.Caption := '';
    LabelF2TPreview.Caption := '';
    Exit;
  end;
  // Rename: the new name of the focused file
  NewName := ExpandRenameMask(ComboRenameMask.Text, Info, 1, 2, RenameOptions, Missing);
  if Missing <> '' then
    LabelRenamePreview.Caption := 'Mangler: ' + Missing
  else if NewName = '' then
    LabelRenamePreview.Caption := '(ugyldig maske)'
  else if SameFileName(ExtractFileDir(NewName), ExtractFileDir(Info.FileName)) then
    LabelRenamePreview.Caption := ExtractFileName(NewName)
  else
    LabelRenamePreview.Caption := ExtractRelativePath(IncludeTrailingPathDelimiter(ExtractFileDir(Info.FileName)), NewName);
  // Tags from file name: what is read out of the focused file's name
  M := MatchFileName(ComboF2TMask.Text, Info.FileName, CheckF2TUnderscores.Checked, F2TCaseMode);
  if not M.Ok then
    LabelF2TPreview.Caption := '(filnavnet passer ikke til masken)'
  else
  begin
    S := '';
    for F := Low(TTagField) to High(TTagField) do
      if F in M.Used then
      begin
        if S <> '' then S := S + '   ';
        S := S + TagFieldCaptions[F] + ': ' + M.Values[F];
      end;
    LabelF2TPreview.Caption := S;
  end;
end;

procedure TFormMain.ButtonVarsClick(Sender: TObject);
var
  I, Bar: Integer;
  M: TMenuItem;
  P: TPoint;
  Btn: TButton;
begin
  Btn := Sender as TButton;
  if Btn = ButtonRenameVars then FVarsTarget := ComboRenameMask else FVarsTarget := ComboF2TMask;
  PopupVars.Items.Clear;
  if FVarsTarget = ComboRenameMask then
  begin
    for I := 0 to High(RenameVars) do
    begin
      M := TMenuItem.Create(PopupVars);
      Bar := Pos('|', RenameVars[I]);
      if Copy(RenameVars[I], 1, Bar - 1) = '-' then M.Caption := '-'
      else M.Caption := Copy(RenameVars[I], 1, Bar - 1) + #9 + Copy(RenameVars[I], Bar + 1, MaxInt);
      M.Tag := I;
      M.OnClick := @VarItemClick;
      PopupVars.Items.Add(M);
    end;
  end
  else
    for I := 0 to High(F2TVars) do
    begin
      M := TMenuItem.Create(PopupVars);
      Bar := Pos('|', F2TVars[I]);
      if Copy(F2TVars[I], 1, Bar - 1) = '-' then M.Caption := '-'
      else M.Caption := Copy(F2TVars[I], 1, Bar - 1) + #9 + Copy(F2TVars[I], Bar + 1, MaxInt);
      M.Tag := I;
      M.OnClick := @VarItemClick;
      PopupVars.Items.Add(M);
    end;
  P := Btn.ClientToScreen(Point(0, Btn.Height));
  PopupVars.PopUp(P.X, P.Y);
end;

procedure TFormMain.VarItemClick(Sender: TObject);
var
  Code: string;
  Idx: Integer;
begin
  Idx := (Sender as TMenuItem).Tag;
  if FVarsTarget = ComboRenameMask then Code := RenameVars[Idx] else Code := F2TVars[Idx];
  Code := Copy(Code, 1, Pos('|', Code) - 1);
  // Complete examples replace the mask; single codes are inserted at the cursor.
  if Pos('Eksempel', (Sender as TMenuItem).Caption) > 0 then
    FVarsTarget.Text := Code
  else
    FVarsTarget.SelText := Code;
  FVarsTarget.SetFocus;
  UpdateInlinePreviews;
end;

procedure TFormMain.ButtonRenamePreviewClick(Sender: TObject);
begin
  SaveInlineOptions;
  ActRenameDialogExecute(Sender);
end;

procedure TFormMain.ButtonRenameDoClick(Sender: TObject);
var
  Items: TAudioInfoArray;
  Plan: TRenamePlan;
  Log: TRenameLog;
  OkCount, Skipped, I: Integer;
  Examples, Problems: string;
begin
  if not RequireTargets(Items) then Exit;
  Plan := PlanRename(Items, ComboRenameMask.Text, RenameOptions);
  OkCount := CountStatus(Plan, rsOk);
  Skipped := Length(Plan) - OkCount - CountStatus(Plan, rsUnchanged);
  if OkCount = 0 then
  begin
    Problems := '';
    for I := 0 to High(Plan) do
      if (Plan[I].Status <> rsUnchanged) and (Length(Problems) < 600) then
        Problems := Problems + ExtractFileName(Plan[I].OldName) + ': ' + RenameStatusText[Plan[I].Status] +
          IfThen(Plan[I].Detail <> '', ' (' + Plan[I].Detail + ')', '') + LineEnding;
    if Problems = '' then Problems := 'Alle filer har allerede det navn, masken giver.';
    MessageDlg('Intet at omdøbe', Problems, mtInformation, [mbOK], 0);
    Exit;
  end;
  Examples := '';
  for I := 0 to High(Plan) do
    if (Plan[I].Status = rsOk) and (Length(Examples) < 400) then
      Examples := Examples + ExtractFileName(Plan[I].OldName) + '  →  ' + ExtractFileName(Plan[I].NewName) + LineEnding;
  if MessageDlg('Omdøb filer', Format('Omdøb %d filer?%s', [OkCount,
    IfThen(Skipped > 0, Format(' (%d springes over - brug "Forhåndsvis..." for at se hvorfor)', [Skipped]), '')]) +
    LineEnding + LineEnding + Examples, mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  AddMaskToHistory('RenameMasks', ComboRenameMask.Text, ComboRenameMask.Items);
  SaveInlineOptions;
  Screen.Cursor := crHourGlass;
  try
    Log := ExecuteRename(Plan);
  finally
    Screen.Cursor := crDefault;
  end;
  if Length(Log) > 0 then SetUndoLog(Log, 'filer');
  SetMessage(Format('%d filer omdøbt, %d fejl', [Length(Log), CountStatus(Plan, rsFailed)]));
  if CountStatus(Plan, rsFailed) > 0 then
  begin
    Problems := '';
    for I := 0 to High(Plan) do
      if Plan[I].Status = rsFailed then
        Problems := Problems + ExtractFileName(Plan[I].OldName) + ': ' + Plan[I].Detail + LineEnding;
    MessageDlg('Nogle filer blev ikke omdøbt', Problems, mtWarning, [mbOK], 0);
  end;
  FileList.Invalidate;
  SelectionChanged;
end;

procedure TFormMain.MultiValueChange(Sender: TObject);
begin
  if FLoading then Exit;
  if Sender = EditMultiArtist then CheckMultiArtist.Checked := True
  else if Sender = EditMultiAlbum then CheckMultiAlbum.Checked := True
  else if Sender = EditMultiAlbumArtist then CheckMultiAlbumArtist.Checked := True
  else if Sender = EditMultiYear then CheckMultiYear.Checked := True
  else if Sender = ComboMultiGenre then CheckMultiGenre.Checked := True
  else if Sender = EditMultiComment then CheckMultiComment.Checked := True;
end;

procedure TFormMain.ButtonMultiCopyClick(Sender: TObject);
var
  Info: TAudioInfo;
begin
  Info := FocusedInfo;
  if Info = nil then Exit;
  FLoading := True;
  try
    EditMultiArtist.Text := Info.Fields[tfArtist];
    EditMultiAlbum.Text := Info.Fields[tfAlbum];
    EditMultiAlbumArtist.Text := Info.Fields[tfAlbumArtist];
    EditMultiYear.Text := Info.Fields[tfYear];
    ComboMultiGenre.Text := Info.Fields[tfGenre];
    EditMultiComment.Text := Info.Fields[tfComment];
  finally
    FLoading := False;
  end;
end;

{ Writes per-file values with progress in the status bar, then reports. }
procedure TFormMain.WriteFieldsBatch(const Items: TAudioInfoArray; const PerItem: array of TFieldValues;
  const PerItemFields: array of TTagFieldSet; const Cover: TBytes; const What: string);
var
  I, Saved, Failed, Skipped: Integer;
  Err: string;
  Skip: Boolean;
  Errors: TStringList;
begin
  Saved := 0;
  Failed := 0;
  Skipped := 0;
  Errors := TStringList.Create;
  Screen.Cursor := crHourGlass;
  try
    for I := 0 to High(Items) do
    begin
      if (PerItemFields[I] = []) and (Cover = nil) then Continue;
      SetMessage(Format('%s: %d af %d...', [What, I + 1, Length(Items)]));
      Application.ProcessMessages;
      if UpdateFileTags(Items[I], PerItem[I], PerItemFields[I], Cover, FKeepTimestamp, Err, Skip) then
        Inc(Saved)
      else if Skip then
        Inc(Skipped)
      else
      begin
        Inc(Failed);
        if Errors.Count < 20 then Errors.Add(ExtractFileName(Items[I].FileName) + ': ' + Err);
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  SetMessage(Format('%s: gemt i %d filer, %d fejl%s', [What, Saved, Failed,
    IfThen(Skipped > 0, Format(', %d sprunget over (filtype)', [Skipped]), '')]));
  if Errors.Count > 0 then
    MessageDlg('Nogle filer blev ikke gemt', Errors.Text, mtWarning, [mbOK], 0);
  Errors.Free;
  FCoverFile := '';
  FileList.Invalidate;
  SelectionChanged;
end;

procedure TFormMain.ButtonMultiSaveClick(Sender: TObject);
var
  Items: TAudioInfoArray;
  Values: TFieldValues;
  Fields: TTagFieldSet;
  PerItem: array of TFieldValues;
  PerFields: array of TTagFieldSet;
  Cleared: string;
  F: TTagField;
  I: Integer;
begin
  Fields := [];
  for F := Low(TTagField) to High(TTagField) do Values[F] := '';
  if CheckMultiArtist.Checked then begin Include(Fields, tfArtist); Values[tfArtist] := Trim(EditMultiArtist.Text); end;
  if CheckMultiAlbum.Checked then begin Include(Fields, tfAlbum); Values[tfAlbum] := Trim(EditMultiAlbum.Text); end;
  if CheckMultiAlbumArtist.Checked then begin Include(Fields, tfAlbumArtist); Values[tfAlbumArtist] := Trim(EditMultiAlbumArtist.Text); end;
  if CheckMultiYear.Checked then begin Include(Fields, tfYear); Values[tfYear] := Trim(EditMultiYear.Text); end;
  if CheckMultiGenre.Checked then begin Include(Fields, tfGenre); Values[tfGenre] := Trim(ComboMultiGenre.Text); end;
  if CheckMultiComment.Checked then begin Include(Fields, tfComment); Values[tfComment] := Trim(EditMultiComment.Text); end;
  if Fields = [] then
  begin
    MessageDlg('Sæt flueben ved de felter, der skal gemmes.', mtInformation, [mbOK], 0);
    Exit;
  end;
  if not RequireTargets(Items) then Exit;
  Cleared := '';
  for F in Fields do
    if Values[F] = '' then
    begin
      if Cleared <> '' then Cleared := Cleared + ', ';
      Cleared := Cleared + TagFieldCaptions[F];
    end;
  if MessageDlg('Gem tags', Format('Gem i %d filer?', [Length(Items)]) +
    IfThen(Cleared <> '', LineEnding + 'Disse felter bliver ryddet: ' + Cleared, ''),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  SetLength(PerItem, Length(Items));
  SetLength(PerFields, Length(Items));
  for I := 0 to High(Items) do
  begin
    PerItem[I] := Values;
    PerFields[I] := Fields;
  end;
  WriteFieldsBatch(Items, PerItem, PerFields, nil, 'Multi-fil-tag-editor');
end;

procedure TFormMain.ButtonF2TPreviewClick(Sender: TObject);
begin
  SaveInlineOptions;
  ActFileToTagDialogExecute(Sender);
end;

procedure TFormMain.ButtonF2TWriteClick(Sender: TObject);
var
  Items: TAudioInfoArray;
  PerItem: array of TFieldValues;
  PerFields: array of TTagFieldSet;
  M: TFileNameMatch;
  I, Ready, NoMatch: Integer;
  F: TTagField;
  AnyChange: Boolean;
begin
  if not RequireTargets(Items) then Exit;
  SetLength(PerItem, Length(Items));
  SetLength(PerFields, Length(Items));
  Ready := 0;
  NoMatch := 0;
  for I := 0 to High(Items) do
  begin
    PerFields[I] := [];
    M := MatchFileName(ComboF2TMask.Text, Items[I].FileName, CheckF2TUnderscores.Checked, F2TCaseMode);
    if not M.Ok then
    begin
      Inc(NoMatch);
      Continue;
    end;
    AnyChange := False;
    for F := Low(TTagField) to High(TTagField) do
    begin
      PerItem[I][F] := M.Values[F];
      if (F in M.Used) and (M.Values[F] <> Items[I].Fields[F]) then AnyChange := True;
    end;
    if AnyChange then
    begin
      PerFields[I] := M.Used;
      Inc(Ready);
    end;
  end;
  if Ready = 0 then
  begin
    MessageDlg('Intet at skrive', Format('Ingen filer ændres (%d passer ikke til masken). ' +
      'Brug "Forhåndsvis..." for at se detaljer.', [NoMatch]), mtInformation, [mbOK], 0);
    Exit;
  end;
  if MessageDlg('Skriv tags', Format('Skriv tags fra filnavnet i %d filer?%s', [Ready,
    IfThen(NoMatch > 0, Format(' (%d passer ikke til masken og springes over)', [NoMatch]), '')]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  AddMaskToHistory('FileToTagMasks', ComboF2TMask.Text, ComboF2TMask.Items);
  SaveInlineOptions;
  WriteFieldsBatch(Items, PerItem, PerFields, nil, 'Tags fra filnavn');
end;

{ TFormMain - covers }

function TFormMain.FindFolderCover(const Dir: string): string;
const
  Names: array[0..5] of string = ('folder.jpg', 'folder.png', 'cover.jpg', 'cover.png', 'front.jpg', 'front.png');
var
  N: string;
begin
  for N in Names do
    if FileExists(IncludeTrailingPathDelimiter(Dir) + N) then
      Exit(IncludeTrailingPathDelimiter(Dir) + N);
  Result := '';
end;

procedure TFormMain.ShowImageBytes(Image: TImage; const Data: TBytes);
var
  S: TBytesStream;
begin
  Image.Picture.Clear;
  if Data = nil then Exit;
  S := TBytesStream.Create(Data);
  try
    try
      if DetectImageMime(Data) = 'image/png' then
        Image.Picture.LoadFromStreamWithFileExt(S, 'png')
      else
        Image.Picture.LoadFromStreamWithFileExt(S, 'jpg');
    except
      Image.Picture.Clear;
    end;
  finally
    S.Free;
  end;
end;

procedure TFormMain.UpdateCovers;
var
  Info, Full: TAudioInfo;
  Dir, CoverPath: string;
  Data: TBytes;
  W, H: Integer;
begin
  if not PanelTools.Visible then Exit;
  Info := FocusedInfo;
  if (Info = nil) and (FView.Count > 0) then Info := Item(0);
  if Info <> nil then Dir := ExtractFileDir(Info.FileName) else Dir := FFolder;
  // folder cover
  if Dir <> FFolderCoverDir then
  begin
    FFolderCoverDir := Dir;
    CoverPath := FindFolderCover(Dir);
    if CoverPath = '' then
    begin
      ImageFolderCover.Picture.Clear;
      LabelFolderCoverInfo.Caption := 'Intet billede. Træk et billede hertil.';
    end
    else
    begin
      try
        Data := ReadFileBytes(CoverPath);
      except
        Data := nil;
      end;
      ShowImageBytes(ImageFolderCover, Data);
      ImageDimensions(Data, W, H);
      LabelFolderCoverInfo.Caption := Format('%s  %dx%d', [ExtractFileName(CoverPath), W, H]);
    end;
  end;
  // embedded cover of the focused file
  if Info = nil then
  begin
    FCoverFile := '';
    ImageFileCover.Picture.Clear;
    LabelFileCoverInfo.Caption := '';
    Exit;
  end;
  if Info.FileName = FCoverFile then Exit;
  FCoverFile := Info.FileName;
  ImageFileCover.Picture.Clear;
  if not Info.HasCover then
  begin
    LabelFileCoverInfo.Caption := 'Intet cover. Træk et billede hertil.';
    Exit;
  end;
  Full := ReadAudioInfo(Info.FileName, True);
  try
    if Length(Full.Pictures) > 0 then
    begin
      ShowImageBytes(ImageFileCover, Full.Pictures[0].Data);
      ImageDimensions(Full.Pictures[0].Data, W, H);
      LabelFileCoverInfo.Caption := Format('%s  %dx%d  (%d billede%s)', [PictureTypeName(Full.Pictures[0].PicType),
        W, H, Length(Full.Pictures), IfThen(Length(Full.Pictures) = 1, '', 'r')]);
    end;
  finally
    Full.Free;
  end;
end;

procedure TFormMain.FormDropFiles(Sender: TObject; const FileNames: array of string);
var
  P: TPoint;
  Img, Dir, Target: string;
  I: Integer;
  Data: TBytes;
  Items: TAudioInfoArray;
  PerItem: array of TFieldValues;
  PerFields: array of TTagFieldSet;
  Info: TAudioInfo;
  CoverStream: TFileStream;

  function Over(C: TControl): Boolean;
  var
    TL: TPoint;
  begin
    TL := C.ClientToScreen(Point(0, 0));
    Result := C.Visible and (P.X >= TL.X) and (P.Y >= TL.Y) and
      (P.X < TL.X + C.Width) and (P.Y < TL.Y + C.Height);
  end;

begin
  if Length(FileNames) = 0 then Exit;
  P := Mouse.CursorPos;
  // A folder dropped anywhere opens it.
  if DirectoryExists(FileNames[0]) then
  begin
    Navigate(FileNames[0]);
    Exit;
  end;
  Img := '';
  for I := 0 to High(FileNames) do
    if IsImageFile(FileNames[I]) then
    begin
      Img := FileNames[I];
      Break;
    end;
  if Img = '' then Exit;
  try
    Data := ReadFileBytes(Img);
  except
    on E: Exception do
    begin
      MessageDlg(E.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;
  if (DetectImageMime(Data, '') <> 'image/jpeg') and (DetectImageMime(Data, '') <> 'image/png') then
  begin
    MessageDlg('Kun JPEG- og PNG-billeder kan bruges som cover.', mtWarning, [mbOK], 0);
    Exit;
  end;

  if Over(PanelFolderCover) then
  begin
    Info := FocusedInfo;
    if Info <> nil then Dir := ExtractFileDir(Info.FileName) else Dir := FFolder;
    if DetectImageMime(Data) = 'image/png' then Target := 'folder.png' else Target := 'folder.jpg';
    Target := IncludeTrailingPathDelimiter(Dir) + Target;
    if FileExists(Target) and (MessageDlg('Mappens cover', Format('%s findes allerede. Erstat det?',
      [ExtractFileName(Target)]), mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then Exit;
    try
      CoverStream := TFileStream.Create(Target, fmCreate);
      try
        WriteBytes(CoverStream, Data);
      finally
        CoverStream.Free;
      end;
    except
      on E: Exception do
      begin
        MessageDlg('Billedet kunne ikke gemmes:' + LineEnding + E.Message, mtError, [mbOK], 0);
        Exit;
      end;
    end;
    FFolderCoverDir := '';
    UpdateCovers;
    SetMessage('Mappens cover gemt som ' + ExtractFileName(Target));
  end
  else if Over(PanelFileCover) then
  begin
    if not RequireTargets(Items) then Exit;
    if MessageDlg('Filens cover', Format('Sæt billedet som forside-cover i %d filer?', [Length(Items)]),
      mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
    SetLength(PerItem, Length(Items));
    SetLength(PerFields, Length(Items));
    for I := 0 to High(Items) do
    begin
      PerItem[I] := FieldValuesOf(Items[I]);
      PerFields[I] := [];
    end;
    WriteFieldsBatch(Items, PerItem, PerFields, Data, 'Cover');
  end;
end;

{ TFormMain - filter }

procedure TFormMain.ButtonFilterApplyClick(Sender: TObject);
begin
  FFilterText := UTF8LowerCase(Trim(EditFilter.Text));
  FFilterField := ComboFilterField.ItemIndex;
  RebuildView;
end;

procedure TFormMain.EditFilterKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    Key := 0;
    ButtonFilterApplyClick(nil);
  end;
end;

procedure TFormMain.ButtonHideSelectedClick(Sender: TObject);
var
  Info: TAudioInfo;
begin
  for Info in SelectedItems do Info.Hidden := True;
  FileList.ClearSelection;
  RebuildView;
end;

procedure TFormMain.ButtonShowAllClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to FItems.Count - 1 do TAudioInfo(FItems[I]).Hidden := False;
  EditFilter.Text := '';
  FFilterText := '';
  RebuildView;
end;

procedure TFormMain.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_ESCAPE) and (ActiveControl = EditFilter) and (EditFilter.Text <> '') then
  begin
    Key := 0;
    ButtonShowAllClick(nil);
  end;
end;

{ TFormMain - actions }

procedure TFormMain.ActOpenFolderExecute(Sender: TObject);
var
  Dir: string;
begin
  Dir := FFolder;
  if SelectDirectory('Vælg mappe', FFolder, Dir) then Navigate(Dir);
end;

procedure TFormMain.ActRefreshExecute(Sender: TObject);
begin
  if FFolder <> '' then StartScan;
end;

procedure TFormMain.ActEditTagExecute(Sender: TObject);
begin
  EditSelected;
end;

procedure TFormMain.ActMultiEditExecute(Sender: TObject);
var
  Items: TAudioInfoArray;
  ScopeCaption: string;
  Prefer: Boolean;
begin
  if not RequireTargets(Items) then Exit;
  TargetItems(ScopeCaption, Prefer);
  TFormMultiEdit.Execute(Items, ScopeCaption, FKeepTimestamp);
  FActKeepDate.Checked := FKeepTimestamp;
  FCoverFile := '';
  FileList.Invalidate;
  SelectionChanged;
end;

procedure TFormMain.ActRenameDialogExecute(Sender: TObject);
var
  Log: TRenameLog;
  Subset: TAudioInfoArray;
  SubsetCaption: string;
  Prefer: Boolean;
begin
  if not CanStartBatch or (FView.Count = 0) then Exit;
  SaveInlineOptions;
  Subset := TargetItems(SubsetCaption, Prefer);
  Log := TFormRename.Execute(AllItems, Subset, SubsetCaption, Prefer);
  if Length(Log) > 0 then SetUndoLog(Log, 'filer');
  FLoading := True;
  try
    LoadInlineOptions; // the dialog may have changed mask/options
  finally
    FLoading := False;
  end;
  FileList.Invalidate;
  SelectionChanged;
end;

procedure TFormMain.ActRenameFolderExecute(Sender: TObject);
var
  Log: TRenameLog;
  Subset: TAudioInfoArray;
  SubsetCaption: string;
  Prefer: Boolean;
begin
  if not CanStartBatch or (FView.Count = 0) then Exit;
  Subset := TargetItems(SubsetCaption, Prefer);
  Log := TFormRename.Execute(AllItems, Subset, SubsetCaption, Prefer, True);
  if Length(Log) > 0 then
  begin
    ApplyRenameLog(Log, False);
    SetUndoLog(Log, 'mapper');
  end;
  SelectionChanged;
end;

procedure TFormMain.ActFileToTagDialogExecute(Sender: TObject);
var
  Subset: TAudioInfoArray;
  SubsetCaption: string;
  Prefer: Boolean;
begin
  if not CanStartBatch or (FView.Count = 0) then Exit;
  SaveInlineOptions;
  Subset := TargetItems(SubsetCaption, Prefer);
  TFormFileToTag.Execute(AllItems, Subset, SubsetCaption, Prefer, FKeepTimestamp);
  FActKeepDate.Checked := FKeepTimestamp;
  FLoading := True;
  try
    LoadInlineOptions;
  finally
    FLoading := False;
  end;
  FileList.Invalidate;
  SelectionChanged;
end;

procedure TFormMain.ActTracksExecute(Sender: TObject);
var
  Subset: TAudioInfoArray;
  SubsetCaption: string;
  Prefer: Boolean;
begin
  if not CanStartBatch or (FView.Count = 0) then Exit;
  Subset := TargetItems(SubsetCaption, Prefer);
  TFormTrackTools.Execute(AllItems, Subset, SubsetCaption, Prefer, FKeepTimestamp);
  FActKeepDate.Checked := FKeepTimestamp;
  FileList.Invalidate;
  SelectionChanged;
end;

procedure TFormMain.ActWebExecute(Sender: TObject);
var
  Items: TAudioInfoArray;
  ScopeCaption: string;
  Prefer, OneFolder: Boolean;
  I: Integer;
begin
  if not CanStartBatch or (FView.Count = 0) then Exit;
  Items := TargetItems(ScopeCaption, Prefer);
  if not Prefer then
  begin
    // Nothing ticked and at most one file selected: take the whole list if it is one album folder.
    Items := AllItems;
    OneFolder := True;
    for I := 1 to High(Items) do
      if not SameFileName(ExtractFileDir(Items[I].FileName), ExtractFileDir(Items[0].FileName)) then
        OneFolder := False;
    if not OneFolder then
    begin
      MessageDlg('Afkryds (☑) eller markér filerne fra ét album, og prøv igen.', mtInformation, [mbOK], 0);
      Exit;
    end;
  end;
  TFormWebLookup.Execute(Items, FKeepTimestamp);
  FActKeepDate.Checked := FKeepTimestamp;
  FCoverFile := '';
  FileList.Invalidate;
  SelectionChanged;
end;

procedure TFormMain.ActPlayExecute(Sender: TObject);
var
  Info: TAudioInfo;
begin
  Info := FocusedInfo;
  if Info <> nil then OpenDocument(Info.FileName);
end;

procedure TFormMain.ActShowInExplorerExecute(Sender: TObject);
var
  Info: TAudioInfo;
begin
  Info := FocusedInfo;
  if Info <> nil then
    ExecuteProcess('explorer.exe', '/select,"' + Info.FileName + '"')
  else if FFolder <> '' then
    OpenDocument(FFolder);
end;

procedure TFormMain.ActExitExecute(Sender: TObject);
begin
  Close;
end;

procedure TFormMain.ActSelectAllExecute(Sender: TObject);
begin
  if ActiveControl is TCustomEdit then
    TCustomEdit(ActiveControl).SelectAll
  else
  begin
    FileList.SelectAll;
    SelectionChanged;
  end;
end;

procedure TFormMain.ActSelectNoneExecute(Sender: TObject);
begin
  FileList.ClearSelection;
  SelectionChanged;
end;

procedure TFormMain.ActCheckSelectedExecute(Sender: TObject);
begin
  SetChecked(SelectedItems, True);
end;

procedure TFormMain.ActUncheckSelectedExecute(Sender: TObject);
begin
  SetChecked(SelectedItems, False);
end;

procedure TFormMain.ActCheckAllExecute(Sender: TObject);
begin
  SetChecked(AllItems, True);
end;

procedure TFormMain.ActUncheckAllExecute(Sender: TObject);
begin
  SetChecked(AllItems, False);
end;

procedure TFormMain.ActInvertChecksExecute(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to FView.Count - 1 do Item(I).Checked := not Item(I).Checked;
  ChecksChanged;
end;

procedure TFormMain.ActCopyTagExecute(Sender: TObject);
var
  Info: TAudioInfo;
begin
  Info := FocusedInfo;
  if Info = nil then Exit;
  FClip := FieldValuesOf(Info);
  FHasClip := True;
  FActPaste.Enabled := True;
  SetMessage('Tag kopieret fra ' + ExtractFileName(Info.FileName));
end;

procedure TFormMain.ActPasteTagExecute(Sender: TObject);
var
  Items: TAudioInfoArray;
  PerItem: array of TFieldValues;
  PerFields: array of TTagFieldSet;
  I: Integer;
  Fields: TTagFieldSet;
begin
  if not FHasClip or not RequireTargets(Items) then Exit;
  Fields := [Low(TTagField)..High(TTagField)] - [tfTitle, tfTrack];
  if MessageDlg('Indsæt tag', Format('Indsæt det kopierede tag i %d filer?' + LineEnding +
    'Alle felter undtagen titel og spornummer overskrives.', [Length(Items)]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  SetLength(PerItem, Length(Items));
  SetLength(PerFields, Length(Items));
  for I := 0 to High(Items) do
  begin
    PerItem[I] := FClip;
    PerFields[I] := Fields;
  end;
  WriteFieldsBatch(Items, PerItem, PerFields, nil, 'Indsæt tag');
end;

procedure TFormMain.ActFindExecute(Sender: TObject);
begin
  PanelFilter.Visible := True;
  FActFilter.Checked := True;
  ActiveControl := EditFilter;
end;

procedure TFormMain.ActToolsPanelExecute(Sender: TObject);
begin
  PanelTools.Visible := FActToolsPanel.Checked;
  if PanelTools.Visible then
  begin
    FFolderCoverDir := '';
    FCoverFile := '';
    UpdateCovers;
  end;
end;

procedure TFormMain.ActFoldersExecute(Sender: TObject);
begin
  if Sender <> FActFolders then FActFolders.Checked := False; // the panel's own close button
  PanelFolders.Visible := FActFolders.Checked;
  Splitter1.Visible := FActFolders.Checked;
  if Splitter1.Visible then Splitter1.Left := PanelFolders.Width + 1;
end;

procedure TFormMain.ActAddressExecute(Sender: TObject);
begin
  PanelAddress.Visible := FActAddress.Checked;
end;

procedure TFormMain.ActFilterBarExecute(Sender: TObject);
begin
  PanelFilter.Visible := FActFilter.Checked;
end;

procedure TFormMain.ActSubfoldersExecute(Sender: TObject);
begin
  if FFolder <> '' then StartScan;
end;

procedure TFormMain.ActKeepDateExecute(Sender: TObject);
begin
  FKeepTimestamp := FActKeepDate.Checked;
end;

procedure TFormMain.ActTabRenameExecute(Sender: TObject);
begin
  ShowTool(0);
end;

procedure TFormMain.ActTabMultiExecute(Sender: TObject);
begin
  ShowTool(1);
end;

procedure TFormMain.ActTabFileToTagExecute(Sender: TObject);
begin
  ShowTool(2);
end;

procedure WritePlaylist(const FileName: string; const Items: TAudioInfoArray);
var
  L: TStringList;
  Info: TAudioInfo;
  Dir, Path, Name: string;
begin
  Dir := IncludeTrailingPathDelimiter(ExtractFileDir(FileName));
  L := TStringList.Create;
  try
    L.Add('#EXTM3U');
    for Info in Items do
    begin
      Name := Info.Fields[tfTitle];
      if Info.Fields[tfArtist] <> '' then Name := Info.Fields[tfArtist] + ' - ' + Name;
      if Info.Fields[tfTitle] = '' then Name := ChangeFileExt(ExtractFileName(Info.FileName), '');
      L.Add(Format('#EXTINF:%d,%s', [Round(Info.Duration), Name]));
      Path := Info.FileName;
      // relative paths keep the playlist working when the music folder moves
      if SameFileName(Copy(Path, 1, Length(Dir)), Dir) then Path := Copy(Path, Length(Dir) + 1, MaxInt);
      L.Add(Path);
    end;
    L.WriteBOM := False;
    L.SaveToFile(FileName);
  finally
    L.Free;
  end;
end;

procedure SavePlaylistDialog(Owner: TFormMain; const Items: TAudioInfoArray);
var
  D: TSaveDialog;
begin
  if Length(Items) = 0 then
  begin
    MessageDlg('Der er ingen filer at gemme.', mtInformation, [mbOK], 0);
    Exit;
  end;
  D := TSaveDialog.Create(Owner);
  try
    D.Title := 'Gem playliste';
    D.Filter := 'Playliste (UTF-8) (*.m3u8)|*.m3u8|Playliste (*.m3u)|*.m3u';
    D.DefaultExt := 'm3u8';
    D.InitialDir := ExtractFileDir(Items[0].FileName);
    D.FileName := ExtractFileName(ExtractFileDir(Items[0].FileName)) + '.m3u8';
    D.Options := D.Options + [ofOverwritePrompt];
    if D.Execute then
    begin
      WritePlaylist(D.FileName, Items);
      Owner.SetMessage(Format('Playliste med %d filer gemt: %s', [Length(Items), ExtractFileName(D.FileName)]));
    end;
  finally
    D.Free;
  end;
end;

procedure TFormMain.ActPlaylistCheckedExecute(Sender: TObject);
var
  ScopeCaption: string;
  Prefer: Boolean;
begin
  SavePlaylistDialog(Self, TargetItems(ScopeCaption, Prefer));
end;

procedure TFormMain.ActPlaylistAllExecute(Sender: TObject);
begin
  SavePlaylistDialog(Self, AllItems);
end;

procedure TFormMain.ActDiscogsTokenExecute(Sender: TObject);
var
  Value: string;
  Ini: TIniFile;
begin
  Ini := OpenSettings;
  try
    Value := Ini.ReadString('Discogs', 'Token', '');
    if not InputQuery('Discogs-token',
      'Lav et personligt token på discogs.com: Settings > Developers > Generate new token.' + LineEnding +
      'Indsæt det her (det gemmes kun på denne computer, i TagKlons indstillingsfil):', True, Value) then Exit;
    Ini.WriteString('Discogs', 'Token', Trim(Value));
  finally
    Ini.Free;
  end;
  SetMessage(IfThen(Trim(Value) = '', 'Discogs-token fjernet', 'Discogs-token gemt'));
end;

procedure TFormMain.ActShortcutsExecute(Sender: TObject);
begin
  MessageDlg('Tastaturgenveje',
    'Enter / dobbeltklik'#9'Rediger tag for den markerede fil' + LineEnding +
    'Mellemrum'#9#9'Afkryds/fjern afkrydsning på markerede filer' + LineEnding +
    'F4'#9#9#9'Omdøb filer' + LineEnding +
    'Ctrl+F4'#9#9'Multi-fil-tag-editor' + LineEnding +
    'Shift+F4'#9#9'Tags fra filnavn' + LineEnding +
    'F8'#9#9#9'Vis/skjul værktøjspanelet' + LineEnding +
    'F5'#9#9#9'Opdater fillisten' + LineEnding +
    'Ctrl+E'#9#9'Rediger flere filer' + LineEnding +
    'Ctrl+T'#9#9'Spornumre' + LineEnding +
    'Ctrl+W'#9#9'Web-opslag' + LineEnding +
    'Ctrl+Z'#9#9'Fortryd omdøbning' + LineEnding +
    'Ctrl+Shift+C / V'#9'Kopiér / indsæt tag' + LineEnding +
    'Ctrl+F'#9#9'Filtrér listen (Esc rydder filteret)' + LineEnding +
    'Ctrl+O'#9#9'Åbn mappe' + LineEnding +
    'Alt+Backspace'#9'Mappe op', mtInformation, [mbOK], 0);
end;

procedure TFormMain.ActAboutExecute(Sender: TObject);
begin
  MessageDlg('Om TagKlon',
    'TagKlon - tag-editor og musikorganisator' + LineEnding +
    'Lavet i Lazarus / Free Pascal.' + LineEnding + LineEnding +
    'Web-data: MusicBrainz (musicbrainz.org), Cover Art Archive og Discogs.' + LineEnding +
    'Ikoner: Lazarus "general_purpose" af Roland Hahn (CC0).' + LineEnding + LineEnding +
    'Indstillinger: ' + SettingsFileName, mtInformation, [mbOK], 0);
end;

procedure TFormMain.ActFolderUpExecute(Sender: TObject);
var
  ParentDir: string;
begin
  ParentDir := ExtractFileDir(FFolder);
  if (ParentDir <> '') and (ParentDir <> FFolder) then Navigate(ParentDir);
end;

procedure TFormMain.ActFavoritesExecute(Sender: TObject);
var
  M: TMenuItem;
  I: Integer;
  P: TPoint;
begin
  PopupFavorites.Items.Clear;
  M := TMenuItem.Create(PopupFavorites);
  M.Caption := 'Tilføj den åbne mappe';
  M.ImageIndex := icoFavorites;
  M.OnClick := @FavoriteAddClick;
  M.Enabled := (FFolder <> '') and (FFavorites.IndexOf(FFolder) < 0);
  PopupFavorites.Items.Add(M);
  M := TMenuItem.Create(PopupFavorites);
  M.Caption := 'Fjern den åbne mappe';
  M.OnClick := @FavoriteRemoveClick;
  M.Enabled := FFavorites.IndexOf(FFolder) >= 0;
  PopupFavorites.Items.Add(M);
  if FFavorites.Count > 0 then
  begin
    M := TMenuItem.Create(PopupFavorites);
    M.Caption := '-';
    PopupFavorites.Items.Add(M);
  end;
  for I := 0 to FFavorites.Count - 1 do
  begin
    M := TMenuItem.Create(PopupFavorites);
    M.Caption := FFavorites[I];
    M.Tag := I;
    M.OnClick := @FavoriteClick;
    PopupFavorites.Items.Add(M);
  end;
  P := ToolBarFolders.ClientToScreen(Point(0, ToolBarFolders.Height));
  PopupFavorites.PopUp(P.X, P.Y);
end;

procedure TFormMain.FavoriteClick(Sender: TObject);
begin
  Navigate(FFavorites[(Sender as TMenuItem).Tag]);
end;

procedure TFormMain.FavoriteAddClick(Sender: TObject);
begin
  if (FFolder <> '') and (FFavorites.IndexOf(FFolder) < 0) then FFavorites.Add(FFolder);
end;

procedure TFormMain.FavoriteRemoveClick(Sender: TObject);
var
  I: Integer;
begin
  I := FFavorites.IndexOf(FFolder);
  if I >= 0 then FFavorites.Delete(I);
end;

procedure TFormMain.ActNewFolderExecute(Sender: TObject);
var
  NewName, Dir: string;
begin
  if FFolder = '' then Exit;
  NewName := '';
  if not InputQuery('Ny mappe', 'Navn på den nye mappe i ' + FFolder + ':', NewName) then Exit;
  NewName := SanitizeNamePart(NewName);
  if NewName = '' then Exit;
  Dir := IncludeTrailingPathDelimiter(FFolder) + NewName;
  if DirectoryExists(Dir) or not CreateDir(Dir) then
  begin
    MessageDlg('Mappen kunne ikke oprettes:' + LineEnding + Dir, mtWarning, [mbOK], 0);
    Exit;
  end;
  try
    ShellTree.UpdateView(FFolder);
  except
  end;
  SetMessage('Mappe oprettet: ' + NewName);
end;

procedure TFormMain.ActRefreshTreeExecute(Sender: TObject);
begin
  try
    ShellTree.UpdateView(FFolder);
  except
  end;
end;

{ TFormMain - settings }

procedure TFormMain.LoadSettings;
var
  Ini: TIniFile;
  Start, S: string;
  I: Integer;
begin
  Start := '';
  Ini := OpenSettings;
  try
    Start := Ini.ReadString('Main', 'LastFolder', '');
    FActSubfolders.Checked := Ini.ReadBool('Main', 'Subfolders', False);
    FKeepTimestamp := Ini.ReadBool('Editor', 'KeepTimestamp', False);
    FActKeepDate.Checked := FKeepTimestamp;
    // Stored at 96 DPI; FormCreate runs before LCL scales the form to the screen DPI.
    PanelFolders.Width := Ini.ReadInteger('Main', 'TreeWidth', PanelFolders.Width);
    FActToolsPanel.Checked := Ini.ReadBool('View', 'ToolsPanel', True);
    FActFolders.Checked := Ini.ReadBool('View', 'Folders', True);
    FActAddress.Checked := Ini.ReadBool('View', 'Address', True);
    FActFilter.Checked := Ini.ReadBool('View', 'Filter', True);
    PageTools.ActivePageIndex := Ini.ReadInteger('View', 'ToolTab', 0);
    for I := 0 to 19 do
    begin
      S := Ini.ReadString('AddressHistory', 'Dir' + IntToStr(I), '');
      if S <> '' then ComboAddress.Items.Add(S);
    end;
    for I := 0 to 49 do
    begin
      S := Ini.ReadString('Favorites', 'Dir' + IntToStr(I), '');
      if S <> '' then FFavorites.Add(S);
    end;
  finally
    Ini.Free;
  end;
  PanelTools.Visible := FActToolsPanel.Checked;
  PanelAddress.Visible := FActAddress.Checked;
  PanelFilter.Visible := FActFilter.Checked;
  ActFoldersExecute(FActFolders);
  if (ParamCount > 0) and DirectoryExists(ParamStr(1)) then
    Start := ParamStr(1);
  if (Start = '') or not DirectoryExists(Start) then
    Start := GetUserDir + 'Music';
  if not DirectoryExists(Start) then
    Start := GetUserDir;
  try
    ShellTree.Path := Start;
  except
    // Folder vanished or is not reachable; the user can pick another.
  end;
  FFolder := ExcludeTrailingPathDelimiter(Start);
  AddAddressHistory(FFolder);
  StartScan;
end;

procedure TFormMain.SaveSettings;
var
  Ini: TIniFile;
  I: Integer;
begin
  Ini := OpenSettings;
  try
    Ini.WriteString('Main', 'LastFolder', FFolder);
    Ini.WriteBool('Main', 'Subfolders', FActSubfolders.Checked);
    Ini.WriteBool('Editor', 'KeepTimestamp', FKeepTimestamp);
    Ini.WriteInteger('Main', 'TreeWidth', ScaleFormTo96(PanelFolders.Width));
    Ini.WriteBool('View', 'ToolsPanel', FActToolsPanel.Checked);
    Ini.WriteBool('View', 'Folders', FActFolders.Checked);
    Ini.WriteBool('View', 'Address', FActAddress.Checked);
    Ini.WriteBool('View', 'Filter', FActFilter.Checked);
    Ini.WriteInteger('View', 'ToolTab', PageTools.ActivePageIndex);
    Ini.EraseSection('AddressHistory');
    for I := 0 to ComboAddress.Items.Count - 1 do
      Ini.WriteString('AddressHistory', 'Dir' + IntToStr(I), ComboAddress.Items[I]);
    Ini.EraseSection('Favorites');
    for I := 0 to FFavorites.Count - 1 do
      Ini.WriteString('Favorites', 'Dir' + IntToStr(I), FFavorites[I]);
  finally
    Ini.Free;
  end;
end;

end.
