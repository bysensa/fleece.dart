// Re-encode every type benchmark input with the upstream Rust library.
use fleece::{Doc, Encoder, SharedKeys, Value, decode, encode};
use std::{env, error::Error, fs, path::Path};

fn main() -> Result<(), Box<dyn Error>> {
    let input = env::args_os().nth(1).ok_or("missing fixture directory")?;
    let mut checked = 0;
    for file in fs::read_dir(&input)? {
        let path = file?.path();
        if path.extension().and_then(|ext| ext.to_str()) != Some("fleece") {
            continue;
        }
        let bytes = fs::read(&path)?;
        let output = match path.file_stem().and_then(|stem| stem.to_str()) {
            Some("uint64") => {
                // The owned U64 variant carries an extension tag. This fixture
                // exercises the standard unsigned primitive in both writers.
                let doc = Doc::new(&bytes)?;
                let mut writer = Encoder::new();
                writer.begin_array()?;
                for item in doc.root().as_array().ok_or("expected array")?.iter() {
                    writer.write_uint(item.as_u64().ok_or("expected uint")?)?;
                }
                writer.end_array()?;
                writer.finish()?
            }
            Some("dict-shared") => {
                let mut keys = SharedKeys::new();
                for key in ["name", "id", "ok"] {
                    keys.encode_and_add(key).ok_or("invalid shared key")?;
                }
                let doc = Doc::trusted(&bytes).with_shared_keys(&keys);
                doc.validate()?;
                let value = Value::from_ref(doc.root())?;
                let mut writer = Encoder::new().with_shared_keys(&mut keys);
                writer.write_value(&value)?;
                writer.finish()?
            }
            Some("dict-inherited") => {
                let base = fs::read(Path::new(&input).join("dict-inherited.base"))?;
                if encode(&decode(&base)?)? != base {
                    return Err("Rust produced different external base bytes".into());
                }
                let doc = Doc::trusted(&bytes).with_base(&base);
                doc.validate()?;
                let value = Value::from_ref(doc.root())?;
                let mut writer = Encoder::new().with_base(&base, true)?;
                writer.write_changed(Doc::new(&base)?.root(), &value)?;
                writer.finish()?
            }
            _ => encode(&decode(&bytes)?)?,
        };
        if bytes != output {
            return Err(format!("Rust produced different bytes for {}", path.display()).into());
        }
        checked += 1;
    }
    if checked == 0 {
        return Err("no type fixtures".into());
    }
    println!("Rust reproduced {checked} type fixtures byte for byte");
    Ok(())
}
