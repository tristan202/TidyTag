unit MainForm;

{ Main window: menu and toolbar (built from one action table), a tools panel with the
  three everyday functions (rename, multi-file tag editor, tags from file name) plus
  folder/file cover panels, address and filter bars, folder tree and the file list. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ComCtrls, ExtCtrls,
  StdCtrls, ShellCtrls, Menus, ActnList, IniFiles, AudioTypes, ScanThread, RenameCore,
  BatchWrite, FieldTools, AppSettings, ID3Sync;

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
    FSwapA, FSwapB, FCopySrc, FCopyDst: TTagField; // last choices in the field dialogs
    FCopyOnlyEmpty: Boolean;
    FActionsMenu: TMenuItem;
    FActManageActions: TAction;
    FActAutoFitAfterScan: TAction;
    FActDeleteFiles: TAction;
    FActAutoResize: TAction;
    FLanguageMenu, FAlbumArtistMenu: TMenuItem; // radio submenus, kept in step with the dialog
    FTestTargetDir: string; // self-test: target of copy/move instead of a folder dialog
    FAutoYes: Boolean;
    FSyncDir: TSyncDirection;
    FSyncExisting: TSyncExisting;
    FRGAlbum, FRGSkip: Boolean;
    FRecentMenu: TMenuItem;
    FAutoLog: TStringList;
    FSortColumn: Integer;
    FSortDescending: Boolean;
    FKeepTimestamp: Boolean;
    FUndoLog: TRenameLog;
    FFilterText: string;
    FFilterField: Integer;     // 0 = file name, 1.. = tag field + 1, last = all fields
    FTagTypeFilter: Integer;   // index into TagTypeTokens, 0 = all
    FSort2Column: Integer;     // previous sort column, decides ties
    FSort2Descending: Boolean;
    CheckFilterWhole, CheckFilterCase: TCheckBox;
    ComboTagType: TComboBox;
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
    procedure ActMoveUpExecute(Sender: TObject);
    procedure ActMoveDownExecute(Sender: TObject);
    procedure ActExportImportExecute(Sender: TObject);
    procedure MoveSelected(Delta: Integer);
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
    procedure AddLanguageMenu(ParentItem: TMenuItem);
    // tag, cover and rename tools
    procedure RunFieldPlans(const Items: TAudioInfoArray; const Plans: array of TFieldPlan; const What: string);
    procedure SwapFields(A, B: TTagField);
    procedure ActSwapArtistTitleExecute(Sender: TObject);
    procedure ActSwapArtistAlbumExecute(Sender: TObject);
    procedure ActSwapAlbumTitleExecute(Sender: TObject);
    procedure ActSwapFieldsExecute(Sender: TObject);
    procedure ActCopyFieldExecute(Sender: TObject);
    procedure ActCleanSpacesExecute(Sender: TObject);
    procedure RefreshInfo(Info: TAudioInfo);
    procedure ActRemoveTagsExecute(Sender: TObject);
    procedure ActCoverToTagsExecute(Sender: TObject);
    procedure ActCoverFromTagsExecute(Sender: TObject);
    procedure ActRenameWordsExecute(Sender: TObject);
    procedure ActManageActionsExecute(Sender: TObject);
    procedure RebuildActionsMenu;
    procedure RenameActionClick(Sender: TObject);
    procedure DoCopyField(Src, Dst: TTagField; OnlyIfEmpty: Boolean);
    procedure BuildFilterExtras;
    procedure BuildVarHelp(Host: TLabel; const Codes: array of string; Rows: Integer;
      const Notes: string);
    procedure ChangeLanguage(const Code: string);
    procedure SyncSettingsMenus;
    procedure MaskEditorClick(Sender: TObject);
    function RenameMaskPreview(const Mask: string): string;
    procedure ActDeleteFolderCoversExecute(Sender: TObject);
    procedure ActResizeFileCoversExecute(Sender: TObject);
    procedure ActResizeFolderCoversExecute(Sender: TObject);
    procedure ActAutoResizeExecute(Sender: TObject);
    procedure ActCoverAsFolderExecute(Sender: TObject);
    procedure ResizeFileCovers;
    procedure ResizeFolderCovers;
    procedure ActDeleteFilesExecute(Sender: TObject);
    procedure ActCopyToExecute(Sender: TObject);
    procedure ActMoveToExecute(Sender: TObject);
    procedure CopyOrMoveTo(Move: Boolean; const Dir: string);
    function InScanScope(const Path: string): Boolean;
    procedure FilterOptionChange(Sender: TObject);
    procedure ActAutoFitExecute(Sender: TObject);
    procedure ActAutoFitAfterScanExecute(Sender: TObject);
    procedure ActRandomOrderExecute(Sender: TObject);
    procedure AutoFitColumns;
    procedure ActNameToolExecute(Sender: TObject);
    procedure RunNameTool(Tool: TNameTool);
    procedure ActID3SyncExecute(Sender: TObject);
    procedure RunID3Sync(Direction: TSyncDirection; Existing: TSyncExisting);
    procedure ActReplayGainExecute(Sender: TObject);
    procedure ActRemoveReplayGainExecute(Sender: TObject);
    procedure RunReplayGain(Album, SkipExisting: Boolean);
    procedure ActRenameManualExecute(Sender: TObject);
    procedure RenameFileDialog;
    procedure RenameFolderManual;
    function RenamePaths(Info: TAudioInfo; const OldName, NewName: string; var Log: TRenameLog): Boolean;
    procedure ActPropertiesExecute(Sender: TObject);
    procedure ActChangeExtExecute(Sender: TObject);
    procedure ActExpandFoldersExecute(Sender: TObject);
    procedure ActCollapseFoldersExecute(Sender: TObject);
    procedure ActPlayFolderExecute(Sender: TObject);
    procedure ActQuickPlaylistExecute(Sender: TObject);
    procedure ActGenresExecute(Sender: TObject);
    procedure RecentFolderClick(Sender: TObject);
    procedure RebuildRecentMenu;
    procedure ApplyViewOptions;
    procedure RefreshGenreCombos;
    procedure PlayWith(const FileName: string);
    procedure FileListCustomDrawSubItem(Sender: TCustomListView; Item: TListItem; SubItem: Integer;
      State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure AddAlbumArtistMenu(ParentItem: TMenuItem);
    procedure AlbumArtistClick(Sender: TObject);
    function LoadPasteFields: TTagFieldSet;
    procedure SavePasteFields(Fields: TTagFieldSet);
    procedure RunRenameAction(const Act: TRenameAction);
    // confirmations and messages that the self-test answers itself
    function AskYes(const Title, Msg: string; DlgType: TMsgDlgType = mtConfirmation): Boolean;
    procedure Inform(const Title, Msg: string; DlgType: TMsgDlgType = mtInformation);
  public
    { Developer check: "TidyTag.exe --selftest <folder> <report.txt>" runs the tag, cover
      and rename tools on the files of <folder> (use copies!) without dialogs. }
    procedure RunSelfTest(const ReportFile: string);
    procedure ActSettingsExecute(Sender: TObject);
  private
    procedure LanguageClick(Sender: TObject);
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
      const PerItemFields: array of TTagFieldSet; const Cover: TBytes; const What: string;
      const PerCover: TCoverArray = nil);
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
  FileToTagForm, FileNameTags, MultiEditForm, TrackToolsForm, WebLookupForm, ExportImportForm,
  Math, Language, Process, TagRemove, ToolDialogs, FileOps, CoverImage, Spin, ButtonPanel,
  ReplayGain, ID3Writer, ProgOptions;

resourcestring
  rsOmdoebFilManuelt = 'Omdøb fil...';
  rsOmdoebFilManueltHint = 'Ret navnet på den markerede fil (eller mappen, når mappetræet er aktivt)';
  rsOmdoebFilTitel = 'Omdøb fil (%d af %d)';
  rsNytNavn = 'Nyt navn:';
  rsForrige = '< Forrige';
  rsNaeste = 'Næste >';
  rsUgyldigtNavn = 'Navnet må ikke være tomt eller indeholde \ / : * ? " < > |';
  rsKunneIkkeOmdoebe = 'Kunne ikke omdøbe';
  rsManuelOmdoebning = 'manuel omdøbning';
  rsOmdoebMappeTitel = 'Omdøb mappe';
  rsEgenskaber = 'Egenskaber';
  rsEgenskaberHint = 'Vis Windows-egenskaber for den markerede fil';
  rsSkiftFiltype = 'Skift filtype';
  rsMp4TilM4a = '.mp4 → .m4a';
  rsTilM4b = '.mp4/.m4a/.m4p → .m4b (lydbog)';
  rsM4bTilM4a = '.m4b → .m4a';
  rsIngenFilerMedFiltypen = 'Ingen af filerne har den filtype.';
  rsFiltypeSkiftet = 'Filtype skiftet for %d filer';
  rsFiltypeFindes = '%s: findes allerede';
  rsUdvidUndermapper = 'Udvid undermapper';
  rsFoldMapperSammen = 'Fold alle mapper sammen';
  rsAfspilMappen = 'Afspil mappen';
  rsAfspilMappenHint = 'Afspil alle filer i listen som én playliste';
  rsSenesteMapper = 'Seneste mapper';
  rsGemPlaylisteHurtigt = 'Gem playliste hurtigt';
  rsGemPlaylisteHurtigtHint = 'Gem de afkrydsede (ellers markerede) filer som playliste uden dialog (navn og mappe fra Indstillinger)';
  rsPlaylisteFindesOverskriv = '%s findes allerede. Overskriv?';
  rsGenreliste = 'Genreliste...';
  rsGenrelisteHint = 'Vælg hvilke standardgenrer der vises, og tilføj dine egne';
  rsMarkerLavBitrate = 'Vis lav bitrate med rødt';
  rsGraenseKbit = 'Grænse (kbit/s):';
  rsMarkerUdenID3v1 = 'Vis MP3-filer uden ID3v1 med orange filnavn';
  rsSkjulFiltypenavne = 'Skjul filtypenavne';
  rsGitterlinjer = 'Gitterlinjer';
  rsSkriftstoerrelse = 'Skriftstørrelse (0 = standard):';
  rsStartmappe = 'Startmappe';
  rsSidsteMappe = 'Den sidste mappe';
  rsFastMappe = 'Fast mappe:';
  rsID3Unicode = 'ID3v2.3: gem altid tekst som Unicode (UTF-16)';
  rsAfspillereFane = 'Afspillere';
  rsAfspillereHjaelp = 'Ét program pr. linje: filtype=program, fx  flac=C:\Program Files\foobar2000\foobar2000.exe' +
    #13#10'"*" gælder alle andre filtyper, m3u8 bruges til "Afspil mappen". Uden linje bruges Windows'' standardprogram.';
  rsPlaylisterFane = 'Playlister';
  rsSkrivExtinf = 'Skriv #EXTINF-linjer (spilletid og titel)';
  rsExtinfTekst = 'Titel i #EXTINF:';
  rsFuldeStier = 'Fulde stier (ellers relative til playlisten)';
  rsPlaylisteMappe = 'Playliste-mappe (tom = filernes mappe):';
  rsHurtigGemNavn = 'Filnavn ved hurtig gem:';
  rsPlaylisteVarHjaelp = 'Masker som ved omdøbning, fx %1 - %2; %f er mappens navn.';
  rsBeregnReplayGain = 'Beregn ReplayGain...';
  rsBeregnReplayGainHint = 'Mål lydstyrken (EBU R128) og skriv ReplayGain-værdier i de afkrydsede filer';
  rsFjernReplayGain = 'Fjern ReplayGain...';
  rsFjernReplayGainHint = 'Slet ReplayGain-værdierne fra de afkrydsede filer';
  rsReplayGainTitel = 'ReplayGain';
  rsRGIntetAtGoere = 'Alle filerne har allerede ReplayGain.';
  rsRGAfbrudt = 'ReplayGain blev afbrudt - intet er gemt.';
  rsRGStille = 'stille - ingen gain';
  rsRGAlbumIkkeSkrevet = 'Album "%s": albumgain er ikke skrevet, fordi %d fil(er) ikke kunne måles.';
  rsRGNogleFiler = 'Nogle filer fik ikke ReplayGain';
  rsRGIngenHarRG = 'Ingen af filerne har ReplayGain.';
  rsRGFjernSpm = 'Fjern ReplayGain fra %d filer?';
  rsIndstillingerMenu = 'Indstillinger...';
  rsIndstillingerMenuHint = 'Alle indstillinger samlet ét sted';
  rsIndstillingerTitel = 'Indstillinger';
  rsGenerelt = 'Generelt';
  rsCoverFane = 'Cover';
  rsFillisteFane = 'Fillisten';
  rsOmdoebningOgWeb = 'Omdøbning og web';
  rsSkalerStoreCoverAutomatisk = 'Skalér store cover automatisk, når tags gemmes';
  rsStoersteSideSetting = 'Største side (pixel):';
  rsJpegKvalitetSetting = 'JPEG-kvalitet (1-100):';
  rsKonverterPngTilJpegSetting = 'Konvertér PNG til JPEG';
  rsRtUdgivelsesdato = '%rt|Udgivelsesdato (hele datoen)';
  rsDbitBitdybde = '%dbit|Bitdybde';
  rsEncKodetAf = '%enc|Kodet af';
  rsRndTilfaeldigtTal = '%rnd|Tilfældigt tal (4 cifre)';
  rsMaskeEditorMenu = 'Maske-editor...';
  rsMaskeEditorTitel = 'Maske-editor';
  rsSletMappeCover = 'Slet mappe-cover i de valgte mapper...';
  rsSletMappeCoverHint = 'Læg folder.jpg/cover.jpg/front.jpg (og .png) i papirkurven';
  rsSkalerCoverIFilerne = 'Skalér cover i filerne...';
  rsSkalerCoverIFilerneHint = 'Gør store billeder i filernes tag mindre (og evt. til JPEG)';
  rsSkalerMappeCover = 'Skalér mappe-cover...';
  rsSkalerMappeCoverHint = 'Gør store folder.jpg/cover.jpg-billeder mindre (og evt. til JPEG)';
  rsBrugFilensCoverSomMappeCover = 'Brug filens cover som mappe-cover';
  rsSkalerStoreCoverVedGem = 'Skalér store cover ved gem...';
  rsSkalerStoreCoverVedGemHint = 'Billeder større end den valgte størrelse gøres mindre, når tags gemmes';
  rsSkalerCover = 'Skalér cover';
  rsSkalerCoverIDFiler = 'Skalér billeder i %d filer til højst %d pixel?';
  rsSkalerCoverIDMapper = 'Skalér mappe-cover i %d mapper til højst %d pixel?';
  rsLaegDMappeCoverIPapirkurven = 'Læg %d cover-billeder fra %d mapper i papirkurven?';
  rsDenMarkeredeFilHarIntetCover = 'Den markerede fil har intet cover.';
  rsKopierTilMappe = 'Kopiér til mappe...';
  rsKopierTilMappeHint = 'Kopiér de afkrydsede/markerede filer til en anden mappe';
  rsFlytTilMappe = 'Flyt til mappe...';
  rsFlytTilMappeHint = 'Flyt de afkrydsede/markerede filer til en anden mappe';
  rsSletFilerMenu = 'Slet filer...';
  rsSletFilerHint = 'Læg de afkrydsede/markerede filer i papirkurven (Delete i fillisten)';
  rsSletFiler = 'Slet filer';
  rsLaegDFilerIPapirkurven = 'Læg %d filer i papirkurven?';
  rsDFilerLagtIPapirkurven = '%d filer lagt i papirkurven';
  rsKopierDFilerTilS = 'Kopiér %d filer til %s?';
  rsFlytDFilerTilS = 'Flyt %d filer til %s?';
  rsDFilerKopieretTilS = '%d filer kopieret til %s';
  rsDFilerFlyttetTilS = '%d filer flyttet til %s';
  rsHeleOrd = 'Hele ord';
  rsStoreSmaaBogstaver = 'Store/små bogstaver';
  rsTagtype = 'Tagtype:';
  rsAlleTagtyper = 'Alle';
  rsIngenTagsFilter = 'Ingen tags';
  rsTilpasKolonnebredder = 'Tilpas kolonnebredder';
  rsTilpasKolonnebredderHint = 'Gør kolonnerne lige så brede som deres indhold';
  rsTilpasKolonnerEfterMappeskift = 'Tilpas kolonner efter mappeskift';
  rsTilfaeldigRaekkefoelge = 'Tilfældig rækkefølge';
  rsTilfaeldigRaekkefoelgeHint = 'Bland filerne i listen (fx før nummerering eller en playliste)';
  rsKunstnerVaerktoejer = 'Kunstner-værktøjer';
  rsFjernTheForrest = 'Fjern "The" forrest i Kunstner';
  rsTheArtistTilArtistThe = '"The Artist" → "Artist, The"';
  rsArtistTheTilTheArtist = '"Artist, The" → "The Artist"';
  rsFornavnEfternavnTil = '"Fornavn Efternavn" → "Efternavn, Fornavn"';
  rsEfternavnFornavnTil = '"Efternavn, Fornavn" → "Fornavn Efternavn"';
  rsMpTagSynkroniseringMenu = 'Mp3-tag-synkronisering...';
  rsMpTagSynkroniseringHint = 'Kopiér felterne mellem ID3v1 og ID3v2 i mp3-filer';
  rsMpTagSynkronisering = 'Mp3-tag-synkronisering';
  rsIngenMpFiler = 'Ingen af de afkrydsede/markerede filer er mp3-filer.';
  rsSynkroniserTagsIDMpFiler = 'Synkronisér tags i %d mp3-filer?';
  rsVaelgFelterDerIndsaettesID = 'Vælg de felter, der indsættes i %d filer:';
  rsAlbumkunstnerVedGem = 'Albumkunstner ved gem';
  rsAlbumkunstnerIngen = 'Ingen automatik';
  rsAlbumkunstnerHvisTom = 'Kopiér Kunstner, hvis Albumkunstner er tom';
  rsAlbumkunstnerAltid = 'Kopiér altid Kunstner til Albumkunstner';
  rsSpornumreMenu = 'Spornumre...';
  rsDiscogsTokenMenu = 'Discogs-token...';
  rsOpMenu = 'Op';
  rsTagVaerktoejer = 'Tag-værktøjer';
  rsCoverVaerktoejer = 'Cover-værktøjer';
  rsOmdoebningshandlingerMenu = 'Omdøbningshandlinger';
  rsKunstnerTitelMenu = 'Byt Kunstner ↔ Titel';
  rsKunstnerAlbumMenu = 'Byt Kunstner ↔ Album';
  rsAlbumTitelMenu = 'Byt Album ↔ Titel';
  rsBytToFelter = 'Byt to felter...';
  rsBytToVilkaarligeFelter = 'Byt indholdet af to vilkårlige felter i de afkrydsede/markerede filer';
  rsKopierFeltTilFelt = 'Kopiér felt til felt...';
  rsKopierTekstFraEtFelt = 'Kopiér teksten fra ét felt til et andet, fx Kunstner til Albumkunstner';
  rsRydMellemrumIFelter = 'Ryd mellemrum i felter';
  rsRydMellemrumHint = 'Fjern mellemrum foran og bagved og dobbelte mellemrum i alle felter';
  rsFjernTagsMenu = 'Fjern tags...';
  rsFjernTagsHint = 'Fjern alle tags fra de afkrydsede/markerede filer';
  rsLaegMappensCoverIndIFilerne = 'Læg mappens cover ind i filerne';
  rsLaegMappensCoverHint = 'Gem folder.jpg/cover.jpg fra hver mappe som forside-cover i mappens filer';
  rsGemFilernesCoverSomFolderJpg = 'Gem filernes cover som folder.jpg';
  rsGemFilernesCoverHint = 'Gem coveret fra filernes tag som folder.jpg i mapper, der ikke har et';
  rsAdministrerHandlinger = 'Administrer handlinger...';
  rsAdministrerHandlingerHint = 'Opret og ret navngivne omdøbninger (filmaske og/eller mappemaske)';
  rsOrdudskiftningerMenu = 'Ordudskiftninger ved omdøbning...';
  rsOrdudskiftningerHint = 'Tekst der erstattes, og ord der altid staves ens, når filer og mapper omdøbes';
  rsIngenFilerAendres = 'Ingen af filerne ændres.';
  rsAendreDFiler = 'Ændre %d filer?';
  rsBytSS = 'Byt %s og %s';
  rsBytFelter = 'Byt felter';
  rsFelt1 = 'Felt 1:';
  rsFelt2 = 'Felt 2:';
  rsKopierFelt = 'Kopiér felt';
  rsFraFelt = 'Fra felt:';
  rsTilFelt = 'Til felt:';
  rsKunHvisFeltetErTomt = 'Kun hvis målfeltet er tomt';
  rsKopierSTilS = 'Kopiér %s til %s';
  rsRydMellemrum = 'Ryd mellemrum';
  rsFjernTags = 'Fjern tags';
  rsFjernAlleTagsIDFiler = 'Fjern alle tags fra %d filer?';
  rsFjernTagsForklaring = 'MP3, WAV/AIFF, APE, WavPack, Musepack og OptimFROG: tags fjernes helt. ' +
    'FLAC, Ogg, MP4 og WMA: alle felter og billeder ryddes; tekniske felter som ReplayGain bevares. ' +
    'Lyddata ændres ikke. Det kan ikke fortrydes.';
  rsMappeCoverIFiler = 'Mappens cover i filerne';
  rsIngenAfMapperneHarEtCover = 'Ingen af mapperne har et folder.jpg/cover.jpg (JPEG eller PNG).';
  rsLaegMappensCoverIndIDFiler = 'Læg mappens cover ind som forside-cover i %d filer?';
  rsDFilerLiggerIMapperUdenCover = '%d filer ligger i mapper uden cover og springes over.';
  rsCoverTilMappe = 'Cover til mappe';
  rsIngenMapperAtGemme = 'Intet at gemme: %d mapper har allerede et cover, og i %d mapper har ingen af filerne et cover.';
  rsGemFilernesCoverIDMapper = 'Gem filernes cover som folder.jpg i %d mapper?' + LineEnding +
    '(%d mapper har allerede et cover og %d mapper har ingen filer med cover - de springes over.)';
  rsCoverGemtIDMapper = 'Cover gemt i %d mapper';
  rsOmdoebningshandling = 'Omdøbningshandling';
  rsKoerHandlingenS = 'Kør handlingen "%s"?';
  rsFilerDOmdoebesMedS = 'Filer: %d omdøbes med %s';
  rsMapperneOmdoebesMedS = 'Mapper: omdøbes bagefter med %s';
  rsFilerMapper = 'filer/mapper';
  rsHandlingDFilerDMapperDFejl = '%s: %d filer og %d mapper omdøbt, %d fejl';
  rsSprogLanguage = 'Sprog (Language)';
  rsSprog = 'Sprog';
  rsAutomatiskWindowsSprog = 'Automatisk (Windows-sprog)';
  rsSprogetSkiftesNaarTidytagGenstartes = 'Sproget skiftes, når TidyTag startes igen. Genstart nu?';
  rsMultiFilTagEditor = 'Multi-fil-tag-editor';
  rsFilerFlertal = 'filer';
  rsMapperFlertal = 'mapper';
  rsKunstner = '%1|Kunstner';
  rsTitel = '%2|Titel';
  rsAlbum = '%3|Album';
  rsAar = '%4|År';
  rsGenre = '%5|Genre';
  rsSpor = '%6|Spor';
  rsDisc = '%#|Disc';
  rsFilnavn = '%7|Filnavn';
  rsFilnummer = '%8|Filnummer';
  rsKommentar = '%9|Kommentar';
  rsBitrate = '%0|Bitrate';
  rsBBpm = '%b|BPM';
  rsTSpilletid = '%t|Spilletid';
  rsAaAlbumkunstner = '%aa|Albumkunstner';
  rsCpKomponist = '%cp|Komponist';
  rsCoDirigent = '%co|Dirigent';
  rsLbPladeselskab = '%lb|Pladeselskab';
  rsCatKatalognr = '%cat|Katalognr.';
  rsGrpGruppering = '%grp|Gruppering';
  rsRbRemixetAf = '%rb|Remixet af';
  rsMdStemning = '%md|Stemning';
  rsKeyToneart = '%key|Toneart';
  rsExtFiltype = '%ext|Filtype';
  rsKhzSamplerate = '%khz|Samplerate';
  rsBindestreg = ' - |" - " (bindestreg)';
  rsNyMappe = '\|\ (ny mappe)';
  rsEksempelSporKunstnerTitel = '%6 - %1 - %2|Eksempel: spor - kunstner - titel';
  rsEksempelMapperPrKunstnerOg = '%1\%3\%6 - %2|Eksempel: mapper pr. kunstner og album';
  rsDSpringOver = '%d|Spring over';
  rsMappeniveau = '\|\ (mappeniveau)';
  rsFilnavn2 = 'Filnavn';
  rsTitel2 = 'Titel';
  rsKunstner2 = 'Kunstner';
  rsAar2 = 'År';
  rsKommentar2 = 'Kommentar';
  rsAlleFelter = 'Alle felter';
  rsBitrate2 = 'Bitrate';
  rsTid = 'Tid';
  rsCover = 'Cover';
  rsSamplerate = 'Samplerate';
  rsCodec = 'Codec';
  rsStoerrelse = 'Størrelse';
  rsMappe = 'Mappe';
  rsRenameNoter = 'Flere variabler under "Variabler". \ laver mapper, fx  %1\%3\%6 - %2'#13#10'Gælder de afkrydsede filer (ellers de markerede).';
  rsKunFelterMedFluebenBliver = '1. Kun felter med flueben bliver ændret (et felt får flueben, når du skriver i det).'#13#10'2. Tags gemmes i de afkrydsede filer (ellers de markerede).'#13#10'3. Et tomt felt med flueben bliver ryddet.'#13#10'4. "Alle felter..." redigerer flere felter og cover på én gang.';
  rsF2TFiltypeHint = 'Filtypen (fx .mp3) fjernes automatisk, før filnavnet sammenlignes med masken.';
  rsF2TNoter = '\ bruger mappenavne, fx  %1\%3\%6 - %2'#13#10'Gælder de afkrydsede filer (ellers de markerede).';
  rsAabnMappe = 'Åbn mappe...';
  rsAabnEnMappe = 'Åbn en mappe';
  rsOpdaterFillisten = 'Opdater fillisten';
  rsLaesMappenIgenF = 'Læs mappen igen (F5)';
  rsRedigerTag = 'Rediger tag...';
  rsRedigerTagForDenMarkerede = 'Rediger tag for den markerede fil (Enter)';
  rsRedigerFlereFiler = 'Rediger flere filer...';
  rsRetFelterOgCoverI = 'Ret felter og cover i alle afkrydsede (eller markerede) filer';
  rsOmdoebMapper = 'Omdøb mapper...';
  rsOmdoebMapperneUdFraFilernes = 'Omdøb mapperne ud fra filernes tags';
  rsAfspilFil = 'Afspil fil';
  rsAfspilDenMarkeredeFil = 'Afspil den markerede fil';
  rsVisIStifinder = 'Vis i Stifinder';
  rsAfslut = 'Afslut';
  rsMarkerAlle = 'Markér alle';
  rsFjernMarkering = 'Fjern markering';
  rsAfkrydsMarkeredeFilerMellemrum = 'Afkryds markerede filer	Mellemrum';
  rsAfkrydsDeMarkeredeFiler = 'Afkryds de markerede filer';
  rsFjernAfkrydsningFraMarkeredeFiler = 'Fjern afkrydsning fra markerede filer';
  rsAfkrydsAlleFiler = 'Afkryds alle filer';
  rsAfkrydsAlleFilerIListen = 'Afkryds alle filer i listen';
  rsFjernAlleAfkrydsninger = 'Fjern alle afkrydsninger';
  rsInverterAfkrydsning = 'Inverter afkrydsning';
  rsKopierTag = 'Kopiér tag';
  rsKopierTagFraDenMarkerede = 'Kopiér tag fra den markerede fil';
  rsIndsaetTag = 'Indsæt tag';
  rsIndsaetDetKopieredeTagUndtagen = 'Indsæt det kopierede tag (undtagen titel og spor) i de afkrydsede/markerede filer';
  rsFlytFilOp = 'Flyt fil op';
  rsFlytDeMarkeredeFilerEt = 'Flyt de markerede filer et trin op (manuel rækkefølge)';
  rsFlytFilNed = 'Flyt fil ned';
  rsFlytDeMarkeredeFilerEt2 = 'Flyt de markerede filer et trin ned (manuel rækkefølge)';
  rsEksporterImporterTags = 'Eksportér/importér tags...';
  rsEksporterTilCsvTxtHtml = 'Eksportér til CSV/TXT/HTML/XML eller importér fra CSV/XLSX';
  rsFindFiltrer = 'Find / filtrér...';
  rsFiltrerFillisten = 'Filtrér fillisten';
  rsVaerktoejspanel = 'Værktøjspanel';
  rsVisSkjulVaerktoejspaneletF = 'Vis/skjul værktøjspanelet (F8)';
  rsMappepanel = 'Mappepanel';
  rsAdresselinje = 'Adresselinje';
  rsFilterlinje = 'Filterlinje';
  rsSoegIUndermapper = 'Søg i undermapper';
  rsMedtagFilerIUndermapper = 'Medtag filer i undermapper';
  rsGemAfkrydsedeMarkeredeFilerSom = 'Gem afkrydsede/markerede filer som playliste...';
  rsGemAlleFilerSomPlayliste = 'Gem alle filer som playliste...';
  rsOmdoebFiler = 'Omdøb filer';
  rsVisFanebladetOmdoebFiler = 'Vis fanebladet Omdøb filer';
  rsVisFanebladetMultiFilTag = 'Vis fanebladet Multi-fil-tag-editor';
  rsTagsFraFilnavn = 'Tags fra filnavn';
  rsVisFanebladetTagsFraFilnavn = 'Vis fanebladet Tags fra filnavn';
  rsOmdoebFilerMedForhaandsvisning = 'Omdøb filer med forhåndsvisning...';
  rsTagsFraFilnavnMedForhaandsvisning = 'Tags fra filnavn med forhåndsvisning...';
  rsFormaterEllerNummererSpornumre = 'Formatér eller nummerér spornumre';
  rsWebOpslagMusicbrainzDiscogs = 'Web-opslag (MusicBrainz/Discogs)...';
  rsHentTitlerSpornumreOgCover = 'Hent titler, spornumre og cover fra MusicBrainz eller Discogs';
  rsFortrydOmdoebning = 'Fortryd omdøbning';
  rsGivDeSenestOmdoebteFiler = 'Giv de senest omdøbte filer/mapper deres gamle navne igen';
  rsBevarFilernesDatoVedGem = 'Bevar filernes dato ved gem';
  rsTastaturgenveje = 'Tastaturgenveje';
  rsOmTidytag = 'Om TidyTag...';
  rsGaaEnMappeOp = 'Gå en mappe op';
  rsFavoritter = 'Favoritter';
  rsFavoritmapper = 'Favoritmapper';
  rsNyMappe2 = 'Ny mappe...';
  rsOpretEnUndermappeIDen = 'Opret en undermappe i den åbne mappe';
  rsOpdaterMappetraeet = 'Opdater mappetræet';
  rsSkjulMappepanelet = 'Skjul mappepanelet';
  rsFiler = '&Filer';
  rsRediger = '&Rediger';
  rsVis = '&Vis';
  rsPlayliste = '&Playliste';
  rsVaerKtoejer = 'Vær&ktøjer';
  rsIndstillinger = '&Indstillinger';
  rsHjaelp = '&Hjælp';
  rsFejl = 'Fejl: ';
  rsIkkeUnderstoettetEndnu = '(ikke understøttet endnu)';
  rsJa = 'Ja';
  rsManuelRaekkefoelgeKlikPaaEn = 'Manuel rækkefølge - klik på en kolonneoverskrift for at sortere igen';
  rsVentVenligstTilAlleTags = 'Vent venligst, til alle tags er læst.';
  rsAfkrydsedeFilerD = 'Afkrydsede filer (%d)';
  rsMarkeredeFilerD = 'Markerede filer (%d)';
  rsAfkrydsEllerMarkerDeFiler = 'Afkryds (☑) eller markér de filer, det skal gælde.';
  rsMappenFindesIkke = 'Mappen findes ikke:';
  rsLaeserTagsDAfD = 'Læser tags: %d af %d filer...';
  rsSoegerEfterFiler = 'Søger efter filer...';
  rsLaeserTags = 'Læser tags';
  rsSoegerEfter = 'Søger efter';
  rsFilerDDSkjult = 'Filer: %d (+%d skjult)';
  rsFilerIAltD = 'Filer i alt: %d';
  rsMarkeredeD = 'Markerede: %d';
  rsSamletTid = 'Samlet tid: ';
  rsMarkeretTid = 'Markeret tid: ';
  rsAfkrydsetD = 'Afkrydset: %d';
  rsFortrydOmdoebningAfDS = 'Fortryd omdøbning af %d %s';
  rsGivDFilerMapperDeres = 'Giv %d filer/mapper deres tidligere navn igen?';
  rsDFilerMapperFikDeres = '%d filer/mapper fik deres gamle navn igen';
  rsDFilerMapperFikDeres2 = '%d filer/mapper fik deres gamle navn igen. Problemer:';
  rsMangler = 'Mangler: ';
  rsUgyldigMaske = '(ugyldig maske)';
  rsFilnavnetPasserIkkeTilMasken = '(filnavnet passer ikke til masken)';
  rsEksempel = 'Eksempel';
  rsAlleFilerHarAlleredeDet = 'Alle filer har allerede det navn, masken giver.';
  rsIntetAtOmdoebe = 'Intet at omdøbe';
  rsOmdoebDFilerS = 'Omdøb %d filer?%s';
  rsDSpringesOverBrugForhaandsvis = ' (%d springes over - brug "Forhåndsvis..." for at se hvorfor)';
  rsDFilerOmdoebtDFejl = '%d filer omdøbt, %d fejl';
  rsNogleFilerBlevIkkeOmdoebt = 'Nogle filer blev ikke omdøbt';
  rsSDAfD = '%s: %d af %d...';
  rsSGemtIDFiler = '%s: gemt i %d filer, %d fejl%s';
  rsDSprungetOverFiltype = ', %d sprunget over (filtype)';
  rsNogleFilerBlevIkkeGemt = 'Nogle filer blev ikke gemt';
  rsSaetFluebenVedDeFelter = 'Sæt flueben ved de felter, der skal gemmes.';
  rsGemTags = 'Gem tags';
  rsGemIDFiler = 'Gem i %d filer?';
  rsDisseFelterBliverRyddet = 'Disse felter bliver ryddet: ';
  rsIntetAtSkrive = 'Intet at skrive';
  rsIngenFilerAendresDPasser = 'Ingen filer ændres (%d passer ikke til masken). Brug "Forhåndsvis..." for at se detaljer.';
  rsSkrivTags = 'Skriv tags';
  rsSkrivTagsFraFilnavnetI = 'Skriv tags fra filnavnet i %d filer?%s';
  rsDPasserIkkeTilMasken = ' (%d passer ikke til masken og springes over)';
  rsIntetBilledeTraekEtBillede = 'Intet billede. Træk et billede hertil.';
  rsSDxD = '%s  %dx%d';
  rsIntetCoverTraekEtBillede = 'Intet cover. Træk et billede hertil.';
  rsSDxDDBillede = '%s  %dx%d  (%d billede)';
  rsSDxDDBilleder = '%s  %dx%d  (%d billeder)';
  rsKunJpegOgPngBilleder = 'Kun JPEG- og PNG-billeder kan bruges som cover.';
  rsMappensCover = 'Mappens cover';
  rsSFindesAlleredeErstatDet = '%s findes allerede. Erstat det?';
  rsBilledetKunneIkkeGemmes = 'Billedet kunne ikke gemmes:';
  rsMappensCoverGemtSom = 'Mappens cover gemt som ';
  rsFilensCover = 'Filens cover';
  rsSaetBilledetSomForsideCover = 'Sæt billedet som forside-cover i %d filer?';
  rsVaelgMappe = 'Vælg mappe';
  rsAfkrydsEllerMarkerFilerneFra = 'Afkryds (☑) eller markér filerne fra ét album, og prøv igen.';
  rsTagKopieretFra = 'Tag kopieret fra ';
  rsIndsaetDetKopieredeTagI = 'Indsæt det kopierede tag i %d filer?'#13#10'Alle felter undtagen titel og spornummer overskrives.';
  rsDerErIngenFilerAt = 'Der er ingen filer at gemme.';
  rsGemPlayliste = 'Gem playliste';
  rsPlaylisteUtfMUM = 'Playliste (UTF-8) (*.m3u8)|*.m3u8|Playliste (*.m3u)|*.m3u';
  rsPlaylisteMedDFilerGemt = 'Playliste med %d filer gemt: %s';
  rsLavEtPersonligtTokenPaa = 'Lav et personligt token på discogs.com: Settings > Developers > Generate new token.'#13#10'Indsæt det her (det gemmes kun på denne computer, i TidyTags indstillingsfil):';
  rsDiscogsTokenFjernet = 'Discogs-token fjernet';
  rsDiscogsTokenGemt = 'Discogs-token gemt';
  rsEnterDobbeltklikRedigerTagFor = 'Enter / dobbeltklik	Rediger tag for den markerede fil'#13#10'Mellemrum		Afkryds/fjern afkrydsning på markerede filer'#13#10'F4			Omdøb filer'#13#10'Ctrl+F4		Multi-fil-tag-editor'#13#10'Shift+F4		Tags fra filnavn'#13#10'F8			Vis/skjul værktøjspanelet'#13#10'F5			Opdater fillisten'#13#10'Ctrl+E		Rediger flere filer'#13#10'Ctrl+T		Spornumre'#13#10'Ctrl+W		Web-opslag'#13#10'Ctrl+Z		Fortryd omdøbning'#13#10'Ctrl+Shift+C / V	Kopiér / indsæt tag'#13#10'Ctrl+Op / Ned	Flyt markerede filer op / ned'#13#10'Ctrl+Shift+X	Eksportér / importér tags'#13#10'Ctrl+F		Filtrér listen (Esc rydder filteret)'#13#10'Ctrl+O		Åbn mappe'#13#10'Alt+Backspace	Mappe op';
  rsOmTidytag2 = 'Om TidyTag';
  rsTidytagTagEditorOgMusikorganisator = 'TidyTag - tag-editor og musikorganisator'#13#10'Lavet i Lazarus / Free Pascal.';
  rsWebDataMusicbrainzMusicbrainzOrg = 'Web-data: MusicBrainz (musicbrainz.org), Cover Art Archive og Discogs.'#13#10'Ikoner: Lazarus "general_purpose" af Roland Hahn (CC0).';
  rsIndstillinger2 = 'Indstillinger: ';
  rsTilfoejDenAabneMappe = 'Tilføj den åbne mappe';
  rsFjernDenAabneMappe = 'Fjern den åbne mappe';
  rsNyMappe3 = 'Ny mappe';
  rsNavnPaaDenNyeMappe = 'Navn på den nye mappe i ';
  rsMappenKunneIkkeOprettes = 'Mappen kunne ikke oprettes:';
  rsMappeOprettet = 'Mappe oprettet: ';


const
  CheckOn = '☑';
  CheckOff = '☐';

  IconNames: array[0..33] of string = ('open', 'refresh', 'search', 'subfolders', 'edit',
    'multiedit', 'renamefiles', 'renamefolder', 'filetotag', 'tracks', 'web', 'play', 'undo',
    'checkall', 'uncheck', 'help', 'info', 'favorites', 'settings', 'preview', 'save', 'filter',
    'copy', 'paste', 'folderup', 'newfolder', 'close', 'exit', 'picture', 'delete',
    'moveup', 'movedown', 'export', 'import');
  icoOpen = 0; icoRefresh = 1; icoSearch = 2; icoSubfolders = 3; icoEdit = 4; icoMultiEdit = 5;
  icoRenameFiles = 6; icoRenameFolder = 7; icoFileToTag = 8; icoTracks = 9; icoWeb = 10;
  icoPlay = 11; icoUndo = 12; icoCheckAll = 13; icoUncheck = 14; icoHelp = 15; icoInfo = 16;
  icoFavorites = 17; icoSettings = 18; icoPreview = 19; icoSave = 20; icoFilter = 21;
  icoCopy = 22; icoPaste = 23; icoFolderUp = 24; icoNewFolder = 25; icoClose = 26;
  icoExit = 27; icoPicture = 28; icoMoveUp = 30; icoMoveDown = 31; icoExport = 32; icoImport = 33;

  DefaultRenameMasks: array[0..5] of string = ('%1 - %2', '%6 - %2', '%6 - %1 - %2',
    '%1 - %3 - %6 - %2', '%1\%3\%6 - %2', '%aa\%4 - %3\%6 - %2');
  DefaultF2TMasks: array[0..6] of string = ('%1 - %2', '%6 - %2', '%6 - %1 - %2', '%6. %2',
    '%6 %1 - %2', '%1\%3\%6 - %2', '%1\%4 - %3\%6 - %2');

  RenameVars: array[0..32] of string = (
    rsKunstner, rsTitel, rsAlbum, rsAar, rsGenre, rsSpor, rsDisc,
    rsFilnavn, rsFilnummer, rsKommentar, rsBitrate, rsBBpm, rsTSpilletid,
    rsAaAlbumkunstner, rsCpKomponist, rsCoDirigent, rsLbPladeselskab, rsCatKatalognr,
    rsGrpGruppering, rsRbRemixetAf, rsMdStemning, rsKeyToneart,
    rsExtFiltype, rsKhzSamplerate, rsRtUdgivelsesdato, rsDbitBitdybde, rsEncKodetAf,
    rsRndTilfaeldigtTal, '-|',
    rsBindestreg, rsNyMappe, rsEksempelSporKunstnerTitel,
    rsEksempelMapperPrKunstnerOg);
  F2TVars: array[0..17] of string = (
    rsKunstner, rsTitel, rsAlbum, rsAar, rsGenre, rsSpor, rsDisc,
    rsKommentar, rsBBpm, rsAaAlbumkunstner, rsCpKomponist, rsCoDirigent,
    rsLbPladeselskab, rsDSpringOver,
    '-|', rsBindestreg, rsMappeniveau, rsEksempelSporKunstnerTitel);

  TagTypeTokens: array[0..8] of string = ('', 'ID3v2', 'ID3v1', 'APE', 'Vorbis', 'MP4', 'ASF',
    'RIFF INFO', '-');

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
  AddColumn(rsFilnavn2, 260, ckFileName);
  AddColumn(TagFieldCaptions[tfArtist], 160, ckField, tfArtist);
  AddColumn(TagFieldCaptions[tfAlbum], 180, ckField, tfAlbum);
  AddColumn(TagFieldCaptions[tfTitle], 220, ckField, tfTitle);
  AddColumn(TagFieldCaptions[tfYear], 70, ckField, tfYear);
  AddColumn(TagFieldCaptions[tfGenre], 110, ckField, tfGenre);
  AddColumn(TagFieldCaptions[tfTrack], 55, ckField, tfTrack, True);
  AddColumn(rsBitrate2, 60, ckBitrate, tfTitle, True);
  AddColumn(rsTid, 60, ckDuration, tfTitle, True);
  AddColumn(rsCover, 50, ckCover);
  AddColumn(TagFieldCaptions[tfDisc], 45, ckField, tfDisc, True);
  AddColumn(TagFieldCaptions[tfAlbumArtist], 140, ckField, tfAlbumArtist);
  AddColumn(TagFieldCaptions[tfComposer], 120, ckField, tfComposer);
  AddColumn(TagFieldCaptions[tfComment], 160, ckField, tfComment);
  AddColumn(TagFieldCaptions[tfBpm], 45, ckField, tfBpm, True);
  AddColumn(rsSamplerate, 75, ckSampleRate, tfTitle, True);
  AddColumn(rsCodec, 70, ckCodec);
  AddColumn('Tag-typer', 120, ckTagTypes);
  AddColumn(rsStoerrelse, 75, ckSize, tfTitle, True);
  AddColumn(TagFieldCaptions[tfPublisher], 140, ckField, tfPublisher);
  AddColumn(TagFieldCaptions[tfCatalogNo], 90, ckField, tfCatalogNo);
  AddColumn(TagFieldCaptions[tfGrouping], 110, ckField, tfGrouping);
  AddColumn(TagFieldCaptions[tfConductor], 120, ckField, tfConductor);
  AddColumn(TagFieldCaptions[tfRGTrackGain], 100, ckField, tfRGTrackGain);
  AddColumn(TagFieldCaptions[tfRGAlbumGain], 100, ckField, tfRGAlbumGain);
  AddColumn(rsMappe, 300, ckFolder);
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
  if SortForm.FSortDescending then Result := -Result;
  // ties: the previous sort column, then folder and file name
  if (Result = 0) and (SortForm.FSort2Column >= 0) and (SortForm.FSort2Column <> SortForm.FSortColumn) then
  begin
    Result := UTF8CompareText(SortForm.CellText(A, SortForm.FSort2Column),
      SortForm.CellText(B, SortForm.FSort2Column));
    if Columns[SortForm.FSort2Column].Numeric then
    begin
      NA := NumericValue(A, Columns[SortForm.FSort2Column]);
      NB := NumericValue(B, Columns[SortForm.FSort2Column]);
      if NA < NB then Result := -1 else if NA > NB then Result := 1 else Result := 0;
    end;
    if SortForm.FSort2Descending then Result := -Result;
  end;
  if Result = 0 then Result := UTF8CompareText(A.FileName, B.FileName);
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

procedure WriteFileBytes(const FileName: string; const Data: TBytes);
var
  S: TFileStream;
begin
  S := TFileStream.Create(FileName, fmCreate);
  try
    if Length(Data) > 0 then S.WriteBuffer(Data[0], Length(Data));
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
  F: TTagField;
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
    ComboFilterField.Items.Add(rsFilnavn2);
    for F := Low(TTagField) to High(TTagField) do ComboFilterField.Items.Add(TagFieldCaptions[F]);
    ComboFilterField.Items.Add(rsAlleFelter);
    ComboFilterField.ItemIndex := 0;
    ComboFilterField.DropDownCount := 20;
    BuildFilterExtras;
    ComboMultiGenre.Items.BeginUpdate;
    try
      for S in GenreList do ComboMultiGenre.Items.Add(S);
    finally
      ComboMultiGenre.Items.EndUpdate;
    end;
    FFilterField := 0;
    BuildVarHelp(LabelRenameHelp, ['%1', '%2', '%3', '%4', '%5', '%6', '%7', '%8', '%9', '%0',
      '%t', '%b', '%#', '%aa', '%co'], 5, rsRenameNoter);
    LabelMultiHelp.Caption :=
      rsKunFelterMedFluebenBliver;
    BuildVarHelp(LabelF2THelp, ['%1', '%2', '%3', '%4', '%5', '%6', '%#', '%9', '%b', '%aa',
      '%cp', '%co', '%lb', '%d'], 5, rsF2TNoter);
    LabelF2THelp.Hint := rsF2TFiltypeHint;
    LabelF2THelp.ShowHint := True;
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
    aToken, aKeys, aAbout, aUp, aFav, aNewFolder, aTreeRefresh, aCloseFolders,
    aMoveUp, aMoveDown, aExport, aSwapAT, aSwapAA, aSwapLT, aSwap, aCopyField, aClean,
    aRemoveTags, aCoverIn, aCoverOut, aWords, aSync, aAutoFit, aRandom, aCopyTo, aMoveTo,
    aDelFolderCover, aResizeFiles, aResizeFolders, aCoverAsFolder, aSettings,
    aReplayGain, aRemoveRG, aRenameManual, aProperties, aExtM4A, aExtM4B, aExtM4BBack,
    aExpandFolders, aCollapseFolders, aPlayFolder, aQuickPlaylist, aGenres: TAction;
  CoverPopup: TPopupMenu;
  PM: TMenuItem;
  NameTools: array[TNameTool] of TAction;
  NT: TNameTool;
  TopMenu, SubMenu: TMenuItem;
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

  function Sub(Parent: TMenuItem; const Caption: string): TMenuItem;
  begin
    Result := TMenuItem.Create(Parent);
    Result.Caption := Caption;
    Parent.Add(Result);
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
  FSort2Column := -1;
  FSyncDir := sdV1ToV2;
  FSyncExisting := seBlankOnly;
  FRGAlbum := True;
  FSwapA := tfArtist;
  FSwapB := tfAlbumArtist;
  FCopySrc := tfArtist;
  FCopyDst := tfAlbumArtist;
  FCopyOnlyEmpty := True;
  FActions := TActionList.Create(Self);
  FActions.Images := ImagesMain;

  aOpen := NewAction(rsAabnMappe, rsAabnEnMappe, ShortCut(VK_O, [ssCtrl]), icoOpen, @ActOpenFolderExecute);
  aRefresh := NewAction(rsOpdaterFillisten, rsLaesMappenIgenF, ShortCut(VK_F5, []), icoRefresh, @ActRefreshExecute);
  aEdit := NewAction(rsRedigerTag, rsRedigerTagForDenMarkerede, 0, icoEdit, @ActEditTagExecute);
  aMulti := NewAction(rsRedigerFlereFiler, rsRetFelterOgCoverI,
    ShortCut(VK_E, [ssCtrl]), icoMultiEdit, @ActMultiEditExecute);
  aRenameFolder := NewAction(rsOmdoebMapper, rsOmdoebMapperneUdFraFilernes, 0, icoRenameFolder, @ActRenameFolderExecute);
  aPlay := NewAction(rsAfspilFil, rsAfspilDenMarkeredeFil, ShortCut(VK_P, [ssCtrl]), icoPlay, @ActPlayExecute);
  aExplorer := NewAction(rsVisIStifinder, '', 0, icoOpen, @ActShowInExplorerExecute);
  aExit := NewAction(rsAfslut, '', ShortCut(VK_F4, [ssAlt]), icoExit, @ActExitExecute);
  aSelAll := NewAction(rsMarkerAlle, '', ShortCut(VK_A, [ssCtrl]), -1, @ActSelectAllExecute);
  aSelNone := NewAction(rsFjernMarkering, '', 0, -1, @ActSelectNoneExecute);
  aChkSel := NewAction(rsAfkrydsMarkeredeFilerMellemrum, rsAfkrydsDeMarkeredeFiler, 0, icoCheckAll, @ActCheckSelectedExecute);
  aUnchkSel := NewAction(rsFjernAfkrydsningFraMarkeredeFiler, '', 0, -1, @ActUncheckSelectedExecute);
  aChkAll := NewAction(rsAfkrydsAlleFiler, rsAfkrydsAlleFilerIListen, 0, icoCheckAll, @ActCheckAllExecute);
  aUnchkAll := NewAction(rsFjernAlleAfkrydsninger, '', 0, icoUncheck, @ActUncheckAllExecute);
  aInvert := NewAction(rsInverterAfkrydsning, '', 0, -1, @ActInvertChecksExecute);
  aCopy := NewAction(rsKopierTag, rsKopierTagFraDenMarkerede, ShortCut(VK_C, [ssCtrl, ssShift]), icoCopy, @ActCopyTagExecute);
  FActPaste := NewAction(rsIndsaetTag, rsIndsaetDetKopieredeTagUndtagen,
    ShortCut(VK_V, [ssCtrl, ssShift]), icoPaste, @ActPasteTagExecute);
  FActPaste.Enabled := False;
  aMoveUp := NewAction(rsFlytFilOp, rsFlytDeMarkeredeFilerEt,
    ShortCut(VK_UP, [ssCtrl]), icoMoveUp, @ActMoveUpExecute);
  aMoveDown := NewAction(rsFlytFilNed, rsFlytDeMarkeredeFilerEt2,
    ShortCut(VK_DOWN, [ssCtrl]), icoMoveDown, @ActMoveDownExecute);
  aExport := NewAction(rsEksporterImporterTags, rsEksporterTilCsvTxtHtml,
    ShortCut(VK_X, [ssCtrl, ssShift]), icoExport, @ActExportImportExecute);
  aFind := NewAction(rsFindFiltrer, rsFiltrerFillisten, ShortCut(VK_F, [ssCtrl]), icoSearch, @ActFindExecute);
  FActToolsPanel := NewAction(rsVaerktoejspanel, rsVisSkjulVaerktoejspaneletF, ShortCut(VK_F8, []), -1, @ActToolsPanelExecute);
  FActFolders := NewAction(rsMappepanel, '', 0, -1, @ActFoldersExecute);
  FActAddress := NewAction(rsAdresselinje, '', 0, -1, @ActAddressExecute);
  FActFilter := NewAction(rsFilterlinje, '', 0, -1, @ActFilterBarExecute);
  FActSubfolders := NewAction(rsSoegIUndermapper, rsMedtagFilerIUndermapper, 0, icoSubfolders, @ActSubfoldersExecute);
  aPlChecked := NewAction(rsGemAfkrydsedeMarkeredeFilerSom, '', 0, icoSave, @ActPlaylistCheckedExecute);
  aPlAll := NewAction(rsGemAlleFilerSomPlayliste, '', 0, icoSave, @ActPlaylistAllExecute);
  aTabRename := NewAction(rsOmdoebFiler, rsVisFanebladetOmdoebFiler, ShortCut(VK_F4, []), icoRenameFiles, @ActTabRenameExecute);
  aTabMulti := NewAction(rsMultiFilTagEditor, rsVisFanebladetMultiFilTag, ShortCut(VK_F4, [ssCtrl]), icoMultiEdit, @ActTabMultiExecute);
  aTabF2T := NewAction(rsTagsFraFilnavn, rsVisFanebladetTagsFraFilnavn, ShortCut(VK_F4, [ssShift]), icoFileToTag, @ActTabFileToTagExecute);
  aRenameDlg := NewAction(rsOmdoebFilerMedForhaandsvisning, '', 0, icoPreview, @ActRenameDialogExecute);
  aF2TDlg := NewAction(rsTagsFraFilnavnMedForhaandsvisning, '', 0, icoPreview, @ActFileToTagDialogExecute);
  aTracks := NewAction(rsSpornumreMenu, rsFormaterEllerNummererSpornumre, ShortCut(VK_T, [ssCtrl]), icoTracks, @ActTracksExecute);
  aWeb := NewAction(rsWebOpslagMusicbrainzDiscogs, rsHentTitlerSpornumreOgCover,
    ShortCut(VK_W, [ssCtrl]), icoWeb, @ActWebExecute);
  FActUndo := NewAction(rsFortrydOmdoebning, rsGivDeSenestOmdoebteFiler,
    ShortCut(VK_Z, [ssCtrl]), icoUndo, @ActUndoExecute);
  FActUndo.Enabled := False;
  FActKeepDate := NewAction(rsBevarFilernesDatoVedGem, '', 0, -1, @ActKeepDateExecute);
  aToken := NewAction(rsDiscogsTokenMenu, '', 0, icoSettings, @ActDiscogsTokenExecute);
  aKeys := NewAction(rsTastaturgenveje, '', ShortCut(VK_F1, []), icoHelp, @ActShortcutsExecute);
  aAbout := NewAction(rsOmTidytag, '', 0, icoInfo, @ActAboutExecute);
  aUp := NewAction(rsOpMenu, rsGaaEnMappeOp, ShortCut(VK_BACK, [ssAlt]), icoFolderUp, @ActFolderUpExecute);
  aFav := NewAction(rsFavoritter, rsFavoritmapper, 0, icoFavorites, @ActFavoritesExecute);
  aNewFolder := NewAction(rsNyMappe2, rsOpretEnUndermappeIDen, 0, icoNewFolder, @ActNewFolderExecute);
  aTreeRefresh := NewAction(rsOpdaterMappetraeet, '', 0, icoRefresh, @ActRefreshTreeExecute);
  aCloseFolders := NewAction(rsSkjulMappepanelet, '', 0, icoClose, @ActFoldersExecute);
  aSwapAT := NewAction(rsKunstnerTitelMenu, '', 0, -1, @ActSwapArtistTitleExecute);
  aSwapAA := NewAction(rsKunstnerAlbumMenu, '', 0, -1, @ActSwapArtistAlbumExecute);
  aSwapLT := NewAction(rsAlbumTitelMenu, '', 0, -1, @ActSwapAlbumTitleExecute);
  aSwap := NewAction(rsBytToFelter, rsBytToVilkaarligeFelter, 0, -1, @ActSwapFieldsExecute);
  aCopyField := NewAction(rsKopierFeltTilFelt, rsKopierTekstFraEtFelt, 0, icoCopy, @ActCopyFieldExecute);
  aClean := NewAction(rsRydMellemrumIFelter, rsRydMellemrumHint, 0, -1, @ActCleanSpacesExecute);
  aRemoveTags := NewAction(rsFjernTagsMenu, rsFjernTagsHint, ShortCut(VK_DELETE, [ssCtrl]), -1, @ActRemoveTagsExecute);
  aCoverIn := NewAction(rsLaegMappensCoverIndIFilerne, rsLaegMappensCoverHint, 0, -1, @ActCoverToTagsExecute);
  aCoverOut := NewAction(rsGemFilernesCoverSomFolderJpg, rsGemFilernesCoverHint, 0, icoSave, @ActCoverFromTagsExecute);
  FActManageActions := NewAction(rsAdministrerHandlinger, rsAdministrerHandlingerHint, 0, icoSettings, @ActManageActionsExecute);
  aWords := NewAction(rsOrdudskiftningerMenu, rsOrdudskiftningerHint, 0, icoSettings, @ActRenameWordsExecute);
  NameTools[ntRemoveThe] := NewAction(rsFjernTheForrest, '', 0, -1, @ActNameToolExecute);
  NameTools[ntTheToEnd] := NewAction(rsTheArtistTilArtistThe, '', 0, -1, @ActNameToolExecute);
  NameTools[ntTheToFront] := NewAction(rsArtistTheTilTheArtist, '', 0, -1, @ActNameToolExecute);
  NameTools[ntNameToSurnameFirst] := NewAction(rsFornavnEfternavnTil, '', 0, -1, @ActNameToolExecute);
  NameTools[ntSurnameFirstToName] := NewAction(rsEfternavnFornavnTil, '', 0, -1, @ActNameToolExecute);
  for NT := Low(TNameTool) to High(TNameTool) do NameTools[NT].Tag := Ord(NT);
  aSync := NewAction(rsMpTagSynkroniseringMenu, rsMpTagSynkroniseringHint, 0, -1, @ActID3SyncExecute);
  aReplayGain := NewAction(rsBeregnReplayGain, rsBeregnReplayGainHint, 0, -1, @ActReplayGainExecute);
  aRemoveRG := NewAction(rsFjernReplayGain, rsFjernReplayGainHint, 0, -1, @ActRemoveReplayGainExecute);
  aRenameManual := NewAction(rsOmdoebFilManuelt, rsOmdoebFilManueltHint, ShortCut(VK_F6, []), -1, @ActRenameManualExecute);
  aProperties := NewAction(rsEgenskaber, rsEgenskaberHint, ShortCut(VK_RETURN, [ssAlt]), -1, @ActPropertiesExecute);
  aExtM4A := NewAction(rsMp4TilM4a, '', 0, -1, @ActChangeExtExecute);
  aExtM4A.Tag := 0;
  aExtM4B := NewAction(rsTilM4b, '', 0, -1, @ActChangeExtExecute);
  aExtM4B.Tag := 1;
  aExtM4BBack := NewAction(rsM4bTilM4a, '', 0, -1, @ActChangeExtExecute);
  aExtM4BBack.Tag := 2;
  aExpandFolders := NewAction(rsUdvidUndermapper, '', 0, -1, @ActExpandFoldersExecute);
  aCollapseFolders := NewAction(rsFoldMapperSammen, '', 0, -1, @ActCollapseFoldersExecute);
  aPlayFolder := NewAction(rsAfspilMappen, rsAfspilMappenHint, ShortCut(VK_P, [ssCtrl, ssShift]), -1, @ActPlayFolderExecute);
  aQuickPlaylist := NewAction(rsGemPlaylisteHurtigt, rsGemPlaylisteHurtigtHint, ShortCut(VK_P, [ssCtrl, ssAlt]), -1, @ActQuickPlaylistExecute);
  aGenres := NewAction(rsGenreliste, rsGenrelisteHint, 0, -1, @ActGenresExecute);
  aDelFolderCover := NewAction(rsSletMappeCover, rsSletMappeCoverHint, 0, -1, @ActDeleteFolderCoversExecute);
  aResizeFiles := NewAction(rsSkalerCoverIFilerne, rsSkalerCoverIFilerneHint, 0, -1, @ActResizeFileCoversExecute);
  aResizeFolders := NewAction(rsSkalerMappeCover, rsSkalerMappeCoverHint, 0, -1, @ActResizeFolderCoversExecute);
  aCoverAsFolder := NewAction(rsBrugFilensCoverSomMappeCover, '', 0, icoSave, @ActCoverAsFolderExecute);
  aSettings := NewAction(rsIndstillingerMenu, rsIndstillingerMenuHint, ShortCut(VK_O, [ssCtrl, ssAlt]),
    icoSettings, @ActSettingsExecute);
  FActAutoResize := NewAction(rsSkalerStoreCoverVedGem, rsSkalerStoreCoverVedGemHint, 0, -1, @ActAutoResizeExecute);
  FActAutoResize.AutoCheck := True;
  aCopyTo := NewAction(rsKopierTilMappe, rsKopierTilMappeHint, 0, icoCopy, @ActCopyToExecute);
  aMoveTo := NewAction(rsFlytTilMappe, rsFlytTilMappeHint, 0, -1, @ActMoveToExecute);
  FActDeleteFiles := NewAction(rsSletFilerMenu, rsSletFilerHint, 0, icoClose, @ActDeleteFilesExecute);
  aAutoFit := NewAction(rsTilpasKolonnebredder, rsTilpasKolonnebredderHint, 0, -1, @ActAutoFitExecute);
  FActAutoFitAfterScan := NewAction(rsTilpasKolonnerEfterMappeskift, '', 0, -1, @ActAutoFitAfterScanExecute);
  FActAutoFitAfterScan.AutoCheck := True;
  aRandom := NewAction(rsTilfaeldigRaekkefoelge, rsTilfaeldigRaekkefoelgeHint, 0, -1, @ActRandomOrderExecute);
  FActToolsPanel.AutoCheck := True;
  FActFolders.AutoCheck := True;
  FActAddress.AutoCheck := True;
  FActFilter.AutoCheck := True;
  FActSubfolders.AutoCheck := True;
  FActKeepDate.AutoCheck := True;

  // ---- main menu
  TopMenu := Menu(rsFiler);
  Add(TopMenu, aOpen); Add(TopMenu, aRefresh); Add(TopMenu, nil);
  Add(TopMenu, aEdit); Add(TopMenu, aMulti); Add(TopMenu, aRenameFolder); Add(TopMenu, nil);
  Add(TopMenu, aPlay); Add(TopMenu, aPlayFolder); Add(TopMenu, aExplorer); Add(TopMenu, aProperties); Add(TopMenu, nil);
  Add(TopMenu, aRenameManual); Add(TopMenu, aCopyTo); Add(TopMenu, aMoveTo); Add(TopMenu, FActDeleteFiles); Add(TopMenu, nil);
  FRecentMenu := Sub(TopMenu, rsSenesteMapper);
  Add(TopMenu, nil);
  Add(TopMenu, aExit);
  TopMenu := Menu(rsRediger);
  Add(TopMenu, aSelAll); Add(TopMenu, aSelNone); Add(TopMenu, nil);
  Add(TopMenu, aChkSel); Add(TopMenu, aUnchkSel); Add(TopMenu, aChkAll); Add(TopMenu, aUnchkAll); Add(TopMenu, aInvert);
  Add(TopMenu, nil); Add(TopMenu, aCopy); Add(TopMenu, FActPaste);
  Add(TopMenu, nil); Add(TopMenu, aMoveUp); Add(TopMenu, aMoveDown); Add(TopMenu, nil); Add(TopMenu, aFind);
  TopMenu := Menu(rsVis);
  Add(TopMenu, FActToolsPanel); Add(TopMenu, FActFolders); Add(TopMenu, FActAddress); Add(TopMenu, FActFilter);
  Add(TopMenu, nil); Add(TopMenu, FActSubfolders); Add(TopMenu, aExpandFolders); Add(TopMenu, aCollapseFolders);
  Add(TopMenu, nil);
  Add(TopMenu, aAutoFit); Add(TopMenu, FActAutoFitAfterScan); Add(TopMenu, aRandom); Add(TopMenu, nil);
  Add(TopMenu, aRefresh);
  TopMenu := Menu(rsPlayliste);
  Add(TopMenu, aPlChecked); Add(TopMenu, aPlAll); Add(TopMenu, aQuickPlaylist);
  TopMenu := Menu(rsVaerKtoejer);
  Add(TopMenu, aTabRename); Add(TopMenu, aTabMulti); Add(TopMenu, aTabF2T); Add(TopMenu, nil);
  Add(TopMenu, aRenameDlg); Add(TopMenu, aF2TDlg); Add(TopMenu, aRenameFolder); Add(TopMenu, aTracks); Add(TopMenu, aWeb);
  Add(TopMenu, aExport);
  Add(TopMenu, nil);
  SubMenu := Sub(TopMenu, rsTagVaerktoejer);
  Add(SubMenu, aSwapAT); Add(SubMenu, aSwapAA); Add(SubMenu, aSwapLT); Add(SubMenu, aSwap);
  Add(SubMenu, nil); Add(SubMenu, aCopyField); Add(SubMenu, aClean);
  SubMenu := Sub(SubMenu, rsKunstnerVaerktoejer);
  for NT := Low(TNameTool) to High(TNameTool) do Add(SubMenu, NameTools[NT]);
  SubMenu := SubMenu.Parent;
  Add(SubMenu, aSync); Add(SubMenu, nil); Add(SubMenu, aRemoveTags);
  SubMenu := Sub(TopMenu, rsCoverVaerktoejer);
  Add(SubMenu, aCoverIn); Add(SubMenu, aCoverOut); Add(SubMenu, aCoverAsFolder); Add(SubMenu, nil);
  Add(SubMenu, aResizeFiles); Add(SubMenu, aResizeFolders); Add(SubMenu, nil); Add(SubMenu, aDelFolderCover);
  SubMenu := Sub(TopMenu, rsReplayGainTitel);
  Add(SubMenu, aReplayGain); Add(SubMenu, nil); Add(SubMenu, aRemoveRG);
  SubMenu := Sub(TopMenu, rsSkiftFiltype);
  Add(SubMenu, aExtM4A); Add(SubMenu, aExtM4B); Add(SubMenu, aExtM4BBack);
  // right click on the file cover
  CoverPopup := TPopupMenu.Create(Self);
  PM := TMenuItem.Create(CoverPopup);
  PM.Action := aCoverAsFolder;
  CoverPopup.Items.Add(PM);
  ImageFileCover.PopupMenu := CoverPopup;
  FActionsMenu := Sub(TopMenu, rsOmdoebningshandlingerMenu);
  RebuildActionsMenu;
  Add(TopMenu, nil); Add(TopMenu, FActUndo);
  TopMenu := Menu(rsIndstillinger);
  Add(TopMenu, aSettings); Add(TopMenu, aGenres); Add(TopMenu, nil);
  Add(TopMenu, FActKeepDate); Add(TopMenu, FActAutoResize); AddAlbumArtistMenu(TopMenu); Add(TopMenu, aWords); Add(TopMenu, aToken);
  Add(TopMenu, nil);
  AddLanguageMenu(TopMenu);
  TopMenu := Menu(rsHjaelp);
  Add(TopMenu, aKeys); Add(TopMenu, aAbout);

  // ---- file list popup
  AddPopup(aEdit); AddPopup(aMulti); AddPopup(nil);
  AddPopup(aChkSel); AddPopup(aUnchkSel); AddPopup(aChkAll); AddPopup(aUnchkAll); AddPopup(aInvert);
  AddPopup(nil); AddPopup(aCopy); AddPopup(FActPaste); AddPopup(nil); AddPopup(aMoveUp); AddPopup(aMoveDown);
  AddPopup(nil); AddPopup(aPlay); AddPopup(aExplorer); AddPopup(aProperties); AddPopup(aRenameManual);
  AddPopup(nil); AddPopup(aCopyTo); AddPopup(aMoveTo); AddPopup(FActDeleteFiles);

  // ---- toolbars
  X := 0;
  Btn(ToolBarMain, aOpen); Btn(ToolBarMain, aRefresh); Btn(ToolBarMain, aFind); Btn(ToolBarMain, nil);
  Btn(ToolBarMain, FActSubfolders, tbsCheck); Btn(ToolBarMain, nil);
  Btn(ToolBarMain, aEdit); Btn(ToolBarMain, aMulti); Btn(ToolBarMain, aRenameDlg);
  Btn(ToolBarMain, aRenameFolder); Btn(ToolBarMain, aF2TDlg); Btn(ToolBarMain, nil);
  Btn(ToolBarMain, aCopy); Btn(ToolBarMain, FActPaste); Btn(ToolBarMain, nil);
  Btn(ToolBarMain, aPlay); Btn(ToolBarMain, aMoveUp); Btn(ToolBarMain, aMoveDown); Btn(ToolBarMain, nil);
  Btn(ToolBarMain, aTracks); Btn(ToolBarMain, aWeb); Btn(ToolBarMain, aExport); Btn(ToolBarMain, nil);
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

function IsWordCharW(C: WideChar): Boolean;
begin
  Result := (WideUpperCase(C) <> WideLowerCase(C)) or ((C >= '0') and (C <= '9'));
end;

{ Needle in Hay; whole words only when Whole (letters and digits form words). }
function ContainsText(const Hay, Needle: UnicodeString; Whole: Boolean): Boolean;
var
  P, Start: Integer;
begin
  Start := 1;
  repeat
    P := Pos(Needle, Copy(Hay, Start, MaxInt));
    if P = 0 then Exit(False);
    P := P + Start - 1;
    if not Whole or (((P = 1) or not IsWordCharW(Hay[P - 1])) and
      ((P + Length(Needle) > Length(Hay)) or not IsWordCharW(Hay[P + Length(Needle)]))) then
      Exit(True);
    Start := P + 1;
  until False;
end;

function TFormMain.MatchesFilter(Info: TAudioInfo): Boolean;
var
  Hay: string;
  F: TTagField;
  H, N: UnicodeString;
begin
  if FTagTypeFilter > 0 then
  begin
    if TagTypeTokens[FTagTypeFilter] = '-' then
    begin
      if (Info.TagTypes <> '') or (Info.Error <> '') then Exit(False);
    end
    else if Pos(TagTypeTokens[FTagTypeFilter], Info.TagTypes) = 0 then
      Exit(False);
  end;
  if FFilterText = '' then Exit(True);
  if FFilterField = 0 then
    Hay := ExtractFileName(Info.FileName)
  else if FFilterField <= Ord(High(TTagField)) + 1 then
    Hay := Info.Fields[TTagField(FFilterField - 1)]
  else
  begin
    Hay := ExtractFileName(Info.FileName);
    for F := Low(TTagField) to High(TTagField) do Hay := Hay + #1 + Info.Fields[F];
  end;
  H := UTF8Decode(Hay);
  N := UTF8Decode(FFilterText);
  if not CheckFilterCase.Checked then
  begin
    H := WideLowerCase(H);
    N := WideLowerCase(N);
  end;
  Result := ContainsText(H, N, CheckFilterWhole.Checked);
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
    ckFileName:
      if AppOptions.HideExtensions then Result := ChangeFileExt(ExtractFileName(Info.FileName), '')
      else Result := ExtractFileName(Info.FileName);
    ckField: Result := Info.Fields[Columns[Col].Field];
    ckDuration: Result := FormatDuration(Info.Duration);
    ckBitrate: if Info.Bitrate > 0 then Result := IntToStr(Info.Bitrate) else Result := '';
    ckSampleRate: if Info.SampleRate > 0 then Result := IntToStr(Info.SampleRate) else Result := '';
    ckCodec: Result := Info.Codec;
    ckTagTypes:
      if Info.Error <> '' then Result := rsFejl + Info.Error
      else if not Info.Supported then Result := rsIkkeUnderstoettetEndnu
      else Result := Info.TagTypes;
    ckCover: if Info.HasCover then Result := rsJa else Result := '';
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
    // the old order decides ties ("second sort column")
    FSort2Column := FSortColumn;
    FSort2Descending := FSortDescending;
    FSortColumn := Column.Index;
    FSortDescending := False;
  end;
  SortItems;
end;

procedure TFormMain.SortItems;
begin
  SortForm := Self;
  if FSortColumn >= 0 then FItems.Sort(@CompareInfos); // -1 = manual order (moved files)
  RebuildView;
end;

{ Moves the selected files one step; the list then keeps this manual order
  (e.g. for "Nummerér i listens rækkefølge") until a column header is clicked. }
procedure TFormMain.MoveSelected(Delta: Integer);
var
  Sel: array of Integer;
  I, K, A, B, IA, IB: Integer;
  T: Pointer;
begin
  Sel := nil;
  for I := 0 to FView.Count - 1 do
    if FileList.Items[I].Selected then
    begin
      SetLength(Sel, Length(Sel) + 1);
      Sel[High(Sel)] := I;
    end;
  if Length(Sel) = 0 then Exit;
  if (Delta < 0) and (Sel[0] = 0) then Exit;
  if (Delta > 0) and (Sel[High(Sel)] = FView.Count - 1) then Exit;
  for K := 0 to High(Sel) do
  begin
    if Delta < 0 then I := Sel[K] else I := Sel[High(Sel) - K];
    A := I;
    B := I + Delta;
    // swap in the view and the same two objects in the master list
    IA := FItems.IndexOf(FView[A]);
    IB := FItems.IndexOf(FView[B]);
    T := FView[A]; FView[A] := FView[B]; FView[B] := T;
    if (IA >= 0) and (IB >= 0) then
    begin
      T := FItems[IA]; FItems[IA] := FItems[IB]; FItems[IB] := T;
    end;
  end;
  FSortColumn := -1;
  FileList.ClearSelection;
  for K := 0 to High(Sel) do
    FileList.Items[Sel[K] + Delta].Selected := True;
  FileList.ItemIndex := Sel[0] + Delta;
  FileList.Items[Sel[0] + Delta].Focused := True;
  FileList.Items[Sel[0] + Delta].MakeVisible(False);
  FileList.Invalidate;
  SetMessage(rsManuelRaekkefoelgeKlikPaaEn);
end;

procedure TFormMain.ActExportImportExecute(Sender: TObject);
var
  Subset: TAudioInfoArray;
  SubsetCaption: string;
  Prefer: Boolean;
begin
  if not CanStartBatch or (FView.Count = 0) then Exit;
  Subset := TargetItems(SubsetCaption, Prefer);
  if TFormExportImport.Execute(AllItems, Subset, SubsetCaption, Prefer, FKeepTimestamp) then
  begin
    FCoverFile := '';
    FileList.Invalidate;
    SelectionChanged;
  end;
end;

procedure TFormMain.ActMoveUpExecute(Sender: TObject);
begin
  MoveSelected(-1);
end;

procedure TFormMain.ActMoveDownExecute(Sender: TObject);
begin
  MoveSelected(1);
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
  else if (Key = VK_DELETE) and (Shift = []) then
  begin
    // only here, not as a shortcut: Delete in a text box must not delete files
    Key := 0;
    FActDeleteFiles.Execute;
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
    MessageDlg(rsVentVenligstTilAlleTags, mtInformation, [mbOK], 0);
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
    ScopeCaption := Format(rsAfkrydsedeFilerD, [Length(Result)]);
    Prefer := True;
  end
  else
  begin
    Result := SelectedItems;
    ScopeCaption := Format(rsMarkeredeFilerD, [Length(Result)]);
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
    MessageDlg(rsAfkrydsEllerMarkerDeFiler, mtInformation, [mbOK], 0);
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
    MessageDlg(rsMappenFindesIkke + LineEnding + Dir, mtWarning, [mbOK], 0);
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
  RebuildRecentMenu;
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
  Caption := 'TidyTag - ' + FFolder;
  FCoverFile := '';
  FFolderCoverDir := '';
  if FSortColumn < 0 then FSortColumn := 1; // a fresh scan starts sorted by file name
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
    if FActAutoFitAfterScan.Checked then AutoFitColumns;
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
      SetMessage(Format(rsLaeserTagsDAfD, [Done, Total]))
    else
      SetMessage(rsSoegerEfterFiler);
  end
  else if Pos(rsLaeserTags, StatusBar.Panels[5].Text) + Pos(rsSoegerEfter, StatusBar.Panels[5].Text) > 0 then
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
    StatusBar.Panels[0].Text := Format(rsFilerDDSkjult, [FView.Count, Hidden])
  else
    StatusBar.Panels[0].Text := Format(rsFilerIAltD, [FView.Count]);
  StatusBar.Panels[1].Text := Format(rsMarkeredeD, [Length(Sel)]);
  StatusBar.Panels[2].Text := rsSamletTid + IfThen(TotalSec > 0, FormatDuration(TotalSec), '0:00');
  StatusBar.Panels[3].Text := rsMarkeretTid + IfThen(SelSec > 0, FormatDuration(SelSec), '0:00');
  StatusBar.Panels[4].Text := Format(rsAfkrydsetD, [Checked]);
end;

{ TFormMain - rename log / undo }

procedure TFormMain.SetUndoLog(const Log: TRenameLog; const What: string);
begin
  FUndoLog := Log;
  FActUndo.Enabled := True;
  ButtonRenameUndo.Enabled := True;
  FActUndo.Hint := Format(rsFortrydOmdoebningAfDS, [Length(Log), What]);
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
    Caption := 'TidyTag - ' + FFolder;
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
  if not AskYes(rsFortrydOmdoebning, Format(rsGivDFilerMapperDeres, [Length(FUndoLog)])) then Exit;
  Errors := TStringList.Create;
  try
    Restored := UndoRename(FUndoLog, Errors);
    ApplyRenameLog(FUndoLog, True);
    FUndoLog := nil;
    FActUndo.Enabled := False;
    ButtonRenameUndo.Enabled := False;
    SetMessage(Format(rsDFilerMapperFikDeres, [Restored]));
    SelectionChanged;
    if Errors.Count > 0 then
      Inform(rsFortrydOmdoebning, Format(rsDFilerMapperFikDeres2,
        [Restored]) + LineEnding + Errors.Text, mtWarning);
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
  ApplyRenameWords(Result);
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
    if Trim(ComboRenameMask.Text) = '' then ComboRenameMask.Text := ComboRenameMask.Items[0];
    SetCaseControls(TCaseMode(Ini.ReadInteger('Rename', 'Case', 0)), CheckRenameCase,
      RadioRenameLower, RadioRenameUpper, RadioRenameTitle, RadioRenameSentence);
    CheckRenameUnderscores.Checked := Ini.ReadBool('Rename', 'Underscores', False);
    CheckRenamePadTrack.Checked := Ini.ReadBool('Rename', 'PadTrack', True);
    ComboF2TMask.Text := Ini.ReadString('FileToTag', 'Mask', ComboF2TMask.Items[0]);
    if Trim(ComboF2TMask.Text) = '' then ComboF2TMask.Text := ComboF2TMask.Items[0];
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

{ The mask with every variable shown as <Field>, e.g. '%1 - %2' -> '<Kunstner> - <Titel>.mp3'.
  Vars are the 'code|caption' lists; the longest matching code wins (%aa before %a...). }
function MaskTemplate(const Mask, Ext: string; const Vars: array of string; SpacesTo: Char): string;
var
  I, J, Best: Integer;
  Code, Cap, BestCode, BestCap, Lit: string;
begin
  Result := '';
  I := 1;
  while I <= Length(Mask) do
  begin
    BestCode := '';
    if Mask[I] = '%' then
      for J := 0 to High(Vars) do
      begin
        Code := Copy(Vars[J], 1, Pos('|', Vars[J]) - 1);
        // variables only: '%' plus letters/digits (not the examples such as '%6 - %1 - %2')
        if (Length(Code) < 2) or (Code[1] <> '%') or (Pos(' ', Code) > 0) or (Pos('%', Code, 2) > 0) then
          Continue;
        if (Length(Code) > Length(BestCode)) and (Copy(Mask, I, Length(Code)) = Code) then
        begin
          BestCode := Code;
          BestCap := Copy(Vars[J], Pos('|', Vars[J]) + 1, MaxInt);
        end;
      end;
    if BestCode <> '' then
    begin
      Best := Pos(' (', BestCap); // 'Udgivelsesdato (hele datoen)' -> 'Udgivelsesdato'
      if Best > 0 then BestCap := Copy(BestCap, 1, Best - 1);
      Result := Result + '<' + BestCap + '>';
      Inc(I, Length(BestCode));
    end
    else
    begin
      Lit := Mask[I];
      if (Lit = ' ') and (SpacesTo <> ' ') then Lit := SpacesTo;
      Result := Result + Lit;
      Inc(I);
    end;
  end;
  if Result <> '' then Result := Result + Ext;
end;

procedure TFormMain.UpdateInlinePreviews;
var
  Info: TAudioInfo;
  NewName, Missing, S, Ext: string;
  M: TFileNameMatch;
  F: TTagField;
  Spaces: Char;
begin
  PanelRenameCase.Enabled := CheckRenameCase.Checked;
  PanelF2TCase.Enabled := CheckF2TCase.Checked;
  Info := FocusedInfo;
  if (Info = nil) and (FView.Count > 0) then Info := Item(0);
  // The boxes show the mask with field names; the focused file's actual result is the hint.
  if Info <> nil then Ext := ExtractFileExt(Info.FileName) else Ext := '.mp3';
  if CheckRenameUnderscores.Checked then Spaces := '_' else Spaces := ' ';
  LabelRenamePreview.Caption := MaskTemplate(ComboRenameMask.Text, Ext, RenameVars, Spaces);
  LabelF2TPreview.Caption := MaskTemplate(ComboF2TMask.Text, Ext, F2TVars, ' ');
  if Info = nil then
  begin
    PanelRenamePreview.Hint := '';
    PanelF2TPreview.Hint := '';
    Exit;
  end;
  // Rename: the new name of the focused file
  NewName := ExpandRenameMask(ComboRenameMask.Text, Info, 1, 2, RenameOptions, Missing);
  if Missing <> '' then
    S := rsMangler + Missing
  else if NewName = '' then
    S := rsUgyldigMaske
  else if SameFileName(ExtractFileDir(NewName), ExtractFileDir(Info.FileName)) then
    S := ExtractFileName(NewName)
  else
    S := ExtractRelativePath(IncludeTrailingPathDelimiter(ExtractFileDir(Info.FileName)), NewName);
  PanelRenamePreview.Hint := ExtractFileName(Info.FileName) + '  →  ' + S;
  // Tags from file name: what is read out of the focused file's name
  M := MatchFileName(ComboF2TMask.Text, Info.FileName, CheckF2TUnderscores.Checked, F2TCaseMode);
  if not M.Ok then
    S := rsFilnavnetPasserIkkeTilMasken
  else
  begin
    S := '';
    for F := Low(TTagField) to High(TTagField) do
      if F in M.Used then
      begin
        if S <> '' then S := S + '   ';
        S := S + TagFieldCaptions[F] + ': ' + M.Values[F];
      end;
  end;
  PanelF2TPreview.Hint := ExtractFileName(Info.FileName) + '  →  ' + S;
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
    M := TMenuItem.Create(PopupVars);
    M.Caption := rsMaskeEditorMenu;
    M.OnClick := @MaskEditorClick;
    PopupVars.Items.Add(M);
    M := TMenuItem.Create(PopupVars);
    M.Caption := '-';
    PopupVars.Items.Add(M);
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
  if Pos(rsEksempel, (Sender as TMenuItem).Caption) > 0 then
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
    if Problems = '' then Problems := rsAlleFilerHarAlleredeDet;
    MessageDlg(rsIntetAtOmdoebe, Problems, mtInformation, [mbOK], 0);
    Exit;
  end;
  Examples := '';
  for I := 0 to High(Plan) do
    if (Plan[I].Status = rsOk) and (Length(Examples) < 400) then
      Examples := Examples + ExtractFileName(Plan[I].OldName) + '  →  ' + ExtractFileName(Plan[I].NewName) + LineEnding;
  if MessageDlg(rsOmdoebFiler, Format(rsOmdoebDFilerS, [OkCount,
    IfThen(Skipped > 0, Format(rsDSpringesOverBrugForhaandsvis, [Skipped]), '')]) +
    LineEnding + LineEnding + Examples, mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  AddComboMaskToHistory('RenameMasks', ComboRenameMask);
  SaveInlineOptions;
  Screen.Cursor := crHourGlass;
  try
    Log := ExecuteRename(Plan);
  finally
    Screen.Cursor := crDefault;
  end;
  if Length(Log) > 0 then SetUndoLog(Log, rsFilerFlertal);
  SetMessage(Format(rsDFilerOmdoebtDFejl, [Length(Log), CountStatus(Plan, rsFailed)]));
  if CountStatus(Plan, rsFailed) > 0 then
  begin
    Problems := '';
    for I := 0 to High(Plan) do
      if Plan[I].Status = rsFailed then
        Problems := Problems + ExtractFileName(Plan[I].OldName) + ': ' + Plan[I].Detail + LineEnding;
    MessageDlg(rsNogleFilerBlevIkkeOmdoebt, Problems, mtWarning, [mbOK], 0);
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
  const PerItemFields: array of TTagFieldSet; const Cover: TBytes; const What: string;
  const PerCover: TCoverArray);
var
  I, Saved, Failed, Skipped: Integer;
  ItemCover: TBytes;
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
      // one cover for all files, or one per file (nil = no change)
      if PerCover <> nil then ItemCover := PerCover[I] else ItemCover := Cover;
      if (PerItemFields[I] = []) and (ItemCover = nil) then Continue;
      SetMessage(Format(rsSDAfD, [What, I + 1, Length(Items)]));
      Application.ProcessMessages;
      if UpdateFileTags(Items[I], PerItem[I], PerItemFields[I], ItemCover, FKeepTimestamp, Err, Skip) then
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
  SetMessage(Format(rsSGemtIDFiler, [What, Saved, Failed,
    IfThen(Skipped > 0, Format(rsDSprungetOverFiltype, [Skipped]), '')]));
  if Errors.Count > 0 then
    Inform(rsNogleFilerBlevIkkeGemt, Errors.Text, mtWarning);
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
    MessageDlg(rsSaetFluebenVedDeFelter, mtInformation, [mbOK], 0);
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
  if MessageDlg(rsGemTags, Format(rsGemIDFiler, [Length(Items)]) +
    IfThen(Cleared <> '', LineEnding + rsDisseFelterBliverRyddet + Cleared, ''),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  SetLength(PerItem, Length(Items));
  SetLength(PerFields, Length(Items));
  for I := 0 to High(Items) do
  begin
    PerItem[I] := Values;
    PerFields[I] := Fields;
  end;
  WriteFieldsBatch(Items, PerItem, PerFields, nil, rsMultiFilTagEditor);
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
    MessageDlg(rsIntetAtSkrive, Format(rsIngenFilerAendresDPasser, [NoMatch]), mtInformation, [mbOK], 0);
    Exit;
  end;
  if MessageDlg(rsSkrivTags, Format(rsSkrivTagsFraFilnavnetI, [Ready,
    IfThen(NoMatch > 0, Format(rsDPasserIkkeTilMasken, [NoMatch]), '')]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  AddComboMaskToHistory('FileToTagMasks', ComboF2TMask);
  SaveInlineOptions;
  WriteFieldsBatch(Items, PerItem, PerFields, nil, rsTagsFraFilnavn);
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
      LabelFolderCoverInfo.Caption := rsIntetBilledeTraekEtBillede;
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
      LabelFolderCoverInfo.Caption := Format(rsSDxD, [ExtractFileName(CoverPath), W, H]);
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
    LabelFileCoverInfo.Caption := rsIntetCoverTraekEtBillede;
    Exit;
  end;
  Full := ReadAudioInfo(Info.FileName, True);
  try
    if Length(Full.Pictures) > 0 then
    begin
      ShowImageBytes(ImageFileCover, Full.Pictures[0].Data);
      ImageDimensions(Full.Pictures[0].Data, W, H);
      LabelFileCoverInfo.Caption := Format(IfThen(Length(Full.Pictures) = 1, rsSDxDDBillede,
        rsSDxDDBilleder), [PictureTypeName(Full.Pictures[0].PicType), W, H, Length(Full.Pictures)]);
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
    MessageDlg(rsKunJpegOgPngBilleder, mtWarning, [mbOK], 0);
    Exit;
  end;

  if Over(PanelFolderCover) then
  begin
    Info := FocusedInfo;
    if Info <> nil then Dir := ExtractFileDir(Info.FileName) else Dir := FFolder;
    if DetectImageMime(Data) = 'image/png' then Target := 'folder.png' else Target := 'folder.jpg';
    Target := IncludeTrailingPathDelimiter(Dir) + Target;
    if FileExists(Target) and (MessageDlg(rsMappensCover, Format(rsSFindesAlleredeErstatDet,
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
        MessageDlg(rsBilledetKunneIkkeGemmes + LineEnding + E.Message, mtError, [mbOK], 0);
        Exit;
      end;
    end;
    FFolderCoverDir := '';
    UpdateCovers;
    SetMessage(rsMappensCoverGemtSom + ExtractFileName(Target));
  end
  else if Over(PanelFileCover) then
  begin
    if not RequireTargets(Items) then Exit;
    if MessageDlg(rsFilensCover, Format(rsSaetBilledetSomForsideCover, [Length(Items)]),
      mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
    SetLength(PerItem, Length(Items));
    SetLength(PerFields, Length(Items));
    for I := 0 to High(Items) do
    begin
      PerItem[I] := FieldValuesOf(Items[I]);
      PerFields[I] := [];
    end;
    WriteFieldsBatch(Items, PerItem, PerFields, Data, rsCover);
  end;
end;

{ TFormMain - filter }

procedure TFormMain.ButtonFilterApplyClick(Sender: TObject);
begin
  FFilterText := Trim(EditFilter.Text);
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
  if SelectDirectory(rsVaelgMappe, FFolder, Dir) then Navigate(Dir);
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
  if Length(Log) > 0 then SetUndoLog(Log, rsFilerFlertal);
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
    SetUndoLog(Log, rsMapperFlertal);
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
  if Length(Items) = 0 then
  begin
    // Nothing ticked or selected: take the whole list if it is one album folder.
    Items := AllItems;
    OneFolder := True;
    for I := 1 to High(Items) do
      if not SameFileName(ExtractFileDir(Items[I].FileName), ExtractFileDir(Items[0].FileName)) then
        OneFolder := False;
    if not OneFolder then
    begin
      MessageDlg(rsAfkrydsEllerMarkerFilerneFra, mtInformation, [mbOK], 0);
      Exit;
    end;
  end;
  TFormWebLookup.Execute(Items, FKeepTimestamp);
  FActKeepDate.Checked := FKeepTimestamp;
  FCoverFile := '';
  FileList.Invalidate;
  SelectionChanged;
end;

procedure TFormMain.PlayWith(const FileName: string);
var
  Prog: string;
  P: TProcess;
begin
  Prog := PlayerFor(FileName);
  if Prog = '' then
  begin
    OpenDocument(FileName);
    Exit;
  end;
  P := TProcess.Create(nil);
  try
    P.Executable := Prog;
    P.Parameters.Add(FileName);
    P.Options := [];
    try
      P.Execute;
    except
      on E: Exception do Inform(rsAfspilFil, Prog + ': ' + E.Message, mtWarning);
    end;
  finally
    P.Free; // the player keeps running
  end;
end;

procedure TFormMain.ActPlayExecute(Sender: TObject);
var
  Info: TAudioInfo;
begin
  Info := FocusedInfo;
  if Info <> nil then PlayWith(Info.FileName);
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
  SetMessage(rsTagKopieretFra + ExtractFileName(Info.FileName));
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
  Fields := LoadPasteFields;
  if not FAutoYes then
  begin
    if not AskFieldSet(rsIndsaetTag, Format(rsVaelgFelterDerIndsaettesID, [Length(Items)]), FClip, Fields) then
      Exit;
    SavePasteFields(Fields);
  end;
  // fields that were empty in the copied file are not pasted (they would clear the targets)
  for I := 0 to Ord(High(TTagField)) do
    if FClip[TTagField(I)] = '' then Exclude(Fields, TTagField(I));
  if Fields = [] then Exit;
  SetLength(PerItem, Length(Items));
  SetLength(PerFields, Length(Items));
  for I := 0 to High(Items) do
  begin
    PerItem[I] := FClip;
    PerFields[I] := Fields;
  end;
  WriteFieldsBatch(Items, PerItem, PerFields, nil, rsIndsaetTag);
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

{ A mask expanded for one file as plain text (no folders, no extension); '' when a field is missing. }
function MaskText(const Mask: string; Info: TAudioInfo): string;
var
  Opt: TRenameOptions;
  Missing: string;
begin
  Opt := Default(TRenameOptions);
  Result := ExpandRenameMask(Mask, Info, 1, 2, Opt, Missing);
  if Result <> '' then Result := ChangeFileExt(ExtractFileName(Result), '');
end;

procedure WritePlaylist(const FileName: string; const Items: TAudioInfoArray; FullPaths: Boolean = False);
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
      if AppOptions.PlExtInf then
      begin
        Name := MaskText(AppOptions.PlInfoMask, Info);
        if Name = '' then Name := ChangeFileExt(ExtractFileName(Info.FileName), '');
        L.Add(Format('#EXTINF:%d,%s', [Round(Info.Duration), Name]));
      end;
      Path := Info.FileName;
      // relative paths keep the playlist working when the music folder moves
      if not FullPaths and not AppOptions.PlFullPaths and SameFileName(Copy(Path, 1, Length(Dir)), Dir) then
        Path := Copy(Path, Length(Dir) + 1, MaxInt);
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
    MessageDlg(rsDerErIngenFilerAt, mtInformation, [mbOK], 0);
    Exit;
  end;
  D := TSaveDialog.Create(Owner);
  try
    D.Title := rsGemPlayliste;
    D.Filter := rsPlaylisteUtfMUM;
    D.DefaultExt := 'm3u8';
    D.InitialDir := ExtractFileDir(Items[0].FileName);
    if (AppOptions.PlFolder <> '') and DirectoryExists(AppOptions.PlFolder) then D.InitialDir := AppOptions.PlFolder;
    D.FileName := ExtractFileName(ExtractFileDir(Items[0].FileName)) + '.m3u8';
    D.Options := D.Options + [ofOverwritePrompt];
    if D.Execute then
    begin
      WritePlaylist(D.FileName, Items);
      Owner.SetMessage(Format(rsPlaylisteMedDFilerGemt, [Length(Items), ExtractFileName(D.FileName)]));
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
      rsLavEtPersonligtTokenPaa, True, Value) then Exit;
    Ini.WriteString('Discogs', 'Token', Trim(Value));
  finally
    Ini.Free;
  end;
  SetMessage(IfThen(Trim(Value) = '', rsDiscogsTokenFjernet, rsDiscogsTokenGemt));
end;

procedure TFormMain.ActShortcutsExecute(Sender: TObject);
begin
  MessageDlg(rsTastaturgenveje,
    rsEnterDobbeltklikRedigerTagFor, mtInformation, [mbOK], 0);
end;

function TFormMain.InScanScope(const Path: string): Boolean;
var
  Dir: string;
begin
  Dir := ExcludeTrailingPathDelimiter(ExtractFileDir(Path));
  if SameFileName(Dir, ExcludeTrailingPathDelimiter(FFolder)) then Exit(True);
  Result := FActSubfolders.Checked and
    SameFileName(Copy(Dir, 1, Length(IncludeTrailingPathDelimiter(FFolder))), IncludeTrailingPathDelimiter(FFolder));
end;

procedure TFormMain.ActDeleteFilesExecute(Sender: TObject);
var
  Items: TAudioInfoArray;
  Names: array of string;
  I, Gone: Integer;
  Errors: TStringList;
begin
  if not RequireTargets(Items) then Exit;
  if not AskYes(rsSletFiler, Format(rsLaegDFilerIPapirkurven, [Length(Items)]), mtWarning) then Exit;
  SetLength(Names, Length(Items));
  for I := 0 to High(Items) do Names[I] := Items[I].FileName;
  Errors := TStringList.Create;
  try
    Gone := RecycleFiles(Names, Errors);
    for I := 0 to High(Items) do
      if not FileExists(Items[I].FileName) then
      begin
        FItems.Remove(Items[I]);
        Items[I].Free;
      end;
    FileList.ClearSelection;
    RebuildView;
    SetMessage(Format(rsDFilerLagtIPapirkurven, [Gone]));
    if Errors.Count > 0 then Inform(rsSletFiler, Errors.Text, mtWarning);
  finally
    Errors.Free;
  end;
  SelectionChanged;
end;

procedure TFormMain.ActCopyToExecute(Sender: TObject);
var
  D: TSelectDirectoryDialog;
begin
  D := TSelectDirectoryDialog.Create(nil);
  try
    D.Title := rsKopierTilMappe;
    D.InitialDir := FFolder;
    if D.Execute then CopyOrMoveTo(False, D.FileName);
  finally
    D.Free;
  end;
end;

procedure TFormMain.ActMoveToExecute(Sender: TObject);
var
  D: TSelectDirectoryDialog;
begin
  D := TSelectDirectoryDialog.Create(nil);
  try
    D.Title := rsFlytTilMappe;
    D.InitialDir := FFolder;
    if D.Execute then CopyOrMoveTo(True, D.FileName);
  finally
    D.Free;
  end;
end;

procedure TFormMain.CopyOrMoveTo(Move: Boolean; const Dir: string);
var
  Items: TAudioInfoArray;
  Names, NewNames: array of string;
  Done: array of Boolean;
  I, Count: Integer;
  Errors: TStringList;
  Title: string;
begin
  if not RequireTargets(Items) then Exit;
  if Move then Title := rsFlytTilMappe else Title := rsKopierTilMappe;
  if not AskYes(Title, Format(IfThen(Move, rsFlytDFilerTilS, rsKopierDFilerTilS), [Length(Items), Dir])) then
    Exit;
  SetLength(Names, Length(Items));
  SetLength(NewNames, Length(Items));
  SetLength(Done, Length(Items));
  for I := 0 to High(Items) do Names[I] := Items[I].FileName;
  Errors := TStringList.Create;
  Screen.Cursor := crHourGlass;
  try
    Count := CopyOrMoveFiles(Names, Dir, Move, Done, NewNames, Errors);
    if Move then
    begin
      for I := 0 to High(Items) do
        if Done[I] then
          if InScanScope(NewNames[I]) then
            Items[I].FileName := NewNames[I]
          else
          begin
            FItems.Remove(Items[I]);
            Items[I].Free;
          end;
      FileList.ClearSelection;
      RebuildView;
    end
    else if (Count > 0) and InScanScope(IncludeTrailingPathDelimiter(Dir) + 'x') then
      StartScan; // the copies belong in the list
    SetMessage(Format(IfThen(Move, rsDFilerFlyttetTilS, rsDFilerKopieretTilS), [Count, Dir]));
    if Errors.Count > 0 then Inform(Title, Errors.Text, mtWarning);
  finally
    Screen.Cursor := crDefault;
    Errors.Free;
  end;
  SelectionChanged;
end;

var
  GCoverOpt: TCoverResize = (MaxSide: 600; Quality: 90; ToJpeg: False);

{ TagWriter.PictureFilter: shrink pictures bigger than the chosen size before saving. }
procedure ShrinkPictures(Info: TAudioInfo);
var
  I: Integer;
  Data: TBytes;
  Mime: string;
begin
  for I := 0 to High(Info.Pictures) do
    if ResizeCover(Info.Pictures[I].Data, GCoverOpt, Data, Mime) then
    begin
      Info.Pictures[I].Data := Data;
      Info.Pictures[I].MimeType := Mime;
    end;
end;

procedure TFormMain.ActAutoResizeExecute(Sender: TObject);
begin
  if (Sender <> nil) and FActAutoResize.Checked and not FAutoYes then
    if not AskCoverResize(rsSkalerStoreCoverVedGem, GCoverOpt) then
    begin
      FActAutoResize.Checked := False;
      Exit;
    end;
  if FActAutoResize.Checked then PictureFilter := @ShrinkPictures else PictureFilter := nil;
end;

procedure TFormMain.ActResizeFileCoversExecute(Sender: TObject);
begin
  if FAutoYes or AskCoverResize(rsSkalerCoverIFilerne, GCoverOpt) then ResizeFileCovers;
end;

procedure TFormMain.ResizeFileCovers;
var
  Items: TAudioInfoArray;
  Full: TAudioInfo;
  I, P, NDone, Failed: Integer;
  Any: Boolean;
  Data: TBytes;
  Mime: string;
  Errors: TStringList;
begin
  if not RequireTargets(Items) then Exit;
  if not AskYes(rsSkalerCover, Format(rsSkalerCoverIDFiler, [Length(Items), GCoverOpt.MaxSide])) then Exit;
  NDone := 0;
  Failed := 0;
  Errors := TStringList.Create;
  Screen.Cursor := crHourGlass;
  try
    for I := 0 to High(Items) do
    begin
      if not Items[I].HasCover or not CanWriteTags(Items[I].FileName) then Continue;
      SetMessage(Format(rsSDAfD, [rsSkalerCover, I + 1, Length(Items)]));
      Application.ProcessMessages;
      Full := ReadAudioInfo(Items[I].FileName, True);
      try
        Any := False;
        for P := 0 to High(Full.Pictures) do
          if ResizeCover(Full.Pictures[P].Data, GCoverOpt, Data, Mime) then
          begin
            Full.Pictures[P].Data := Data;
            Full.Pictures[P].MimeType := Mime;
            Any := True;
          end;
        if Any then
          try
            WriteAudioTags(Full, FKeepTimestamp);
            Inc(NDone);
          except
            on E: Exception do
            begin
              Inc(Failed);
              Errors.Add(ExtractFileName(Items[I].FileName) + ': ' + E.Message);
            end;
          end;
      finally
        Full.Free;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  SetMessage(Format(rsSGemtIDFiler, [rsSkalerCover, NDone, Failed, '']));
  if Errors.Count > 0 then Inform(rsNogleFilerBlevIkkeGemt, Errors.Text, mtWarning);
  Errors.Free;
  FCoverFile := '';
  SelectionChanged;
end;

procedure TFormMain.ActResizeFolderCoversExecute(Sender: TObject);
begin
  if FAutoYes or AskCoverResize(rsSkalerMappeCover, GCoverOpt) then ResizeFolderCovers;
end;

procedure TFormMain.ResizeFolderCovers;
var
  Items: TAudioInfoArray;
  Dirs: TStringList;
  I, NDone: Integer;
  Path, Target, Mime: string;
  Data: TBytes;
  Errors: TStringList;
begin
  if not RequireTargets(Items) then Exit;
  Dirs := TStringList.Create;
  Errors := TStringList.Create;
  try
    Dirs.Sorted := True;
    Dirs.Duplicates := dupIgnore;
    for I := 0 to High(Items) do
      if FindFolderCover(ExtractFileDir(Items[I].FileName)) <> '' then
        Dirs.Add(ExtractFileDir(Items[I].FileName));
    if Dirs.Count = 0 then
    begin
      Inform(rsSkalerMappeCover, rsIngenAfMapperneHarEtCover);
      Exit;
    end;
    if not AskYes(rsSkalerMappeCover, Format(rsSkalerCoverIDMapper, [Dirs.Count, GCoverOpt.MaxSide])) then Exit;
    NDone := 0;
    for I := 0 to Dirs.Count - 1 do
    begin
      Path := FindFolderCover(Dirs[I]);
      try
        if not ResizeCover(ReadFileBytes(Path), GCoverOpt, Data, Mime) then Continue;
        Target := Path;
        if (Mime = 'image/jpeg') and SameText(ExtractFileExt(Path), '.png') then
          Target := ChangeFileExt(Path, '.jpg');
        WriteFileBytes(Target, Data);
        if Target <> Path then RecycleFiles([Path], Errors); // the PNG became a JPEG
        Inc(NDone);
      except
        on E: Exception do Errors.Add(Path + ': ' + E.Message);
      end;
    end;
    SetMessage(Format(rsCoverGemtIDMapper, [NDone]));
    if Errors.Count > 0 then Inform(rsSkalerMappeCover, Errors.Text, mtWarning);
  finally
    Dirs.Free;
    Errors.Free;
  end;
  FFolderCoverDir := '';
  SelectionChanged;
end;

procedure TFormMain.ActDeleteFolderCoversExecute(Sender: TObject);
const
  Names: array[0..5] of string = ('folder.jpg', 'folder.png', 'cover.jpg', 'cover.png', 'front.jpg', 'front.png');
var
  Items: TAudioInfoArray;
  Dirs: TStringList;
  Files: array of string;
  I: Integer;
  N: string;
  Errors: TStringList;
begin
  if not RequireTargets(Items) then Exit;
  Dirs := TStringList.Create;
  Errors := TStringList.Create;
  try
    Dirs.Sorted := True;
    Dirs.Duplicates := dupIgnore;
    for I := 0 to High(Items) do Dirs.Add(ExtractFileDir(Items[I].FileName));
    Files := nil;
    for I := 0 to Dirs.Count - 1 do
      for N in Names do
        if FileExists(IncludeTrailingPathDelimiter(Dirs[I]) + N) then
        begin
          SetLength(Files, Length(Files) + 1);
          Files[High(Files)] := IncludeTrailingPathDelimiter(Dirs[I]) + N;
        end;
    if Length(Files) = 0 then
    begin
      Inform(rsSletMappeCover, rsIngenAfMapperneHarEtCover);
      Exit;
    end;
    if not AskYes(rsSletMappeCover, Format(rsLaegDMappeCoverIPapirkurven, [Length(Files), Dirs.Count]),
      mtWarning) then Exit;
    SetMessage(Format(rsDFilerLagtIPapirkurven, [RecycleFiles(Files, Errors)]));
    if Errors.Count > 0 then Inform(rsSletMappeCover, Errors.Text, mtWarning);
  finally
    Dirs.Free;
    Errors.Free;
  end;
  FFolderCoverDir := '';
  SelectionChanged;
end;

procedure TFormMain.ActCoverAsFolderExecute(Sender: TObject);
var
  Info, Full: TAudioInfo;
  Pic, I: Integer;
  Target: string;
begin
  Info := FocusedInfo;
  if (Info = nil) and (FView.Count > 0) then Info := Item(0);
  if (Info = nil) or not Info.HasCover then
  begin
    Inform(rsBrugFilensCoverSomMappeCover, rsDenMarkeredeFilHarIntetCover);
    Exit;
  end;
  Full := ReadAudioInfo(Info.FileName, True);
  try
    Pic := -1;
    for I := 0 to High(Full.Pictures) do
      if Full.Pictures[I].PicType = PicTypeFrontCover then begin Pic := I; Break; end;
    if (Pic < 0) and (Length(Full.Pictures) > 0) then Pic := 0;
    if Pic < 0 then Exit;
    if Full.Pictures[Pic].MimeType = 'image/png' then Target := 'folder.png' else Target := 'folder.jpg';
    Target := IncludeTrailingPathDelimiter(ExtractFileDir(Info.FileName)) + Target;
    if FileExists(Target) and not AskYes(rsMappensCover, Format(rsSFindesAlleredeErstatDet,
      [ExtractFileName(Target)])) then Exit;
    try
      WriteFileBytes(Target, Full.Pictures[Pic].Data);
      SetMessage(rsMappensCoverGemtSom + Target);
    except
      on E: Exception do Inform(rsMappensCover, rsBilledetKunneIkkeGemmes + LineEnding + E.Message, mtWarning);
    end;
  finally
    Full.Free;
  end;
  FFolderCoverDir := '';
  SelectionChanged;
end;

function TFormMain.RenameMaskPreview(const Mask: string): string;
var
  Info: TAudioInfo;
  Missing, Dir: string;
begin
  Info := FocusedInfo;
  if (Info = nil) and (FView.Count > 0) then Info := Item(0);
  if Info = nil then Exit('');
  Result := ExpandRenameMask(Mask, Info, 1, 2, RenameOptions, Missing);
  if Result = '' then
  begin
    if Missing <> '' then Result := rsMangler + Missing else Result := rsUgyldigMaske;
    Exit;
  end;
  Dir := IncludeTrailingPathDelimiter(ExtractFileDir(Info.FileName));
  if SameFileName(Copy(Result, 1, Length(Dir)), Dir) then Delete(Result, 1, Length(Dir));
end;

procedure TFormMain.MaskEditorClick(Sender: TObject);
var
  Mask: string;
begin
  Mask := ComboRenameMask.Text;
  if not EditMask(rsMaskeEditorTitel, Mask, RenameVars, @RenameMaskPreview, 'SavedRenameMasks') then Exit;
  ComboRenameMask.Text := Mask;
  UpdateInlinePreviews;
end;

procedure TFormMain.SyncSettingsMenus;
var
  I: Integer;
  Cur: string;
begin
  if FLanguageMenu <> nil then
  begin
    Cur := LanguageSetting;
    for I := 0 to FLanguageMenu.Count - 1 do
      if FLanguageMenu[I].Tag < 0 then FLanguageMenu[I].Checked := Cur = ''
      else FLanguageMenu[I].Checked := Cur = LanguageCodes[FLanguageMenu[I].Tag];
  end;
  if FAlbumArtistMenu <> nil then
    for I := 0 to FAlbumArtistMenu.Count - 1 do
      FAlbumArtistMenu[I].Checked := FAlbumArtistMenu[I].Tag = Ord(AlbumArtistRule);
end;

type
  { Buttons on the settings dialog that open the existing dialogs. }
  TSettingsButtons = class
    Main: TFormMain;
    procedure WordsClick(Sender: TObject);
    procedure ActionsClick(Sender: TObject);
    procedure TokenClick(Sender: TObject);
    procedure GenresClick(Sender: TObject);
  end;

procedure TSettingsButtons.GenresClick(Sender: TObject);
begin
  Main.ActGenresExecute(nil);
end;

procedure TSettingsButtons.WordsClick(Sender: TObject);
begin
  Main.ActRenameWordsExecute(nil);
end;

procedure TSettingsButtons.ActionsClick(Sender: TObject);
begin
  Main.ActManageActionsExecute(nil);
end;

procedure TSettingsButtons.TokenClick(Sender: TObject);
begin
  Main.ActDiscogsTokenExecute(nil);
end;

procedure TFormMain.ActSettingsExecute(Sender: TObject);
var
  F: TForm;
  Pages: TPageControl;
  Tab: TTabSheet;
  RLang, RAlbum: TRadioGroup;
  CKeep, CAuto, CJpeg, CFit, CSub, CLow, CNoV1, CHideExt, CGrid, CUni, CExtInf, CFull: TCheckBox;
  ESide, EQual, ELow, EFont: TSpinEdit;
  RStart: TRadioGroup;
  EStart, EInfo, EPlFolder, EPlName: TEdit;
  MPlayers: TMemo;
  L: TLabel;
  BP: TButtonPanel;
  Btns: TSettingsButtons;
  I, Y: Integer;
  Cur, NewLang: string;
  R: TAlbumArtistRule;

  function NewTab(const ACaption: string): TTabSheet;
  begin
    Result := Pages.AddTabSheet;
    Result.Caption := ACaption;
    Y := 10;
  end;

  function Chk(Parent_: TWinControl; const ACaption: string; Value: Boolean): TCheckBox;
  begin
    Result := TCheckBox.Create(F);
    Result.Parent := Parent_;
    Result.Caption := ACaption;
    Result.Checked := Value;
    Result.Left := F.Scale96ToForm(12);
    Result.Top := F.Scale96ToForm(Y);
    Inc(Y, 30);
  end;

  function Lbl(Parent_: TWinControl; const ACaption: string): TLabel;
  begin
    Result := TLabel.Create(F);
    Result.Parent := Parent_;
    Result.Caption := ACaption;
    Result.Left := F.Scale96ToForm(32);
    Result.Top := F.Scale96ToForm(Y + 3);
  end;

  function Spin(Parent_: TWinControl; AMin, AMax, Value: Integer): TSpinEdit;
  begin
    Result := TSpinEdit.Create(F);
    Result.Parent := Parent_;
    Result.MinValue := AMin;
    Result.MaxValue := AMax;
    Result.Value := Value;
    Result.SetBounds(F.Scale96ToForm(260), F.Scale96ToForm(Y), F.Scale96ToForm(90), F.Scale96ToForm(23));
    Inc(Y, 32);
  end;

  function Ed(Parent_: TWinControl; const Value: string): TEdit;
  begin
    Result := TEdit.Create(F);
    Result.Parent := Parent_;
    Result.Text := Value;
    Result.SetBounds(F.Scale96ToForm(260), F.Scale96ToForm(Y), F.Scale96ToForm(332), F.Scale96ToForm(23));
    Inc(Y, 32);
  end;

  function Btn(Parent_: TWinControl; const ACaption: string; Handler: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(F);
    Result.Parent := Parent_;
    Result.Caption := ACaption;
    Result.SetBounds(F.Scale96ToForm(12), F.Scale96ToForm(Y), F.Scale96ToForm(300), F.Scale96ToForm(28));
    Result.OnClick := Handler;
    Inc(Y, 38);
  end;

begin
  F := TForm.CreateNew(Self);
  Btns := TSettingsButtons.Create;
  try
    Btns.Main := Self;
    F.Caption := rsIndstillingerTitel;
    F.BorderStyle := bsDialog;
    F.Position := poMainFormCenter;
    F.ClientWidth := F.Scale96ToForm(620);
    F.ClientHeight := F.Scale96ToForm(480);
    BP := TButtonPanel.Create(F);
    BP.Parent := F;
    BP.ShowButtons := [pbOK, pbCancel];
    Pages := TPageControl.Create(F);
    Pages.Parent := F;
    Pages.Align := alClient;

    // general
    Tab := NewTab(rsGenerelt);
    RLang := TRadioGroup.Create(F);
    RLang.Parent := Tab;
    RLang.Caption := rsSprogLanguage;
    RLang.SetBounds(F.Scale96ToForm(12), F.Scale96ToForm(8), F.Scale96ToForm(240), F.Scale96ToForm(230));
    RLang.Items.Add(rsAutomatiskWindowsSprog);
    for I := 0 to High(LanguageNames) do RLang.Items.Add(LanguageNames[I]);
    Cur := LanguageSetting;
    RLang.ItemIndex := 0;
    for I := 0 to High(LanguageCodes) do
      if LanguageCodes[I] = Cur then RLang.ItemIndex := I + 1;
    RAlbum := TRadioGroup.Create(F);
    RAlbum.Parent := Tab;
    RAlbum.Caption := rsAlbumkunstnerVedGem;
    RAlbum.SetBounds(F.Scale96ToForm(264), F.Scale96ToForm(8), F.Scale96ToForm(340), F.Scale96ToForm(130));
    RAlbum.Items.Add(rsAlbumkunstnerIngen);
    RAlbum.Items.Add(rsAlbumkunstnerHvisTom);
    RAlbum.Items.Add(rsAlbumkunstnerAltid);
    RAlbum.ItemIndex := Ord(AlbumArtistRule);
    Y := 250;
    CKeep := Chk(Tab, rsBevarFilernesDatoVedGem, FKeepTimestamp);
    CUni := Chk(Tab, rsID3Unicode, AppOptions.ID3Unicode);
    Btn(Tab, rsGenreliste, @Btns.GenresClick);

    // covers
    Tab := NewTab(rsCoverFane);
    CAuto := Chk(Tab, rsSkalerStoreCoverAutomatisk, FActAutoResize.Checked);
    Lbl(Tab, rsStoersteSideSetting);
    ESide := Spin(Tab, 50, 5000, GCoverOpt.MaxSide);
    Lbl(Tab, rsJpegKvalitetSetting);
    EQual := Spin(Tab, 1, 100, GCoverOpt.Quality);
    CJpeg := Chk(Tab, rsKonverterPngTilJpegSetting, GCoverOpt.ToJpeg);

    // file list
    Tab := NewTab(rsFillisteFane);
    CFit := Chk(Tab, rsTilpasKolonnerEfterMappeskift, FActAutoFitAfterScan.Checked);
    CSub := Chk(Tab, rsSoegIUndermapper, FActSubfolders.Checked);
    CLow := Chk(Tab, rsMarkerLavBitrate, AppOptions.MarkLowBitrate);
    Lbl(Tab, rsGraenseKbit);
    ELow := Spin(Tab, 8, 1000, AppOptions.LowBitrate);
    CNoV1 := Chk(Tab, rsMarkerUdenID3v1, AppOptions.MarkNoID3v1);
    CHideExt := Chk(Tab, rsSkjulFiltypenavne, AppOptions.HideExtensions);
    CGrid := Chk(Tab, rsGitterlinjer, AppOptions.GridLines);
    Lbl(Tab, rsSkriftstoerrelse).Left := F.Scale96ToForm(12);
    EFont := Spin(Tab, 0, 24, AppOptions.ListFontSize);
    RStart := TRadioGroup.Create(F);
    RStart.Parent := Tab;
    RStart.Caption := rsStartmappe;
    RStart.SetBounds(F.Scale96ToForm(12), F.Scale96ToForm(Y), F.Scale96ToForm(236), F.Scale96ToForm(64));
    RStart.Items.Add(rsSidsteMappe);
    RStart.Items.Add(rsFastMappe);
    if AppOptions.FixedStartFolder then RStart.ItemIndex := 1 else RStart.ItemIndex := 0;
    Inc(Y, 32);
    EStart := Ed(Tab, AppOptions.StartFolder);
    if EStart.Text = '' then EStart.Text := FFolder;

    // rename and web
    Tab := NewTab(rsOmdoebningOgWeb);
    Btn(Tab, rsOrdudskiftningerMenu, @Btns.WordsClick);
    Btn(Tab, rsAdministrerHandlinger, @Btns.ActionsClick);
    Btn(Tab, rsDiscogsTokenMenu, @Btns.TokenClick);

    // players
    Tab := NewTab(rsAfspillereFane);
    L := TLabel.Create(F);
    L.Parent := Tab;
    L.WordWrap := True;
    L.AutoSize := False;
    L.SetBounds(F.Scale96ToForm(12), F.Scale96ToForm(8), F.Scale96ToForm(580), F.Scale96ToForm(64));
    L.Caption := rsAfspillereHjaelp;
    MPlayers := TMemo.Create(F);
    MPlayers.Parent := Tab;
    MPlayers.ScrollBars := ssAutoBoth;
    MPlayers.WordWrap := False;
    MPlayers.SetBounds(F.Scale96ToForm(12), F.Scale96ToForm(78), F.Scale96ToForm(580), F.Scale96ToForm(300));
    for I := 0 to High(AppOptions.Players) do MPlayers.Lines.Add(AppOptions.Players[I]);

    // playlists
    Tab := NewTab(rsPlaylisterFane);
    CExtInf := Chk(Tab, rsSkrivExtinf, AppOptions.PlExtInf);
    Lbl(Tab, rsExtinfTekst);
    EInfo := Ed(Tab, AppOptions.PlInfoMask);
    CFull := Chk(Tab, rsFuldeStier, AppOptions.PlFullPaths);
    Lbl(Tab, rsPlaylisteMappe).Left := F.Scale96ToForm(12);
    Inc(Y, 22);
    EPlFolder := Ed(Tab, AppOptions.PlFolder);
    EPlFolder.Left := F.Scale96ToForm(12);
    EPlFolder.Width := F.Scale96ToForm(580);
    Lbl(Tab, rsHurtigGemNavn).Left := F.Scale96ToForm(12);
    EPlName := Ed(Tab, AppOptions.PlNameMask);
    L := Lbl(Tab, rsPlaylisteVarHjaelp);
    L.Left := F.Scale96ToForm(12);
    L.Font.Color := clGrayText;

    Pages.ActivePageIndex := 0;
    if F.ShowModal <> mrOK then Exit;

    // apply
    R := TAlbumArtistRule(RAlbum.ItemIndex);
    if R <> AlbumArtistRule then
    begin
      FAlbumArtistMenu[Ord(R)].Click; // stores the setting as well
    end;
    FKeepTimestamp := CKeep.Checked;
    FActKeepDate.Checked := FKeepTimestamp;
    GCoverOpt.MaxSide := ESide.Value;
    GCoverOpt.Quality := EQual.Value;
    GCoverOpt.ToJpeg := CJpeg.Checked;
    FActAutoResize.Checked := CAuto.Checked;
    ActAutoResizeExecute(nil);
    FActAutoFitAfterScan.Checked := CFit.Checked;
    AppOptions.ID3Unicode := CUni.Checked;
    AppOptions.MarkLowBitrate := CLow.Checked;
    AppOptions.LowBitrate := ELow.Value;
    AppOptions.MarkNoID3v1 := CNoV1.Checked;
    AppOptions.HideExtensions := CHideExt.Checked;
    AppOptions.GridLines := CGrid.Checked;
    AppOptions.ListFontSize := EFont.Value;
    AppOptions.FixedStartFolder := RStart.ItemIndex = 1;
    AppOptions.StartFolder := Trim(EStart.Text);
    AppOptions.Players := nil;
    for I := 0 to MPlayers.Lines.Count - 1 do
      if Pos('=', MPlayers.Lines[I]) > 1 then
      begin
        SetLength(AppOptions.Players, Length(AppOptions.Players) + 1);
        AppOptions.Players[High(AppOptions.Players)] := Trim(MPlayers.Lines[I]);
      end;
    AppOptions.PlExtInf := CExtInf.Checked;
    AppOptions.PlInfoMask := Trim(EInfo.Text);
    if AppOptions.PlInfoMask = '' then AppOptions.PlInfoMask := '%1 - %2';
    AppOptions.PlFullPaths := CFull.Checked;
    AppOptions.PlFolder := Trim(EPlFolder.Text);
    AppOptions.PlNameMask := Trim(EPlName.Text);
    if AppOptions.PlNameMask = '' then AppOptions.PlNameMask := '%f';
    SaveAppOptions;
    ApplyViewOptions;
    if CSub.Checked <> FActSubfolders.Checked then FActSubfolders.Execute; // rescans
    SaveSettings;
    if RLang.ItemIndex <= 0 then NewLang := '' else NewLang := LanguageCodes[RLang.ItemIndex - 1];
    if NewLang <> LanguageSetting then ChangeLanguage(NewLang);
  finally
    Btns.Free;
    F.Free;
  end;
end;

{ Caption of a mask variable ('Kunstner' for '%1') from the 'code|caption' lists. }
function MaskVarCaption(const Code: string): string;
var
  S: string;
begin
  for S in RenameVars do
    if Copy(S, 1, Length(Code) + 1) = Code + '|' then Exit(Copy(S, Length(Code) + 2, MaxInt));
  for S in F2TVars do
    if Copy(S, 1, Length(Code) + 1) = Code + '|' then Exit(Copy(S, Length(Code) + 2, MaxInt));
  Result := '';
end;

{ Lays the variables out as a table in Host's place (column by column, Rows per column,
  captions aligned after the codes) and leaves Host underneath for the notes. The table
  uses LCL child sizing and anchors, so it follows DPI scaling and translated widths. }
procedure TFormMain.BuildVarHelp(Host: TLabel; const Codes: array of string; Rows: Integer;
  const Notes: string);
var
  Table: TPanel;
  Cols, C, R, I: Integer;

  procedure Cell(const Text: string; RightSpace: Integer);
  var
    L: TLabel;
  begin
    L := TLabel.Create(Self);
    L.Caption := Text;
    L.ShowAccelChar := False;
    L.BorderSpacing.Right := RightSpace;
    L.Parent := Table;
  end;

begin
  Cols := (Length(Codes) + Rows - 1) div Rows;
  Table := TPanel.Create(Self);
  Table.BevelOuter := bvNone;
  Table.AutoSize := True;
  Table.Left := Host.Left;
  Table.Top := Host.Top;
  // children fill a column top to bottom, then the next column: codes, captions, codes, ...
  Table.ChildSizing.Layout := cclTopToBottomThenLeftToRight;
  Table.ChildSizing.ControlsPerLine := Rows;
  Table.ChildSizing.HorizontalSpacing := Scale96ToForm(6);
  Table.ChildSizing.VerticalSpacing := Scale96ToForm(1);
  Table.Parent := Host.Parent;
  for C := 0 to Cols - 1 do
  begin
    for R := 0 to Rows - 1 do
    begin
      I := C * Rows + R;
      if I <= High(Codes) then Cell(Codes[I], 0) else Cell('', 0);
    end;
    for R := 0 to Rows - 1 do
    begin
      I := C * Rows + R;
      if I <= High(Codes) then Cell(MaskVarCaption(Codes[I]), Scale96ToForm(18))
      else Cell('', Scale96ToForm(18));
    end;
  end;
  // the notes go below the table, as high as their wrapped text
  Host.AnchorSide[akTop].Control := Table;
  Host.AnchorSide[akTop].Side := asrBottom;
  Host.BorderSpacing.Top := Scale96ToForm(4);
  // wrapped at the tab's right edge; the height follows the text
  Host.AnchorSide[akRight].Control := Host.Parent;
  Host.AnchorSide[akRight].Side := asrRight;
  Host.BorderSpacing.Right := Scale96ToForm(8);
  Host.Anchors := [akLeft, akTop, akRight];
  Host.WordWrap := True;
  Host.AutoSize := True;
  Host.Caption := Notes;
end;

procedure TFormMain.BuildFilterExtras;
var
  L: TLabel;
  X, I: Integer;
  Bmp: TBitmap;

  function TextW(const T: string): Integer;
  begin
    Result := Bmp.Canvas.TextWidth(T);
  end;

  function Check(const Caption: string): TCheckBox;
  begin
    Result := TCheckBox.Create(Self);
    Result.Parent := PanelFilter;
    Result.Caption := Caption;
    Result.Left := X;
    Result.Top := ButtonShowAll.Top + Scale96ToForm(3);
    Result.OnClick := @FilterOptionChange;
    X := X + TextW(Caption) + Scale96ToForm(32);
  end;

begin
  Bmp := TBitmap.Create;
  try
    Bmp.Canvas.Font.Assign(PanelFilter.Font);
    // filter bar: narrower text box, then the two options after the buttons
    EditFilter.Width := Scale96ToForm(200);
    ButtonFilterApply.Left := EditFilter.Left + EditFilter.Width + Scale96ToForm(8);
    ButtonHideSelected.Left := ButtonFilterApply.Left + ButtonFilterApply.Width + Scale96ToForm(6);
    ButtonShowAll.Left := ButtonHideSelected.Left + ButtonHideSelected.Width + Scale96ToForm(6);
    X := ButtonShowAll.Left + ButtonShowAll.Width + Scale96ToForm(14);
    CheckFilterWhole := Check(rsHeleOrd);
    CheckFilterCase := Check(rsStoreSmaaBogstaver);
    // tag type: in the address bar, which has room to the right
    X := ComboAddress.Left + ComboAddress.Width + Scale96ToForm(16);
    L := TLabel.Create(Self);
    L.Parent := PanelAddress;
    L.Caption := rsTagtype;
    L.Left := X;
    L.Top := LabelAddress.Top;
    ComboTagType := TComboBox.Create(Self);
    ComboTagType.Parent := PanelAddress;
    ComboTagType.Style := csDropDownList;
    ComboTagType.Left := X + TextW(rsTagtype) + Scale96ToForm(8);
    ComboTagType.Top := ComboAddress.Top;
    ComboTagType.Width := Scale96ToForm(120);
    ComboTagType.Items.Add(rsAlleTagtyper);
    for I := 1 to High(TagTypeTokens) - 1 do ComboTagType.Items.Add(TagTypeTokens[I]);
    ComboTagType.Items.Add(rsIngenTagsFilter);
    ComboTagType.ItemIndex := 0;
    ComboTagType.OnChange := @FilterOptionChange;
  finally
    Bmp.Free;
  end;
end;

procedure TFormMain.FilterOptionChange(Sender: TObject);
begin
  FTagTypeFilter := ComboTagType.ItemIndex;
  if FLoading then Exit;
  RebuildView;
end;

procedure TFormMain.AutoFitColumns;
var
  C, I, W, Best, Rows: Integer;
  Bmp: TBitmap;
begin
  if FileList.Columns.Count = 0 then Exit;
  Bmp := TBitmap.Create;
  try
    Bmp.Canvas.Font.Assign(FileList.Font);
    Rows := Min(FView.Count, 1000); // enough to judge the width, quick for big lists
    for C := 1 to FileList.Columns.Count - 1 do // column 0 is the check mark
    begin
      Best := Bmp.Canvas.TextWidth(FileList.Columns[C].Caption) + Scale96ToForm(24);
      for I := 0 to Rows - 1 do
      begin
        W := Bmp.Canvas.TextWidth(CellText(Item(I), C)) + Scale96ToForm(16);
        if W > Best then Best := W;
      end;
      FileList.Columns[C].Width := Min(Best, Scale96ToForm(450));
    end;
  finally
    Bmp.Free;
  end;
end;

procedure TFormMain.ActAutoFitExecute(Sender: TObject);
begin
  AutoFitColumns;
end;

procedure TFormMain.ActAutoFitAfterScanExecute(Sender: TObject);
begin
  if FActAutoFitAfterScan.Checked then AutoFitColumns;
end;

procedure TFormMain.ActRandomOrderExecute(Sender: TObject);
var
  I, J: Integer;
begin
  Randomize;
  for I := FItems.Count - 1 downto 1 do
  begin
    J := Random(I + 1);
    FItems.Exchange(I, J);
  end;
  FSortColumn := -1; // manual order until a column is clicked
  FSort2Column := -1;
  RebuildView;
  SetMessage(rsManuelRaekkefoelgeKlikPaaEn);
end;

procedure TFormMain.ActNameToolExecute(Sender: TObject);
begin
  RunNameTool(TNameTool((Sender as TComponent).Tag));
end;

procedure TFormMain.RunNameTool(Tool: TNameTool);
var
  Items: TAudioInfoArray;
  Plans: array of TFieldPlan;
  I: Integer;
begin
  if not RequireTargets(Items) then Exit;
  SetLength(Plans, Length(Items));
  for I := 0 to High(Items) do Plans[I] := PlanNameTool(Items[I], tfArtist, Tool);
  RunFieldPlans(Items, Plans, rsKunstnerVaerktoejer);
end;

procedure TFormMain.ActID3SyncExecute(Sender: TObject);
begin
  if AskID3Sync(FSyncDir, FSyncExisting) then RunID3Sync(FSyncDir, FSyncExisting);
end;

procedure TFormMain.RunID3Sync(Direction: TSyncDirection; Existing: TSyncExisting);
var
  Items, Mp3: TAudioInfoArray;
  I, NChanged, Failed: Integer;
  Errors: TStringList;
begin
  if not RequireTargets(Items) then Exit;
  Mp3 := nil;
  for I := 0 to High(Items) do
    if SameText(ExtractFileExt(Items[I].FileName), '.mp3') then
    begin
      SetLength(Mp3, Length(Mp3) + 1);
      Mp3[High(Mp3)] := Items[I];
    end;
  if Length(Mp3) = 0 then
  begin
    Inform(rsMpTagSynkronisering, rsIngenMpFiler);
    Exit;
  end;
  if not AskYes(rsMpTagSynkronisering, Format(rsSynkroniserTagsIDMpFiler, [Length(Mp3)])) then Exit;
  NChanged := 0;
  Failed := 0;
  Errors := TStringList.Create;
  Screen.Cursor := crHourGlass;
  try
    for I := 0 to High(Mp3) do
    begin
      SetMessage(Format(rsSDAfD, [rsMpTagSynkronisering, I + 1, Length(Mp3)]));
      Application.ProcessMessages;
      try
        if SyncID3(Mp3[I].FileName, Direction, Existing, FKeepTimestamp) then Inc(NChanged);
      except
        on E: Exception do
        begin
          Inc(Failed);
          if Errors.Count < 20 then Errors.Add(ExtractFileName(Mp3[I].FileName) + ': ' + E.Message);
        end;
      end;
      RefreshInfo(Mp3[I]);
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  SetMessage(Format(rsSGemtIDFiler, [rsMpTagSynkronisering, NChanged, Failed, '']));
  if Errors.Count > 0 then Inform(rsNogleFilerBlevIkkeGemt, Errors.Text, mtWarning);
  Errors.Free;
  FileList.Invalidate;
  SelectionChanged;
end;

procedure TFormMain.ActReplayGainExecute(Sender: TObject);
begin
  if AskReplayGain(FRGAlbum, FRGSkip) then RunReplayGain(FRGAlbum, FRGSkip);
end;

{ Album gain covers the files of one folder with the same album name. }
function RGAlbumKey(Info: TAudioInfo): string;
begin
  Result := LowerCase(ExtractFileDir(Info.FileName)) + '|' + LowerCase(Trim(Info.Fields[tfAlbum]));
end;

procedure TFormMain.RunReplayGain(Album, SkipExisting: Boolean);
var
  Items, Todo: TAudioInfoArray;
  Keys, Groups, Errors: TStringList;
  Files: TStringArray;
  Batch: TRGBatch;
  PerItem: array of TFieldValues;
  PerFields: array of TTagFieldSet;
  Members: array of TRGMeasure;
  F: TTagField;
  I, J, Bad: Integer;
  Gain, Peak, AlbumName: string;
  Done: Boolean;

  function HasValues(Info: TAudioInfo): Boolean;
  begin
    Result := (Info.Fields[tfRGTrackGain] <> '') and (not Album or (Info.Fields[tfRGAlbumGain] <> ''));
  end;

begin
  if not RequireTargets(Items) then Exit;
  // groups that are complete already are skipped as a whole, so album values stay consistent
  Groups := TStringList.Create;
  Keys := TStringList.Create;
  Errors := TStringList.Create;
  try
    Groups.Sorted := True;
    Groups.Duplicates := dupIgnore;
    if SkipExisting then
      for I := 0 to High(Items) do
        if not HasValues(Items[I]) then
        begin
          if Album then Groups.Add(RGAlbumKey(Items[I])) else Groups.Add(Items[I].FileName);
        end;
    Todo := nil;
    for I := 0 to High(Items) do
    begin
      if Album then Done := Groups.IndexOf(RGAlbumKey(Items[I])) < 0
      else Done := Groups.IndexOf(Items[I].FileName) < 0;
      if SkipExisting and Done then Continue;
      SetLength(Todo, Length(Todo) + 1);
      Todo[High(Todo)] := Items[I];
      Keys.Add(RGAlbumKey(Items[I]));
    end;
    if Length(Todo) = 0 then
    begin
      Inform(rsReplayGainTitel, rsRGIntetAtGoere);
      Exit;
    end;
    SetLength(Files, Length(Todo));
    for I := 0 to High(Todo) do Files[I] := Todo[I].FileName;
    SetLength(PerItem, Length(Todo));
    SetLength(PerFields, Length(Todo));
    Batch := TRGBatch.Create(Files);
    try
      if not RunReplayGainBatch(rsReplayGainTitel, Batch) then
      begin
        SetMessage(rsRGAfbrudt);
        Exit;
      end;
      for I := 0 to High(Todo) do
      begin
        for F := Low(TTagField) to High(TTagField) do PerItem[I][F] := '';
        PerFields[I] := [];
        Gain := TrackGainText(Batch.Results[I]);
        if Batch.Results[I].Error <> '' then
          Errors.Add(ExtractFileName(Files[I]) + ': ' + Batch.Results[I].Error)
        else if Gain = '' then
          Errors.Add(ExtractFileName(Files[I]) + ': ' + rsRGStille)
        else
        begin
          PerItem[I][tfRGTrackGain] := Gain;
          PerItem[I][tfRGTrackPeak] := RGPeakText(Batch.Results[I].Peak);
          PerFields[I] := [tfRGTrackGain, tfRGTrackPeak];
        end;
      end;
      if Album then
      begin
        Groups.Clear;
        for I := 0 to Keys.Count - 1 do Groups.Add(Keys[I]);
        for J := 0 to Groups.Count - 1 do
        begin
          Members := nil;
          Bad := 0;
          AlbumName := '';
          for I := 0 to High(Todo) do
            if Keys[I] = Groups[J] then
            begin
              AlbumName := Todo[I].Fields[tfAlbum];
              if PerFields[I] = [] then Inc(Bad)
              else
              begin
                SetLength(Members, Length(Members) + 1);
                Members[High(Members)] := Batch.Results[I];
              end;
            end;
          if (Bad > 0) or (Length(Members) = 0) then
          begin
            if Length(Members) > 0 then Errors.Add(Format(rsRGAlbumIkkeSkrevet, [AlbumName, Bad]));
            Continue;
          end;
          AlbumValues(Members, Gain, Peak);
          if Gain = '' then Continue;
          for I := 0 to High(Todo) do
            if Keys[I] = Groups[J] then
            begin
              PerItem[I][tfRGAlbumGain] := Gain;
              PerItem[I][tfRGAlbumPeak] := Peak;
              PerFields[I] := PerFields[I] + [tfRGAlbumGain, tfRGAlbumPeak];
            end;
        end;
      end;
    finally
      Batch.Free;
    end;
    WriteFieldsBatch(Todo, PerItem, PerFields, nil, rsReplayGainTitel);
    if Errors.Count > 0 then Inform(rsRGNogleFiler, Errors.Text, mtWarning);
  finally
    Groups.Free;
    Keys.Free;
    Errors.Free;
  end;
end;

procedure TFormMain.ActRemoveReplayGainExecute(Sender: TObject);
var
  Items, Todo: TAudioInfoArray;
  PerItem: array of TFieldValues;
  PerFields: array of TTagFieldSet;
  F: TTagField;
  I: Integer;
  Any: Boolean;
begin
  if not RequireTargets(Items) then Exit;
  Todo := nil;
  for I := 0 to High(Items) do
  begin
    Any := False;
    for F in RGFields do
      if Items[I].Fields[F] <> '' then Any := True;
    if not Any then Continue;
    SetLength(Todo, Length(Todo) + 1);
    Todo[High(Todo)] := Items[I];
  end;
  if Length(Todo) = 0 then
  begin
    Inform(rsReplayGainTitel, rsRGIngenHarRG);
    Exit;
  end;
  if not AskYes(rsReplayGainTitel, Format(rsRGFjernSpm, [Length(Todo)])) then Exit;
  SetLength(PerItem, Length(Todo));
  SetLength(PerFields, Length(Todo));
  for I := 0 to High(Todo) do
  begin
    for F := Low(TTagField) to High(TTagField) do PerItem[I][F] := '';
    PerFields[I] := RGFields;
  end;
  WriteFieldsBatch(Todo, PerItem, PerFields, nil, rsReplayGainTitel);
end;

const
  SHOP_FILEPATH = 2;

function SHObjectProperties(Wnd: THandle; ObjectType: Cardinal; ObjectName, PropertyPage: PWideChar): LongBool;
  stdcall; external 'shell32.dll';

procedure TFormMain.ApplyViewOptions;
begin
  ID3AlwaysUnicode := AppOptions.ID3Unicode;
  FileList.GridLines := AppOptions.GridLines;
  FileList.Font.Size := AppOptions.ListFontSize;
  ShellTree.Font.Size := AppOptions.ListFontSize;
  FileList.Invalidate;
end;

procedure TFormMain.FileListCustomDrawSubItem(Sender: TCustomListView; Item: TListItem;
  SubItem: Integer; State: TCustomDrawState; var DefaultDraw: Boolean);
var
  Info: TAudioInfo;
  Col: TColor;
begin
  DefaultDraw := True;
  Col := clWindowText;
  if (Item <> nil) and (Item.Index < FView.Count) and (SubItem <= High(Columns)) then
  begin
    Info := TAudioInfo(FView[Item.Index]);
    case Columns[SubItem].Kind of
      ckBitrate:
        if AppOptions.MarkLowBitrate and (Info.Bitrate > 0) and (Info.Bitrate < AppOptions.LowBitrate) then
          Col := clRed;
      ckFileName:
        if AppOptions.MarkNoID3v1 and SameText(ExtractFileExt(Info.FileName), '.mp3') and
          (Pos('ID3v1', Info.TagTypes) = 0) then
          Col := RGBToColor(205, 102, 0);
    end;
  end;
  Sender.Canvas.Font.Color := Col;
end;

procedure TFormMain.RebuildRecentMenu;
var
  I: Integer;
  M: TMenuItem;
begin
  if FRecentMenu = nil then Exit;
  FRecentMenu.Clear;
  for I := 0 to Min(ComboAddress.Items.Count, 15) - 1 do
  begin
    M := TMenuItem.Create(FRecentMenu);
    M.Caption := StringReplace(ComboAddress.Items[I], '&', '&&', [rfReplaceAll]);
    M.Hint := ComboAddress.Items[I];
    M.Tag := I;
    M.OnClick := @RecentFolderClick;
    FRecentMenu.Add(M);
  end;
  FRecentMenu.Enabled := FRecentMenu.Count > 0;
end;

procedure TFormMain.RecentFolderClick(Sender: TObject);
begin
  Navigate(TMenuItem(Sender).Hint);
end;

procedure TFormMain.ActExpandFoldersExecute(Sender: TObject);
begin
  if ShellTree.Selected <> nil then
  begin
    Screen.Cursor := crHourGlass;
    try
      ShellTree.Selected.Expand(True);
    finally
      Screen.Cursor := crDefault;
    end;
  end;
end;

procedure TFormMain.ActCollapseFoldersExecute(Sender: TObject);
begin
  ShellTree.FullCollapse;
  try
    ShellTree.Path := FFolder; // keep the open folder visible
  except
  end;
end;

procedure TFormMain.ActPlayFolderExecute(Sender: TObject);
var
  Items: TAudioInfoArray;
  PlName: string;
begin
  Items := AllItems;
  if Length(Items) = 0 then Exit;
  PlName := GetTempDir + 'TidyTag-afspil.m3u8';
  WritePlaylist(PlName, Items, True);
  PlayWith(PlName);
end;

procedure TFormMain.ActQuickPlaylistExecute(Sender: TObject);
var
  Items: TAudioInfoArray;
  ScopeCaption, Dir, PlName: string;
  Prefer: Boolean;
begin
  Items := TargetItems(ScopeCaption, Prefer);
  if Length(Items) = 0 then
  begin
    Inform(rsGemPlaylisteHurtigt, rsDerErIngenFilerAt);
    Exit;
  end;
  Dir := AppOptions.PlFolder;
  if (Dir = '') or not DirectoryExists(Dir) then Dir := ExtractFileDir(Items[0].FileName);
  PlName := MaskText(AppOptions.PlNameMask, Items[0]);
  if PlName = '' then PlName := ExtractFileName(ExtractFileDir(Items[0].FileName));
  PlName := IncludeTrailingPathDelimiter(Dir) + PlName + '.m3u8';
  if FileExists(PlName) and not AskYes(rsGemPlaylisteHurtigt, Format(rsPlaylisteFindesOverskriv,
    [ExtractFileName(PlName)])) then Exit;
  WritePlaylist(PlName, Items);
  SetMessage(Format(rsPlaylisteMedDFilerGemt, [Length(Items), PlName]));
end;

procedure TFormMain.RefreshGenreCombos;
var
  S, Keep: string;
begin
  Keep := ComboMultiGenre.Text;
  ComboMultiGenre.Items.BeginUpdate;
  try
    ComboMultiGenre.Items.Clear;
    for S in GenreList do ComboMultiGenre.Items.Add(S);
  finally
    ComboMultiGenre.Items.EndUpdate;
  end;
  ComboMultiGenre.Text := Keep;
end;

procedure TFormMain.ActGenresExecute(Sender: TObject);
begin
  if not EditGenreList(AppOptions.CustomGenres, AppOptions.HiddenGenres) then Exit;
  SaveAppOptions;
  RefreshGenreCombos;
end;

procedure TFormMain.ActPropertiesExecute(Sender: TObject);
var
  Info: TAudioInfo;
  W: UnicodeString;
begin
  Info := FocusedInfo;
  if Info <> nil then W := UnicodeString(Info.FileName)
  else if FFolder <> '' then W := UnicodeString(FFolder)
  else Exit;
  SHObjectProperties(Handle, SHOP_FILEPATH, PWideChar(W), nil);
end;

function ValidFileName(const S: string): Boolean;
var
  C: Char;
begin
  Result := (Trim(S) <> '') and (S <> '.') and (S <> '..');
  for C in S do
    if C in ['\', '/', ':', '*', '?', '"', '<', '>', '|'] then Exit(False);
end;

function TFormMain.RenamePaths(Info: TAudioInfo; const OldName, NewName: string; var Log: TRenameLog): Boolean;
var
  Plan: TRenamePlan;
  Done: TRenameLog;
begin
  SetLength(Plan, 1);
  Plan[0].Info := Info;
  Plan[0].OldName := OldName;
  Plan[0].NewName := NewName;
  Plan[0].Status := rsOk;
  Plan[0].Detail := '';
  Done := ExecuteRename(Plan);
  Result := Length(Done) = 1;
  if Result then
  begin
    SetLength(Log, Length(Log) + 1);
    Log[High(Log)] := Done[0];
  end
  else if Plan[0].Status = rsExists then
    Inform(rsKunneIkkeOmdoebe, Format(rsFiltypeFindes, [ExtractFileName(NewName)]), mtWarning)
  else
    Inform(rsKunneIkkeOmdoebe, Plan[0].Detail, mtWarning);
end;

procedure TFormMain.RenameFileDialog;
var
  F: TForm;
  E: TEdit;
  LExt, LDir: TLabel;
  BP: TButtonPanel;
  BPrev, BNext: TButton;
  Idx, R: Integer;
  Info: TAudioInfo;
  Log: TRenameLog;
  NewName: string;
begin
  if FileList.ItemIndex < 0 then Exit;
  Idx := FileList.ItemIndex;
  Log := nil;
  F := TForm.CreateNew(Self);
  try
    F.BorderStyle := bsDialog;
    F.Position := poMainFormCenter;
    F.ClientWidth := F.Scale96ToForm(560);
    F.ClientHeight := F.Scale96ToForm(140);
    LDir := TLabel.Create(F);
    LDir.Parent := F;
    LDir.SetBounds(F.Scale96ToForm(12), F.Scale96ToForm(10), F.Scale96ToForm(536), F.Scale96ToForm(17));
    LDir.AutoSize := False;
    LDir.Font.Color := clGrayText;
    with TLabel.Create(F) do
    begin
      Parent := F;
      Caption := rsNytNavn;
      Left := F.Scale96ToForm(12);
      Top := F.Scale96ToForm(40);
    end;
    E := TEdit.Create(F);
    E.Parent := F;
    E.SetBounds(F.Scale96ToForm(90), F.Scale96ToForm(36), F.Scale96ToForm(390), F.Scale96ToForm(23));
    LExt := TLabel.Create(F);
    LExt.Parent := F;
    LExt.Left := F.Scale96ToForm(486);
    LExt.Top := F.Scale96ToForm(40);
    BP := TButtonPanel.Create(F);
    BP.Parent := F;
    BP.ShowButtons := [pbOK, pbCancel];
    BPrev := TButton.Create(F);
    BPrev.Parent := F;
    BPrev.Caption := rsForrige;
    BPrev.ModalResult := mrRetry;
    BPrev.SetBounds(F.Scale96ToForm(12), F.Scale96ToForm(72), F.Scale96ToForm(110), F.Scale96ToForm(26));
    BNext := TButton.Create(F);
    BNext.Parent := F;
    BNext.Caption := rsNaeste;
    BNext.ModalResult := mrIgnore;
    BNext.SetBounds(F.Scale96ToForm(130), F.Scale96ToForm(72), F.Scale96ToForm(110), F.Scale96ToForm(26));
    repeat
      Info := TAudioInfo(FView[Idx]);
      F.Caption := Format(rsOmdoebFilTitel, [Idx + 1, FView.Count]);
      LDir.Caption := ExtractFileDir(Info.FileName);
      E.Text := ChangeFileExt(ExtractFileName(Info.FileName), '');
      LExt.Caption := ExtractFileExt(Info.FileName);
      BPrev.Enabled := Idx > 0;
      BNext.Enabled := Idx < FView.Count - 1;
      F.ActiveControl := E;
      E.SelectAll;
      R := F.ShowModal;
      if R = mrCancel then Break;
      NewName := Trim(E.Text);
      if NewName <> ChangeFileExt(ExtractFileName(Info.FileName), '') then
      begin
        if not ValidFileName(NewName) then
        begin
          Inform(rsKunneIkkeOmdoebe, rsUgyldigtNavn, mtWarning);
          Continue;
        end;
        RenamePaths(Info, Info.FileName,
          IncludeTrailingPathDelimiter(ExtractFileDir(Info.FileName)) + NewName + ExtractFileExt(Info.FileName), Log);
        FileList.Invalidate;
      end;
      if R = mrRetry then Dec(Idx)
      else if R = mrIgnore then Inc(Idx)
      else Break;
      FileList.ClearSelection;
      FileList.ItemIndex := Idx;
      FileList.Items[Idx].MakeVisible(False);
    until False;
  finally
    F.Free;
  end;
  if Length(Log) > 0 then SetUndoLog(Log, rsManuelOmdoebning);
  SelectionChanged;
end;

procedure TFormMain.RenameFolderManual;
var
  Dir, NewName: string;
  Log: TRenameLog;
begin
  Dir := ExcludeTrailingPathDelimiter(ShellTree.Path);
  if (Dir = '') or not DirectoryExists(Dir) or (ExtractFileName(Dir) = '') then Exit;
  NewName := ExtractFileName(Dir);
  if not InputQuery(rsOmdoebMappeTitel, rsNytNavn, NewName) then Exit;
  NewName := Trim(NewName);
  if NewName = ExtractFileName(Dir) then Exit;
  if not ValidFileName(NewName) then
  begin
    Inform(rsKunneIkkeOmdoebe, rsUgyldigtNavn, mtWarning);
    Exit;
  end;
  Log := nil;
  if RenamePaths(nil, Dir, IncludeTrailingPathDelimiter(ExtractFileDir(Dir)) + NewName, Log) then
  begin
    ApplyRenameLog(Log, False);
    SetUndoLog(Log, rsManuelOmdoebning);
  end;
end;

procedure TFormMain.ActRenameManualExecute(Sender: TObject);
begin
  if ShellTree.Focused then RenameFolderManual else RenameFileDialog;
end;

procedure TFormMain.ActChangeExtExecute(Sender: TObject);
const
  FromExt: array[0..2] of string = ('.mp4', '.mp4.m4a.m4p', '.m4b');
  ToExt: array[0..2] of string = ('.m4a', '.m4b', '.m4a');
var
  Items: TAudioInfoArray;
  Plan: TRenamePlan;
  Log: TRenameLog;
  Errors: TStringList;
  I, K, N: Integer;
  Ext: string;
begin
  if not RequireTargets(Items) then Exit;
  K := TAction(Sender).Tag;
  Plan := nil;
  Errors := TStringList.Create;
  try
    for I := 0 to High(Items) do
    begin
      Ext := LowerCase(ExtractFileExt(Items[I].FileName));
      if (Ext = '') or (Pos(Ext, FromExt[K]) = 0) or (Ext = ToExt[K]) then Continue;
      N := Length(Plan);
      SetLength(Plan, N + 1);
      Plan[N].Info := Items[I];
      Plan[N].OldName := Items[I].FileName;
      Plan[N].NewName := ChangeFileExt(Items[I].FileName, ToExt[K]);
      Plan[N].Detail := '';
      if FileExists(Plan[N].NewName) then
      begin
        Plan[N].Status := rsExists;
        Errors.Add(Format(rsFiltypeFindes, [ExtractFileName(Plan[N].NewName)]));
      end
      else
        Plan[N].Status := rsOk;
    end;
    if Length(Plan) = 0 then
    begin
      Inform(rsSkiftFiltype, rsIngenFilerMedFiltypen);
      Exit;
    end;
    Log := ExecuteRename(Plan);
    for I := 0 to High(Plan) do
      if Plan[I].Status = rsFailed then Errors.Add(ExtractFileName(Plan[I].OldName) + ': ' + Plan[I].Detail);
    if Length(Log) > 0 then SetUndoLog(Log, rsSkiftFiltype);
    FileList.Invalidate;
    SetMessage(Format(rsFiltypeSkiftet, [Length(Log)]));
    if Errors.Count > 0 then Inform(rsSkiftFiltype, Errors.Text, mtWarning);
  finally
    Errors.Free;
  end;
end;

procedure TFormMain.AddAlbumArtistMenu(ParentItem: TMenuItem);
const
  Captions: array[TAlbumArtistRule] of string = (rsAlbumkunstnerIngen, rsAlbumkunstnerHvisTom,
    rsAlbumkunstnerAltid);
var
  Sub, M: TMenuItem;
  R: TAlbumArtistRule;
  Ini: TIniFile;
  N: Integer;
begin
  Ini := OpenSettings;
  try
    N := Ini.ReadInteger('Main', 'AlbumArtistRule', 0);
    if (N >= Ord(Low(TAlbumArtistRule))) and (N <= Ord(High(TAlbumArtistRule))) then
      AlbumArtistRule := TAlbumArtistRule(N);
  finally
    Ini.Free;
  end;
  Sub := TMenuItem.Create(ParentItem);
  Sub.Caption := rsAlbumkunstnerVedGem;
  ParentItem.Add(Sub);
  FAlbumArtistMenu := Sub;
  for R := Low(TAlbumArtistRule) to High(TAlbumArtistRule) do
  begin
    M := TMenuItem.Create(Sub);
    M.Caption := Captions[R];
    M.Tag := Ord(R);
    M.RadioItem := True;
    M.GroupIndex := 2;
    M.Checked := R = AlbumArtistRule;
    M.OnClick := @AlbumArtistClick;
    Sub.Add(M);
  end;
end;

procedure TFormMain.AlbumArtistClick(Sender: TObject);
var
  Ini: TIniFile;
begin
  AlbumArtistRule := TAlbumArtistRule((Sender as TMenuItem).Tag);
  (Sender as TMenuItem).Checked := True;
  Ini := OpenSettings;
  try
    Ini.WriteInteger('Main', 'AlbumArtistRule', Ord(AlbumArtistRule));
  finally
    Ini.Free;
  end;
end;

function TFormMain.LoadPasteFields: TTagFieldSet;
var
  Ini: TIniFile;
  S: string;
  Part: string;
  N: Integer;
begin
  Ini := OpenSettings;
  try
    S := Ini.ReadString('Main', 'PasteFields', '');
  finally
    Ini.Free;
  end;
  if S = '' then Exit([Low(TTagField)..High(TTagField)] - [tfTitle, tfTrack] - RGFields);
  Result := [];
  for Part in S.Split([',']) do
  begin
    N := StrToIntDef(Part, -1);
    if (N >= Ord(Low(TTagField))) and (N <= Ord(High(TTagField))) then Include(Result, TTagField(N));
  end;
end;

procedure TFormMain.SavePasteFields(Fields: TTagFieldSet);
var
  Ini: TIniFile;
  F: TTagField;
  S: string;
begin
  S := '';
  for F in Fields do
  begin
    if S <> '' then S := S + ',';
    S := S + IntToStr(Ord(F));
  end;
  if S = '' then S := '-1'; // nothing ticked (differs from 'not set yet')
  Ini := OpenSettings;
  try
    Ini.WriteString('Main', 'PasteFields', S);
  finally
    Ini.Free;
  end;
end;

function TFormMain.AskYes(const Title, Msg: string; DlgType: TMsgDlgType): Boolean;
begin
  if FAutoYes then
  begin
    FAutoLog.Add('  ? ' + Title + ': ' + StringReplace(Msg, LineEnding, ' / ', [rfReplaceAll]));
    Exit(True);
  end;
  Result := MessageDlg(Title, Msg, DlgType, [mbYes, mbNo], 0) = mrYes;
end;

procedure TFormMain.Inform(const Title, Msg: string; DlgType: TMsgDlgType);
begin
  if FAutoYes then
    FAutoLog.Add('  ! ' + Title + ': ' + StringReplace(Msg, LineEnding, ' / ', [rfReplaceAll]))
  else
    MessageDlg(Title, Msg, DlgType, [mbOK], 0);
end;

function FileCountIn(const Dir: string): Integer;
var
  R: TSearchRec;
begin
  Result := 0;
  if FindFirst(IncludeTrailingPathDelimiter(Dir) + '*.*', faAnyFile, R) = 0 then
  begin
    repeat
      if (R.Attr and faDirectory) = 0 then Inc(Result);
    until FindNext(R) <> 0;
    FindClose(R);
  end;
end;

procedure TFormMain.RunSelfTest(const ReportFile: string);
var
  I, W, H: Integer;
  Act: TRenameAction;
  ExtAct: TAction;
  Log: TRenameLog;
  Info: TAudioInfo;
  PlFile: string;
  PlLines: TStringList;

  function FileNamesIn(const Dir: string): string;
  var
    SR: TSearchRec;
    L: TStringList;
  begin
    L := TStringList.Create;
    try
      L.Sorted := True;
      if FindFirst(IncludeTrailingPathDelimiter(Dir) + '*', faAnyFile and not faDirectory, SR) = 0 then
      try
        repeat
          if (SR.Attr and faDirectory) = 0 then L.Add(SR.Name);
        until FindNext(SR) <> 0;
      finally
        FindClose(SR);
      end;
      L.Delimiter := '|';
      L.StrictDelimiter := True;
      Result := L.DelimitedText;
    finally
      L.Free;
    end;
  end;

  procedure Dump(const Step: string);
  var
    J: Integer;
    D: TAudioInfo;
  begin
    FAutoLog.Add('== ' + Step);
    for J := 0 to FItems.Count - 1 do
    begin
      D := ReadAudioInfo(TAudioInfo(FItems[J]).FileName, False);
      try
        FAutoLog.Add(Format('  %s | kunstner=%s | albumkunstner=%s | titel=%s | album=%s | cover=%s | tags=%s | rg=%s %s / %s %s',
          [ExtractFileName(D.FileName), D.Fields[tfArtist], D.Fields[tfAlbumArtist], D.Fields[tfTitle],
          D.Fields[tfAlbum], BoolToStr(D.HasCover, 'ja', 'nej'), D.TagTypes, D.Fields[tfRGTrackGain],
          D.Fields[tfRGTrackPeak], D.Fields[tfRGAlbumGain], D.Fields[tfRGAlbumPeak]]));
      finally
        D.Free;
      end;
    end;
  end;

begin
  FAutoLog := TStringList.Create;
  try
    for I := 1 to 1500 do // wait for the scan (max. 30 s)
    begin
      if FScanner = nil then Break;
      Application.ProcessMessages;
      Sleep(20);
    end;
    FAutoYes := True;
    UseRecycleBin := False;
    for I := 0 to FItems.Count - 1 do TAudioInfo(FItems[I]).Checked := True;
    Dump('start');
    // filter: text in all fields, whole words, tag type
    ComboFilterField.ItemIndex := ComboFilterField.Items.Count - 1;
    EditFilter.Text := 'rocaz';
    ButtonFilterApplyClick(nil);
    FAutoLog.Add(Format('  filter "rocaz" i alle felter: %d filer', [FView.Count]));
    CheckFilterWhole.Checked := True;
    ButtonFilterApplyClick(nil);
    FAutoLog.Add(Format('  ... kun hele ord: %d filer', [FView.Count]));
    CheckFilterWhole.Checked := False;
    EditFilter.Text := '';
    ButtonFilterApplyClick(nil);
    ComboTagType.ItemIndex := 1; // ID3v2
    FilterOptionChange(nil);
    FAutoLog.Add(Format('  tagtype ID3v2: %d filer', [FView.Count]));
    ComboTagType.ItemIndex := ComboTagType.Items.Count - 1; // no tags
    FilterOptionChange(nil);
    FAutoLog.Add(Format('  ingen tags: %d filer', [FView.Count]));
    ComboTagType.ItemIndex := 0;
    FilterOptionChange(nil);
    AutoFitColumns;
    DoCopyField(tfArtist, tfAlbumArtist, True);
    Dump('kopier kunstner -> albumkunstner (kun tomme)');
    SwapFields(tfAlbum, tfTitle);
    Dump('byt album og titel');
    ActCleanSpacesExecute(nil);
    Dump('ryd mellemrum');
    RunNameTool(ntNameToSurnameFirst);
    Dump('kunstner: efternavn foerst');
    RunNameTool(ntSurnameFirstToName);
    Dump('kunstner: fornavn foerst igen');
    RunID3Sync(sdV2ToV1, seOverwrite);
    Dump('ID3v2 -> ID3v1');
    FClip := FieldValuesOf(TAudioInfo(FItems[FItems.Count - 1]));
    FHasClip := True;
    ActPasteTagExecute(nil);
    Dump('indsaet tag fra sidste fil (uden titel og spor)');
    ActCoverToTagsExecute(nil);
    Dump('mappens cover ind i filerne');
    DeleteFile(FindFolderCover(FFolder));
    ActCoverFromTagsExecute(nil);
    FAutoLog.Add('  mappe-cover efter udtraek: ' + ExtractFileName(FindFolderCover(FFolder)));
    GCoverOpt.MaxSide := 32;
    GCoverOpt.Quality := 80;
    GCoverOpt.ToJpeg := True;
    ResizeFileCovers;
    for I := 0 to FItems.Count - 1 do
      with ReadAudioInfo(TAudioInfo(FItems[I]).FileName, True) do
      try
        if Length(Pictures) > 0 then
        begin
          ImageDimensions(Pictures[0].Data, W, H);
          FAutoLog.Add(Format('  %s: billede %dx%d %s', [ExtractFileName(FileName), W, H, Pictures[0].MimeType]));
        end;
      finally
        Free;
      end;
    ResizeFolderCovers;
    FAutoLog.Add('  mappe-cover efter skalering: ' + ExtractFileName(FindFolderCover(FFolder)) + ' ' +
      IntToStr(Length(ReadFileBytes(FindFolderCover(FFolder)))) + ' byte');
    Dump('cover skaleret til 32 px');
    ActDeleteFolderCoversExecute(nil);
    FAutoLog.Add('  mappe-cover efter sletning: "' + ExtractFileName(FindFolderCover(FFolder)) + '"');
    ActCoverAsFolderExecute(nil);
    FAutoLog.Add('  mappe-cover fra filens cover: ' + ExtractFileName(FindFolderCover(FFolder)));
    // automatic shrinking when saving: the 32 px folder cover goes into the files as 16 px
    GCoverOpt.MaxSide := 16;
    FActAutoResize.Checked := True;
    ActAutoResizeExecute(nil);
    ActCoverToTagsExecute(nil);
    FActAutoResize.Checked := False;
    ActAutoResizeExecute(nil);
    with ReadAudioInfo(TAudioInfo(FItems[0]).FileName, True) do
    try
      if Length(Pictures) > 0 then ImageDimensions(Pictures[0].Data, W, H) else W := 0;
      FAutoLog.Add(Format('  automatisk skalering ved gem: %dx%d', [W, H]));
    finally
      Free;
    end;
    Act.Name := 'Selvtest';
    Act.FileMask := '%1 - %2';
    Act.FolderMask := 'Selvtest-mappe';
    RunRenameAction(Act);
    FAutoLog.Add('  mappe efter handling: ' + FFolder);
    Dump('omdoebningshandling');
    ActUndoExecute(nil);
    FAutoLog.Add('  mappe efter fortryd: ' + FFolder);
    Dump('fortryd');
    // C package: extension change with undo, manual rename with undo, quick playlist,
    // hidden extensions, recent folders
    ExtAct := TAction.Create(nil);
    try
      ExtAct.Tag := 1; // -> .m4b
      ActChangeExtExecute(ExtAct);
      FAutoLog.Add('  filer efter .m4b: ' + FileNamesIn(FFolder));
      ActUndoExecute(nil);
      FAutoLog.Add('  filer efter fortryd: ' + FileNamesIn(FFolder));
      ExtAct.Tag := 0; // .mp4 -> .m4a
      ActChangeExtExecute(ExtAct);
      FAutoLog.Add('  filer efter .m4a: ' + FileNamesIn(FFolder));
    finally
      ExtAct.Free;
    end;
    Log := nil;
    if FItems.Count > 0 then
    begin
      Info := TAudioInfo(FItems[0]);
      RenamePaths(Info, Info.FileName, ExtractFilePath(Info.FileName) + 'Manuelt navn' +
        ExtractFileExt(Info.FileName), Log);
      SetUndoLog(Log, rsManuelOmdoebning);
      FAutoLog.Add('  filer efter manuel omdøbning: ' + FileNamesIn(FFolder));
      ActUndoExecute(nil);
      FAutoLog.Add('  filer efter fortryd: ' + FileNamesIn(FFolder));
      AppOptions.HideExtensions := True;
      FAutoLog.Add('  skjult filtype: ' + CellText(Info, 1));
      AppOptions.HideExtensions := False;
    end;
    AppOptions.PlInfoMask := '%2 (%1)';
    AppOptions.PlNameMask := '%f';
    AppOptions.PlFolder := '';
    AppOptions.PlFullPaths := False;
    AppOptions.PlExtInf := True;
    ActQuickPlaylistExecute(nil);
    PlFile := IncludeTrailingPathDelimiter(FFolder) + ExtractFileName(FFolder) + '.m3u8';
    if FileExists(PlFile) then
    begin
      PlLines := TStringList.Create;
      try
        PlLines.LoadFromFile(PlFile);
        FAutoLog.Add('  playliste ' + ExtractFileName(PlFile) + ':');
        for I := 0 to PlLines.Count - 1 do FAutoLog.Add('    ' + PlLines[I]);
      finally
        PlLines.Free;
      end;
      SysUtils.DeleteFile(PlFile);
    end
    else
      FAutoLog.Add('  playliste mangler: ' + PlFile);
    FAutoLog.Add(Format('  seneste mapper i menuen: %d', [FRecentMenu.Count]));
    // ReplayGain: track + album, then skipping (nothing to do), removing, track only
    RunReplayGain(True, False);
    Dump('replaygain');
    RunReplayGain(True, True);
    ActRemoveReplayGainExecute(nil);
    Dump('fjern replaygain');
    RunReplayGain(False, False);
    Dump('kun sporgain');
    ActRemoveTagsExecute(nil);
    Dump('fjern tags');
    FTestTargetDir := ExtractFileDir(ExcludeTrailingPathDelimiter(FFolder)) + PathDelim + 'kopi';
    ForceDirectories(FTestTargetDir);
    CopyOrMoveTo(False, FTestTargetDir);
    FAutoLog.Add(Format('  kopieret: %d filer i %s, %d i listen', [FileCountIn(FTestTargetDir), 'kopi', FItems.Count]));
    CopyOrMoveTo(False, FTestTargetDir);
    FAutoLog.Add('  kopieret igen (skal springe over, filerne findes)');
    ForceDirectories(ExtractFileDir(FTestTargetDir) + PathDelim + 'flyttet');
    CopyOrMoveTo(True, ExtractFileDir(FTestTargetDir) + PathDelim + 'flyttet');
    FAutoLog.Add(Format('  efter flyt: %d i listen', [FItems.Count]));
  except
    on E: Exception do FAutoLog.Add('!! undtagelse: ' + E.ClassName + ': ' + E.Message);
  end;
  try
    FAutoLog.SaveToFile(ReportFile);
  finally
    FAutoYes := False;
    FreeAndNil(FAutoLog);
  end;
end;


{ ---------- tag tools ---------- }

procedure TFormMain.RunFieldPlans(const Items: TAudioInfoArray; const Plans: array of TFieldPlan;
  const What: string);
var
  PerItem: array of TFieldValues;
  PerFields: array of TTagFieldSet;
  I, Count: Integer;
begin
  SetLength(PerItem, Length(Items));
  SetLength(PerFields, Length(Items));
  Count := 0;
  for I := 0 to High(Items) do
  begin
    PerItem[I] := Plans[I].Values;
    PerFields[I] := Plans[I].Fields;
    if Plans[I].Fields <> [] then Inc(Count);
  end;
  if Count = 0 then
  begin
    Inform(What, rsIngenFilerAendres);
    Exit;
  end;
  if not AskYes(What, Format(rsAendreDFiler, [Count])) then Exit;
  WriteFieldsBatch(Items, PerItem, PerFields, nil, What);
end;

procedure TFormMain.SwapFields(A, B: TTagField);
var
  Items: TAudioInfoArray;
  Plans: array of TFieldPlan;
  I: Integer;
begin
  if not RequireTargets(Items) then Exit;
  SetLength(Plans, Length(Items));
  for I := 0 to High(Items) do Plans[I] := PlanSwap(Items[I], A, B);
  RunFieldPlans(Items, Plans, Format(rsBytSS, [TagFieldCaptions[A], TagFieldCaptions[B]]));
end;

procedure TFormMain.ActSwapArtistTitleExecute(Sender: TObject);
begin
  SwapFields(tfArtist, tfTitle);
end;

procedure TFormMain.ActSwapArtistAlbumExecute(Sender: TObject);
begin
  SwapFields(tfArtist, tfAlbum);
end;

procedure TFormMain.ActSwapAlbumTitleExecute(Sender: TObject);
begin
  SwapFields(tfAlbum, tfTitle);
end;

procedure TFormMain.ActSwapFieldsExecute(Sender: TObject);
var
  Dummy: Boolean;
begin
  Dummy := False;
  if AskFieldPair(rsBytFelter, rsFelt1, rsFelt2, '', FSwapA, FSwapB, Dummy) then
    SwapFields(FSwapA, FSwapB);
end;

procedure TFormMain.ActCopyFieldExecute(Sender: TObject);
begin
  if AskFieldPair(rsKopierFelt, rsFraFelt, rsTilFelt, rsKunHvisFeltetErTomt,
    FCopySrc, FCopyDst, FCopyOnlyEmpty) then
    DoCopyField(FCopySrc, FCopyDst, FCopyOnlyEmpty);
end;

procedure TFormMain.DoCopyField(Src, Dst: TTagField; OnlyIfEmpty: Boolean);
var
  Items: TAudioInfoArray;
  Plans: array of TFieldPlan;
  I: Integer;
begin
  if not RequireTargets(Items) then Exit;
  SetLength(Plans, Length(Items));
  for I := 0 to High(Items) do Plans[I] := PlanCopy(Items[I], Src, Dst, OnlyIfEmpty);
  RunFieldPlans(Items, Plans, Format(rsKopierSTilS, [TagFieldCaptions[Src], TagFieldCaptions[Dst]]));
end;

procedure TFormMain.ActCleanSpacesExecute(Sender: TObject);
var
  Items: TAudioInfoArray;
  Plans: array of TFieldPlan;
  I: Integer;
begin
  if not RequireTargets(Items) then Exit;
  SetLength(Plans, Length(Items));
  for I := 0 to High(Items) do Plans[I] := PlanCleanSpaces(Items[I]);
  RunFieldPlans(Items, Plans, rsRydMellemrum);
end;

procedure TFormMain.RefreshInfo(Info: TAudioInfo);
var
  Fresh: TAudioInfo;
  F: TTagField;
begin
  Fresh := ReadAudioInfo(Info.FileName, False);
  try
    for F := Low(TTagField) to High(TTagField) do Info.Fields[F] := Fresh.Fields[F];
    Info.TagTypes := Fresh.TagTypes;
    Info.HasCover := Fresh.HasCover;
    Info.FileSize := Fresh.FileSize;
    Info.Error := Fresh.Error;
  finally
    Fresh.Free;
  end;
end;

procedure TFormMain.ActRemoveTagsExecute(Sender: TObject);
var
  Items: TAudioInfoArray;
  I, Done, Failed: Integer;
  Errors: TStringList;
begin
  if not RequireTargets(Items) then Exit;
  if not AskYes(rsFjernTags, Format(rsFjernAlleTagsIDFiler, [Length(Items)]) + LineEnding + LineEnding +
    rsFjernTagsForklaring, mtWarning) then Exit;
  Done := 0;
  Failed := 0;
  Errors := TStringList.Create;
  Screen.Cursor := crHourGlass;
  try
    for I := 0 to High(Items) do
    begin
      SetMessage(Format(rsSDAfD, [rsFjernTags, I + 1, Length(Items)]));
      Application.ProcessMessages;
      try
        RemoveAllTags(Items[I].FileName, FKeepTimestamp);
        Inc(Done);
      except
        on E: Exception do
        begin
          Inc(Failed);
          if Errors.Count < 20 then Errors.Add(ExtractFileName(Items[I].FileName) + ': ' + E.Message);
        end;
      end;
      RefreshInfo(Items[I]);
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  SetMessage(Format(rsSGemtIDFiler, [rsFjernTags, Done, Failed, '']));
  if Errors.Count > 0 then Inform(rsNogleFilerBlevIkkeGemt, Errors.Text, mtWarning);
  Errors.Free;
  FCoverFile := '';
  FFolderCoverDir := '';
  FileList.Invalidate;
  SelectionChanged;
end;

{ ---------- cover tools ---------- }

procedure TFormMain.ActCoverToTagsExecute(Sender: TObject);
var
  Items: TAudioInfoArray;
  PerItem: array of TFieldValues;
  PerFields: array of TTagFieldSet;
  PerCover: TCoverArray;
  Dirs: TStringList;
  I, K, WithCover: Integer;
  Dir, Path: string;
  Data: TBytes;
  Empty: TFieldValues;
  F: TTagField;
  Covers: array of TBytes; // per entry of Dirs
begin
  if not RequireTargets(Items) then Exit;
  for F := Low(TTagField) to High(TTagField) do Empty[F] := '';
  SetLength(PerItem, Length(Items));
  SetLength(PerFields, Length(Items));
  SetLength(PerCover, Length(Items));
  Dirs := TStringList.Create; // folder -> index into Covers (Objects), -1 = none
  try
    WithCover := 0;
    for I := 0 to High(Items) do
    begin
      PerItem[I] := Empty;
      PerFields[I] := [];
      Dir := ExtractFileDir(Items[I].FileName);
      K := Dirs.IndexOf(Dir);
      if K < 0 then
      begin
        Path := FindFolderCover(Dir);
        Data := nil;
        if Path <> '' then
          try
            Data := ReadFileBytes(Path);
          except
            Data := nil;
          end;
        if (Data <> nil) and (DetectImageMime(Data, '') = '') then Data := nil; // not JPEG/PNG
        K := Dirs.Add(Dir);
        SetLength(Covers, Dirs.Count);
        Covers[K] := Data;
      end;
      PerCover[I] := Covers[K];
      if PerCover[I] <> nil then Inc(WithCover);
    end;
  finally
    Dirs.Free;
  end;
  if WithCover = 0 then
  begin
    Inform(rsMappeCoverIFiler, rsIngenAfMapperneHarEtCover);
    Exit;
  end;
  if not AskYes(rsMappeCoverIFiler, Format(rsLaegMappensCoverIndIDFiler, [WithCover]) +
    IfThen(WithCover < Length(Items), LineEnding + Format(rsDFilerLiggerIMapperUdenCover,
    [Length(Items) - WithCover]), '')) then Exit;
  WriteFieldsBatch(Items, PerItem, PerFields, nil, rsMappeCoverIFiler, PerCover);
end;

procedure TFormMain.ActCoverFromTagsExecute(Sender: TObject);
var
  Items: TAudioInfoArray;
  Dirs: TStringList;
  I, K, Saved, Existing, Without: Integer;
  Dir, Target: string;
  Full: TAudioInfo;
  Pic, K2: Integer;
  Errors: TStringList;
begin
  if not RequireTargets(Items) then Exit;
  Dirs := TStringList.Create;
  Errors := TStringList.Create;
  try
    // one entry per folder: the first file with a cover (Objects = item index + 1)
    for I := 0 to High(Items) do
    begin
      Dir := ExtractFileDir(Items[I].FileName);
      K := Dirs.IndexOf(Dir);
      if K < 0 then K := Dirs.AddObject(Dir, nil);
      if (Dirs.Objects[K] = nil) and Items[I].HasCover then Dirs.Objects[K] := TObject(PtrInt(I + 1));
    end;
    Existing := 0;
    Without := 0;
    for K := 0 to Dirs.Count - 1 do
      if FindFolderCover(Dirs[K]) <> '' then Inc(Existing)
      else if Dirs.Objects[K] = nil then Inc(Without);
    if Dirs.Count - Existing - Without = 0 then
    begin
      Inform(rsCoverTilMappe, Format(rsIngenMapperAtGemme, [Existing, Without]));
      Exit;
    end;
    if not AskYes(rsCoverTilMappe, Format(rsGemFilernesCoverIDMapper,
      [Dirs.Count - Existing - Without, Existing, Without])) then Exit;
    Saved := 0;
    Screen.Cursor := crHourGlass;
    try
      for K := 0 to Dirs.Count - 1 do
      begin
        if (Dirs.Objects[K] = nil) or (FindFolderCover(Dirs[K]) <> '') then Continue;
        I := PtrInt(Dirs.Objects[K]) - 1;
        Full := ReadAudioInfo(Items[I].FileName, True);
        try
          Pic := -1;
          for K2 := 0 to High(Full.Pictures) do
            if Full.Pictures[K2].PicType = PicTypeFrontCover then begin Pic := K2; Break; end;
          if (Pic < 0) and (Length(Full.Pictures) > 0) then Pic := 0;
          if Pic < 0 then Continue;
          if Full.Pictures[Pic].MimeType = 'image/png' then Target := 'folder.png' else Target := 'folder.jpg';
          Target := IncludeTrailingPathDelimiter(Dirs[K]) + Target;
          try
            WriteFileBytes(Target, Full.Pictures[Pic].Data);
            Inc(Saved);
          except
            on E: Exception do Errors.Add(Target + ': ' + E.Message);
          end;
        finally
          Full.Free;
        end;
      end;
    finally
      Screen.Cursor := crDefault;
    end;
    SetMessage(Format(rsCoverGemtIDMapper, [Saved]));
    if Errors.Count > 0 then Inform(rsCoverTilMappe, Errors.Text, mtWarning);
  finally
    Dirs.Free;
    Errors.Free;
  end;
  FFolderCoverDir := '';
  SelectionChanged;
end;

{ ---------- rename words and actions ---------- }

procedure TFormMain.ActRenameWordsExecute(Sender: TObject);
var
  W: TRenameWords;
begin
  W := LoadRenameWords;
  if not EditRenameWords(W) then Exit;
  SaveRenameWords(W);
  SelectionChanged; // the live rename result uses them
end;

procedure TFormMain.ActManageActionsExecute(Sender: TObject);
var
  A: TRenameActions;
begin
  A := LoadRenameActions;
  if not EditRenameActions(A, ComboRenameMask.Text) then Exit;
  SaveRenameActions(A);
  RebuildActionsMenu;
end;

procedure TFormMain.RebuildActionsMenu;
var
  A: TRenameActions;
  I: Integer;
  M: TMenuItem;
begin
  FActionsMenu.Clear;
  A := LoadRenameActions;
  for I := 0 to High(A) do
  begin
    M := TMenuItem.Create(FActionsMenu);
    M.Caption := A[I].Name;
    M.Tag := I;
    M.OnClick := @RenameActionClick;
    FActionsMenu.Add(M);
  end;
  if Length(A) > 0 then
  begin
    M := TMenuItem.Create(FActionsMenu);
    M.Caption := '-';
    FActionsMenu.Add(M);
  end;
  M := TMenuItem.Create(FActionsMenu);
  M.Action := FActManageActions;
  FActionsMenu.Add(M);
end;

procedure TFormMain.RenameActionClick(Sender: TObject);
var
  A: TRenameActions;
  I: Integer;
begin
  A := LoadRenameActions;
  I := (Sender as TMenuItem).Tag;
  if (I >= 0) and (I <= High(A)) then RunRenameAction(A[I]);
end;

procedure TFormMain.RunRenameAction(const Act: TRenameAction);
var
  Items: TAudioInfoArray;
  FilePlan, FolderPlan: TRenamePlan;
  FileLog, FolderLog, Log: TRenameLog;
  Opt: TRenameOptions;
  FileCount, FolderCount, I, Failed: Integer;
  Msg, Problems: string;
begin
  if not CanStartBatch or not RequireTargets(Items) then Exit;
  Opt := RenameOptions;
  FilePlan := nil;
  FileCount := 0;
  if Act.FileMask <> '' then
  begin
    FilePlan := PlanRename(Items, Act.FileMask, Opt);
    FileCount := CountStatus(FilePlan, rsOk);
  end;
  Msg := Format(rsKoerHandlingenS, [Act.Name]) + LineEnding;
  if Act.FileMask <> '' then
    Msg := Msg + LineEnding + Format(rsFilerDOmdoebesMedS, [FileCount, Act.FileMask]);
  if Act.FolderMask <> '' then
    Msg := Msg + LineEnding + Format(rsMapperneOmdoebesMedS, [Act.FolderMask]);
  if not AskYes(rsOmdoebningshandling, Msg) then Exit;

  Failed := 0;
  FileLog := nil;
  FolderLog := nil;
  FolderPlan := nil;
  Screen.Cursor := crHourGlass;
  try
    if FileCount > 0 then
    begin
      FileLog := ExecuteRename(FilePlan);
      Inc(Failed, CountStatus(FilePlan, rsFailed));
    end;
    FolderCount := 0;
    if Act.FolderMask <> '' then
    begin
      FolderPlan := PlanFolderRename(Items, Act.FolderMask, Opt); // after the file renames
      if CountStatus(FolderPlan, rsOk) > 0 then
      begin
        FolderLog := ExecuteRename(FolderPlan);
        FolderCount := Length(FolderLog);
        Inc(Failed, CountStatus(FolderPlan, rsFailed));
        ApplyRenameLog(FolderLog, False);
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  // one undo step for both: files first, then their folders
  Log := Concat(FileLog, FolderLog);
  if Length(Log) > 0 then SetUndoLog(Log, rsFilerMapper);
  SetMessage(Format(rsHandlingDFilerDMapperDFejl, [Act.Name, Length(FileLog), FolderCount, Failed]));
  if Failed > 0 then
  begin
    Problems := '';
    for I := 0 to High(FilePlan) do
      if FilePlan[I].Status = rsFailed then
        Problems := Problems + ExtractFileName(FilePlan[I].OldName) + ': ' + FilePlan[I].Detail + LineEnding;
    for I := 0 to High(FolderPlan) do
      if FolderPlan[I].Status = rsFailed then
        Problems := Problems + FolderPlan[I].OldName + ': ' + FolderPlan[I].Detail + LineEnding;
    Inform(rsNogleFilerBlevIkkeOmdoebt, Problems, mtWarning);
  end;
  FileList.Invalidate;
  SelectionChanged;
end;

procedure TFormMain.AddLanguageMenu(ParentItem: TMenuItem);
var
  Sub, M: TMenuItem;
  I: Integer;
  Cur: string;
begin
  Cur := LanguageSetting;
  Sub := TMenuItem.Create(ParentItem);
  Sub.Caption := rsSprogLanguage;
  ParentItem.Add(Sub);
  FLanguageMenu := Sub;
  for I := -1 to High(LanguageCodes) do
  begin
    M := TMenuItem.Create(Sub);
    M.Tag := I;
    if I < 0 then
    begin
      M.Caption := rsAutomatiskWindowsSprog;
      M.Checked := Cur = '';
    end
    else
    begin
      M.Caption := LanguageNames[I];
      M.Checked := Cur = LanguageCodes[I];
    end;
    M.RadioItem := True;
    M.GroupIndex := 1;
    M.OnClick := @LanguageClick;
    Sub.Add(M);
  end;
end;

{ The language is applied at start-up, so a change restarts the program in the same folder. }
procedure TFormMain.LanguageClick(Sender: TObject);
var
  M: TMenuItem;
begin
  M := Sender as TMenuItem;
  M.Checked := True;
  if M.Tag < 0 then ChangeLanguage('') else ChangeLanguage(LanguageCodes[M.Tag]);
end;

procedure TFormMain.ChangeLanguage(const Code: string);
var
  Old: string;
  P: TProcess;
begin
  Old := EffectiveLanguage;
  SetLanguageSetting(Code);
  SyncSettingsMenus;
  if EffectiveLanguage = Old then Exit;
  if MessageDlg(rsSprog, rsSprogetSkiftesNaarTidytagGenstartes, mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  SaveSettings;
  P := TProcess.Create(nil);
  try
    P.Executable := ParamStr(0);
    if FFolder <> '' then P.Parameters.Add(FFolder);
    P.Execute;
  finally
    P.Free;
  end;
  Close;
end;

procedure TFormMain.ActAboutExecute(Sender: TObject);
begin
  MessageDlg(rsOmTidytag2,
    rsTidytagTagEditorOgMusikorganisator + LineEnding + LineEnding +
    rsWebDataMusicbrainzMusicbrainzOrg + LineEnding + LineEnding +
    rsIndstillinger2 + SettingsFileName, mtInformation, [mbOK], 0);
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
  M.Caption := rsTilfoejDenAabneMappe;
  M.ImageIndex := icoFavorites;
  M.OnClick := @FavoriteAddClick;
  M.Enabled := (FFolder <> '') and (FFavorites.IndexOf(FFolder) < 0);
  PopupFavorites.Items.Add(M);
  M := TMenuItem.Create(PopupFavorites);
  M.Caption := rsFjernDenAabneMappe;
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
  if not InputQuery(rsNyMappe3, rsNavnPaaDenNyeMappe + FFolder + ':', NewName) then Exit;
  NewName := SanitizeNamePart(NewName);
  if NewName = '' then Exit;
  Dir := IncludeTrailingPathDelimiter(FFolder) + NewName;
  if DirectoryExists(Dir) or not CreateDir(Dir) then
  begin
    MessageDlg(rsMappenKunneIkkeOprettes + LineEnding + Dir, mtWarning, [mbOK], 0);
    Exit;
  end;
  try
    ShellTree.UpdateView(FFolder);
  except
  end;
  SetMessage(rsMappeOprettet + NewName);
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
  LoadAppOptions;
  ApplyViewOptions;
  Start := '';
  Ini := OpenSettings;
  try
    Start := Ini.ReadString('Main', 'LastFolder', '');
    FActSubfolders.Checked := Ini.ReadBool('Main', 'Subfolders', False);
    FActAutoFitAfterScan.Checked := Ini.ReadBool('View', 'AutoFitColumns', False);
    GCoverOpt.MaxSide := Ini.ReadInteger('Cover', 'MaxSide', 600);
    GCoverOpt.Quality := Ini.ReadInteger('Cover', 'Quality', 90);
    GCoverOpt.ToJpeg := Ini.ReadBool('Cover', 'ToJpeg', False);
    FActAutoResize.Checked := Ini.ReadBool('Cover', 'AutoResize', False);
    ActAutoResizeExecute(nil);
    CheckFilterWhole.Checked := Ini.ReadBool('View', 'FilterWholeWord', False);
    CheckFilterCase.Checked := Ini.ReadBool('View', 'FilterMatchCase', False);
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
  if AppOptions.FixedStartFolder and DirectoryExists(AppOptions.StartFolder) then
    Start := AppOptions.StartFolder;
  if (ParamCount > 0) and DirectoryExists(ParamStr(1)) then
    Start := ParamStr(1)
  else if (ParamCount >= 2) and (ParamStr(1) = '--selftest') then
    Start := ParamStr(2);
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
  FileList.OnCustomDrawSubItem := @FileListCustomDrawSubItem;
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
    Ini.WriteBool('View', 'AutoFitColumns', FActAutoFitAfterScan.Checked);
    Ini.WriteBool('Cover', 'AutoResize', FActAutoResize.Checked);
    Ini.WriteInteger('Cover', 'MaxSide', GCoverOpt.MaxSide);
    Ini.WriteInteger('Cover', 'Quality', GCoverOpt.Quality);
    Ini.WriteBool('Cover', 'ToJpeg', GCoverOpt.ToJpeg);
    Ini.WriteBool('View', 'FilterWholeWord', CheckFilterWhole.Checked);
    Ini.WriteBool('View', 'FilterMatchCase', CheckFilterCase.Checked);
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
