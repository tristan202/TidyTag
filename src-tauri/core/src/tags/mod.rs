//! Tag readers, one module per Pascal reader unit.
//! Each exposes `read(&mut impl Read + Seek, &mut AudioInfo) -> Result<(), String>`.

use crate::model::AudioInfo;
use std::io::{Read, Seek};

macro_rules! not_yet {
    ($($m:ident),*) => {$(
        pub mod $m {
            use super::*;
            pub fn read<R: Read + Seek>(_s: &mut R, _info: &mut AudioInfo) -> Result<(), String> {
                Err("not implemented".into())
            }
        }
    )*};
}

// Replaced one by one by the real readers (Tasks 3-7).
pub mod id3;
pub mod mp3;
pub mod ape;
pub mod vorbis;
pub mod mp4;
pub mod riff;

not_yet!(asf);

/// '.flac' and '.ogg' share the Vorbis reader but enter it differently.
pub mod flac {
    use super::*;
    pub fn read<R: Read + Seek>(s: &mut R, info: &mut AudioInfo) -> Result<(), String> {
        super::vorbis::read_flac(s, info)
    }
}
