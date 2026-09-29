import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:crap4dart/crap4dart.dart';

import 'mutant.dart';

const Map<String, String> _binarySwaps = {
  '<': '<=',
  '<=': '<',
  '>': '>=',
  '>=': '>',
  '==': '!=',
  '!=': '==',
  '&&': '||',
  '||': '&&',
  '+': '-',
  '-': '+',
  '*': '/',
  '/': '*',
  '%': '*',
  '~/': '*',
};

const Map<String, MutationOperator> _binaryOperators = {
  '<': MutationOperator.relationalBoundary,
  '<=': MutationOperator.relationalBoundary,
  '>': MutationOperator.relationalBoundary,
  '>=': MutationOperator.relationalBoundary,
  '==': MutationOperator.equality,
  '!=': MutationOperator.equality,
  '&&': MutationOperator.logical,
  '||': MutationOperator.logical,
  '+': MutationOperator.arithmetic,
  '-': MutationOperator.arithmetic,
  '*': MutationOperator.arithmetic,
  '/': MutationOperator.arithmetic,
  '%': MutationOperator.arithmetic,
  '~/': MutationOperator.arithmetic,
};

const Map<String, String> _assignmentSwaps = {
  '+=': '-=',
  '-=': '+=',
  '*=': '/=',
  '/=': '*=',
  '??=': '=',
};

/// Member names swapped by the `collection` operator; each pair has the
/// same type, so the mutant always compiles.
const Map<String, String> _collectionSwaps = {
  'isEmpty': 'isNotEmpty',
  'isNotEmpty': 'isEmpty',
  'first': 'last',
  'last': 'first',
  'any': 'every',
  'every': 'any',
};

/// Finds the mutants of a Dart source file by walking its syntax tree.
///
/// Only code that runs is mutated: annotations and `assert`s are skipped,
/// and `+` is left alone when an operand is a string literal (string
/// concatenation has no `-`). Mutants are returned in source order.
class MutantFinder {
  /// Creates a [MutantFinder] applying [operators] (default: all).
  const MutantFinder({this.operators});

  /// Operators to apply, or `null` for every [MutationOperator].
  final Set<MutationOperator>? operators;

  /// Finds the mutants of [source], reported against [file] (a
  /// project-relative path). Throws a [DartParseException] when the
  /// source does not parse.
  List<Mutant> find(String source, {required String file}) {
    final parsed = DartParser().parse(content: source, path: file);
    final visitor = _MutantVisitor(
      source,
      file,
      parsed.lineInfo,
      operators ?? MutationOperator.values.toSet(),
      _IgnorePragmas.scan(parsed.unit, parsed.lineInfo, source),
    );
    parsed.unit.accept(visitor);
    return visitor.mutants..sort((a, b) => a.offset.compareTo(b.offset));
  }
}

/// The lines silenced by `// mutate4dart: ignore [operator ids]`
/// comments. A trailing comment covers its own line; a comment alone on a
/// line covers the next line. Without ids every operator is ignored.
class _IgnorePragmas {
  _IgnorePragmas._(this._byLine);

  /// Ignored operator ids per line; an empty set means every operator.
  final Map<int, Set<String>> _byLine;

  static const String _prefix = 'mutate4dart:';

  /// Collects the pragmas from the comment tokens of [unit].
  static _IgnorePragmas scan(
    CompilationUnit unit,
    LineInfo lineInfo,
    String source,
  ) {
    final byLine = <int, Set<String>>{};
    for (Token? token = unit.beginToken;
        token != null;
        token = token.type == TokenType.EOF ? null : token.next) {
      for (Token? c = token.precedingComments; c != null; c = c.next) {
        final ids = _parse(c.lexeme);
        if (ids == null) continue;
        final target = _targetLine(c, lineInfo, source);
        byLine[target] = _merge(byLine[target], ids);
      }
    }
    return _IgnorePragmas._(byLine);
  }

  /// The line a pragma [comment] covers: its own when code precedes it,
  /// otherwise the next one.
  static int _targetLine(Token comment, LineInfo lineInfo, String source) {
    final line = lineInfo.getLocation(comment.offset).lineNumber;
    final lineStart = lineInfo.getOffsetOfLine(line - 1);
    final alone = source.substring(lineStart, comment.offset).trim().isEmpty;
    return alone ? line + 1 : line;
  }

  /// Two pragmas on one line: an empty set (every operator) wins.
  static Set<String> _merge(Set<String>? existing, Set<String> ids) {
    if (existing == null) return ids;
    if (existing.isEmpty || ids.isEmpty) return {};
    return {...existing, ...ids};
  }

  /// The operator ids of an ignore pragma, empty for all, or `null` when
  /// [comment] is not one.
  static Set<String>? _parse(String comment) {
    var text = comment.trim();
    while (text.startsWith('/')) {
      text = text.substring(1);
    }
    text = text.trim();
    if (!text.startsWith(_prefix)) return null;
    final words =
        text.substring(_prefix.length).trim().split(RegExp(r'[,\s]+'));
    if (words.first != 'ignore') return null;
    return {
      for (final id in words.skip(1))
        if (id.isNotEmpty) id
    };
  }

  /// Whether the pragma on [line] covers [operator].
  bool covers(int line, MutationOperator operator) {
    final ids = _byLine[line];
    return ids != null && (ids.isEmpty || ids.contains(operator.id));
  }
}

class _MutantVisitor extends RecursiveAstVisitor<void> {
  _MutantVisitor(
    this.source,
    this.file,
    this.lineInfo,
    this.enabled,
    this.pragmas,
  );

  final String source;
  final String file;
  final LineInfo lineInfo;
  final Set<MutationOperator> enabled;
  final _IgnorePragmas pragmas;
  final List<Mutant> mutants = [];

  void _add(
    MutationOperator operator,
    int offset,
    int length,
    String replacement,
  ) {
    if (!enabled.contains(operator)) return;
    final line = lineInfo.getLocation(offset).lineNumber;
    mutants.add(Mutant(
      file: file,
      line: line,
      offset: offset,
      length: length,
      replacement: replacement,
      operator: operator.id,
      ignored: pragmas.covers(line, operator),
    ));
  }

  void _swapToken(MutationOperator operator, Token token, String to) =>
      _add(operator, token.offset, token.length, to);

  /// Negates [condition], unless another operator already produces the
  /// same program: `a == b` / `a != b` (equality swap) and `!x`
  /// (remove_not).
  /// Also skipped when the condition promotes a variable (see
  /// [_promotes]): the negated code would not compile.
  void _negate(Expression condition) {
    final bare = condition.unParenthesized;
    if (bare is PrefixExpression && bare.operator.lexeme == '!') return;
    if (bare is BinaryExpression &&
        _binaryOperators[bare.operator.lexeme] == MutationOperator.equality) {
      return;
    }
    if (_promotes(condition)) return;
    _add(
      MutationOperator.negateCondition,
      condition.offset,
      condition.length,
      '!(${_text(condition)})',
    );
  }

  @override
  void visitAnnotation(Annotation node) {}

  @override
  void visitAssertStatement(AssertStatement node) {}

  @override
  void visitAssertInitializer(AssertInitializer node) {}

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final lexeme = node.operator.lexeme;
    if (lexeme == '??') {
      _add(
        MutationOperator.nullCoalescing,
        node.offset,
        node.length,
        _text(node.rightOperand),
      );
    } else if (_binarySwaps[lexeme] case final to?) {
      if (!_keepsOperator(node, lexeme)) {
        _swapToken(_binaryOperators[lexeme]!, node.operator, to);
      }
    }
    super.visitBinaryExpression(node);
  }

  /// Swaps that would not compile or not mean anything: string `+`, and
  /// swaps that break type promotion: `x == null` flipped, or `&&`/`||`
  /// around a null or `is` check (`x == null || x.isEmpty`).
  static bool _keepsOperator(BinaryExpression node, String lexeme) =>
      switch (_binaryOperators[lexeme]) {
        MutationOperator.arithmetic =>
          lexeme == '+' && _isStringConcatenation(node),
        MutationOperator.equality => _isNullCheck(node),
        MutationOperator.logical => _promotes(node),
        _ => false,
      };

  /// Whether [e] is, or chains with `&&`/`||`/`!`, a null check or an
  /// `is` test: Dart promotes the tested variable after it, so changing
  /// the logic around it makes later uses fail to compile.
  static bool _promotes(Expression e) => switch (e.unParenthesized) {
        IsExpression() => true,
        final BinaryExpression b when _isNullCheck(b) => true,
        BinaryExpression(
          :final operator,
          :final leftOperand,
          :final rightOperand
        )
            when operator.lexeme == '&&' || operator.lexeme == '||' =>
          _promotes(leftOperand) || _promotes(rightOperand),
        PrefixExpression(:final operator, :final operand)
            when operator.lexeme == '!' =>
          _promotes(operand),
        _ => false,
      };

  /// `x == null` or `x != null` (either side).
  static bool _isNullCheck(BinaryExpression b) =>
      (b.operator.lexeme == '==' || b.operator.lexeme == '!=') &&
      (b.leftOperand is NullLiteral || b.rightOperand is NullLiteral);

  /// `xs.isEmpty`, `a.b.first`, `f().last`: a member access on any
  /// target.
  @override
  void visitPropertyAccess(PropertyAccess node) {
    _swapMember(node.propertyName);
    super.visitPropertyAccess(node);
  }

  /// `xs.isEmpty` where `xs` is a plain identifier parses as a prefixed
  /// identifier, not a property access.
  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    _swapMember(node.identifier);
    super.visitPrefixedIdentifier(node);
  }

  /// `xs.any(p)` ↔ `xs.every(p)`; only calls with a target, since a bare
  /// `any(p)` is the caller's own function.
  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target != null) _swapMember(node.methodName);
    super.visitMethodInvocation(node);
  }

  void _swapMember(SimpleIdentifier name) {
    if (_collectionSwaps[name.name] case final to?) {
      _swapToken(MutationOperator.collection, name.token, to);
    }
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    if (_assignmentSwaps[node.operator.lexeme] case final to?) {
      _swapToken(MutationOperator.assignment, node.operator, to);
    }
    super.visitAssignmentExpression(node);
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    final lexeme = node.operator.lexeme;
    if (lexeme == '!') {
      _add(
        MutationOperator.removeNot,
        node.offset,
        node.length,
        _text(node.operand),
      );
    } else if (lexeme == '++' || lexeme == '--') {
      _swapToken(
          MutationOperator.increment, node.operator, _flipIncrement(lexeme));
    }
    super.visitPrefixExpression(node);
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    final lexeme = node.operator.lexeme;
    if (lexeme == '++' || lexeme == '--') {
      _swapToken(
          MutationOperator.increment, node.operator, _flipIncrement(lexeme));
    }
    super.visitPostfixExpression(node);
  }

  @override
  void visitExpressionStatement(ExpressionStatement node) {
    if (_isRemovableCall(node)) {
      // Only the newlines are kept, so the line numbers of the rest of
      // the file do not move.
      _add(
        MutationOperator.removeCall,
        node.offset,
        node.length,
        _text(node).replaceAll(RegExp(r'[^\n]'), ''),
      );
    }
    super.visitExpressionStatement(node);
  }

  @override
  void visitBooleanLiteral(BooleanLiteral node) {
    if (_isPerformanceHint(node)) return;
    _swapToken(
      MutationOperator.booleanLiteral,
      node.literal,
      node.value ? 'false' : 'true',
    );
  }

  @override
  void visitIfStatement(IfStatement node) {
    if (node.caseClause == null) _negate(node.expression);
    super.visitIfStatement(node);
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    _negate(node.condition);
    super.visitWhileStatement(node);
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    _negate(node.condition);
    super.visitConditionalExpression(node);
  }

  String _text(AstNode node) => source.substring(node.offset, node.end);
}

/// A call whose result is discarded, directly in a block or a `case`
/// body: `save(x);`, `a.b(c);`, `callback();`, `await sync();`. Not
/// mutated: calls on `super` (the analyzer already enforces them) and
/// `print` / `debugPrint` (removing logging is noise, not a bug). A
/// statement that is the body of an `if` or a loop is kept, because
/// removing it would make the next statement the body.
bool _isRemovableCall(ExpressionStatement node) {
  if (node.parent is! Block && node.parent is! SwitchMember) return false;
  var e = node.expression;
  if (e is AwaitExpression) e = e.expression;
  return switch (e) {
    MethodInvocation(:final target, :final methodName) =>
      target is! SuperExpression && !_logging.contains(methodName.name),
    FunctionExpressionInvocation() => true,
    _ => false,
  };
}

const Set<String> _logging = {'print', 'debugPrint'};

String _flipIncrement(String lexeme) => lexeme == '++' ? '--' : '++';

bool _isStringConcatenation(BinaryExpression node) =>
    node.leftOperand is StringLiteral || node.rightOperand is StringLiteral;

/// Named arguments that only tune performance, never behaviour a test can
/// observe: `toList(growable: false)`, `List.filled(n, 0, growable: true)`.
const Set<String> _performanceHints = {'growable'};

/// Whether [node] is the value of a performance-only named argument.
bool _isPerformanceHint(BooleanLiteral node) {
  final parent = node.parent;
  return parent is NamedExpression &&
      _performanceHints.contains(parent.name.label.name);
}
