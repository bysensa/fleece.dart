# Соответствие тестам Rust

Эталонная ревизия содержит 14 модульных тестов, 87 интеграционных и 7 исполняемых примеров документации. В Dart некоторые проверки разбиты по типам и способам чтения. [Исходный набор](https://github.com/bysensa/the-base/tree/1be207fdffd8f20d714ab8083b37442934cf77fb/crates/fleece)

| Набор Rust | Число | Проверки в Dart |
| --- | ---: | --- |
| `src/format.rs`, `src/value.rs`, `src/json.rs` | 10 | [Минимальные целые и varint, f16, decimal, bigdecimal, UUID, base64, даты и типизированный JSON](json_values_test.dart) |
| `src/key.rs`, `src/keypath.rs`, `src/delta.rs` | 4 | [Ключи чисел](properties_test.dart), [разбор путей](storage_test.dart), [строковые дельты](json_values_test.dart) |
| `tests/format.rs` | 14 | [Байты Couchbase, потоковая запись и чтение](format_test.dart), [наследование, расширения, ошибки, максимальная глубина, широкие указатели, произвольные входные данные](document_test.dart) |
| `tests/golden.rs` | 7 | [Фиксированные байты скаляров, коллекций и расширений](format_test.dart), [версия формата](json_values_test.dart) |
| `tests/geo.rs` | 6 | [Преобразования, кольца, геометрические алгоритмы и повторное использование буферов](geo_test.dart) |
| `tests/limits.rs` | 7 | [Бюджеты значений и байтов, serde, ограничения наследования, совпадение числовых и текстовых ключей и измерение времени](limits_test.dart) |
| `tests/properties.rs` | 11 | [Генераторы значений, атрибутов, обновлений и повреждённых документов, дельты, shared keys и JSON](properties_test.dart) |
| `tests/reference.rs` | 8 | [Порядок типов, бесконечностей, строк байтов и списков](properties_test.dart), [сравнение чисел, half, rust_decimal и num_bigint](reference_test.dart) |
| `tests/serde.rs` | 7 | [Структура Dog, варианты enum, числовые ключи, заимствованные поля, несовместимые типы и shared keys](serde_test.dart), [байты Rust serde](reference_test.dart) |
| `tests/storage.rs` | 7 | [Обновление и извлечение по путям, откат ключей, простые и составные Kind](storage_test.dart) |
| `tests/surreal.rs` | 3 | [Байты чисел и порядок значений, таблиц и записей в surrealdb-types](reference_test.dart) |
| `tests/text.rs` | 10 | [Операции с текстом, UTF-8, наборы атрибутов, повреждённые метки, ключи и JSON](text_test.dart) |
| `tests/vectors.rs` | 7 | [Буферы, расстояния, префиксы и сохранение порядка ближайших векторов](vector_test.dart), [преобразования f16 и f32 по библиотеке half](reference_test.dart) |
| Документация `lib`, `encoder`, `compact`, `update`, `geo`, `serde` | 7 | [Исполняемые примеры публичного API](examples_test.dart) |

## Эталонные данные

[Генератор](reference/generate.py) собирает crate с его `Cargo.lock` и включает стратегии из исходных тестов. Для проверки порядка он вызывает `surrealdb-types`, для представления чисел — `half`, `rust_decimal` и `num_bigint`. Фиксированный seed делает результат воспроизводимым. Данные для всех пяти fuzz-сценариев (`read`, `json`, `delta`, `update`, `shared`) взяты из `examples/fuzz_seeds.rs`. Их прогоняет обычный `dart test`. [Эталонные данные](reference/cases.json)

```sh
python3 test/reference/generate.py ../the-base/crates/fleece
dart test test/reference_test.dart
dart test -p node test/reference_test.dart
```

[Межъязыковой тест](interop_test.dart) дополнительно собирает Rust-кодек через `rustc`, обменивается двоичными буферами и сравнивает побайтово обычную запись, общие ключи, внутренние и внешние дельты, обновление, извлечение, структурные дельты и компактацию. Для повреждённых и нестандартно закодированных документов он сравнивает результаты валидации, чтения и копирования в обеих реализациях.

[Тест CLI](cli_test.dart) выполняет все семь команд в отдельных процессах. Для независимого сравнения можно указать исполняемый файл Rust, собранный с `cargo build --locked -p fleece --all-features --example fleece`, в переменной `FLEECE_REFERENCE_CLI`.

## Обмен с Couchbase

Команда ниже запускает также оригинальные `tools/reference/documents.py` и `deltas.py` с Dart CLI. Она проверяет взаимное чтение 307 документов, применение дельт на 400 парах и 200 документов с шестью последовательными добавлениями и финальной компактацией. Для сборки версии Couchbase, закреплённой в исходном `build.sh`, требуются Git, CMake и компилятор C++. Аргумент `--tools DIR` позволяет использовать уже собранные `fleece/build/fleeceTool` и `delta`.

```sh
python3 test/reference/couchbase.py ../the-base/crates/fleece
```

Флаг `--rust-cli /path/to/target/debug/examples/fleece` прогоняет те же 307 документов через обе реализации и требует совпадения каждого байта при взаимном чтении.
