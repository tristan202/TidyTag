//! Tag readers and writers, one module per Pascal unit.
//! Readers expose `read(&mut impl Read + Seek, &mut AudioInfo) -> Result<(), String>`,
//! writers `write(&Path, &AudioInfo, &WriteOptions) -> Result<(), String>`.

pub mod ape;
pub mod asf;
pub mod id3;
pub mod mp3;
pub mod mp4;
pub mod riff;
pub mod vorbis;

pub mod ape_write;
pub mod asf_write;
pub mod flac_write;
pub mod id3_write;
pub mod mp4_write;
pub mod ogg_write;
pub mod riff_write;

/// '.flac' uses the FLAC entry of the Vorbis-comment reader.
pub mod flac {
    pub use super::vorbis::read_flac as read;
}
