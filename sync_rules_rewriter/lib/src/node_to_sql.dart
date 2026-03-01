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
        '"$identifier"',
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

  static String toSql(AstNode node) {
    final builder = FixedNodeToSql();
    builder.visit(node, null);
    return builder.buffer.toString();
  }
}
