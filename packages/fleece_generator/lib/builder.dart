import 'dart:convert' show jsonEncode;

import 'package:analyzer/dart/analysis/utilities.dart' show parseString;
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

Builder fleeceModelBuilder(BuilderOptions options) => PartBuilder(
  [_Generator(_Naming(options.config))],
  '.fleece.g.dart',
  options: options,
);

const _model = TypeChecker.typeNamedLiterally(
  'FleeceModel',
  inPackage: 'fleece',
);
const _key = TypeChecker.typeNamedLiterally('FleeceKey', inPackage: 'fleece');
const _native = TypeChecker.typeNamedLiterally(
  'FleeceValue',
  inPackage: 'fleece',
);
const _float32 = TypeChecker.typeNamedLiterally(
  'FleeceFloat32',
  inPackage: 'fleece',
);
const _float64 = TypeChecker.typeNamedLiterally(
  'FleeceFloat64',
  inPackage: 'fleece',
);

// Stable across packages whose builders use different naming options.
String _format(String model) => '\$${model}FleeceFormat';
String _boundType(String model) => '\$${model}Fleece';

class _Naming {
  _Naming(Map<String, dynamic> config)
    : template = _option(config, 'class_name', '{name}Document'),
      stripPrefix = _option(config, 'strip_prefix', ''),
      stripSuffix = _option(config, 'strip_suffix', '') {
    if ('{name}'.allMatches(template).length != 1) {
      throw ArgumentError('class_name must contain exactly one {name}.');
    }
  }

  final String template;
  final String stripPrefix;
  final String stripSuffix;

  static String _option(
    Map<String, dynamic> config,
    String key,
    String fallback,
  ) {
    if (!config.containsKey(key)) return fallback;
    final value = config[key];
    if (value is String) return value;
    throw ArgumentError('$key must be a string.');
  }

  String forModel(InterfaceElement model) {
    final override = _model
        .firstAnnotationOfExact(model)
        ?.getField('name')
        ?.toStringValue();
    var stem = model.displayName;
    if (stripPrefix.isNotEmpty && stem.startsWith(stripPrefix)) {
      stem = stem.substring(stripPrefix.length);
    }
    if (stripSuffix.isNotEmpty && stem.endsWith(stripSuffix)) {
      stem = stem.substring(0, stem.length - stripSuffix.length);
    }
    final name = override ?? template.replaceAll('{name}', stem);
    if (!RegExp(r'^[a-zA-Z$][a-zA-Z0-9_$]*$').hasMatch(name) ||
        parseString(
          content: 'class $name {}',
          throwIfDiagnostics: false,
        ).errors.isNotEmpty) {
      _reject(
        model,
        '"$name" is not a valid public Dart class name. Check class_name or @FleeceModel(name: ...).',
      );
    }
    return name;
  }
}

bool _nullable(DartType t) =>
    t is DynamicType || t.nullabilitySuffix == NullabilitySuffix.question;
// Quote a literal in the generated Dart source, including Dart interpolation.
String _literal(String key) => jsonEncode(key).replaceAll(r'$', r'\$');

Never _reject(Element e, String reason) =>
    throw InvalidGenerationSourceError(reason, element: e);

String _prefix(LibraryElement lib, Element target) {
  if (target.library == lib) return '';
  for (final import in lib.firstFragment.libraryImports) {
    final name = import.prefix?.element.name;
    final prefix = name == null ? '' : '$name.';
    if (import.namespace.get2(prefix + target.displayName) == target)
      return prefix;
  }
  return _reject(
    target,
    'Import the library exposing ${target.displayName} in the model library.',
  );
}

class _Generator extends Generator {
  const _Generator(this.naming);
  final _Naming naming;

  @override
  String generate(LibraryReader library, BuildStep buildStep) {
    final out = StringBuffer();
    final names = {
      for (final element in library.element.children)
        if (!(element.firstFragment.libraryFragment?.source.uri.path.endsWith(
              '.fleece.g.dart',
            ) ??
            false))
          element.displayName,
    };
    for (final annotation in library.annotatedWith(_model)) {
      final cls = annotation.element;
      if (cls is! ClassElement || cls.typeParameters.isNotEmpty) {
        _reject(cls, '@FleeceModel requires a non-generic class.');
      }
      final ctor = cls.unnamedConstructor;
      if (ctor == null || cls.isAbstract && !ctor.isFactory) {
        _reject(
          cls,
          'Provide an unnamed constructor that can construct ${cls.displayName}.',
        );
      }
      final prefix = _prefix(
        library.element,
        annotation.annotation.objectValue.type!.element!,
      );
      final generated = naming.forModel(cls);
      for (final id in [
        generated,
        '${generated}Operations',
        _format(cls.displayName),
        _boundType(cls.displayName),
      ]) {
        if (!names.add(id)) {
          _reject(
            cls,
            'Generated name "$id" is already in use. Choose class_name or @FleeceModel(name: ...) for ${cls.displayName}.',
          );
        }
      }
      final emitter = _ModelEmitter(
        library.element,
        cls,
        prefix,
        naming,
        generated,
      );
      out.writeln(emitter.generate(ctor));
    }
    return out.toString();
  }
}

class _Field {
  _Field(this.param, this.key);
  final FormalParameterElement param;
  final String key;
  String get name => param.displayName;
}

class _ModelEmitter {
  _ModelEmitter(this.lib, this.cls, this.api, this.naming, this.generated);
  final LibraryElement lib;
  final ClassElement cls;
  final String api;
  final _Naming naming;
  final String generated;
  late final bytesType = sdkType(
    'Uint8List',
    'dart:typed_data',
    r'$FleeceBytes',
  );
  late final resultType = sdkType('FutureOr', 'dart:async', r'$FleeceResult');

  String sdkType(String name, String uri, String fallback) {
    for (final import in lib.firstFragment.libraryImports) {
      final id = import.prefix?.element.name;
      final spelling = id == null ? name : '$id.$name';
      if (import.namespace.get2(spelling)?.library?.uri.toString() == uri &&
          (id != null || lib.getClass(name) == null))
        return spelling;
    }
    return api + fallback;
  }

  String boundType(InterfaceElement model) => model.library == lib
      ? naming.forModel(model)
      : _prefix(lib, model) + _boundType(model.displayName);

  // In a document, model-valued elements use their generated subtype even
  // under List or Map. The setter still accepts the original model type.
  ({String type, String read})? binding(
    DartType type,
    String cursor, [
    int depth = 0,
  ]) {
    if (type is! InterfaceType) return null;
    final nullable = _nullable(type);
    final suffix = nullable ? '?' : '';
    if (_model.hasAnnotationOfExact(type.element)) {
      final format =
          _prefix(lib, type.element) + _format(type.element.displayName);
      final method = nullable ? 'optionalObject' : 'object';
      return (
        type: boundType(type.element) + suffix,
        read: '$cursor.$method($format.codec.bind)',
      );
    }
    if (!type.isDartCoreList && !type.isDartCoreMap) return null;
    final item = 'item$depth';
    final nested = binding(type.typeArguments.last, item, depth + 1);
    if (nested == null) return null;
    final prefix = _prefix(lib, type.element);
    final collection = type.isDartCoreList
        ? '${prefix}List<${nested.type}>'
        : '${prefix}Map<${prefix}String, ${nested.type}>';
    final method = type.isDartCoreList ? 'listItems' : 'mapItems';
    final read = '$cursor.$method<${nested.type}>(($item) => ${nested.read})';
    return (
      type: collection + suffix,
      read: nullable ? '$cursor.hasValue ? $read : null' : read,
    );
  }

  Iterable<FieldElement> storedFields(InterfaceElement owner) sync* {
    yield* owner.fields;
    for (final mixin in owner.mixins) {
      yield* mixin.element.fields;
    }
    final parent = owner.supertype;
    if (parent != null) yield* storedFields(parent.element);
  }

  // The generated part is outside the class that declared the constructor.
  // Preserve class constants in interpolation and collection literals too.
  void collectDefaultConstants(
    AstNode expression,
    Set<FieldElement> constants,
  ) {
    if (expression is SimpleIdentifier && !expression.isQualified) {
      final getter = expression.element;
      final field = getter is GetterElement ? getter.variable : null;
      if (field is FieldElement &&
          field.isConst &&
          field.enclosingElement == cls) {
        constants.add(field);
      }
    }
    for (final child in expression.childEntities.whereType<AstNode>()) {
      collectDefaultConstants(child, constants);
    }
  }

  String typeName(DartType type, Element field) {
    if (type is DynamicType) return 'dynamic';
    if (type is! InterfaceType) _reject(field, 'Unsupported field type $type.');
    final arguments = type.typeArguments;
    final args = arguments.isEmpty
        ? ''
        : '<${arguments.map((t) => typeName(t, field)).join(', ')}>';
    return _prefix(lib, type.element) +
        type.element.displayName +
        args +
        (_nullable(type) ? '?' : '');
  }

  String codec(DartType type, Element field) {
    if (type is DynamicType || type.isDartCoreObject && _nullable(type)) {
      return '${api}FleeceCodecs.value';
    }
    if (type is! InterfaceType) _reject(field, 'Unsupported field type $type.');
    final element = type.element, name = element.displayName;
    final codecs = '${api}FleeceCodecs';
    final String code;
    if (type.isDartCoreList) {
      code = '$codecs.list(${codec(type.typeArguments.single, field)})';
    } else if (type.isDartCoreMap) {
      final key = type.typeArguments.first;
      if (!key.isDartCoreString || _nullable(key)) {
        _reject(field, 'Fleece dictionary keys must have type String.');
      }
      code = '$codecs.map(${codec(type.typeArguments.last, field)})';
    } else if (element.library.isDartCore) {
      final member = const {
        'String': 'string',
        'bool': 'boolean',
        'int': 'integer',
        'double': 'floating',
        'BigInt': 'bigInteger',
        'DateTime': 'dateTime',
        'Object': 'object',
        'num': 'number',
      }[name];
      if (member == null)
        _reject(field, 'Unsupported Fleece field type $type.');
      code = '$codecs.$member';
    } else if (element.library.uri.toString() == 'dart:typed_data' &&
        name == 'Uint8List') {
      code = '$codecs.bytes';
    } else if (_model.hasAnnotationOfExact(element)) {
      code = '${_prefix(lib, element)}${_format(name)}.codec';
    } else if (element is EnumElement) {
      code = '$codecs.enumeration(${_prefix(lib, element)}$name.values)';
    } else if (_float32.isExactly(element)) {
      code = '$codecs.float32';
    } else if (_float64.isExactly(element)) {
      code = '$codecs.float64';
    } else if (_native.isAssignableFromType(type)) {
      code = '$codecs.native<${_prefix(lib, element)}$name>()';
    } else {
      _reject(
        field,
        'Unsupported Fleece field type $type. Annotate a nested model with @FleeceModel().',
      );
    }
    return _nullable(type) ? '$code.nullable()' : code;
  }

  String generate(ConstructorElement ctor) {
    final name = cls.displayName, fields = <_Field>[], keys = <String>{};
    final schema = '_${name}Fields', format = _format(name);
    for (final p in ctor.formalParameters) {
      final getter = cls.thisType.lookUpGetter(p.displayName, lib);
      if (p.isPrivate ||
          getter == null ||
          !lib.typeSystem.isSubtypeOf(getter.returnType, p.type)) {
        _reject(
          p,
          'Constructor parameter ${p.displayName} needs a public getter of the same type.',
        );
      }
      final rename =
          _key.firstAnnotationOfExact(getter.variable) ??
          _key.firstAnnotationOfExact(getter) ??
          _key.firstAnnotationOfExact(p);
      final key = rename?.getField('name')?.toStringValue() ?? p.displayName;
      if (!keys.add(key)) _reject(p, 'Duplicate Fleece key $key.');
      fields.add(_Field(p, key));
    }
    for (final field in storedFields(cls)) {
      if (!field.isPrivate &&
          !field.isStatic &&
          !field.isOriginGetterSetter &&
          !fields.any((f) => f.name == field.displayName)) {
        _reject(
          field,
          'Include stored field ${field.displayName} in the unnamed constructor.',
        );
      }
    }

    final out = StringBuffer()
      ..writeln('typedef ${_boundType(name)} = $generated;')
      ..writeln('extension $format on $name {')
      ..writeln(
        'static final codec = ${api}FleeceModelCodec<$name, $generated>(_write$name, _read$name, $generated._);',
      )
      ..writeln('$bytesType toFleece({${api}SharedKeys? sharedKeys}) {')
      ..writeln('final model = this;')
      ..writeln(
        'return model is $generated ? model._\$fleeceCursor.toBytes(sharedKeys: sharedKeys) : codec.encode(model, sharedKeys: sharedKeys); } }',
      )
      ..writeln('abstract final class $schema {');
    final constants = <FieldElement>{};
    for (final field in fields) {
      final expression = field.param.constantInitializer;
      if (expression != null) collectDefaultConstants(expression, constants);
    }
    for (final constant in constants) {
      final id = constant.displayName;
      out.writeln('static const $id = $name.$id;');
    }
    for (final f in fields) {
      final type = f.param.type, t = typeName(type, f.param);
      final defaultCode = f.param.defaultValueCode;
      // An optional argument preserves Dart's constant context for defaults.
      final fallback = defaultCode != null
          ? '([$t value = $defaultCode]) => value'
          : _nullable(type)
          ? '() => null'
          : null;
      out.writeln(
        'static final ${f.name} = ${api}FleeceField<$t>('
        '${_literal(f.key)}, ${codec(type, f.param)}'
        '${fallback == null ? '' : ', whenMissing: $fallback'});',
      );
    }
    out
      ..writeln('}')
      ..writeln('void _write$name(${api}Encoder e, $name value) {')
      ..writeln(
        'if (value is $generated) { value._\$fleeceCursor.writeTo(e); return; }',
      )
      ..writeln('e.beginDict();');
    final sorted = [...fields]..sort((a, b) => _compareNames(a.key, b.key));
    for (final f in sorted) {
      out.writeln('$schema.${f.name}.write(e, value.${f.name});');
    }
    out
      ..writeln('e.endDict(); }')
      ..writeln('$name _read$name(${api}ValueRef ref) {')
      ..writeln(
        '${fields.isEmpty ? '' : 'final dict = '}${api}FleeceCodecs.dictionary(ref);',
      )
      ..writeln('return $name(');
    for (final f in fields) {
      out.writeln(
        '${f.param.isNamed ? '${f.name}: ' : ''}$schema.${f.name}.read(dict[${_literal(f.key)}]),',
      );
    }
    out.writeln('); }');
    writeModel(out, fields, ctor, schema, format);
    return out.toString();
  }

  void writeModel(
    StringBuffer out,
    List<_Field> fields,
    ConstructorElement ctor,
    String schema,
    String format,
  ) {
    final name = cls.displayName;
    final properties = {for (final f in fields) f.name};
    final owners = [
      cls,
      ...cls.allSupertypes
          .where((s) => !s.isDartCoreObject)
          .map((s) => s.element),
    ];
    // Inherit business methods and computed properties from the model itself.
    // A pure data interface can be bound without running a DTO constructor.
    final inherit = owners.any(
      (c) =>
          c.methods.any((m) => !m.isStatic) ||
          c.getters.any(
            (g) => !g.isStatic && !properties.contains(g.displayName),
          ) ||
          c.setters.any(
            (s) => !s.isStatic && !properties.contains(s.variable.displayName),
          ),
    );
    ConstructorElement? superCtor;
    var arguments = ctor.formalParameters;
    if (inherit) {
      var target = ctor;
      final seen = <ConstructorElement>{};
      while (target.isFactory &&
          target.redirectedConstructor != null &&
          seen.add(target)) {
        target = target.redirectedConstructor!;
      }
      final parent = target.enclosingElement;
      if (target.isGenerative &&
          target.isAccessibleIn(lib) &&
          (parent.library == lib ||
              parent is ClassElement &&
                  !parent.isPrivate &&
                  parent.isExtendableOutside)) {
        superCtor = target;
      } else {
        superCtor = cls.constructors
            .where((c) => c.isGenerative && c.formalParameters.isEmpty)
            .firstOrNull;
        if (superCtor == null) {
          _reject(
            cls,
            'To inherit the domain methods of $name, provide a generative constructor or a redirecting factory with an accessible implementation.',
          );
        }
        arguments = const [];
      }
    }
    const cursor = r'_$fleeceCursor';
    out
      ..writeln(
        'final class $generated ${superCtor == null ? 'implements $name' : 'extends ${typeName(superCtor.returnType, cls)}'} {',
      )
      ..writeln(
        'factory $generated($bytesType bytes, { $bytesType? base, ${api}SharedKeys? sharedKeys, ${api}FleeceTracking Function()? tracking }) =>',
      )
      ..writeln(
        '$format.codec.open(bytes, base: base, sharedKeys: sharedKeys, tracking: tracking);',
      )
      ..writeln('final ${api}FleeceCursor $cursor;');
    if (superCtor == null) {
      out.writeln('$generated._(this.$cursor);');
    } else {
      final suffix = superCtor.name == 'new' ? '' : '.${superCtor.name}';
      out.writeln('$generated._(this.$cursor) : super$suffix(');
      for (final p in arguments) {
        final n = p.displayName;
        out.writeln('${p.isNamed ? '$n: ' : ''}$cursor.initial($schema.$n),');
      }
      out.writeln(');');
    }
    for (final f in fields) {
      final type = f.param.type, t = typeName(type, f.param), n = f.name;
      final child = '_\$${n}Cursor';
      final nested = binding(type, child);
      if (nested != null) {
        out.writeln('late final $child = $cursor.child($schema.$n);');
        out.writeln('@override ${nested.type} get $n => ${nested.read};');
      } else {
        out.writeln('@override $t get $n => $cursor.get($schema.$n);');
      }
      out.writeln('set $n($t value) => $cursor.set($schema.$n, value);');
    }
    out
      ..writeln('}')
      ..writeln('extension ${generated}Operations on $generated {')
      ..writeln('$name toModel() => $cursor.read($format.codec);')
      ..writeln(
        '$resultType<R> transaction<R>($resultType<R> Function($generated) edit) => $cursor.transaction<$generated, R>($format.codec.bind, edit);',
      )
      ..writeln(
        '$generated beginTransaction() => $cursor.beginTransaction($format.codec.bind);',
      )
      ..writeln('void commit() => $cursor.commit();')
      ..writeln('void rollback() => $cursor.rollback();')
      ..writeln('bool get isActive => $cursor.isActive;')
      ..writeln('$bytesType? get sharedKeyState => $cursor.sharedKeyState;')
      ..writeln('void dispose() => $cursor.dispose(); }');
  }
}

// Unicode scalar order agrees with the byte order of valid UTF-8 keys.
int _compareNames(String a, String b) {
  final left = a.runes.iterator, right = b.runes.iterator;
  while (left.moveNext()) {
    if (!right.moveNext()) return 1;
    final order = left.current.compareTo(right.current);
    if (order != 0) return order;
  }
  return right.moveNext() ? -1 : 0;
}
