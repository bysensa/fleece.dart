// Built against the requested checkout of the-base by interop_test.dart.
use fleece::{
    BigDecimal, Date, Datetime, Decimal, Doc, Duration, Encoder, F16, File, Geometry, Interval,
    Number, Object, Point, Polygon, Range, RecordId, RecordIdKey, SharedKeys, Text, Time,
    Timestamp, Uuid, Value, Vector,
};
use std::{env, fs, ops::Bound, path::Path};

fn number(n: Number) -> Value {
    Value::Number(n)
}
fn fields(pairs: &[(&str, Value)]) -> Object {
    pairs
        .iter()
        .map(|(k, v)| (k.to_string(), v.clone()))
        .collect()
}

// The same abstract values are built independently in Dart.
struct Rng(u64);
impl Rng {
    fn next(&mut self, n: u64) -> u64 {
        self.0 = self.0 * 48271 % 2147483647;
        self.0 % n
    }
    fn value(&mut self, depth: usize) -> Value {
        match self.next(if depth < 4 { 14 } else { 10 }) {
            0 => Value::Null,
            1 => Value::Bool(self.next(2) == 0),
            2 => (self.next(1 << 30) as i64 - (1 << 29)).into(),
            3 => number(Number::U64(u64::MAX - self.next(1 << 30))),
            4 => (self.next(1000000) as f64 / 10.0).into(),
            5 => number(Number::F32(self.next(65536) as f32 / 8.0)),
            6 => ["", "a", "repeat", "é", "\u{feff}𐀀", "0123456789abcdef"][self.next(6) as usize]
                .into(),
            7 => Value::Bytes((0..self.next(20)).map(|_| self.next(256) as u8).collect()),
            8 => number(Number::I16(self.next(65536) as i32 as i16)),
            9 => Value::Table("repeat".into()),
            10 | 11 => Value::Array((0..self.next(6)).map(|_| self.value(depth + 1)).collect()),
            12 => Value::Set((0..self.next(5)).map(|_| self.value(depth + 1)).collect()),
            _ => Value::Object(
                (0..self.next(5))
                    .map(|i| (format!("k{i}"), self.value(depth + 1)))
                    .collect(),
            ),
        }
    }
}

fn documents() -> Vec<Value> {
    let point = Point { x: -1.5, y: 2.25 };
    let line = vec![point, Point { x: 0.0, y: -3.0 }];
    let polygon = Polygon {
        exterior: line.clone(),
        interiors: vec![vec![], line.clone()],
    };
    let geometry = Geometry::Collection(vec![
        Geometry::Point(point),
        Geometry::Line(line.clone()),
        Geometry::Polygon(polygon.clone()),
        Geometry::MultiPoint(line.clone()),
        Geometry::MultiLine(vec![line, vec![]]),
        Geometry::MultiPolygon(vec![polygon]),
        Geometry::Collection(vec![]),
    ]);
    let uuid = Uuid([0xab; 16]);
    let bound = Range {
        start: Bound::Included("A".into()),
        end: Bound::Excluded("Z".into()),
    };
    let record_key = RecordIdKey::try_from(Value::Range(Box::new(bound.clone()))).unwrap();
    let all = Value::Array(vec![
        Value::None,
        number(Number::I8(-128)),
        number(Number::U8(255)),
        number(Number::I16(-32768)),
        number(Number::U16(65535)),
        number(Number::I32(i32::MIN)),
        number(Number::U32(u32::MAX)),
        number(Number::U64(u64::MAX)),
        number(Number::F16(F16(0xfc01))),
        number(Number::Decimal(
            Decimal::new((1 << 96) - 1, 28, true).unwrap(),
        )),
        number(Number::BigDecimal(
            BigDecimal::new(&[0x01, 0x80], 294910).unwrap(),
        )),
        Value::Duration(Duration {
            secs: u64::MAX,
            nanos: 999999999,
        }),
        Value::Datetime(Datetime {
            secs: i64::MIN,
            nanos: 2,
        }),
        Value::Uuid(uuid),
        Value::Date(Date { days: i32::MIN }),
        Value::Time(Time {
            nanos: Time::MAX_NANOS,
        }),
        Value::Timestamp(Timestamp {
            secs: i64::MAX,
            nanos: 123,
        }),
        Value::Interval(Interval {
            months: -12,
            days: 3,
            micros: i64::MIN,
        }),
        Value::Table("repeat".into()),
        Value::RecordId(RecordId::new("dogs", record_key)),
        Value::File(File {
            bucket: "🐕".into(),
            key: "/a".into(),
        }),
        Value::Range(Box::new(bound)),
        Value::Regex("repeat".into()),
        Value::Set(vec![2.into(), 1.into(), 1.into()]),
        Value::Geometry(geometry),
        Value::Vector(Vector::Bits {
            bytes: vec![0xfd, 0x07],
            len: 11,
        }),
        Text::from_runs([
            ("🙂", None),
            ("é", Some(fields(&[("bold", true.into())]))),
            ("x", Some(fields(&[("bold", true.into())]))),
            ("𐀀", None),
        ])
        .into(),
    ]);
    let mut docs = vec![all];
    let mut ints = Vec::new();
    for bit in [7, 8, 11, 15, 16, 23, 24, 31, 32, 39, 40, 47, 48, 55, 56, 62] {
        let n = 1i64 << bit;
        for v in [n - 1, n, n + 1, -n - 1, -n, -n + 1] {
            ints.push(v.into());
        }
    }
    docs.push(Value::Array(ints));
    docs.push(Value::Object(fields(&[
        ("𐀀", 1.into()),
        ("\u{e000}", 2.into()),
        ("a\0", 3.into()),
        ("\u{feff}\u{feff}key", 4.into()),
        ("é", 5.into()),
        ("e\u{301}", 6.into()),
    ])));
    docs.push(Value::Array(
        [
            "x",
            "aa",
            "aa",
            "123456789012345",
            "123456789012345",
            "1234567890123456",
            "1234567890123456",
            "é",
            "é",
        ]
        .into_iter()
        .map(Value::from)
        .collect(),
    ));
    for n in [0, 1, 14, 15, 127, 128, 16383, 16384, 32762, 32763] {
        docs.push(Value::Bytes((0..n).map(|i| i as u8).collect()));
    }
    for n in [2046, 2047, 2048, 2174, 2175, 40000] {
        docs.push(Value::Array((0..n).map(|i| (i % 128).into()).collect()));
    }
    docs.push(Value::Array(
        (0..3000)
            .map(|i| format!("long string number {i}").into())
            .collect(),
    ));
    let mut rng = Rng(1203);
    docs.extend((0..1024).map(|_| rng.value(0)));
    docs
}

struct Exchange<'a> {
    input: &'a [u8],
    output: Vec<u8>,
    count: usize,
}
impl Exchange<'_> {
    // Take a document independently written by Dart and return Rust's bytes
    // separately so Dart can decode them even when a layout is noncanonical.
    fn frame(&mut self, expected: &[u8]) -> Vec<u8> {
        let (len, rest) = self.input.split_at(4);
        let (got, rest) = rest.split_at(u32::from_le_bytes(len.try_into().unwrap()) as usize);
        self.input = rest;
        let difference = got.iter().zip(expected).position(|(a, b)| a != b);
        assert!(
            got == expected,
            "document {}: lengths {}/{}, first difference {:?}",
            self.count,
            got.len(),
            expected.len(),
            difference
        );
        self.output
            .extend_from_slice(&(expected.len() as u32).to_le_bytes());
        self.output.extend_from_slice(expected);
        self.count += 1;
        got.to_vec()
    }
}

fn main() {
    assert_eq!(fleece::FORMAT_VERSION, 1);
    let dir = env::args().nth(1).unwrap();
    let dir = Path::new(&dir);
    let input = fs::read(dir.join("dart.bin")).unwrap();
    let mut ex = Exchange {
        input: &input,
        output: vec![],
        count: 0,
    };
    for value in documents() {
        let got = ex.frame(&fleece::encode(&value).unwrap());
        assert_eq!(fleece::decode(&got).unwrap(), value);
    }
    let mut floats = Vec::new();
    for bits in [
        0, 0x80000000, 1, 0x7f800000, 0xff800000, 0x7fa00001, 0xffc12345,
    ] {
        floats.push(number(Number::F32(f32::from_bits(bits))));
    }
    for bits in [
        0,
        1 << 63,
        1,
        0x7ff0000000000000,
        0xfff0000000000000,
        0x7ff8000000000000,
        0xfff8000020000000,
        0x7ff0000000000001,
        0x7ff8000000000001,
    ] {
        floats.push(f64::from_bits(bits).into());
    }
    let floats = fleece::encode(&Value::Array(floats)).unwrap();
    let got = ex.frame(&floats);
    assert_eq!(
        fleece::encode(&fleece::decode(&got).unwrap()).unwrap(),
        floats
    );

    let fields: Object = (0..32)
        .map(|i| (format!("field{i}"), format!("value {i}").into()))
        .collect();
    let mut new = fields.clone();
    new.remove("field12");
    new.insert("field4".into(), Value::Null);
    let old = Value::Object(fields);
    let new = Value::Object(new);
    let mut keys = SharedKeys::new();
    keys.encode_and_add("field4");
    let mut e = Encoder::new().with_shared_keys(&mut keys);
    e.write_value(&old).unwrap();
    let shared = ex.frame(&e.finish().unwrap());
    let state = ex.frame(&keys.to_state().unwrap());
    let restored = SharedKeys::from_state(&state).unwrap();
    let doc = Doc::trusted(&shared).with_shared_keys(&restored);
    doc.validate().unwrap();
    assert_eq!(Value::from_ref(doc.root()).unwrap(), old);
    let base = ex.frame(&fleece::encode(&old).unwrap());
    let delta = ex.frame(&fleece::delta::append_delta(&base, &new).unwrap());
    let mut e = Encoder::new().with_base(&base, true).unwrap();
    e.write_changed(Doc::new(&base).unwrap().root(), &new)
        .unwrap();
    let external = ex.frame(&e.finish().unwrap());
    let doc = Doc::trusted(&external).with_base(&base);
    doc.validate().unwrap();
    assert_eq!(Value::from_ref(doc.root()).unwrap(), new);
    let joined = [base.as_slice(), delta.as_slice()].concat();
    let compact = ex.frame(&fleece::compact(&Doc::new(&joined).unwrap()).unwrap());
    assert_eq!(fleece::decode(&compact).unwrap(), new);
    let mut patch = fleece::Patch::new();
    let added = Value::Array(vec![7.into(), "水".into()]);
    patch.set(&"field4".parse().unwrap(), &Value::Null);
    patch.remove(&"field12".parse().unwrap());
    patch.set(&"more.items".parse().unwrap(), &added);
    let edited = ex.frame(&fleece::update(&doc, &patch).unwrap());
    let edited = Doc::new(&edited).unwrap();
    ex.frame(
        &fleece::extract(&edited, &"more.items[-1]".parse().unwrap())
            .unwrap()
            .unwrap(),
    );
    let structure = fleece::delta::diff(&old, &new).unwrap();
    ex.frame(&fleece::encode(&structure).unwrap());
    ex.frame(&fleece::encode(&fleece::delta::apply(&old, &structure).unwrap()).unwrap());
    assert!(ex.input.is_empty());
    fs::write(dir.join("rust.bin"), ex.output).unwrap();

    let cases = fs::read(dir.join("checks.bin")).unwrap();
    let mut input = cases.as_slice();
    let mut results = Vec::new();
    while !input.is_empty() {
        let (n, rest) = input.split_at(4);
        let (bytes, rest) = rest.split_at(u32::from_le_bytes(n.try_into().unwrap()) as usize);
        input = rest;
        let (canonical, compacted) = match fleece::decode(bytes) {
            Ok(value) => (
                fleece::encode(&value).unwrap(),
                fleece::compact(&Doc::new(bytes).unwrap()).unwrap(),
            ),
            Err(_) => (Vec::new(), Vec::new()),
        };
        let trusted = Value::from_ref(Doc::trusted(bytes).root())
            .ok()
            .and_then(|v| fleece::encode(&v).ok())
            .unwrap_or_default();
        let mut copy = Encoder::new();
        let copied = copy
            .write_copy(Doc::trusted(bytes).root())
            .and_then(|_| copy.finish())
            .unwrap_or_default();
        let validation = Doc::new(bytes)
            .err()
            .map(|e| format!("{e:?}"))
            .unwrap_or_default();
        for bytes in [
            canonical,
            compacted,
            trusted,
            copied,
            validation.into_bytes(),
        ] {
            results.extend_from_slice(&(bytes.len() as u32).to_le_bytes());
            results.extend_from_slice(&bytes);
        }
    }
    fs::write(dir.join("checked.bin"), results).unwrap();
}
