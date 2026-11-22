import 'dart:convert' show jsonEncode;

import 'package:analyzer/dart/analysis/utilities.dart' show parseString;
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
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
const _useCodec = TypeChecker.typeNamedLiterally(
  'FleeceUseCodec',
  inPackage: 'fleece',
);
const _codecType = TypeChecker.typeNamedLiterally(
  'FleeceCodec',
  inPackage: 'fleece',
);
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
      if (cls is! ClassElement) {
        _reject(cls, '@FleeceModel requires a Dart class.');
      }
      final selected = annotation.annotation.peek('constructor')?.stringValue;
      final ctor = selected == null || selected.isEmpty || selected == 'new'
          ? cls.unnamedConstructor
          : cls.getNamedConstructor(selected);
      if (ctor == null || cls.isAbstract && !ctor.isFactory) {
        _reject(
          cls,
          'Provide a constructor that can construct ${cls.displayName}. '
          'Select a named constructor with @FleeceModel(constructor: ...).',
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
        '_${cls.displayName}Fields',
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
  _Field(this.param, this.key, this.custom);
  final FormalParameterElement param;
  final String key;
  final _CustomCodec? custom;
  String get name => param.displayName;
  String get slot => 'field\$$name';
}

class _CustomCodec {
  _CustomCodec(this.type, this.valueType);
  final InterfaceType type;
  final DartType valueType;

  bool accepts(DartType fieldType, LibraryElement lib) =>
      valueType == fieldType ||
      valueType == lib.typeSystem.promoteToNonNull(fieldType);
}

class _ModelEmitter {
  _ModelEmitter(this.lib, this.cls, this.api, this.naming, this.generated);
  final LibraryElement lib;
  final ClassElement cls;
  final String api;
  final _Naming naming;
  final String generated;
  // Construct compound and custom codecs once per concrete model schema.
  // Lazy fields also allow self-referential and mutually recursive models.
  final _codecs = <String, String>{};
  String cached(String expression) => expression.contains('(')
      ? _codecs.putIfAbsent(expression, () => '_codec\$${_codecs.length}')
      : expression;
  String get _args => _angles(cls.typeParameters.map((p) => p.displayName));
  String get _decl => _angles(
    cls.typeParameters.map(
      (p) => p.bound == null
          ? p.displayName
          : '${p.displayName} extends ${typeName(p.bound!, p)}',
    ),
  );
  String get _codecParams => cls.typeParameters
      .map(
        (p) =>
            'required ${api}FleeceCodec<${p.displayName}> codec${p.displayName}, ',
      )
      .join();
  String get _codecArgs => cls.typeParameters
      .map((p) => 'codec${p.displayName}: codec${p.displayName}, ')
      .join();
  List<String> get _codecNames => [
    for (final p in cls.typeParameters) 'codec${p.displayName}',
  ];

  Iterable<String> codecParameters(DartType type, _Field field) sync* {
    if (field.custom?.accepts(type, lib) ?? false) return;
    if (type is TypeParameterType) {
      yield 'codec${type.element.displayName}';
    } else if (type is InterfaceType) {
      for (final arg in type.typeArguments) {
        yield* codecParameters(arg, field);
      }
    }
  }

  static String _angles(Iterable<String> args) =>
      args.isEmpty ? '' : '<${args.join(', ')}>';
  String _formatCodec(String format) =>
      _args.isEmpty ? '$format.codec' : '$format.codec$_args($_codecArgs)';
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
    String cursor,
    _Field field, [
    int depth = 0,
  ]) {
    if (field.custom?.accepts(type, lib) ?? false) return null;
    if (type is TypeParameterType) {
      return (
        type: typeName(type, field.param),
        read: '${codec(type, field)}.bindValue($cursor)',
      );
    }
    if (type is! InterfaceType) return null;
    final nullable = _nullable(type);
    final suffix = nullable ? '?' : '';
    if (_model.hasAnnotationOfExact(type.element)) {
      final method = nullable ? 'optionalObject' : 'object';
      return (
        type:
            boundType(type.element) +
            _angles(type.typeArguments.map((t) => typeName(t, field.param))) +
            suffix,
        read: '$cursor.$method(${modelCodec(type, field)}.bind)',
      );
    }
    if (!type.isDartCoreList && !type.isDartCoreMap) return null;
    final item = 'item$depth';
    final elementType = type.typeArguments.last;
    final input = typeName(elementType, field.param);
    final nested = binding(elementType, item, field, depth + 1);
    final output = nested?.type ?? input;
    final args = '<$input, $output>';
    final collection =
        api + (type.isDartCoreList ? 'FleeceList' : 'FleeceMap') + args;
    final method = type.isDartCoreList ? 'list' : 'map';
    final bind = nested == null ? '' : ', ($item) => ${nested.read}';
    final read = '$cursor.$method$args(${codec(elementType, field)}$bind)';
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

  String? defaultCode(FormalParameterElement param) {
    final code = param.defaultValueCode;
    if (code == null ||
        param is! SuperFormalParameterElement ||
        param.constantInitializer != null)
      return code;
    // Source text from the superclass can reference private constants and
    // import prefixes that have completely different meanings in this part.
    final value = param.computeConstantValue();
    if (value == null)
      _reject(param, 'Declare an explicit default for ${param.displayName}.');
    return inheritedConstant(value, param);
  }

  String inheritedConstant(DartObject value, FormalParameterElement param) {
    String emit(DartObject value) => inheritedConstant(value, param);
    if (value.isNull) return 'null';
    if (value.toStringValue() case final string?) return _literal(string);
    if (value.toIntValue() case final number?) return number.toString();
    if (value.toBoolValue() case final flag?) return flag.toString();
    if (value.toDoubleValue() case final number?) {
      if (number.isNaN) return 'double.nan';
      if (number.isInfinite)
        return number.isNegative
            ? 'double.negativeInfinity'
            : 'double.infinity';
      return number.toString();
    }
    final type = value.type;
    if (type is InterfaceType) {
      final args = _angles(type.typeArguments.map((t) => typeName(t, param)));
      if (value.toListValue() case final items?)
        return 'const $args[${items.map(emit).join(', ')}]';
      if (value.toMapValue() case final map?) {
        final pairs = map.entries.map(
          (e) =>
              '${e.key == null ? 'null' : emit(e.key!)}: ${e.value == null ? 'null' : emit(e.value!)}',
        );
        return 'const $args{${pairs.join(', ')}}';
      }
      if (value.toSetValue() case final set?)
        return 'const $args{${set.map(emit).join(', ')}}';
      if (type.element case final EnumElement enumeration) {
        for (final constant in enumeration.constants) {
          if (constant.computeConstantValue() == value) {
            return '${typeName(type, param)}.${constant.displayName}';
          }
        }
      }
      final call = value.constructorInvocation;
      if (call != null &&
          call.constructor.isAccessibleIn(lib) &&
          call.constructor.enclosingElement.isAccessibleIn(lib)) {
        final owner = typeName(
          type.asInstanceOf(call.constructor.enclosingElement) ??
              call.constructor.returnType,
          param,
        );
        final name = call.constructor.name;
        final parameters = [
          ...call.positionalArguments.map(emit),
          for (final entry in call.namedArguments.entries)
            '${entry.key}: ${emit(entry.value)}',
        ];
        return "const $owner${name == 'new' ? '' : '.$name'}(${parameters.join(', ')})";
      }
    }
    return _reject(
      param,
      'Declare an explicit default for ${param.displayName} that is accessible in this library.',
    );
  }

  String typeName(DartType type, Element field) {
    if (type is DynamicType) return 'dynamic';
    if (type is NeverType) return _nullable(type) ? 'Never?' : 'Never';
    if (type is TypeParameterType)
      return type.element.displayName + (_nullable(type) ? '?' : '');
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

  String modelCodec(InterfaceType type, _Field f) {
    final element = type.element;
    final format =
        '${_prefix(lib, element)}${_format(element.displayName)}.codec';
    if (type.typeArguments.isEmpty) return format;
    final args = _angles(type.typeArguments.map((t) => typeName(t, f.param)));
    final codecs = [
      for (var i = 0; i < type.typeArguments.length; i++)
        'codec${element.typeParameters[i].displayName}: ${codec(type.typeArguments[i], f)}',
    ];
    return cached('$format$args(${codecs.join(', ')})');
  }

  String codec(DartType type, _Field f) => cached(_codec(type, f));

  String _codec(DartType type, _Field f) {
    final field = f.param;
    final custom = f.custom;
    if (custom != null && custom.accepts(type, lib)) {
      final code = '${typeName(custom.type, field)}()';
      return _nullable(type) && !_nullable(custom.valueType)
          ? '$code.nullable()'
          : code;
    }
    if (type is TypeParameterType) {
      final code = 'codec${type.element.displayName}';
      return _nullable(type) ? '$code.nullable()' : code;
    }
    if (type is DynamicType || type.isDartCoreObject && _nullable(type)) {
      return '${api}FleeceCodecs.value';
    }
    if (type is! InterfaceType) _reject(field, 'Unsupported field type $type.');
    final element = type.element, name = element.displayName;
    final codecs = '${api}FleeceCodecs';
    final String code;
    if (type.isDartCoreList) {
      code = '$codecs.list(${codec(type.typeArguments.single, f)})';
    } else if (type.isDartCoreMap) {
      final key = type.typeArguments.first;
      if (!key.isDartCoreString || _nullable(key)) {
        _reject(field, 'Fleece dictionary keys must have type String.');
      }
      code = '$codecs.map(${codec(type.typeArguments.last, f)})';
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
      code = modelCodec(type, f);
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

  _CustomCodec? customCodec(FormalParameterElement p, GetterElement getter) {
    final annotation =
        _useCodec.firstAnnotationOfExact(getter.variable) ??
        _useCodec.firstAnnotationOfExact(getter) ??
        _useCodec.firstAnnotationOfExact(p);
    if (annotation == null) return null;
    final type = annotation.getField('type')?.toTypeValue();
    if (type is! InterfaceType || type.element is! ClassElement) {
      _reject(p, '@FleeceUseCodec requires a concrete FleeceCodec class.');
    }
    final cls = type.element as ClassElement;
    final ctor = cls.unnamedConstructor;
    final base = type.allSupertypes
        .where((t) => _codecType.isExactly(t.element))
        .firstOrNull;
    if (base == null ||
        ctor == null ||
        !ctor.isAccessibleIn(lib) ||
        cls.isAbstract && !ctor.isFactory ||
        ctor.formalParameters.any((p) => p.isRequired)) {
      _reject(
        p,
        'Provide a FleeceCodec with an accessible zero-argument constructor.',
      );
    }
    final codec = _CustomCodec(type, base.typeArguments.single);
    var at = p.type;
    while (!codec.accepts(at, lib)) {
      if (at is! InterfaceType || !at.isDartCoreList && !at.isDartCoreMap) {
        _reject(
          p,
          '${cls.displayName} encodes ${codec.valueType}, which does not match ${p.type}.',
        );
      }
      at = at.typeArguments.last;
    }
    return codec;
  }

  String generate(ConstructorElement ctor) {
    final name = cls.displayName, fields = <_Field>[], keys = <String>{};
    final schema = '_${name}Fields', format = _format(name);
    for (final p in ctor.formalParameters) {
      final getter = cls.thisType.lookUpGetter(p.displayName, lib);
      if (p.isPrivate || getter == null || getter.returnType != p.type) {
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
      fields.add(_Field(p, key, customCodec(p, getter)));
    }
    for (final field in storedFields(cls)) {
      if (!field.isPrivate &&
          !field.isStatic &&
          !field.isOriginGetterSetter &&
          !fields.any((f) => f.name == field.displayName)) {
        _reject(
          field,
          'Include stored field ${field.displayName} in the selected constructor.',
        );
      }
    }

    final modelType = '$name$_args', bound = '$generated$_args';
    final codecType = '${api}FleeceModelCodec<$modelType, $bound>';
    final out = StringBuffer()
      ..writeln('typedef ${_boundType(name)}$_decl = $bound;')
      ..writeln('extension $format$_decl on $modelType {');
    if (_args.isEmpty) {
      out.writeln('static final codec = $schema().modelCodec;');
    } else {
      out.writeln(
        'static $codecType codec$_decl({$_codecParams}) => $schema$_args($_codecArgs).modelCodec;',
      );
    }
    final sameCodecs = _args.isEmpty
        ? ''
        : ' && model._\$fleeceFields._uses(${_codecNames.join(', ')})';
    out
      ..writeln(
        '$bytesType toFleece({$_codecParams ${api}SharedKeys? sharedKeys}) {',
      )
      ..writeln('final model = this;')
      ..writeln(
        'return model is $bound$sameCodecs ? model._\$fleeceCursor.toBytes(sharedKeys: sharedKeys) : ${_formatCodec(format)}.encode(model, sharedKeys: sharedKeys); } }',
      )
      ..writeln('final class $schema$_decl {');
    if (_args.isNotEmpty) {
      for (final p in cls.typeParameters) {
        out.writeln(
          'final ${api}FleeceCodec<${p.displayName}> codec${p.displayName};',
        );
      }
      final init = cls.typeParameters
          .map((p) => 'required this.codec${p.displayName}')
          .join(', ');
      out.writeln('$schema({$init});');
      final params = cls.typeParameters
          .map(
            (p) => '${api}FleeceCodec<${p.displayName}> other${p.displayName}',
          )
          .join(', ');
      final same = cls.typeParameters
          .map((p) => 'identical(codec${p.displayName}, other${p.displayName})')
          .join(' && ');
      out.writeln('bool _uses($params) => $same;');
    }
    out.writeln(
      'late final modelCodec = $codecType(_write, _read, (cursor) => $bound._(cursor, this));',
    );
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
      final defaultValue = defaultCode(f.param);
      // An optional argument preserves Dart's constant context for defaults.
      final fallback = defaultValue != null
          ? '([$t value = $defaultValue]) => value'
          : _nullable(type)
          ? '() => null'
          : null;
      out.writeln(
        'late final ${f.slot} = ${api}FleeceField<$t>('
        '${_literal(f.key)}, ${codec(type, f)}'
        '${fallback == null ? '' : ', whenMissing: $fallback'});',
      );
      final nested = binding(type, 'cursor', f);
      if (nested != null) {
        out.writeln(
          '${nested.type} bind\$${f.name}(${api}FleeceCursor cursor) => ${nested.read};',
        );
      }
    }
    out.writeln('void _write(${api}Encoder e, $modelType value) {');
    out.writeln('if (value is $bound) {');
    final affected = {
      for (final field in fields)
        field: codecParameters(field.param.type, field).toSet(),
    }..removeWhere((_, params) => params.isEmpty);
    if (affected.isNotEmpty) {
      out.writeln('final source = value._\$fleeceFields;');
      out.writeln('if (!source._uses(${_codecNames.join(', ')})) {');
      out.writeln(
        'value._\$fleeceCursor.writeTo(e, writeField: (key) { switch (key) {',
      );
      for (final entry in affected.entries) {
        final field = entry.key;
        final differs = entry.value
            .map((n) => '!identical($n, source.$n)')
            .join(' || ');
        final guard = entry.value.length == _codecNames.length
            ? ''
            : ' when $differs';
        out.writeln('case ${_literal(field.key)}$guard:');
        out.writeln(
          '${field.slot}.codec.write(e, value.${field.name}); return true;',
        );
      }
      out.writeln('default: return false; } }); return; }');
    }
    out.writeln('value._\$fleeceCursor.writeTo(e); return; }');
    out.writeln('e.beginDict();');
    final sorted = [...fields]..sort((a, b) => _compareNames(a.key, b.key));
    for (final f in sorted) {
      out.writeln('${f.slot}.write(e, value.${f.name});');
    }
    out
      ..writeln('e.endDict(); }')
      ..writeln('$modelType _read(${api}ValueRef ref) {')
      ..writeln(
        '${fields.isEmpty ? '' : 'final dict = '}${api}FleeceCodecs.dictionary(ref);',
      )
      ..writeln(
        'return $modelType${ctor.name == 'new' ? '' : '.${ctor.name}'}(',
      );
    for (final f in fields) {
      out.writeln(
        '${f.param.isNamed ? '${f.name}: ' : ''}${f.slot}.read(dict[${_literal(f.key)}]),',
      );
    }
    out.writeln('); }');
    for (final entry in _codecs.entries) {
      out.writeln('late final ${entry.value} = ${entry.key};');
    }
    out.writeln('}');
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
    const cursor = r'_$fleeceCursor', fieldsVar = r'_$fleeceFields';
    final modelType = '$name$_args', bound = '$generated$_args';
    final formatCodec = _formatCodec(format);
    out
      ..writeln(
        'final class $generated$_decl ${superCtor == null ? 'implements $modelType' : 'extends ${typeName(superCtor.returnType, cls)}'} {',
      )
      ..writeln(
        'factory $generated($bytesType bytes, { $_codecParams $bytesType? base, ${api}SharedKeys? sharedKeys, ${api}FleeceTracking Function()? tracking }) =>',
      )
      ..writeln(
        '$formatCodec.open(bytes, base: base, sharedKeys: sharedKeys, tracking: tracking);',
      )
      ..writeln('final $schema$_args $fieldsVar;')
      ..writeln('final ${api}FleeceCursor $cursor;');
    if (cls.thisType.lookUpGetter('codec', lib) == null &&
        cls.thisType.lookUpMethod('codec', lib) == null &&
        cls.thisType.lookUpSetter('codec', lib) == null) {
      out.writeln(
        _args.isEmpty
            ? 'static final codec = $formatCodec;'
            : 'static ${api}FleeceModelCodec<$modelType, $bound> codec$_decl({$_codecParams}) => $formatCodec;',
      );
    }
    if (superCtor == null) {
      out.writeln('$generated._(this.$cursor, this.$fieldsVar);');
    } else {
      final suffix = superCtor.name == 'new' ? '' : '.${superCtor.name}';
      out.writeln(
        '$generated._(this.$cursor, this.$fieldsVar) : super$suffix(',
      );
      for (final p in arguments) {
        final n = p.displayName;
        out.writeln(
          '${p.isNamed ? '$n: ' : ''}$cursor.initial($fieldsVar.field\$$n),',
        );
      }
      out.writeln(');');
    }
    for (final f in fields) {
      final type = f.param.type, t = typeName(type, f.param), n = f.name;
      final child = '_\$${n}Cursor';
      final nested = binding(type, child, f);
      if (nested != null) {
        out.writeln('late final $child = $cursor.child($fieldsVar.${f.slot});');
        out.writeln(
          '@override ${nested.type} get $n => $fieldsVar.bind\$$n($child);',
        );
      } else {
        out.writeln(
          '@override $t get $n => $cursor.get($fieldsVar.${f.slot});',
        );
      }
      final setter = cls.thisType.lookUpSetter(n, lib);
      if (setter?.isOriginDeclaration == true) {
        out.writeln(
          'set $n($t value) => $cursor.applySetter<$modelType>($fieldsVar.modelCodec, (model) => model.$n = value);',
        );
      } else {
        out.writeln(
          'set $n($t value) => $cursor.set($fieldsVar.${f.slot}, value);',
        );
      }
    }
    out
      ..writeln('}')
      ..writeln('extension ${generated}Operations$_decl on $bound {')
      ..writeln('$modelType toModel() => $cursor.read($fieldsVar.modelCodec);');
    if (_args.isNotEmpty) {
      final overrides = cls.typeParameters
          .map(
            (p) =>
                '${api}FleeceCodec<${p.displayName}>? codec${p.displayName}, ',
          )
          .join();
      final codecs = _codecNames.map((n) => '$n: $n ?? $fieldsVar.$n, ').join();
      out.writeln(
        '$bytesType toFleece({$overrides ${api}SharedKeys? sharedKeys}) => $format$_args(this).toFleece(${codecs}sharedKeys: sharedKeys);',
      );
    }
    // A domain type parameter can itself be called R.
    var result = 'R';
    while (cls.typeParameters.any((p) => p.displayName == result)) {
      result = '${result}Result';
    }
    out
      ..writeln(
        '$resultType<$result> transaction<$result>($resultType<$result> Function($bound) edit) => $cursor.transaction<$bound, $result>($fieldsVar.modelCodec.bind, edit);',
      )
      ..writeln(
        '$bound beginTransaction() => $cursor.beginTransaction($fieldsVar.modelCodec.bind);',
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
