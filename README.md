# fleece.dart

Бинарный формат Fleece на чистом Dart. Пакет читает и записывает стандартные значения Fleece и все 27 расширений из `bysensa/the-base`. Версия формата — 1. Байтовый эталон зафиксирован на коммите `1be207f`. [Исходная реализация на Rust](https://github.com/bysensa/the-base/tree/1be207fdffd8f20d714ab8083b37442934cf77fb/crates/fleece)

## Запись и чтение

```dart
import 'package:fleece/fleece.dart';

void main() {
  final bytes = encode({
    'name': 'Милу',
    'visits': FleeceInt.u8(7),
    'tags': ['dog', 'dog'],
  });

  final doc = Doc(bytes);
  print(doc.root.asDict!['name']!.asString); // Милу
  print(doc.root.asDict!['tags']!.asArray![1].asString); // dog

  final fields = decode(bytes) as Map<String, Object?>;
  print((fields['visits'] as FleeceInt).value); // 7
}
```

`encode` записывает поля `Map<String, Object?>` в порядке байтов UTF-8, как `fleece::encode` записывает Rust `BTreeMap`. Для воспроизведения последовательности вызовов Rust `Encoder` используйте Dart `Encoder` и передавайте ключи в той же последовательности. От этого зависят расположение строк в документе и байты указателей.

| Значение | Представление в Dart |
| --- | --- |
| Null, bool, строка, массив, словарь | `null`, `bool`, `String`, `List`, `Map<String, Object?>` |
| Бинарные данные | `Uint8List` |
| Стандартные числа | `int` или `BigInt` для i64, `double` для f64, `FleeceFloat32` для f32 |
| Типизированные числа | `FleeceInt.i8` … `FleeceInt.u64`, `FleeceFloat16.fromBits`, `FleeceDecimal`, `FleeceBigDecimal` |
| Время с наносекундами | `FleeceDuration`, `FleeceDatetime`, `FleeceTimestamp`, `FleeceDate`, `FleeceTime`, `FleeceInterval` |
| Идентификаторы и составные значения | `FleeceNone`, `FleeceUuid`, `FleeceTable`, `FleeceRecordId`, `FleeceFile`, `FleeceRange`, `FleeceRegex`, `FleeceSet` |
| Геометрия, векторы, текст с атрибутами | `FleeceGeometry`, `FleeceVector`, `FleeceText` |

Для полного диапазона u64 используйте, например, `FleeceInt.u64(BigInt.parse('18446744073709551615'))`. При компиляции в JavaScript число `1.0` совпадает с Dart `int` по типу во время выполнения. `FleeceFloat64(1.0)` явно задаёт f64 на любой платформе. Конструкторы `fromBits` сохраняют точное представление IEEE 754.

`Doc(bytes)` проверяет достижимые значения, границы слотов, указатели, UTF-8 и типы расширений. После проверки можно читать отдельные элементы по индексу и искать ключи двоичным поиском. `doc.root.read()` строит самостоятельное значение за один обход и по мере чтения проверяет глубину, число раскрытых значений и суммарный размер строк и двоичных данных. `decode(bytes)` возвращает самостоятельную копию значения. `Doc.trusted(bytes)` даёт доступ к заранее проверенному буферу. Пока используются ссылки из `Doc`, буфер должен сохранять своё содержимое.

## Общие ключи и дельты

`SharedKeys` присваивает ключам номера. Передайте одну таблицу в `encode(value, sharedKeys: keys)` и `decode(bytes, sharedKeys: keys)`. Её состояние хранится как отдельный Fleece-документ через `keys.toState()` и `SharedKeys.fromState(bytes)`.

`appendDelta(base, value)` возвращает байты, которые можно дописать к базе и читать как единый документ. Для раздельного хранения вызовите `appendDelta(base, value, external: true)` и откройте результат через `Doc(delta, base: base)`. `compact(doc)` собирает актуальные значения в самостоятельный документ.

Для редактирования по пути используйте `Patch`. Отрицательный индекс отсчитывается от конца массива. Новые промежуточные словари создаются при записи. `extract` возвращает выбранное значение как отдельный документ.

```dart
final doc = Doc(encode({'tags': ['dog'], 'visits': 41}));
final patch = Patch()
  ..set(KeyPath.parse('visits'), 42)
  ..set(KeyPath.parse('tags[1]'), 'white');
final changed = Doc(update(doc, patch));
final last = extract(changed, KeyPath.parse('tags[-1]'));
print(decode(last!)); // white
```

`diff(old, next)` строит структурную дельту. При равных значениях результат — `null`. Для замены значения на `null` функция возвращает `FleeceDelta(null)`. `apply(old, delta)` принимает объект дельты или его поле `.value` после передачи через Fleece или типизированный JSON. `doc.liveBytes` считает достижимые байты, а `dump(doc)` показывает значения и адреса указателей.

## Типы, индексы и адаптеры

| Задача | API |
| --- | --- |
| Ключ индекса в порядке SurrealDB | `encodeKey(value)`, `encodeKeyInto(value, bytesBuilder)` |
| Проверка типа поля | `Kind.conforms(valueRef)`, `Kind.conformsWith(valueRef, named)`, `KindLiteral` |
| Обмен типизированным JSON | `jsonToFleece(text)`, `fleeceToJson(bytes)`; для дерева JSON — `toJson` и `fromJson` |
| Чтение векторов из документа | `ref.asVector`, `prefix`, `dot`, `cosine`, `l2Squared`, `hamming` |
| Текст с атрибутами | `FleeceText.fromRuns`, `FleeceText.withMarks`, `ref.asText`, `marks`, `runs`. Смещения и длины заданы в байтах UTF-8 |
| Геометрия | `geometryFromGeo`, `geometry.toGeo()`, `ref.asGeometry`, `ref.asGeo`. Последний возвращает геометрию пакета `geobase` |
| Прикладные типы | `FleeceAdapter<T>`, `toVec`, `toEncoder`, `fromSlice`, `fromRef`; `FleeceVariant` задаёт варианты перечислений с данными |
| Ссылки на исходный буфер | `ValueRef.asData`, `ValueRef.asUtf8`, `SerdeReader.bytes`, `SerdeReader.utf8Bytes`. Геттер `asString` декодирует строку в Dart |

Аналог Rust `#[derive(Serialize, Deserialize)]` в этом пакете — явный адаптер с двумя функциями. Порядок полей, возвращаемых первой функцией, соответствует порядку полей Rust-структуры.

```dart
typedef Dog = ({String name, int age});

final dogs = FleeceAdapter<Dog>(
  (dog) => {'name': dog.name, 'age': dog.age},
  (r) => (name: r['name'].string, age: r['age'].integer(bits: 8, signed: false).toInt()),
);
final bytes = toVec((name: 'Milou', age: 9), adapter: dogs);
final dog = fromSlice(bytes, dogs);
```

Все функции экспортируются из `package:fleece/fleece.dart`. Для отдельных модулей доступны `package:fleece/delta.dart`, `key.dart`, `json.dart`, `geo.dart` и `serde.dart`.

## Командная строка

```sh
dart run fleece encode < old.json > old.fleece
dart run fleece decode < old.fleece
dart run fleece dump < old.fleece
dart run fleece diff old.json new.json > delta.json
dart run fleece apply old.json delta.json
dart run fleece append old.fleece new.json > delta.fleece
cat old.fleece delta.fleece | dart run fleece compact > new.fleece
```

## Проверка совместимости

```sh
dart pub get
dart analyze
dart test --run-skipped
dart test -p node --run-skipped
```

В пакет входят побайтовые примеры Fleece и всех расширений, а также фиксированные данные, полученные из Rust. Они проверяются на Dart VM и в Node.js. Флаг `--run-skipped` включает измерение стоимости наследуемых словарей, пропускаемое по умолчанию в исходном наборе.

Межъязыковой тест запускает `rustc`, независимо строит документы на двух языках, сравнивает байты и читает результаты в обе стороны. Он автоматически находит соседний `../the-base/crates/fleece`. Для другой структуры каталогов задайте `FLEECE_REFERENCE`. Опциональная переменная `FLEECE_REFERENCE_CLI` включает прямое сравнение stdout всех семи команд.

```sh
FLEECE_REFERENCE=/path/to/the-base/crates/fleece dart test test/interop_test.dart
FLEECE_REFERENCE_CLI=/path/to/target/debug/examples/fleece dart test test/cli_test.dart
```

Соответствие исходным тестам и команды обновления эталонных данных перечислены в [описании тестов](test/README.md).

## Производительность

Бенчмарк сравнивает Dart AOT и Rust на одинаковых документах. Он охватывает 32 операции, включая кодирование, чтение по пути, обновления, векторные операции и геометрию. Режим `--wide-root` дополнительно измеряет запись четырёхбайтовых слотов корневого массива. Отдельный набор измеряет запись и чтение всех 27 расширений и базовых типов. [CPU-профиль и замеры `encode()`](benchmark/wide-slots.md) · [Замеры чтения](benchmark/io.md) · [Бенчмарк Rust и команды запуска](benchmark/README.md)
