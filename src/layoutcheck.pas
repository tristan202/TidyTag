unit LayoutCheck;

{ Developer check for translations: "TagKlon.exe --layoutcheck <report.txt>" creates every
  window in the current language and lists texts that do not fit their control or that
  overlap a neighbouring control. }

{$mode objfpc}{$H+}

interface

function LayoutCheckRequested: Boolean;
procedure RunLayoutCheck;

implementation

uses
  Classes, SysUtils, Types, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Buttons,
  Graphics, MainForm, TagEditForm, RenameForm, FileToTagForm, MultiEditForm,
  TrackToolsForm, WebLookupForm, ExportImportForm, AudioTypes, AppSettings, ToolDialogs, ID3Sync, BatchWrite, CoverImage;

resourcestring
  // same texts as in the main window, so they get the same translations
  rsKopierFelt = 'Kopiér felt';
  rsFraFelt = 'Fra felt:';
  rsTilFelt = 'Til felt:';
  rsKunHvisFeltetErTomt = 'Kun hvis målfeltet er tomt';
  rsIndsaetTag = 'Indsæt tag';
  rsSkalerCoverIFilerne = 'Skalér cover i filerne...';
  rsMaskeEditor = 'Maske-editor';
  rsVaelgFelterDerIndsaettes = 'Vælg de felter, der indsættes i %d filer:';

type
  { Checks a modal dialog while it is shown, then closes it. Two rounds through the
    message queue: the first lets LayoutFit (also queued) adjust the dialog. }
  TModalInspector = class
    Report: TStrings;
    Round: Integer;
    procedure Inspect(Data: PtrInt);
    function Preview(const Mask: string): string;
  end;

procedure CheckTree(W: TWinControl; Report: TStrings; const FormName: string); forward;

function TModalInspector.Preview(const Mask: string): string;
begin
  Result := Mask + '.mp3';
end;

procedure TModalInspector.Inspect(Data: PtrInt);
var
  F: TCustomForm;
  I: Integer;
begin
  F := Screen.ActiveCustomForm;
  if (Round < 3) or (F = nil) or (F = FormMain) then
  begin
    Inc(Round);
    if Round < 50 then Application.QueueAsyncCall(@Inspect, 0);
    Exit;
  end;
  CheckTree(F, Report, 'Dialog "' + F.Caption + '"');
  // TAGKLON_LAYOUT_PAUSE=<ms>: keep the dialog open, e.g. for a screenshot
  for I := 1 to StrToIntDef(GetEnvironmentVariable('TAGKLON_LAYOUT_PAUSE'), 0) div 50 do
  begin
    Application.ProcessMessages;
    Sleep(50);
  end;
  F.ModalResult := mrCancel;
end;

function LayoutCheckRequested: Boolean;
begin
  Result := (ParamCount >= 2) and (ParamStr(1) = '--layoutcheck');
end;

function PlainCaption(const S: string): string;
begin
  Result := StringReplace(S, '&', '', [rfReplaceAll]);
  if Pos(LineEnding, Result) > 0 then Result := Copy(Result, 1, Pos(LineEnding, Result) - 1);
end;

function TextW(C: TControl; const S: string): Integer;
var
  Bmp: TBitmap;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.Canvas.Font.Assign(C.Font);
    Result := Bmp.Canvas.TextWidth(S);
  finally
    Bmp.Free;
  end;
end;

function Path(C: TControl): string;
begin
  Result := C.Name;
  while (C.Parent <> nil) and not (C.Parent is TCustomForm) do
  begin
    C := C.Parent;
    Result := C.Name + '.' + Result;
  end;
end;

procedure CheckControl(C: TControl; Report: TStrings; const FormName: string);
var
  Need, I: Integer;
  S: string;
  Sib: TControl;
  R: TRect;
begin
  if not C.Visible then Exit;
  S := PlainCaption(C.Caption);
  Need := 0;
  if (C is TCustomButton) or (C is TSpeedButton) then
    Need := TextW(C, S) + 12
  else if ((C is TCustomCheckBox) or (C is TRadioButton)) and not C.AutoSize then
    Need := TextW(C, S) + 22
  else if (C is TCustomGroupBox) then
    Need := TextW(C, S) + 16
  else if (C is TCustomLabel) and not C.AutoSize and not TLabel(C).WordWrap then
    Need := TextW(C, S);
  if (S <> '') and (Need > C.Width) then
    Report.Add(Format('%s  %s: "%s" needs %d px, has %d', [FormName, Path(C), S, Need, C.Width]));
  // pushed out of its container
  if (C.Parent <> nil) and (C.Align = alNone) and (C.Left + C.Width > C.Parent.ClientWidth + 1) then
    Report.Add(Format('%s  %s: "%s" ends at %d, container is %d wide', [FormName, Path(C), S,
      C.Left + C.Width, C.Parent.ClientWidth]));
  // overlap with any sibling (texts that grew, controls that were moved)
  if (C.Parent <> nil) and (C.Align = alNone) then
    for I := 0 to C.Parent.ControlCount - 1 do
    begin
      Sib := C.Parent.Controls[I];
      if (Sib = C) or not Sib.Visible or (Sib.Align <> alNone) then Continue;
      // each pair once: the left one (or the upper one at equal Left) reports
      if (Sib.Left < C.Left) or ((Sib.Left = C.Left) and (Sib.Top <= C.Top)) then Continue;
      if not IntersectRect(R, C.BoundsRect, Sib.BoundsRect) then Continue;
      Report.Add(Format('%s  %s: "%s" overlaps %s', [FormName, Path(C), S, Sib.Name]));
    end;
end;

procedure CheckTree(W: TWinControl; Report: TStrings; const FormName: string);
var
  I: Integer;
begin
  for I := 0 to W.ControlCount - 1 do
  begin
    CheckControl(W.Controls[I], Report, FormName);
    if W.Controls[I] is TWinControl then
      CheckTree(TWinControl(W.Controls[I]), Report, FormName);
  end;
end;

procedure CheckForm(F: TForm; Report: TStrings);
var
  I: Integer;
begin
  F.Show;
  Application.ProcessMessages;
  // visit every tab so that its controls get their real size
  for I := 0 to F.ComponentCount - 1 do
    if F.Components[I] is TPageControl then
      TPageControl(F.Components[I]).ActivePageIndex := 0;
  CheckTree(F, Report, F.ClassName);
end;

procedure CheckDialogs(Report: TStrings);
var
  Insp: TModalInspector;
  A, B: TTagField;
  Check: Boolean;
  W: TRenameWords;
  Acts: TRenameActions;
  Dir: TSyncDirection;
  Ex: TSyncExisting;
  Vals: TFieldValues;
  Fs: TTagFieldSet;
  T: TTagField;
  CO: TCoverResize;
  MaskText: string;

  procedure Arm;
  begin
    Insp.Round := 0;
    Application.QueueAsyncCall(@Insp.Inspect, 0);
  end;

begin
  Insp := TModalInspector.Create;
  try
    Insp.Report := Report;
    A := tfArtist;
    B := tfAlbumArtist;
    Check := True;
    Arm;
    AskFieldPair(rsKopierFelt, rsFraFelt, rsTilFelt, rsKunHvisFeltetErTomt, A, B, Check);
    W := LoadRenameWords;
    Arm;
    EditRenameWords(W);
    Acts := nil;
    SetLength(Acts, 1);
    Acts[0].Name := 'Test';
    Acts[0].FileMask := '%1 - %2';
    Acts[0].FolderMask := '%1';
    Arm;
    EditRenameActions(Acts, '%1 - %2');
    Dir := sdV1ToV2;
    Ex := seBlankOnly;
    Arm;
    AskID3Sync(Dir, Ex);
    for T := Low(TTagField) to High(TTagField) do Vals[T] := TagFieldCaptions[T] + ' (eksempel)';
    Fs := [tfArtist, tfAlbum];
    Arm;
    AskFieldSet(rsIndsaetTag, rsVaelgFelterDerIndsaettes, Vals, Fs);
    CO.MaxSide := 600;
    CO.Quality := 90;
    CO.ToJpeg := False;
    Arm;
    AskCoverResize(rsSkalerCoverIFilerne, CO);
    MaskText := '%1 - %2';
    Arm;
    EditMask(rsMaskeEditor, MaskText, ['%1|' + TagFieldCaptions[tfArtist], '%2|' + TagFieldCaptions[tfTitle],
      '%3|' + TagFieldCaptions[tfAlbum], '%aa|' + TagFieldCaptions[tfAlbumArtist], '%rt|Udgivelsesdato'],
      @Insp.Preview, 'LayoutCheckMasks');
    Arm;
    FormMain.ActSettingsExecute(nil);
  finally
    Insp.Free;
  end;
end;

procedure RunLayoutCheck;
const
  Classes_: array[0..6] of TFormClass = (TFormTagEdit, TFormRename, TFormFileToTag,
    TFormMultiEdit, TFormTrackTools, TFormWebLookup, TFormExportImport);
var
  Report: TStringList;
  F: TForm;
  C: TFormClass;
begin
  Report := TStringList.Create;
  try
    CheckForm(FormMain, Report);
    for C in Classes_ do
    begin
      F := C.Create(Application);
      try
        CheckForm(F, Report);
      finally
        F.Free;
      end;
    end;
    CheckDialogs(Report);
    Report.SaveToFile(ParamStr(2));
  finally
    Report.Free;
  end;
end;

end.
