// The generator compiles this alongside the upstream integration-test sources.
#[path = "up_properties.rs"]
mod properties;
#[path = "up_reference.rs"]
mod reference;
#[path = "up_seeds.rs"]
mod seeds;
#[path = "up_surreal.rs"]
mod surreal;

#[path = "up_serde.rs"]
mod dog;
use fleece::{Doc, Value, encode, json::fleece_to_json, key::encode_key};
use proptest::{
    strategy::{Strategy, ValueTree},
    test_runner::TestRunner,
};
use serde_json::{Value as Json, json};

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}
fn sample<S: Strategy>(s: &S, r: &mut TestRunner) -> S::Value {
    s.new_tree(r).unwrap().current()
}
fn wire(v: &Value) -> String {
    hex(&encode(v).unwrap())
}

fn checksum(bytes: impl Iterator<Item = u8>) -> u32 {
    let (mut a, mut b) = (1, 0);
    for x in bytes {
        a = (a + u32::from(x)) % 65521;
        b = (b + a) % 65521;
    }
    b * 65536 + a
}

fn main() {
    let mut r = TestRunner::deterministic();
    let (values, numbers, surreal) = (
        properties::value(),
        reference::finite_number(),
        surreal::value(),
    );
    let mut rows = Vec::<Json>::new();
    for _ in 0..256 {
        let v = sample(&values, &mut r);
        let data = encode(&v).unwrap();
        let doc = Doc::new(&data).unwrap();
        rows.push(json!([
            "value",
            hex(&data),
            fleece_to_json(&data).unwrap(),
            hex(&encode_key(&v)),
            doc.live_bytes(),
            fleece::dump(&doc)
        ]));
        let (a, b) = (sample(&numbers, &mut r), sample(&numbers, &mut r));
        rows.push(json!([
            "number",
            wire(&Value::Number(a.clone())),
            wire(&Value::Number(b.clone())),
            reference::compare(&a, &b) as i8
        ]));
        let (a, b) = (sample(&surreal, &mut r), sample(&surreal, &mut r));
        rows.push(json!([
            "surreal",
            wire(&a),
            wire(&b),
            surreal::to_surreal(&a).cmp(&surreal::to_surreal(&b)) as i8
        ]));
        let text = sample(&"-?[0-9]{1,40}(\\.[0-9]{1,20})?", &mut r);
        let decimal: surrealdb_types::BigDecimal = text.parse().unwrap();
        let mut key = vec![];
        decimal.encode_ordered(&mut key);
        rows.push(json!(["ordered", text, hex(&key)]));
        let mantissa = sample(&(0..1u128 << 96), &mut r);
        let scale = sample(&(0..=28u32), &mut r);
        let negative = sample(&proptest::bool::ANY, &mut r);
        let mut d = rust_decimal::Decimal::from_i128_with_scale(mantissa as i128, scale);
        d.set_sign_negative(negative);
        rows.push(json!(["decimal", d.to_string(), hex(&d.serialize())]));
        let bytes = sample(
            &proptest::collection::vec(proptest::num::u8::ANY, 0..80),
            &mut r,
        );
        let n = num_bigint::BigInt::from_signed_bytes_le(&bytes);
        rows.push(json!([
            "bigint",
            hex(&bytes),
            n.to_string(),
            hex(&n.to_signed_bytes_le()),
            scale
        ]));
        let bits = sample(&proptest::num::u64::ANY, &mut r);
        let d = f64::from_bits(bits);
        let h = half::f16::from_f64(d);
        rows.push(json!([
            "half",
            format!("{bits:016x}"),
            if d.is_nan() {
                Some(0x7e00)
            } else if h.to_f64().to_bits() == bits {
                Some(h.to_bits())
            } else {
                None
            }
        ]));
    }
    for table in ["a", "ba", "c"] {
        for of in ["a", "ba", "c"] {
            for k in [-3i64, 0, 2] {
                let a = Value::Table(table.into());
                let b = Value::RecordId(fleece::RecordId::new(of, k));
                let order = surreal::to_surreal(&a).cmp(&surreal::to_surreal(&b));
                rows.push(json!([
                    "table",
                    table,
                    of,
                    k,
                    if order.is_eq() { -1 } else { order as i8 }
                ]));
            }
        }
    }
    rows.push(json!(["dog", hex(&dog::dog_bytes())]));
    for v in seeds::values() {
        let data = encode(&v).unwrap();
        let mut keys = fleece::SharedKeys::new();
        let mut writer = fleece::Encoder::new().with_shared_keys(&mut keys);
        writer.write_value(&v).unwrap();
        let shared = writer.finish().unwrap();
        rows.push(json!([
            "seed",
            hex(&data),
            fleece_to_json(&data).unwrap(),
            hex(&keys.to_state().unwrap()),
            hex(&shared)
        ]));
    }
    let f32s = checksum(
        (0..=u16::MAX).flat_map(|b| half::f16::from_bits(b).to_f32().to_bits().to_le_bytes()),
    );
    let halfs = checksum((0..=u32::MAX).step_by(4099).flat_map(|b| {
        half::f16::from_f32(f32::from_bits(b))
            .to_bits()
            .to_le_bytes()
    }));
    rows.push(json!(["half_sweep", f32s, halfs]));
    // Each line is a case, so changes to a pinned reference are reviewable.
    println!(
        "[\n{}\n]",
        rows.iter()
            .map(Json::to_string)
            .collect::<Vec<_>>()
            .join(",\n")
    );
}
