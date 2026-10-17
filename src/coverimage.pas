unit CoverImage;

{ Resizing cover pictures: shrinks JPEG/PNG data so that neither side exceeds MaxSide
  (good quality Mitchell interpolation) and optionally converts PNG to JPEG. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TCoverResize = record
    MaxSide: Integer;   // pixels
    Quality: Integer;   // JPEG quality 1..100
    ToJpeg: Boolean;    // also convert PNG pictures to JPEG
  end;

{ Returns True and the new data/MIME type when the picture had to change. }
function ResizeCover(const Data: TBytes; const Opt: TCoverResize; out NewData: TBytes;
  out NewMime: string): Boolean;

implementation

uses
  Graphics, IntfGraphics, LazCanvas, FPImage, FPCanvas, GraphType, AudioTypes, TagUtils;

function ResizeCover(const Data: TBytes; const Opt: TCoverResize; out NewData: TBytes;
  out NewMime: string): Boolean;
var
  Mime: string;
  W, H, NW, NH: Integer;
  Src: TPicture;
  SrcBmp, DstBmp: TBitmap;
  SrcImg, DstImg: TLazIntfImage;
  Canvas: TLazCanvas;
  In_, Out_: TBytesStream;
  Jpg: TJPEGImage;
  Png: TPortableNetworkGraphic;
begin
  Result := False;
  NewData := nil;
  NewMime := '';
  Mime := DetectImageMime(Data, '');
  if (Mime = '') or not ImageDimensions(Data, W, H) or (W <= 0) or (H <= 0) then Exit;
  if (W <= Opt.MaxSide) and (H <= Opt.MaxSide) and not (Opt.ToJpeg and (Mime = 'image/png')) then
    Exit; // nothing to do
  if (W > Opt.MaxSide) or (H > Opt.MaxSide) then
  begin
    if W >= H then
    begin
      NW := Opt.MaxSide;
      NH := Round(H * Opt.MaxSide / W);
    end
    else
    begin
      NH := Opt.MaxSide;
      NW := Round(W * Opt.MaxSide / H);
    end;
    if NW < 1 then NW := 1;
    if NH < 1 then NH := 1;
  end
  else
  begin
    NW := W;
    NH := H;
  end;

  Src := TPicture.Create;
  SrcBmp := TBitmap.Create;
  DstBmp := TBitmap.Create;
  SrcImg := nil;
  DstImg := nil;
  Canvas := nil;
  In_ := TBytesStream.Create(Data);
  Out_ := TBytesStream.Create;
  try
    if Mime = 'image/png' then Src.LoadFromStreamWithFileExt(In_, 'png')
    else Src.LoadFromStreamWithFileExt(In_, 'jpg');
    // draw onto white first, so transparent PNG areas do not turn black in JPEG
    SrcBmp.SetSize(W, H);
    SrcBmp.Canvas.Brush.Color := clWhite;
    SrcBmp.Canvas.FillRect(0, 0, W, H);
    SrcBmp.Canvas.Draw(0, 0, Src.Graphic);
    SrcImg := SrcBmp.CreateIntfImage;
    DstImg := TLazIntfImage.Create(0, 0, [riqfRGB]);
    DstImg.DataDescription := GetDescriptionFromDevice(0, NW, NH);
    Canvas := TLazCanvas.Create(DstImg);
    Canvas.Interpolation := TMitchelInterpolation.Create;
    try
      Canvas.StretchDraw(0, 0, NW, NH, SrcImg);
    finally
      Canvas.Interpolation.Free;
      Canvas.Interpolation := nil;
    end;
    DstBmp.LoadFromIntfImage(DstImg);
    if (Mime = 'image/png') and not Opt.ToJpeg then
    begin
      Png := TPortableNetworkGraphic.Create;
      try
        Png.Assign(DstBmp);
        Png.SaveToStream(Out_);
      finally
        Png.Free;
      end;
      NewMime := 'image/png';
    end
    else
    begin
      Jpg := TJPEGImage.Create;
      try
        Jpg.CompressionQuality := Opt.Quality;
        Jpg.Assign(DstBmp);
        Jpg.SaveToStream(Out_);
      finally
        Jpg.Free;
      end;
      NewMime := 'image/jpeg';
    end;
    NewData := StreamBytes(Out_);
    Result := Length(NewData) > 0;
  finally
    Canvas.Free;
    DstImg.Free;
    SrcImg.Free;
    Out_.Free;
    In_.Free;
    DstBmp.Free;
    SrcBmp.Free;
    Src.Free;
  end;
end;

end.
