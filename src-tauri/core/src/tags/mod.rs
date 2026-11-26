//! Tag readers, one module per Pascal reader unit.
//! Each exposes `read(&mut impl Read + Seek, &mut AudioInfo) -> Result<(), String>`.

pub mod ape;
pub mod asf;
pub mod id3;
pub mod mp3;
pub mod mp4;
pub mod riff;
pub mod vorbis;

macro_rules! writer_not_yet {
    ($($m:ident),*) => {$(
        pub mod $m {
            pub fn write(_p: &std::path::Path, _i: &crate::model::AudioInfo, _o: &crate::write::WriteOptions) -> Result<(), String> {
                Err("not implemented".into())
            }
        }
    )*};
}

// Replaced one by one by the real writers (phase 2, Tasks 2-8).
pub mod id3_write;
pub mod flac_write;
pub mod ogg_write;
pub mod mp4_write;
writer_not_yet!(riff_write, ape_write, asf_write);

/// '.flac' uses the FLAC entry of the Vorbis-comment reader.
pub mod flac {
    pub use super::vorbis::read_flac as read;
}
