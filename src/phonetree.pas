unit PhoneTree;

{ The folder tree with paired phones beside the drives. This unit declares a
  TShellTreeView that the main form's .lfm picks up (it is used after ShellCtrls).
  Phone nodes carry paths like \\TidyTag-Phone\<phone>\Music, so the main form's code that
  reads ShellTree.Path works unchanged; everything that would make Windows look up
  \\TidyTag-Phone on the network (sub-folder checks, shell icons, setting Path) is handled
  here through the file layer instead. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Graphics, ComCtrls, ShellCtrls;

type
  { A folder on a phone (or the phone itself, when Parent = nil). }
  TPhoneNode = class(TShellTreeNode)
  public
    procedure Init(const Base: string);
  end;

  TPhoneErrorEvent = procedure(const Msg: string) of object;

  TShellTreeView = class(ShellCtrls.TShellTreeView)
  private
    FMakePhoneNode: Boolean;
    FUnreachable: TStringList; // names of phones that did not answer
    FOnPhoneError: TPhoneErrorEvent;
    function GetPathEx: string;
    procedure SetPathEx(const AValue: string);
    function AddPhoneNode(ParentNode: TTreeNode; const NodeName, Base: string): TTreeNode;
    function PhoneRoot(const PhoneName: string): TTreeNode;
  protected
    procedure DoCreateNodeClass(var NewNodeClass: TTreeNodeClass); override;
    procedure Loaded; override;
    function CanExpand(Node: TTreeNode): Boolean; override;
    function NodeHasChildren(Node: TTreeNode): Boolean; override;
    function DrawBuiltInIcon(ANode: TTreeNode; ARect: TRect): TSize; override;
    function IsCustomDrawn(Target: TCustomDrawTarget; Stage: TCustomDrawStage): Boolean; override;
    function CustomDrawItem(Node: TTreeNode; State: TCustomDrawState; Stage: TCustomDrawStage;
      var PaintImages: Boolean): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Adds the paired phones again (after pairing, or after the drives were rebuilt). }
    procedure RefreshPhones;
    procedure UpdateView(AStartDir: string = '');
    property Path: string read GetPathEx write SetPathEx;
    property OnPhoneError: TPhoneErrorEvent read FOnPhoneError write FOnPhoneError;
  end;

implementation

uses
  Windows, ShellApi, FileLayer, PhoneClient;

var
  FolderIcon: HICON = 0; // Windows' own small folder icon, looked up without touching a disk

function SmallFolderIcon: HICON;
var
  Info: TSHFileInfoW;
begin
  if FolderIcon = 0 then
  begin
    FillChar(Info, SizeOf(Info), 0);
    if SHGetFileInfoW('folder', FILE_ATTRIBUTE_DIRECTORY, Info, SizeOf(Info),
      SHGFI_ICON or SHGFI_SMALLICON or SHGFI_USEFILEATTRIBUTES) <> 0 then
      FolderIcon := Info.hIcon;
  end;
  Result := FolderIcon;
end;

{ TPhoneNode }

procedure TPhoneNode.Init(const Base: string);
begin
  SetBasePath(Base);
  FFileInfo.Name := Text;
  FFileInfo.Attr := faDirectory;
end;

{ TShellTreeView }

constructor TShellTreeView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FUnreachable := TStringList.Create;
end;

destructor TShellTreeView.Destroy;
begin
  FUnreachable.Free;
  inherited Destroy;
end;

procedure TShellTreeView.DoCreateNodeClass(var NewNodeClass: TTreeNodeClass);
begin
  if FMakePhoneNode then NewNodeClass := TPhoneNode
  else inherited DoCreateNodeClass(NewNodeClass);
end;

function TShellTreeView.AddPhoneNode(ParentNode: TTreeNode; const NodeName, Base: string): TTreeNode;
begin
  FMakePhoneNode := True;
  try
    Result := Items.AddChild(ParentNode, NodeName);
  finally
    FMakePhoneNode := False;
  end;
  TPhoneNode(Result).Init(Base);
  Result.HasChildren := True; // found out when it is opened: no network call now
end;

procedure TShellTreeView.Loaded;
begin
  inherited Loaded;
  RefreshPhones;
end;

procedure TShellTreeView.RefreshPhones;
var
  PhoneName: string;
  I: Integer;
begin
  Items.BeginUpdate;
  try
    for I := Items.Count - 1 downto 0 do
      if (Items[I] is TPhoneNode) and (Items[I].Parent = nil) then Items[I].Delete;
    for PhoneName in PairedPhoneNames do
      AddPhoneNode(nil, PhoneName, ExcludeTrailingPathDelimiter(PhonePrefix));
  finally
    Items.EndUpdate;
  end;
end;

procedure TShellTreeView.UpdateView(AStartDir: string);
begin
  if IsPhonePath(AStartDir) then
  begin
    inherited UpdateView('');
    RefreshPhones;
    SetPathEx(AStartDir);
  end
  else
  begin
    inherited UpdateView(AStartDir);
    RefreshPhones;
  end;
end;

function TShellTreeView.PhoneRoot(const PhoneName: string): TTreeNode;
var
  N: TTreeNode;
begin
  N := Items.GetFirstNode;
  while N <> nil do
  begin
    if (N is TPhoneNode) and SameText(N.Text, PhoneName) then Exit(N);
    N := N.GetNextSibling;
  end;
  Result := nil;
end;

function TShellTreeView.CanExpand(Node: TTreeNode): Boolean;
var
  Entries: TPhoneEntries;
  E: TPhoneEntry;
  Dir: string;
  TopNode: TTreeNode;
begin
  if not (Node is TPhoneNode) then Exit(inherited CanExpand(Node));
  TopNode := Node;
  while TopNode.Parent <> nil do TopNode := TopNode.Parent;
  Dir := GetPathFromNode(Node);
  try
    Entries := ListDirL(Dir);
  except
    on Ex: Exception do
    begin
      if FUnreachable.IndexOf(TopNode.Text) < 0 then FUnreachable.Add(TopNode.Text);
      Invalidate;
      if Assigned(FOnPhoneError) then FOnPhoneError(Ex.Message);
      Exit(False);
    end;
  end;
  if FUnreachable.IndexOf(TopNode.Text) >= 0 then
  begin
    FUnreachable.Delete(FUnreachable.IndexOf(TopNode.Text));
    Invalidate;
  end;
  Items.BeginUpdate;
  try
    Node.DeleteChildren;
    for E in Entries do
      if E.IsDir and (E.Name <> '') and (E.Name[1] <> '.') then
        AddPhoneNode(Node, E.Name, ExcludeTrailingPathDelimiter(Dir));
    Node.AlphaSort;
  finally
    Items.EndUpdate;
  end;
  Node.HasChildren := Node.Count > 0;
  Result := True;
end;

function TShellTreeView.NodeHasChildren(Node: TTreeNode): Boolean;
begin
  if Node is TPhoneNode then Result := Node.HasChildren
  else Result := inherited NodeHasChildren(Node);
end;

function TShellTreeView.DrawBuiltInIcon(ANode: TTreeNode; ARect: TRect): TSize;
var
  Glyph: UnicodeString;
  OldName: string;
  OldColor: TColor;
  OldSize: Integer;
begin
  if not (ANode is TPhoneNode) then Exit(inherited DrawBuiltInIcon(ANode, ARect));
  Result := GetBuiltinIconSize;
  if (ANode.Parent <> nil) and (SmallFolderIcon <> 0) then
  begin
    DrawIconEx(Canvas.Handle, ARect.Left, ARect.Top + (ARect.Bottom - ARect.Top - Result.cy) div 2,
      SmallFolderIcon, Result.cx, Result.cy, 0, 0, DI_NORMAL);
    Exit;
  end;
  Glyph := WideChar($E8EA); // cell phone
  OldName := Canvas.Font.Name;
  OldColor := Canvas.Font.Color;
  OldSize := Canvas.Font.Height;
  try
    Canvas.Font.Name := 'Segoe MDL2 Assets';
    Canvas.Font.Height := -Result.cy;
    if (ANode.Parent = nil) and (FUnreachable.IndexOf(ANode.Text) >= 0) then Canvas.Font.Color := clGrayText;
    Canvas.Brush.Style := bsClear;
    Canvas.TextOut(ARect.Left, ARect.Top + (ARect.Bottom - ARect.Top - Result.cy) div 2, UTF8Encode(Glyph));
  finally
    Canvas.Font.Name := OldName;
    Canvas.Font.Color := OldColor;
    Canvas.Font.Height := OldSize;
  end;
end;

function TShellTreeView.IsCustomDrawn(Target: TCustomDrawTarget; Stage: TCustomDrawStage): Boolean;
begin
  Result := ((Target = dtItem) and (FUnreachable.Count > 0)) or inherited IsCustomDrawn(Target, Stage);
end;

function TShellTreeView.CustomDrawItem(Node: TTreeNode; State: TCustomDrawState; Stage: TCustomDrawStage;
  var PaintImages: Boolean): Boolean;
begin
  if (Node is TPhoneNode) and (Node.Parent = nil) and (FUnreachable.IndexOf(Node.Text) >= 0) then
    Canvas.Font.Color := clGrayText;
  Result := inherited CustomDrawItem(Node, State, Stage, PaintImages);
end;

function TShellTreeView.GetPathEx: string;
begin
  Result := inherited Path;
end;

procedure TShellTreeView.SetPathEx(const AValue: string);
var
  Rest, Part: string;
  Parts: TStringArray;
  N, C: TTreeNode;
begin
  if not IsPhonePath(AValue) then
  begin
    inherited Path := AValue;
    Exit;
  end;
  Rest := ExcludeTrailingPathDelimiter(Copy(AValue, Length(PhonePrefix) + 1, MaxInt));
  Parts := Rest.Split(['\']);
  if Length(Parts) = 0 then Exit;
  N := PhoneRoot(Parts[0]);
  if N = nil then Exit;
  for Part in Copy(Parts, 1, MaxInt) do
  begin
    N.Expand(False);
    C := N.GetFirstChild;
    while (C <> nil) and not SameText(C.Text, Part) do C := C.GetNextSibling;
    if C = nil then Break; // stop at the deepest folder found
    N := C;
  end;
  Selected := N;
  N.MakeVisible;
end;

finalization
  if FolderIcon <> 0 then DestroyIcon(FolderIcon);
end.
