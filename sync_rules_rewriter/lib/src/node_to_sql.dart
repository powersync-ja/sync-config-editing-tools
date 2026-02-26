import 'package:sqlparser/sqlparser.dart';
import 'package:sqlparser/utils/node_to_text.dart';

/// Variant of [NodeSqlBuilder] that properly generates schema names in function
/// calls.
final class FixedNodeToSql extends NodeSqlBuilder {
  static final _upperCase = RegExp('[A-Z]');

  @override
  void identifier(String identifier,
      {bool spaceBefore = true, bool spaceAfter = true}) {
    // Quote identifiers containing uppercase to preserve case for PostgreSQL.
    // Lowercase identifiers survive PostgreSQL case-folding without quoting.
    if (_upperCase.hasMatch(identifier)) {
      identifier = '"$identifier"';
    }
    symbol(identifier, spaceBefore: spaceBefore, spaceAfter: spaceAfter);
  }

  @override
  void visitFunction(FunctionExpression e, void arg) {
    if (e.schemaName != null) {
      identifier(e.schemaName!, spaceAfter: false);
      symbol('.');
    }
    identifier(e.name);
    symbol('(');
    visit(e.parameters, arg);
    symbol(')', spaceAfter: true);
  }

  static String toSql(AstNode node) {
    final builder = FixedNodeToSql();
    builder.visit(node, null);
    return builder.buffer.toString();
  }
}
