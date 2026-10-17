program TagKlon;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, MainForm;

{$R *.res}
{$R res/icons.rc}

begin
  RequireDerivedFormResource := True;
  Application.Title := 'TagKlon';
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
end.
