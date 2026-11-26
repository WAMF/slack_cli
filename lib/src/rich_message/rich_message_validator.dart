import 'dart:convert';

import 'package:dart_slack/src/rich_message/rich_message_schema.g.dart';

/// A card file that breaks the shared RichMessage schema.
///
/// [field] is the JSON path of the first field that breaks it, for example
/// `links[1].url`. The message has the same form as the backend validator
/// (`RichMessage.<field>: <problem>`), so an agent reads one error format
/// whichever side refused the card.
class RichMessageValidationError implements Exception {
  /// Creates a [RichMessageValidationError].
  const new(this.field, this.problem);

  /// The JSON path of the field that breaks the schema.
  final String field;

  /// What is wrong with [field].
  final String problem;

  /// The error as one line.
  String get message => 'RichMessage.$field: $problem';

  @override
  String toString() => message;
}

/// The decoded shared schema.
///
/// The limits live in the schema and nowhere else. [validateRichMessage]
/// reads them from here, so a sync of the schema changes them too.
final Map<String, dynamic> richMessageSchema =
    jsonDecode(richMessageSchemaJson) as Map<String, dynamic>;

/// Checks [value] against the shared RichMessage schema.
///
/// Returns [value] as a map when it is valid. Throws a
/// [RichMessageValidationError] that names the first field that breaks the
/// schema. The order of the checks is the same as in the backend validator
/// (`rich_message/types.ts`), so both name the same field for the same
/// input.
Map<String, dynamic> validateRichMessage(Object? value) {
  _check(richMessageSchema, value, '');
  return value! as Map<String, dynamic>;
}

/// Refuses a card that needs a click to come back.
///
/// Phase 1 cards are static. `actions` and `choice` are valid in the schema,
/// but nothing receives the click yet, so a card that holds them is refused
/// instead of being drawn without its buttons.
void assertStaticRichMessage(Map<String, dynamic> message) {
  const problem =
      'needs interactivity, which phase 1 does not support; use links instead';
  final actions = message['actions'];
  if (actions is List && actions.isNotEmpty) {
    throw const RichMessageValidationError('actions', problem);
  }
  if (message.containsKey('choice')) {
    throw const RichMessageValidationError('choice', problem);
  }
}

/// The name of the JSON type of [value], as the backend validator gives it.
String _describe(Object? value) => switch (value) {
  null => 'null',
  List<dynamic>() => 'array',
  Map<dynamic, dynamic>() => 'object',
  String() => 'string',
  num() => 'number',
  bool() => 'boolean',
  _ => value.runtimeType.toString(),
};

void _check(Map<String, dynamic> node, Object? value, String path) {
  final values = node['enum'];
  if (values is List) return _checkEnum(values.cast<String>(), value, path);
  switch (node['type']) {
    case 'string':
      return _checkString(node, value, path);
    case 'array':
      return _checkArray(node, value, path);
    case 'object':
      return _checkObject(node, value, path);
  }
}

void _checkEnum(List<String> values, Object? value, String path) {
  if (value is! String || !values.contains(value)) {
    throw RichMessageValidationError(
      path,
      'must be one of ${values.join(', ')}',
    );
  }
}

void _checkString(Map<String, dynamic> node, Object? value, String path) {
  if (value is! String) {
    throw RichMessageValidationError(
      path,
      'must be a string, got ${_describe(value)}',
    );
  }
  // JSON Schema `maxLength` counts Unicode code points, not UTF-16 units.
  final length = value.runes.length;
  final minLength = node['minLength'] as int?;
  final maxLength = node['maxLength'] as int?;
  final pattern = node['pattern'] as String?;
  if (minLength != null && length < minLength) {
    throw RichMessageValidationError(path, 'must not be empty');
  }
  if (maxLength != null && length > maxLength) {
    throw RichMessageValidationError(
      path,
      'is $length characters; the maximum is $maxLength',
    );
  }
  if (pattern != null && !RegExp(pattern).hasMatch(value)) {
    throw RichMessageValidationError(path, 'must match $pattern');
  }
}

void _checkArray(Map<String, dynamic> node, Object? value, String path) {
  if (value is! List) {
    throw RichMessageValidationError(
      path,
      'must be an array, got ${_describe(value)}',
    );
  }
  final minItems = node['minItems'] as int?;
  final maxItems = node['maxItems'] as int?;
  if (minItems != null && value.length < minItems) {
    throw RichMessageValidationError(path, 'needs at least $minItems item(s)');
  }
  if (maxItems != null && value.length > maxItems) {
    throw RichMessageValidationError(
      path,
      'has ${value.length} items; the maximum is $maxItems',
    );
  }
  final items = node['items'] as Map<String, dynamic>?;
  if (items == null) return;
  for (var index = 0; index < value.length; index++) {
    _check(items, value[index], '$path[$index]');
  }
}

void _checkObject(Map<String, dynamic> node, Object? value, String path) {
  if (value is! Map<String, dynamic>) {
    throw RichMessageValidationError(
      path.isEmpty ? '(root)' : path,
      'must be an object, got ${_describe(value)}',
    );
  }
  final properties = (node['properties'] as Map<String, dynamic>?) ?? const {};
  String at(String key) => path.isEmpty ? key : '$path.$key';
  for (final key
      in (node['required'] as List?)?.cast<String>() ?? const <String>[]) {
    if (!value.containsKey(key)) {
      throw RichMessageValidationError(at(key), 'is required');
    }
  }
  for (final MapEntry<String, dynamic>(:key, value: child) in value.entries) {
    final childNode = properties[key] as Map<String, dynamic>?;
    if (childNode != null) {
      _check(childNode, child, at(key));
    } else if (node['additionalProperties'] == false) {
      throw RichMessageValidationError(at(key), 'is not a RichMessage field');
    }
  }
}
