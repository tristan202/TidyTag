unit WebLookupForm;

{ "Web-opslag": search releases on MusicBrainz or Discogs, pair the files with the
  release's tracks, then write the chosen fields and the front cover (Cover Art Archive
  for MusicBrainz, the release's primary image for Discogs). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, ComCtrls,
  AudioTypes, MusicBrainz, TrackMatch;

type
  TWebJobKind = (wjSearch, wjDetail, wjCover);
  TWebSource = (wsMusicBrainz, wsDiscogs);

  { Runs one blocking web call off the main thread. }
  TWebJob = class(TThread)
  protected
    procedure Execute; override;
  public
    Kind: TWebJobKind;
    Source: TWebSource;
    Artist, Album, ReleaseId, GroupId, CoverUrl, Token: string;
    Releases: TMBReleases;
    Detail: TMBReleaseDetail;
    Cover: TBytes;
    Error: string;
    constructor Create(AKind: TWebJobKind);
  end;

  { TFormWebLookup }

  TFormWebLookup = class(TForm)
    ButtonClose: TButton;
    ButtonDown: TButton;
    ButtonSearch: TButton;
    ButtonToken: TButton;
    ButtonUp: TButton;
    ButtonWrite: TButton;
    CheckAlbum: TCheckBox;
    CheckAlbumArtist: TCheckBox;
    CheckArtist: TCheckBox;
    CheckCoverFolder: TCheckBox;
    CheckCoverTags: TCheckBox;
    CheckDisc: TCheckBox;
    CheckGenre: TCheckBox;
    CheckKeepTimestamp: TCheckBox;
    CheckTitle: TCheckBox;
    CheckTrack: TCheckBox;
    CheckTrackTotal: TCheckBox;
    CheckYear: TCheckBox;
    CheckYearOnly: TCheckBox;
    ComboSource: TComboBox;
    EditAlbum: TEdit;
    EditArtist: TEdit;
    GroupOptions: TGroupBox;
    ImageCover: TImage;
    LabelAlbum: TLabel;
    LabelArtist: TLabel;
    LabelCover: TLabel;
    LabelStatus: TLabel;
    LabelTracks: TLabel;
    ListReleases: TListView;
    ListTracks: TListView;
    procedure ButtonCloseClick(Sender: TObject);
    procedure ButtonDownClick(Sender: TObject);
    procedure ButtonSearchClick(Sender: TObject);
    procedure ButtonTokenClick(Sender: TObject);
    procedure ComboSourceChange(Sender: TObject);
    procedure ButtonUpClick(Sender: TObject);
    procedure ButtonWriteClick(Sender: TObject);
    procedure EditKeyPress(Sender: TObject; var Key: Char);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure ListReleasesSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
  private
    FItems: TAudioInfoArray;
    FReleases: TMBReleases;
    FDetail: TMBReleaseDetail;
    FHaveDetail: Boolean;
    FRows: TMatchRows;
    FCover: TBytes;
    FBusy: Boolean;
    FChanged: Boolean;
    FToken: string;
    function Source: TWebSource;
    function SourceName: string;
    function NewJob(Kind: TWebJobKind): TWebJob;
    function RunJob(Job: TWebJob; const Status: string): Boolean;
    procedure SetBusy(Value: Boolean);
    procedure LoadRelease(Index: Integer);
    procedure ShowTracks(SelectRow: Integer = -1);
    procedure ShowCover;
    function Options: TWebWriteOptions;
    procedure LoadOptions;
    procedure SaveOptions;
  public
    class function Execute(const Items: TAudioInfoArray; var KeepTimestamp: Boolean): Boolean;
  end;

implementation

{$R *.lfm}

uses
  StrUtils, IniFiles, AppSettings, AudioTags, TagWriter, TagUtils, Discogs;

{ TWebJob }

constructor TWebJob.Create(AKind: TWebJobKind);
begin
  Kind := AKind;
  FreeOnTerminate := False;
  inherited Create(True);
end;

procedure TWebJob.Execute;
begin
  try
    if Source = wsDiscogs then
      case Kind of
        wjSearch: Releases := DiscogsSearch(Artist, Album, Token);
        wjDetail: Detail := DiscogsRelease(ReleaseId, Token);
        wjCover: Cover := DiscogsCover(CoverUrl, Token);
      end
    else
      case Kind of
        wjSearch: Releases := SearchReleases(Artist, Album);
        wjDetail: Detail := GetReleaseDetail(ReleaseId);
        wjCover: Cover := GetFrontCover(ReleaseId, GroupId, 500);
      end;
  except
    on E: Exception do Error := E.Message;
  end;
end;

{ TFormWebLookup }

function CommonValue(const Items: TAudioInfoArray; F: TTagField): string;
var
  I: Integer;
begin
  Result := '';
  if Length(Items) = 0 then Exit;
  Result := Items[0].Fields[F];
  for I := 1 to High(Items) do
    if Items[I].Fields[F] <> Result then Exit('');
end;

class function TFormWebLookup.Execute(const Items: TAudioInfoArray; var KeepTimestamp: Boolean): Boolean;
var
  F: TFormWebLookup;
  Artist: string;
begin
  F := TFormWebLookup.Create(Application);
  try
    F.FItems := Items;
    F.LoadOptions;
    F.ButtonToken.Visible := F.Source = wsDiscogs;
    F.CheckKeepTimestamp.Checked := KeepTimestamp;
    Artist := CommonValue(Items, tfAlbumArtist);
    if Artist = '' then Artist := CommonValue(Items, tfArtist);
    F.EditArtist.Text := Artist;
    F.EditAlbum.Text := CommonValue(Items, tfAlbum);
    F.Caption := Format('Web-opslag - %d filer', [Length(Items)]);
    F.LabelStatus.Caption := 'Skriv kunstner og album, og tryk Søg.';
    F.ShowTracks;
    F.ShowModal;
    KeepTimestamp := F.CheckKeepTimestamp.Checked;
    Result := F.FChanged;
  finally
    F.Free;
  end;
end;

procedure TFormWebLookup.LoadOptions;
var
  Ini: TIniFile;
begin
  Ini := OpenSettings;
  try
    CheckTitle.Checked := Ini.ReadBool('Web', 'Title', True);
    CheckArtist.Checked := Ini.ReadBool('Web', 'Artist', True);
    CheckAlbum.Checked := Ini.ReadBool('Web', 'Album', True);
    CheckAlbumArtist.Checked := Ini.ReadBool('Web', 'AlbumArtist', True);
    CheckYear.Checked := Ini.ReadBool('Web', 'Year', True);
    CheckYearOnly.Checked := Ini.ReadBool('Web', 'YearOnly', True);
    CheckTrack.Checked := Ini.ReadBool('Web', 'Track', True);
    CheckTrackTotal.Checked := Ini.ReadBool('Web', 'TrackTotal', False);
    CheckDisc.Checked := Ini.ReadBool('Web', 'Disc', True);
    CheckGenre.Checked := Ini.ReadBool('Web', 'Genre', False);
    CheckCoverTags.Checked := Ini.ReadBool('Web', 'CoverTags', True);
    CheckCoverFolder.Checked := Ini.ReadBool('Web', 'CoverFolder', False);
    ComboSource.ItemIndex := Ini.ReadInteger('Web', 'Source', 0);
    FToken := Ini.ReadString('Discogs', 'Token', '');
  finally
    Ini.Free;
  end;
end;

procedure TFormWebLookup.SaveOptions;
var
  Ini: TIniFile;
begin
  Ini := OpenSettings;
  try
    Ini.WriteBool('Web', 'Title', CheckTitle.Checked);
    Ini.WriteBool('Web', 'Artist', CheckArtist.Checked);
    Ini.WriteBool('Web', 'Album', CheckAlbum.Checked);
    Ini.WriteBool('Web', 'AlbumArtist', CheckAlbumArtist.Checked);
    Ini.WriteBool('Web', 'Year', CheckYear.Checked);
    Ini.WriteBool('Web', 'YearOnly', CheckYearOnly.Checked);
    Ini.WriteBool('Web', 'Track', CheckTrack.Checked);
    Ini.WriteBool('Web', 'TrackTotal', CheckTrackTotal.Checked);
    Ini.WriteBool('Web', 'Disc', CheckDisc.Checked);
    Ini.WriteBool('Web', 'Genre', CheckGenre.Checked);
    Ini.WriteBool('Web', 'CoverTags', CheckCoverTags.Checked);
    Ini.WriteBool('Web', 'CoverFolder', CheckCoverFolder.Checked);
    Ini.WriteInteger('Web', 'Source', ComboSource.ItemIndex);
  finally
    Ini.Free;
  end;
end;

function TFormWebLookup.Source: TWebSource;
begin
  if ComboSource.ItemIndex = 1 then Result := wsDiscogs else Result := wsMusicBrainz;
end;

function TFormWebLookup.SourceName: string;
begin
  if Source = wsDiscogs then Result := 'Discogs' else Result := 'MusicBrainz';
end;

function TFormWebLookup.NewJob(Kind: TWebJobKind): TWebJob;
begin
  Result := TWebJob.Create(Kind);
  Result.Source := Source;
  Result.Token := FToken;
end;

procedure TFormWebLookup.ComboSourceChange(Sender: TObject);
begin
  // Results of one source mean nothing to the other.
  FReleases := nil;
  ListReleases.Items.Clear;
  FHaveDetail := False;
  FCover := nil;
  ShowTracks;
  ShowCover;
  ButtonWrite.Enabled := False;
  ButtonToken.Visible := Source = wsDiscogs;
  if (Source = wsDiscogs) and (FToken = '') then
    LabelStatus.Caption := 'Discogs kræver et personligt token til søgning - tryk "Discogs-token...".'
  else
    LabelStatus.Caption := 'Tryk Søg.';
end;

procedure TFormWebLookup.ButtonTokenClick(Sender: TObject);
var
  Value: string;
  Ini: TIniFile;
begin
  Value := FToken;
  if not InputQuery('Discogs-token',
    'Lav et personligt token på discogs.com: Settings > Developers > Generate new token.' + LineEnding +
    'Indsæt det her (det gemmes kun på denne computer, i TagKlons indstillingsfil):', True, Value) then Exit;
  FToken := Trim(Value);
  Ini := OpenSettings;
  try
    Ini.WriteString('Discogs', 'Token', FToken);
  finally
    Ini.Free;
  end;
  if FToken = '' then LabelStatus.Caption := 'Discogs-token fjernet.'
  else LabelStatus.Caption := 'Discogs-token gemt. Tryk Søg.';
end;

procedure TFormWebLookup.SetBusy(Value: Boolean);
begin
  FBusy := Value;
  ButtonSearch.Enabled := not Value;
  ListReleases.Enabled := not Value;
  ButtonWrite.Enabled := not Value and FHaveDetail;
  ButtonUp.Enabled := not Value;
  ButtonDown.Enabled := not Value;
  if Value then Screen.Cursor := crAppStart else Screen.Cursor := crDefault;
end;

{ Runs Job in the background while the window stays responsive. Frees nothing:
  the caller reads the results and frees the job. }
function TFormWebLookup.RunJob(Job: TWebJob; const Status: string): Boolean;
begin
  SetBusy(True);
  try
    LabelStatus.Caption := Status;
    Job.Start;
    while not Job.Finished do
    begin
      Application.ProcessMessages;
      Sleep(15);
    end;
    Job.WaitFor;
    Result := Job.Error = '';
    if not Result then LabelStatus.Caption := 'Fejl: ' + Job.Error;
  finally
    SetBusy(False);
  end;
end;

procedure TFormWebLookup.EditKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then
  begin
    Key := #0;
    ButtonSearchClick(nil);
  end;
end;

procedure TFormWebLookup.ButtonSearchClick(Sender: TObject);
var
  Job: TWebJob;
  I: Integer;
  Item: TListItem;
begin
  if FBusy then Exit;
  Job := NewJob(wjSearch);
  try
    Job.Artist := Trim(EditArtist.Text);
    Job.Album := Trim(EditAlbum.Text);
    if not RunJob(Job, 'Søger på ' + SourceName + '...') then Exit;
    FReleases := Job.Releases;
  finally
    Job.Free;
  end;
  ListReleases.Items.BeginUpdate;
  try
    ListReleases.Items.Clear;
    for I := 0 to High(FReleases) do
    begin
      Item := ListReleases.Items.Add;
      Item.Caption := FReleases[I].Artist;
      Item.SubItems.Add(FReleases[I].Title +
        IfThen(FReleases[I].Disambiguation <> '', ' (' + FReleases[I].Disambiguation + ')', ''));
      Item.SubItems.Add(FReleases[I].Date);
      Item.SubItems.Add(FReleases[I].Country);
      Item.SubItems.Add(IfThen(FReleases[I].TrackCount > 0, IntToStr(FReleases[I].TrackCount), ''));
      Item.SubItems.Add(FReleases[I].Formats);
      Item.SubItems.Add(FReleases[I].LabelName);
      Item.SubItems.Add(FReleases[I].CatalogNo);
    end;
  finally
    ListReleases.Items.EndUpdate;
  end;
  if Length(FReleases) = 0 then
    LabelStatus.Caption := 'Ingen udgivelser fundet. Prøv med færre ord eller en anden stavemåde.'
  else
  begin
    LabelStatus.Caption := Format('%d udgivelser fundet på %s. Vælg den rigtige (dato, format og ' +
      'katalognummer hjælper).', [Length(FReleases), SourceName]);
    // Preselect the first release with as many tracks as there are files, else the best hit.
    for I := 0 to High(FReleases) do
      if FReleases[I].TrackCount = Length(FItems) then
      begin
        ListReleases.Items[I].Selected := True;
        ListReleases.Items[I].MakeVisible(False);
        Exit;
      end;
    ListReleases.Items[0].Selected := True;
  end;
end;

procedure TFormWebLookup.ListReleasesSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if Selected and not FBusy and (Item <> nil) then LoadRelease(Item.Index);
end;

procedure TFormWebLookup.LoadRelease(Index: Integer);
var
  Job: TWebJob;
  ByNumber: Boolean;
begin
  if (Index < 0) or (Index > High(FReleases)) then Exit;
  FHaveDetail := False;
  FCover := nil;
  ShowCover;
  Job := NewJob(wjDetail);
  try
    Job.ReleaseId := FReleases[Index].Id;
    if not RunJob(Job, 'Henter sporliste...') then Exit;
    FDetail := Job.Detail;
  finally
    Job.Free;
  end;
  FHaveDetail := True;
  FRows := MatchFilesToTracks(FItems, FDetail, ByNumber);
  ShowTracks;
  if ByNumber then
    LabelStatus.Caption := 'Filerne er parret efter deres spornumre. Henter cover...'
  else
    LabelStatus.Caption := 'Filerne er parret i listens rækkefølge - ret med Op/Ned. Henter cover...';

  Job := NewJob(wjCover);
  try
    Job.ReleaseId := FDetail.Release.Id;
    Job.GroupId := FDetail.Release.ReleaseGroupId;
    Job.CoverUrl := FDetail.CoverUrl;
    if RunJob(Job, LabelStatus.Caption) then FCover := Job.Cover;
  finally
    Job.Free;
  end;
  ShowCover;
  LabelStatus.Caption := StringReplace(LabelStatus.Caption, ' Henter cover...', '', []);
  ButtonWrite.Enabled := True;
end;

procedure TFormWebLookup.ShowCover;
var
  S: TBytesStream;
  W, H: Integer;
begin
  ImageCover.Picture.Clear;
  if FCover = nil then
  begin
    if FHaveDetail then LabelCover.Caption := 'Intet cover fundet'
    else LabelCover.Caption := '';
    Exit;
  end;
  S := TBytesStream.Create(FCover);
  try
    try
      if DetectImageMime(FCover) = 'image/png' then
        ImageCover.Picture.LoadFromStreamWithFileExt(S, 'png')
      else
        ImageCover.Picture.LoadFromStreamWithFileExt(S, 'jpg');
    except
      ImageCover.Picture.Clear;
    end;
  finally
    S.Free;
  end;
  ImageDimensions(FCover, W, H);
  LabelCover.Caption := Format('Cover: %dx%d, %d KB', [W, H, (Length(FCover) + 1023) div 1024]);
end;

procedure TFormWebLookup.ShowTracks(SelectRow: Integer);
var
  I: Integer;
  Item: TListItem;
  T: TMBTrack;
  F: TAudioInfo;
begin
  ListTracks.Items.BeginUpdate;
  try
    ListTracks.Items.Clear;
    if not FHaveDetail then
    begin
      // Before a release is chosen, just list the files.
      for I := 0 to High(FItems) do
      begin
        Item := ListTracks.Items.Add;
        Item.Caption := '';
        Item.SubItems.Add('');
        Item.SubItems.Add('');
        Item.SubItems.Add('');
        Item.SubItems.Add(ExtractFileName(FItems[I].FileName));
        Item.SubItems.Add(FormatDuration(FItems[I].Duration));
      end;
      Exit;
    end;
    for I := 0 to High(FRows) do
    begin
      Item := ListTracks.Items.Add;
      if FRows[I].TrackIdx >= 0 then
      begin
        T := FDetail.Tracks[FRows[I].TrackIdx];
        if FDetail.DiscCount > 1 then
          Item.Caption := Format('%d-%.2d', [T.Disc, T.Position])
        else
          Item.Caption := IntToStr(T.Position);
        Item.SubItems.Add(T.Title);
        Item.SubItems.Add(T.Artist);
        Item.SubItems.Add(FormatDuration(T.LengthMs / 1000));
      end
      else
      begin
        Item.Caption := '-';
        Item.SubItems.Add('(intet spor - filen ændres ikke)');
        Item.SubItems.Add('');
        Item.SubItems.Add('');
      end;
      if FRows[I].FileIdx >= 0 then
      begin
        F := FItems[FRows[I].FileIdx];
        Item.SubItems.Add(ExtractFileName(F.FileName));
        Item.SubItems.Add(FormatDuration(F.Duration));
      end
      else
      begin
        Item.SubItems.Add('');
        Item.SubItems.Add('');
      end;
    end;
  finally
    ListTracks.Items.EndUpdate;
  end;
  if (SelectRow >= 0) and (SelectRow < ListTracks.Items.Count) then
  begin
    ListTracks.Items[SelectRow].Selected := True;
    ListTracks.Items[SelectRow].Focused := True;
    ListTracks.Items[SelectRow].MakeVisible(False);
  end;
end;

procedure TFormWebLookup.ButtonUpClick(Sender: TObject);
var
  Row: Integer;
begin
  if (ListTracks.Selected = nil) or not FHaveDetail then Exit;
  Row := ListTracks.Selected.Index;
  if Row = 0 then Exit;
  MoveFile(FRows, Row, -1);
  ShowTracks(Row - 1);
end;

procedure TFormWebLookup.ButtonDownClick(Sender: TObject);
var
  Row: Integer;
begin
  if (ListTracks.Selected = nil) or not FHaveDetail then Exit;
  Row := ListTracks.Selected.Index;
  if Row >= High(FRows) then Exit;
  MoveFile(FRows, Row, 1);
  ShowTracks(Row + 1);
end;

function TFormWebLookup.Options: TWebWriteOptions;
begin
  Result.Fields := [];
  if CheckTitle.Checked then Include(Result.Fields, tfTitle);
  if CheckArtist.Checked then Include(Result.Fields, tfArtist);
  if CheckAlbum.Checked then Include(Result.Fields, tfAlbum);
  if CheckAlbumArtist.Checked then Include(Result.Fields, tfAlbumArtist);
  if CheckYear.Checked then Include(Result.Fields, tfYear);
  if CheckTrack.Checked then Include(Result.Fields, tfTrack);
  if CheckDisc.Checked then Include(Result.Fields, tfDisc);
  if CheckGenre.Checked then Include(Result.Fields, tfGenre);
  Result.YearOnly := CheckYearOnly.Checked;
  Result.TrackWithTotal := CheckTrackTotal.Checked;
end;

{ Front cover first; other pictures (back, booklet, ...) are kept. }
procedure SetFrontCover(Info: TAudioInfo; const Data: TBytes);
var
  Keep: TTagPictures;
  I, N: Integer;
begin
  Keep := nil;
  SetLength(Keep, Length(Info.Pictures) + 1);
  Keep[0].PicType := PicTypeFrontCover;
  Keep[0].MimeType := DetectImageMime(Data);
  Keep[0].Description := '';
  Keep[0].Data := Data;
  N := 1;
  for I := 0 to High(Info.Pictures) do
    if Info.Pictures[I].PicType <> PicTypeFrontCover then
    begin
      Keep[N] := Info.Pictures[I];
      Inc(N);
    end;
  SetLength(Keep, N);
  Info.Pictures := Keep;
end;

procedure TFormWebLookup.ButtonWriteClick(Sender: TObject);
var
  Opt: TWebWriteOptions;
  I, Saved, Failed, Skipped, Folders, Pairs: Integer;
  Full: TAudioInfo;
  Errors, DoneDirs: TStringList;
  Dir, CoverName: string;
  S: TFileStream;
begin
  if not FHaveDetail then Exit;
  Opt := Options;
  Pairs := 0;
  for I := 0 to High(FRows) do
    if (FRows[I].TrackIdx >= 0) and (FRows[I].FileIdx >= 0) then Inc(Pairs);
  if (Opt.Fields = []) and not CheckCoverTags.Checked and not CheckCoverFolder.Checked then
  begin
    MessageDlg('Vælg, hvad der skal skrives.', mtInformation, [mbOK], 0);
    Exit;
  end;
  if MessageDlg('Skriv tags', Format('Skriv oplysninger fra "%s" i %d filer?',
    [FDetail.Release.Title, Pairs]), mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  SaveOptions;

  Saved := 0;
  Failed := 0;
  Skipped := 0;
  Folders := 0;
  Errors := TStringList.Create;
  DoneDirs := TStringList.Create;
  SetBusy(True);
  try
    for I := 0 to High(FRows) do
    begin
      if (FRows[I].TrackIdx < 0) or (FRows[I].FileIdx < 0) then Continue;
      Full := nil;
      with FItems[FRows[I].FileIdx] do
      begin
        LabelStatus.Caption := 'Skriver ' + ExtractFileName(FileName) + '...';
        Application.ProcessMessages;
        if not CanWriteTags(FileName) then
        begin
          Inc(Skipped);
          Continue;
        end;
        Full := ReadAudioInfo(FileName, True);
      end;
      try
        if Full.Error <> '' then
        begin
          Inc(Failed);
          Errors.Add(ExtractFileName(Full.FileName) + ': ' + Full.Error);
          Continue;
        end;
        ApplyTrack(Full, FDetail, FRows[I].TrackIdx, Opt);
        if CheckCoverTags.Checked and (FCover <> nil) then SetFrontCover(Full, FCover);
        try
          WriteAudioTags(Full, CheckKeepTimestamp.Checked);
          ApplyTrack(FItems[FRows[I].FileIdx], FDetail, FRows[I].TrackIdx, Opt);
          FItems[FRows[I].FileIdx].HasCover := Length(Full.Pictures) > 0;
          Inc(Saved);
          FChanged := True;
        except
          on E: Exception do
          begin
            Inc(Failed);
            Errors.Add(ExtractFileName(Full.FileName) + ': ' + E.Message);
          end;
        end;
      finally
        Full.Free;
      end;
    end;

    // folder.jpg next to the files (never overwrites an existing one)
    if CheckCoverFolder.Checked and (FCover <> nil) then
      for I := 0 to High(FRows) do
      begin
        if FRows[I].FileIdx < 0 then Continue;
        Dir := ExtractFileDir(FItems[FRows[I].FileIdx].FileName);
        if DoneDirs.IndexOf(Dir) >= 0 then Continue;
        DoneDirs.Add(Dir);
        if DetectImageMime(FCover) = 'image/png' then CoverName := 'folder.png' else CoverName := 'folder.jpg';
        CoverName := IncludeTrailingPathDelimiter(Dir) + CoverName;
        if FileExists(CoverName) then
        begin
          Errors.Add(CoverName + ' findes allerede - ikke overskrevet');
          Continue;
        end;
        try
          S := TFileStream.Create(CoverName, fmCreate);
          try
            WriteBytes(S, FCover);
          finally
            S.Free;
          end;
          Inc(Folders);
        except
          on E: Exception do Errors.Add(CoverName + ': ' + E.Message);
        end;
      end;
  finally
    SetBusy(False);
  end;
  LabelStatus.Caption := Format('Gemt i %d filer   ·   %d fejl   ·   %d sprunget over (filtype)', [Saved, Failed, Skipped]);
  if Folders > 0 then
    LabelStatus.Caption := LabelStatus.Caption + Format('   ·   cover gemt i %d mapper', [Folders]);
  if Errors.Count > 0 then
  begin
    while Errors.Count > 20 do Errors.Delete(Errors.Count - 1);
    MessageDlg('Bemærk', Errors.Text, mtWarning, [mbOK], 0);
  end;
  Errors.Free;
  DoneDirs.Free;
end;

procedure TFormWebLookup.ButtonCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TFormWebLookup.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  // A running web call finishes on its own (max. ~20 s timeout); wait for it.
  CanClose := not FBusy;
  if CanClose then SaveOptions;
end;

end.
