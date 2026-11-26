//! iniset <file> <section> <key> <value>: sets one value with the round-trip Ini (manual check).
fn main() {
    let a: Vec<String> = std::env::args().skip(1).collect();
    let mut ini = tidytag_core::settings::Ini::load(std::path::Path::new(&a[0])).unwrap();
    ini.set(&a[1], &a[2], &a[3]);
    ini.save().unwrap();
}
