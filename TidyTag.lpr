program TidyTag;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, Language, LayoutFit, MainForm, LayoutCheck;

{$R *.res}
{$R res/icons.res} // precompiled from res/icons.rc by tools/make-icons-res.ps1 (FPC cannot compile .rc in paths with spaces)

begin
  RequireDerivedFormResource := True;
  Application.Title := 'TidyTag';
  Application.Scaled := True;
  Application.Initialize;
  ApplyLanguage;
  Application.CreateForm(TFormMain, FormMain);
  if LayoutCheckRequested then
  begin
    RunLayoutCheck;
    Exit;
  end;
  if (ParamCount >= 3) and (ParamStr(1) = '--selftest') then
  begin
    FormMain.Show;
    FormMain.RunSelfTest(ParamStr(3));
    Exit;
  end;
  Application.Run;
end.
