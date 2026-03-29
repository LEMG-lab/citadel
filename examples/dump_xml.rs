use keepass::{Database, DatabaseKey};
use std::fs::File;
fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mut f = File::open(&args[1]).unwrap();
    let key = DatabaseKey::new().with_password(&args[2]);
    let xml = Database::get_xml(&mut f, key).unwrap();
    println!("{}", String::from_utf8_lossy(&xml));
}
