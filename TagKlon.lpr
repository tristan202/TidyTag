program TagKlon;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, Language, LayoutFit, MainForm, LayoutCheck;

{$R *.res}
{$R res/icons.rc}

begin
  RequireDerivedFormResource := True;
  Application.Title := 'TagKlon';
  Application.Scaled := True;
  Application.Initialize;
  ApplyLanguage;
  Application.CreateForm(TFormMain, FormMain);
  if LayoutCheckRequested then
  begin
    RunLayoutCheck;
    Exit;
  end;
  Application.Run;
end.
