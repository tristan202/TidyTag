//! Tag readers, one module per Pascal reader unit.
//! Each exposes `read(&mut impl Read + Seek, &mut AudioInfo) -> Result<(), String>`.

pub mod ape;
pub mod asf;
pub mod id3;
pub mod mp3;
pub mod mp4;
pub mod riff;
pub mod vorbis;

/// '.flac' uses the FLAC entry of the Vorbis-comment reader.
pub mod flac {
    pub use super::vorbis::read_flac as read;
}
