/// A single source change that a good test suite should detect.
class Mutant {
  /// Creates a [Mutant].
  const Mutant({
    required this.file,
    required this.line,
    required this.offset,
    required this.length,
    required this.replacement,
    required this.operator,
  });

  /// Project-relative path of the mutated file.
  final String file;

  /// 1-based line of the change.
  final int line;

  /// Character offset of the replaced source range.
  final int offset;

  /// Length of the replaced source range.
  final int length;

  /// Source text that replaces the range.
  final String replacement;

  /// Id of the operator that produced this mutant (see [MutationOperator]).
  final String operator;

  /// Applies this mutant to [source], the unmutated content of [file].
  String apply(String source) =>
      source.replaceRange(offset, offset + length, replacement);

  /// The replaced source text within [source].
  String original(String source) => source.substring(offset, offset + length);

  @override
  String toString() => '$file:$line [$operator] -> $replacement';
}

/// The mutation operators mutate4dart applies.
enum MutationOperator {
  /// `<` ↔ `<=`, `>` ↔ `>=`: off-by-one boundaries.
  relationalBoundary('relational_boundary'),

  /// `==` ↔ `!=`.
  equality('equality'),

  /// `&&` ↔ `||`.
  logical('logical'),

  /// `+` ↔ `-`, `*` ↔ `/`, `%` → `*`, `~/` → `*`.
  arithmetic('arithmetic'),

  /// `+=` ↔ `-=`, `*=` ↔ `/=`.
  assignment('assignment'),

  /// `++` ↔ `--` (prefix and postfix).
  increment('increment'),

  /// `true` ↔ `false`.
  booleanLiteral('boolean_literal'),

  /// `!x` → `x`.
  removeNot('remove_not'),

  /// `if (c)` / `while (c)` / `c ? a : b` → `!(c)`.
  negateCondition('negate_condition'),

  /// `a ?? b` → `b` (the fallback is always used).
  nullCoalescing('null_coalescing'),

  /// A call statement whose result is discarded is removed:
  /// `save(x);` → nothing. Tests that never check the side effect miss it.
  removeCall('remove_call');

  const MutationOperator(this.id);

  /// Stable id used in reports and `--operators`.
  final String id;
}
