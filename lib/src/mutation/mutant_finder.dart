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
    );
    parsed.unit.accept(visitor);
    return visitor.mutants..sort((a, b) => a.offset.compareTo(b.offset));
  }
}

class _MutantVisitor extends RecursiveAstVisitor<void> {
  _MutantVisitor(this.source, this.file, this.lineInfo, this.enabled);

  final String source;
  final String file;
  final LineInfo lineInfo;
  final Set<MutationOperator> enabled;
  final List<Mutant> mutants = [];

  void _add(
    MutationOperator operator,
    int offset,
    int length,
    String replacement,
  ) {
    if (!enabled.contains(operator)) return;
    mutants.add(Mutant(
      file: file,
      line: lineInfo.getLocation(offset).lineNumber,
      offset: offset,
      length: length,
      replacement: replacement,
      operator: operator.id,
    ));
  }

  void _swapToken(MutationOperator operator, Token token, String to) =>
      _add(operator, token.offset, token.length, to);

  /// Negates [condition], unless another operator already produces the
  /// same program: `a == b` / `a != b` (equality swap) and `!x`
  /// (remove_not).
  void _negate(Expression condition) {
    final bare = condition.unParenthesized;
    if (bare is PrefixExpression && bare.operator.lexeme == '!') return;
    if (bare is BinaryExpression &&
        _binaryOperators[bare.operator.lexeme] == MutationOperator.equality) {
      return;
    }
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
      if (lexeme != '+' || !_isStringConcatenation(node)) {
        _swapToken(_binaryOperators[lexeme]!, node.operator, to);
      }
    }
    super.visitBinaryExpression(node);
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
  void visitBooleanLiteral(BooleanLiteral node) {
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

  static String _flipIncrement(String lexeme) => lexeme == '++' ? '--' : '++';

  static bool _isStringConcatenation(BinaryExpression node) =>
      node.leftOperand is StringLiteral || node.rightOperand is StringLiteral;
}
