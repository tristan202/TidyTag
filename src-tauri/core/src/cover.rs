//! Cover pictures: resizing (port of coverimage.pas) and folder covers (mainform.pas).

use crate::model::{detect_image_mime, image_dimensions, AudioInfo, Picture, PIC_TYPE_FRONT_COVER};
use std::path::{Path, PathBuf};

/// [Cover] MaxSide / Quality / ToJpeg
#[derive(Debug, Clone, Copy, PartialEq, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CoverResize {
    pub max_side: u32,
    pub quality: u8,
    pub to_jpeg: bool,
}

impl Default for CoverResize {
    fn default() -> Self {
        CoverResize { max_side: 600, quality: 90, to_jpeg: false }
    }
}

/// The new data and MIME type when the picture had to change, else None.
// from: ResizeCover (Mitchell interpolation there; Catmull-Rom here, the image crate has no Mitchell)
pub fn resize_cover(data: &[u8], opt: &CoverResize) -> Option<(Vec<u8>, &'static str)> {
    // shortcut: only JPEG and PNG, as 1.2 (it raised on GIF/BMP; here they stay as they are)
    let mime = match detect_image_mime(data, "") {
        "image/png" => "image/png",
        "image/jpeg" => "image/jpeg",
        _ => return None,
    };
    let (w, h) = image_dimensions(data).filter(|&(w, h)| w > 0 && h > 0)?;
    let max = opt.max_side.max(1);
    let png = mime == "image/png";
    if w <= max && h <= max && !(opt.to_jpeg && png) {
        return None;
    }
    let (nw, nh) = if w > max || h > max {
        let r = |other: u32, longer: u32| ((other as f64 * max as f64 / longer as f64).round_ties_even() as u32).max(1);
        if w >= h { (max, r(h, w)) } else { (r(w, h), max) }
    } else {
        (w, h)
    };
    let img = image::load_from_memory(data).ok()?;
    // onto white first, so transparent PNG areas do not turn black
    let rgba = img.to_rgba8();
    let mut rgb = image::RgbImage::new(rgba.width(), rgba.height());
    for (d, s) in rgb.pixels_mut().zip(rgba.pixels()) {
        let a = s[3] as u32;
        for c in 0..3 {
            d[c] = ((s[c] as u32 * a + 255 * (255 - a) + 127) / 255) as u8;
        }
    }
    let out = if (nw, nh) == (rgb.width(), rgb.height()) {
        rgb
    } else {
        image::imageops::resize(&rgb, nw, nh, image::imageops::FilterType::CatmullRom)
    };
    let mut bytes = Vec::new();
    let new_mime = if png && !opt.to_jpeg {
        out.write_with_encoder(image::codecs::png::PngEncoder::new(&mut bytes)).ok()?;
        "image/png"
    } else {
        out.write_with_encoder(image::codecs::jpeg::JpegEncoder::new_with_quality(&mut bytes, opt.quality.clamp(1, 100)))
            .ok()?;
        "image/jpeg"
    };
    (!bytes.is_empty()).then_some((bytes, new_mime))
}

/// Resizes every picture of `info` that needs it (1.2's ShrinkPictures).
pub fn shrink_pictures(info: &mut AudioInfo, opt: &CoverResize) {
    for p in &mut info.pictures {
        if let Some((data, mime)) = resize_cover(&p.data, opt) {
            p.data = data;
            p.mime = mime.to_string();
        }
    }
}

/// The front cover, otherwise the first picture.
pub fn main_picture(info: &AudioInfo) -> Option<&Picture> {
    info.pictures.iter().find(|p| p.pic_type == PIC_TYPE_FRONT_COVER).or(info.pictures.first())
}

pub const FOLDER_COVER_NAMES: [&str; 6] = ["folder.jpg", "folder.png", "cover.jpg", "cover.png", "front.jpg", "front.png"];

// from: FindFolderCover
pub fn find_folder_cover(dir: &Path) -> Option<PathBuf> {
    FOLDER_COVER_NAMES.iter().map(|n| dir.join(n)).find(|p| p.is_file())
}

/// folder.png for PNG pictures, else folder.jpg (ActCoverAsFolder / ActCoverFromTags).
pub fn folder_cover_target(dir: &Path, mime: &str) -> PathBuf {
    dir.join(if mime == "image/png" { "folder.png" } else { "folder.jpg" })
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    pub(crate) fn jpeg(w: u32, h: u32) -> Vec<u8> {
        let img = image::RgbImage::from_pixel(w, h, image::Rgb([200, 30, 30]));
        let mut b = Vec::new();
        img.write_with_encoder(image::codecs::jpeg::JpegEncoder::new_with_quality(&mut b, 80)).unwrap();
        b
    }

    fn png(w: u32, h: u32) -> Vec<u8> {
        let img = image::RgbaImage::from_pixel(w, h, image::Rgba([0, 0, 255, 128]));
        let mut b = Vec::new();
        img.write_with_encoder(image::codecs::png::PngEncoder::new(&mut b)).unwrap();
        b
    }

    #[test]
    fn resize_large_jpeg() {
        let (data, mime) = resize_cover(&jpeg(2000, 1000), &CoverResize::default()).unwrap();
        assert_eq!(mime, "image/jpeg");
        assert_eq!(image_dimensions(&data), Some((600, 300)));
    }

    #[test]
    fn png_to_jpeg() {
        let opt = CoverResize { to_jpeg: true, ..Default::default() };
        let (data, mime) = resize_cover(&png(100, 100), &opt).unwrap();
        assert_eq!(mime, "image/jpeg");
        assert_eq!(detect_image_mime(&data, ""), "image/jpeg");
        assert_eq!(image_dimensions(&data), Some((100, 100)));
    }

    #[test]
    fn small_jpeg_unchanged() {
        assert!(resize_cover(&jpeg(300, 300), &CoverResize::default()).is_none());
        assert!(resize_cover(b"not an image", &CoverResize::default()).is_none());
    }

    #[test]
    fn large_png_stays_png() {
        let (data, mime) = resize_cover(&png(1200, 300), &CoverResize::default()).unwrap();
        assert_eq!(mime, "image/png");
        assert_eq!(image_dimensions(&data), Some((600, 150)));
    }
}
