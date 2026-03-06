import 'package:sqlparser/sqlparser.dart';
import 'package:sqlparser/utils/node_to_text.dart';

/// An implementation of [NodeSqlBuilder] that preserves quotes around
/// identifiers to ensure they're correctly parsed by the sync service.
final class FixedNodeToSql extends NodeSqlBuilder {
  @override
  void identifier(
    String identifier, {
    IdentifierToken? fromToken,
    bool spaceBefore = true,
    bool spaceAfter = true,
  }) {
    // The sync service parses identifiers as lowercase if they're not wrapped
    // in double quotes. For this reason, we want to preserve double quotes from
    // the source SQL statement.
    if (fromToken != null && fromToken.escaped) {
      return symbol(
        escapeIdentifier(identifier),
        spaceBefore: spaceBefore,
        spaceAfter: spaceAfter,
      );
    }

    return super.identifier(
      identifier,
      fromToken: fromToken,
      spaceBefore: spaceBefore,
      spaceAfter: spaceAfter,
    );
  }

  @override
  void visitBinaryExpression(BinaryExpression e, void arg) {
    // Rewrite `auth.parameters() ->> 'x'` to `auth.parameter('x')`.
    if (e.left case FunctionExpression(
      name: 'parameters',
      schemaName: final schema?,
    )) {
      if (e.right case final StringLiteral right) {
        return super.visitFunction(
          FunctionExpression(
            name: 'parameter',
            schemaName: schema,
            parameters: ExprFunctionParameters(parameters: [right]),
          ),
          arg,
        );
      }
    }

    super.visitBinaryExpression(e, arg);
  }

  static String toSql(AstNode node) {
    final builder = FixedNodeToSql();
    builder.visit(node, null);
    return builder.buffer.toString();
  }
}
