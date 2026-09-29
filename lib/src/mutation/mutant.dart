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
    this.ignored = false,
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

  /// Whether a `// mutate4dart: ignore` pragma covers this mutant, so it
  /// is not run.
  final bool ignored;

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
  relationalBoundary(
    'relational_boundary',
    'Assert the result for the boundary value itself, where `<` and `<=` '
        '(or `>` and `>=`) differ.',
  ),

  /// `==` ↔ `!=`.
  equality(
    'equality',
    'Add a case where the compared values are equal and one where they '
        'differ, and assert the outcome of each.',
  ),

  /// `&&` ↔ `||`.
  logical(
    'logical',
    'Cover an input where exactly one operand is true; `&&` and `||` '
        'agree on every other input.',
  ),

  /// `+` ↔ `-`, `*` ↔ `/`, `%` → `*`, `~/` → `*`.
  arithmetic(
    'arithmetic',
    'Assert the computed value with operands where the swapped operator '
        'gives a different result (avoid 0, 1 and 2).',
  ),

  /// `+=` ↔ `-=`, `*=` ↔ `/=`, `??=` → `=`.
  assignment(
    'assignment',
    'Assert the value after the update; for `??=`, update a variable that '
        'already has a value and check it is kept.',
  ),

  /// `++` ↔ `--` (prefix and postfix).
  increment('increment', 'Assert the counter after the step.'),

  /// `true` ↔ `false`.
  booleanLiteral(
    'boolean_literal',
    'Assert the boolean this branch returns or stores.',
  ),

  /// `!x` → `x`.
  removeNot(
    'remove_not',
    'Add a case where the negated expression is true and one where it is '
        'false, and assert the outcome of each.',
  ),

  /// `if (c)` / `while (c)` / `c ? a : b` → `!(c)`.
  negateCondition(
    'negate_condition',
    'Cover both outcomes of this condition and assert what each one does.',
  ),

  /// `a ?? b` → `b` (the fallback is always used).
  nullCoalescing(
    'null_coalescing',
    'Test with a non-null left operand whose value differs from the '
        'fallback, and assert that value is used.',
  ),

  /// A call statement whose result is discarded is removed:
  /// `save(x);` → nothing. Tests that never check the side effect miss it.
  removeCall(
    'remove_call',
    'Assert the side effect of this call: the resulting state, an '
        'interaction on a mock or an emitted event.',
  ),

  /// `isEmpty` ↔ `isNotEmpty`, `first` ↔ `last`, `any` ↔ `every`.
  collection(
    'collection',
    'Test with an empty and a non-empty collection, or one whose first '
        'and last elements differ, and assert the result.',
  );

  const MutationOperator(this.id, this.hint);

  /// Stable id used in reports and `--operators`.
  final String id;

  /// One sentence on what a test needs to detect this mutation.
  final String hint;

  /// The operator with [id], or `null`.
  static MutationOperator? byId(String id) {
    for (final operator in values) {
      if (operator.id == id) return operator;
    }
    return null;
  }
}
