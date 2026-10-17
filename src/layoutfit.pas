unit LayoutFit;

{ Makes room for translated texts, which are often longer than the Danish ones the forms
  were laid out for. When a form is shown for the first time:
  - a button too narrow for its caption grows (towards its anchored side) and pushes the
    controls next to it in the same row;
  - a label, check box or radio button that runs into a control to its right moves that
    control: input fields keep their right edge (they get narrower), other controls and
    everything after them in the row are shifted.
  Danish texts fit already, so nothing changes there. }

{$mode objfpc}{$H+}

interface

uses
  Forms;

procedure FitFormLayout(F: TCustomForm);

implementation

uses
  Classes, SysUtils, Math, Controls, StdCtrls, ExtCtrls, ComCtrls, Buttons, Spin, Graphics;

const
  MinInputWidth = 60;

var
  Measure: TBitmap;
  Fitted: TList;

function TextW(C: TControl; const S: string): Integer;
begin
  Measure.Canvas.Font.Assign(C.Font);
  Result := Measure.Canvas.TextWidth(StringReplace(S, '&', '', [rfReplaceAll]));
end;

function Gap(C: TControl): Integer;
begin
  Result := C.Scale96ToForm(6);
end;

{ Width the caption needs; 0 = no requirement. }
function NeededWidth(C: TControl): Integer;
var
  S: string;
begin
  Result := 0;
  S := C.Caption;
  if (S = '') or (Pos(#10, S) > 0) then Exit;
  if (C is TCustomButton) or (C is TSpeedButton) then
    Result := TextW(C, S) + C.Scale96ToForm(16)
  else if (C is TCustomCheckBox) or (C is TRadioButton) then
    Result := TextW(C, S) + C.Scale96ToForm(24)
  else if (C is TCustomLabel) and not TLabel(C).WordWrap then
    Result := TextW(C, S);
end;

function SameRow(A, B: TControl): Boolean;
begin
  Result := (A.Top < B.Top + B.Height - 4) and (B.Top < A.Top + A.Height - 4);
end;

function IsInput(C: TControl): Boolean;
begin
  Result := (C is TCustomEdit) or (C is TCustomComboBox) or (C is TCustomSpinEdit) or
    (C is TCustomFloatSpinEdit);
end;

{ Moves every visible control of the row that starts at or after X by D. }
procedure ShiftRow(Parent: TWinControl; Row: TControl; X, D: Integer; Skip: TControl);
var
  I: Integer;
  S: TControl;
begin
  for I := 0 to Parent.ControlCount - 1 do
  begin
    S := Parent.Controls[I];
    if (S = Skip) or (S = Row) or not S.Visible or not SameRow(S, Row) or (S is TImage) then
      Continue;
    if S.Left < X then Continue;
    // fixed-width labels keep their right edge, like input fields
    if (S is TCustomLabel) and not S.AutoSize and (S.Width - D >= S.Scale96ToForm(40)) then
      S.SetBounds(S.Left + D, S.Top, S.Width - D, S.Height)
    else
      S.Left := S.Left + D;
  end;
end;

function IsButton(C: TControl): Boolean;
begin
  Result := (C is TCustomButton) or (C is TSpeedButton);
end;

{ A row of buttons that now runs past the right edge moves left into free space. }
procedure PullRowBack(W: TWinControl; Row: TControl);
var
  I, Start, Limit, RightMost, Over: Integer;
  S: TControl;
begin
  Start := MaxInt;
  RightMost := 0;
  for I := 0 to W.ControlCount - 1 do
  begin
    S := W.Controls[I];
    if not S.Visible or not SameRow(S, Row) or not IsButton(S) then Continue;
    Start := Min(Start, S.Left);
    RightMost := Max(RightMost, S.Left + S.Width);
  end;
  Over := RightMost - (W.ClientWidth - Gap(Row));
  if Over <= 0 then Exit;
  // free space: up to the nearest other control on the row left of the buttons
  Limit := Gap(Row);
  for I := 0 to W.ControlCount - 1 do
  begin
    S := W.Controls[I];
    if S.Visible and SameRow(S, Row) and not IsButton(S) and not (S is TImage) and
      (S.Left + S.Width <= Start) then
      Limit := Max(Limit, S.Left + S.Width + Gap(Row));
  end;
  Over := Min(Over, Start - Limit);
  if Over <= 0 then Exit;
  for I := 0 to W.ControlCount - 1 do
  begin
    S := W.Controls[I];
    if S.Visible and SameRow(S, Row) and IsButton(S) and (S.Left >= Start) then
      S.Left := S.Left - Over;
  end;
end;

procedure FitContainer(W: TWinControl);
var
  List: TList;
  I, J, Need, D, OldRight: Integer;
  C, S: TControl;
begin
  List := TList.Create;
  try
    for I := 0 to W.ControlCount - 1 do
      if W.Controls[I].Visible then List.Add(W.Controls[I]);
    // left to right, so pushes cascade in reading order
    for I := 0 to List.Count - 1 do
      for J := I + 1 to List.Count - 1 do
        if TControl(List[J]).Left < TControl(List[I]).Left then List.Exchange(I, J);

    for I := 0 to List.Count - 1 do
    begin
      C := TControl(List[I]);
      if (C.Parent <> W) or (C.Align <> alNone) then Continue;
      Need := NeededWidth(C);
      if Need <= 0 then Continue;
      if (C is TCustomButton) or (C is TSpeedButton) then
      begin
        if Need <= C.Width then Continue;
        D := Need - C.Width;
        if (akRight in C.Anchors) and not (akLeft in C.Anchors) then
        begin
          // right-aligned button: grow to the left, push its left neighbours left
          OldRight := C.Left;
          C.SetBounds(C.Left - D, C.Top, Need, C.Height);
          for J := 0 to List.Count - 1 do
          begin
            S := TControl(List[J]);
            if (S <> C) and SameRow(S, C) and (S.Left + S.Width <= OldRight + 2) and
              (akRight in S.Anchors) and not (akLeft in S.Anchors) then
              S.Left := S.Left - D;
          end;
        end
        else
        begin
          OldRight := C.Left + C.Width;
          C.Width := Need;
          ShiftRow(W, C, OldRight - 2, D, C);
          PullRowBack(W, C);
        end;
        Continue;
      end;

      // captions that are not auto-sized get the width they need
      if not C.AutoSize and (Need > C.Width) then C.Width := Need;
      Need := Max(Need, C.Width);
      for J := 0 to List.Count - 1 do
      begin
        S := TControl(List[J]);
        if (S = C) or not SameRow(S, C) or (S.Left <= C.Left) then Continue;
        D := C.Left + Need + Gap(C) - S.Left;
        if D <= 0 then Continue;
        if IsInput(S) and (S.Width - D >= C.Scale96ToForm(MinInputWidth)) then
          S.SetBounds(S.Left + D, S.Top, S.Width - D, S.Height)
        else
          ShiftRow(W, C, S.Left, D, C);
      end;
    end;
  finally
    List.Free;
  end;
  for I := 0 to W.ControlCount - 1 do
    if W.Controls[I] is TWinControl then
      FitContainer(TWinControl(W.Controls[I]));
end;

procedure FitFormLayout(F: TCustomForm);
begin
  if Fitted.IndexOf(F) >= 0 then Exit;
  Fitted.Add(F);
  F.DisableAutoSizing;
  try
    FitContainer(F);
  finally
    F.EnableAutoSizing;
  end;
end;

type
  THook = class
    procedure VisibleChanged(Sender: TObject; Form: TCustomForm);
    procedure DoFit(Data: PtrInt);
    procedure FormRemoved(Sender: TObject; Form: TCustomForm);
  end;

{ The form is fitted right after it has been shown: before that its size (DPI scaling,
  anchors to the bottom/right) is not final, and moving anchored controls too early puts
  them in the wrong place. }
procedure THook.VisibleChanged(Sender: TObject; Form: TCustomForm);
begin
  if Form.Visible and (Fitted.IndexOf(Form) < 0) then
    Application.QueueAsyncCall(@DoFit, PtrInt(Form));
end;

procedure THook.DoFit(Data: PtrInt);
var
  I: Integer;
begin
  // the form may have been closed and freed in the meantime
  for I := 0 to Screen.CustomFormCount - 1 do
    if PtrInt(Screen.CustomForms[I]) = Data then
    begin
      FitFormLayout(Screen.CustomForms[I]);
      Exit;
    end;
end;

procedure THook.FormRemoved(Sender: TObject; Form: TCustomForm);
begin
  Fitted.Remove(Form);
end;

var
  Hook: THook;

initialization
  Measure := TBitmap.Create;
  Fitted := TList.Create;
  Hook := THook.Create;
  Screen.AddHandlerFormVisibleChanged(@Hook.VisibleChanged);
  Screen.AddHandlerRemoveForm(@Hook.FormRemoved);

finalization
  Application.RemoveAsyncCalls(Hook);
  Screen.RemoveHandlerFormVisibleChanged(@Hook.VisibleChanged);
  Screen.RemoveHandlerRemoveForm(@Hook.FormRemoved);
  Hook.Free;
  Fitted.Free;
  Measure.Free;
end.
