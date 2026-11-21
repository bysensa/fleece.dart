// Compiled together with upstream throughput.rs to use its private record builder.
#[test]
fn dart_inputs_match() {
    let dir = std::path::PathBuf::from(std::env::var_os("FLEECE_BENCH_INPUTS").unwrap());
    let check = |name: &str, rust: &[u8]| {
        let dart = std::fs::read(dir.join(name)).unwrap();
        assert!(
            dart == rust,
            "{name}: Dart {} bytes, Rust {} bytes, common prefix {} bytes",
            dart.len(),
            rust.len(),
            dart.iter().zip(rust).take_while(|(a, b)| a == b).count()
        );
    };

    let mut records = Value::Array((0..1000).map(record).collect());
    let bytes = encode(&records).unwrap();
    check("records.fleece", &bytes);
    if std::env::var("FLEECE_BENCH_DICT_STRINGS").as_deref() == Ok("1")
        || dir.join("addresses.fleece").exists()
        || dir.join("short-strings.fleece").exists()
    {
        let (addresses, strings) = dictionary_inputs(&records);
        check("addresses.fleece", &encode(&addresses).unwrap());
        check("short-strings.fleece", &encode(&strings).unwrap());
    }
    check(
        "records.json",
        fleece::json::to_json(&records).to_string().as_bytes(),
    );

    let one = record(500);
    check("record.fleece", &encode(&one).unwrap());
    let mut keys = fleece::SharedKeys::new();
    let mut encoder = fleece::Encoder::new().with_shared_keys(&mut keys);
    encoder.write_value(&one).unwrap();
    check("record-shared.fleece", &encoder.finish().unwrap());

    let Value::Array(rows) = &mut records else {
        unreachable!()
    };
    let Value::Object(row) = &mut rows[500] else {
        unreachable!()
    };
    row.insert("age".into(), Value::Number(Number::U8(99)));
    check("change.fleece", &append_delta(&bytes, &records).unwrap());

    let embedding: Vec<f32> = (0..768)
        .map(|i| ((i * 37 % 101) as f32 - 50.0) / 400.0)
        .collect();
    let query: Vec<f32> = (0..768)
        .map(|i| ((i * 53 % 97) as f32 - 48.0) / 400.0)
        .collect();
    let path: KeyPath = "embedding".parse().unwrap();
    let mut scores = Vec::new();
    let mut decoded_dot = None;
    for (name, vector) in [
        ("f32", fleece::Vector::F32(embedding.clone())),
        ("f16", fleece::Vector::quantized_f16(&embedding)),
        ("i8", fleece::Vector::quantized_i8(&embedding)),
        ("bits", fleece::Vector::quantized_bits(&embedding)),
    ] {
        let bytes = encode(&object([
            ("title", "Tintin in Tibet".into()),
            ("embedding", Value::Vector(vector)),
        ]))
        .unwrap();
        check(&format!("vector-{name}.fleece"), &bytes);
        let root = Doc::trusted(&bytes).root();
        let field = path.eval(root).unwrap().as_vector().unwrap();
        scores.push(field.dot(&query).unwrap());
        if name == "f32" {
            scores.push(field.cosine(&query).unwrap());
            let Value::Object(fields) = Value::from_ref(root).unwrap() else {
                unreachable!()
            };
            let Value::Vector(fleece::Vector::F32(values)) = &fields["embedding"] else {
                unreachable!()
            };
            decoded_dot = Some(values.iter().zip(&query).map(|(a, b)| a * b).sum::<f32>());
        }
    }
    scores.push(decoded_dot.unwrap());
    scores.push(
        embedding
            .iter()
            .zip(&query)
            .map(|(a, b)| a * b)
            .sum::<f32>(),
    );
    let bits: Vec<u8> = scores.into_iter().flat_map(f32::to_le_bytes).collect();
    check("vector-results.f32", &bits);
}

fn dictionary_inputs(records: &Value) -> (Value, Value) {
    let Value::Array(rows) = records else { unreachable!() };
    let mut addresses = Vec::new();
    let mut strings = Vec::new();
    for row in rows {
        let Value::Object(row) = row else { unreachable!() };
        let Value::Object(address) = &row["address"] else { unreachable!() };
        let Value::RecordId(id) = &row["id"] else { unreachable!() };
        let Value::Array(tags) = &row["tags"] else { unreachable!() };
        addresses.push(row["address"].clone());
        strings.extend([
            address["city"].clone(),
            address["zip"].clone(),
            Value::from(id.table.clone()),
            row["name"].clone(),
        ]);
        strings.extend_from_slice(tags);
    }
    (Value::Array(addresses), Value::Array(strings))
}

#[test]
fn encode_dict_strings() {
    let records = Value::Array((0..1000).map(record).collect());
    let (addresses, strings) = dictionary_inputs(&records);
    println!();
    for (name, value) in [
        ("fleece: encode address dictionaries", addresses),
        ("fleece: encode short string values", strings),
    ] {
        measure(name, encode(&value).unwrap().len(), || {
            encode(black_box(&value)).unwrap()
        });
    }
}

#[test]
fn close_wide_root() {
    let value = Value::Array((0..1000).map(record).collect());
    let Value::Array(records) = &value else { unreachable!() };
    let prepare = || {
        let mut encoder = fleece::Encoder::new();
        encoder.begin_array().unwrap();
        for record in records {
            encoder.write_value(record).unwrap();
        }
        encoder
    };
    let mut sample = prepare();
    sample.end_array().unwrap();
    let bytes = sample.finish().unwrap();
    assert_eq!(bytes, encode(&value).unwrap());
    assert_ne!(bytes[Doc::trusted(&bytes).root().position()] & 0x08, 0);

    const BATCHES: i32 = 64;
    const COUNT: usize = 8;
    let mut elapsed = std::time::Duration::ZERO;
    for batch in -2..BATCHES {
        let mut writers: Vec<_> = (0..COUNT).map(|_| prepare()).collect();
        let start = Instant::now();
        for writer in &mut writers {
            writer.end_array().unwrap();
        }
        if batch >= 0 {
            elapsed += start.elapsed();
        }
        for writer in writers {
            black_box(writer.finish().unwrap());
        }
    }
    let us = elapsed.as_secs_f64() * 1e6 / (BATCHES as usize * COUNT) as f64;
    println!("\nfleece: close wide root  {us:.3} µs");
}
