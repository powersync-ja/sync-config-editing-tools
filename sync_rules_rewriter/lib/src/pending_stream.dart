import 'dart:math';

import 'package:source_span/source_span.dart';
import 'package:sqlparser/sqlparser.dart';

import 'error.dart';
import 'node_to_sql.dart';

/// A sync stream created from a collection of `bucket_definition`s.
///
/// We merge all bucket definitions with the same priority into the same sync
/// stream (using multiple data queries). This results in a Sync Config where
/// users can just add more queries to the existing stream without having to
/// understand all concepts of Sync Streams and the `auto_subscribe` behavior.
final class TranslatedSyncStream {
  final int priority;
  final Map<String, String> ctes = {};

  /// Queries added to the stream, grouped by the bucket definition from which
  /// we've extracted them.
  final List<(String, List<String>)> queriesByDefinition = [];

  Iterable<String> get allQueries => queriesByDefinition.expand((e) => e.$2);

  TranslatedSyncStream(this.priority);
}

final class SyncStreamsCollection {
  final Map<int, TranslatedSyncStream> pendingStreams = {};

  String nameForStream(TranslatedSyncStream stream) {
    if (pendingStreams.length == 1) {
      return 'migrated_to_streams';
    } else {
      return 'migrated_to_streams_prio_${stream.priority}';
    }
  }

  void addTranslatedStream(TranslationContext context) {
    final stream = pendingStreams.putIfAbsent(
      context.priority,
      () => TranslatedSyncStream(context.priority),
    );

    // Turn parameter queries into common table expressions to use them across
    // potentially multiple data queries.
    for (final (i, param) in context.parameterQueries.indexed) {
      final cteName = parameterCteName(
        context.bucketDefinitionName,
        context.parameterQueries.length,
        i,
      );
      stream.ctes[cteName] = param;
    }

    stream.queriesByDefinition.add((
      context.bucketDefinitionName,
      context.data,
    ));
  }
}

final class TranslationContext {
  final String bucketDefinitionName;
  final List<DiagnosticMessage> messages;
  final List<String> parameterQueries = [];
  final Map<String, List<Expression>> trivialParameters = {};
  int priority;

  final List<String> data = [];

  TranslationContext(this.bucketDefinitionName, this.messages, this.priority);

  /// Whether the node is a trivial parameter query (without a `FROM` clause or
  /// `WHERE` conditions).
  ///
  /// For those queries, we inline the definition into use-sites. This results
  /// in more idiomatic outputs in many cases. For instance, a parameter query
  /// `SELECT request.user_id() as user_id` would result in `auth.user_id()`
  /// being inlined instead of us adding a CTE for this. This makes it clearer
  /// that parameters and data no longer need to be separate queries.
  ///
  /// Technically, we can always inline all parameter queries by joining them
  /// and adopting their `WHERE` clause. But the general case requires
  /// introducing table aliases and might make outputs less readable.
  bool _tryInlining(AstNode node) {
    if (node case SelectStatement(
      columns: final columns,
      from: null,
      where: null,
    )) {
      final instantiation = <String, Expression>{};

      for (final column in columns) {
        if (column is ExpressionResultColumn) {
          var name = (column.as?.name ?? column.expression.resultColumnName)
              .toLowerCase();
          instantiation[name] = column.expression;
        }
      }

      instantiation.forEach(
        (k, v) => trivialParameters.putIfAbsent(k, () => []).add(v),
      );
      return true;
    }

    return false;
  }

  void addParameter(FileSpan span) {
    final root = _ToStreamTranslator(
      this,
      isDataQuery: false,
    ).transform(_parse(span), null);
    if (root != null && root is! InvalidStatement) {
      if (_tryInlining(root)) {
        return;
      }

      parameterQueries.add(FixedNodeToSql.toSql(root));
    }
  }

  void addData(FileSpan span) {
    final root = _ToStreamTranslator(
      this,
      isDataQuery: true,
    ).transform(_parse(span), null);
    if (root != null && root is! InvalidStatement) {
      data.add(FixedNodeToSql.toSql(root));
    }
  }

  AstNode _parse(FileSpan span) {
    final parsed = _engine.parseSpan(ParserEntrypoint.statement, span);
    for (final error in parsed.errors) {
      messages.add(DiagnosticMessage(error.token.span, error.message));
    }
    return parsed.rootNode;
  }
}

final class _ToStreamTranslator extends Transformer<void> {
  final TranslationContext stream;
  (String, IdentifierToken?)? defaultTableName;
  bool isDataQuery;

  final int parameterQueryCount;

  _ToStreamTranslator(this.stream, {required this.isDataQuery})
    : parameterQueryCount = isDataQuery ? stream.parameterQueries.length : 0;

  @override
  AstNode? visitFunction(FunctionExpression e, void arg) {
    if (e.schemaName?.toLowerCase() == 'request') {
      if (_requestFunctions[e.name.toLowerCase()]
          case (final schema, final name)?) {
        return FunctionExpression(
          name: name,
          schemaName: schema,
          parameters: visit(e.parameters, null) as FunctionParameters,
        );
      }
    }

    return super.visitFunction(e, arg);
  }

  @override
  AstNode? visitStarResultColumn(StarResultColumn e, void arg) {
    if (e.tableName == null) {
      return StarResultColumn(defaultTableName?.$1)
        ..tableNameToken = defaultTableName?.$2;
    }

    return e;
  }

  @override
  AstNode? visitReference(Reference e, void arg) {
    if (e.entityName == null) {
      final (tableName, tableNameToken) = defaultTableName ?? (null, null);
      return Reference(columnName: e.columnName, entityName: tableName)
        ..columnNameToken = e.columnNameToken
        ..entityNameToken = tableNameToken;
    }

    return e;
  }

  @override
  AstNode? visitExpressionResultColumn(ExpressionResultColumn e, void arg) {
    if (e.as case AliasClause(name: '_priority')) {
      if (e.expression case NumericLiteral(isInt: true, :final value)) {
        stream.priority = min(stream.priority, value.toInt());
      }

      return null;
    }

    return super.visitExpressionResultColumn(e, arg);
  }

  @override
  AstNode? visitSelectStatement(SelectStatement e, void arg) {
    // Join CTEs for parameter queries to main statement
    if (parameterQueryCount > 0 && e.from is TableReference) {
      final tableReference = e.from as TableReference;
      if (tableReference.as case final alias?) {
        defaultTableName = (alias.name, alias.nameToken);
      } else {
        defaultTableName = (
          tableReference.tableName,
          tableReference.tableNameToken,
        );
      }

      e.from = JoinClause(
        primary: tableReference,
        joins: [
          for (var i = 0; i < parameterQueryCount; i++)
            Join(
              operator: .comma(),
              query: TableReference(
                parameterCteName(
                  stream.bucketDefinitionName,
                  parameterQueryCount,
                  i,
                ),
                as: AliasClause(_parameterAliasName(parameterQueryCount, i)),
              ),
            ),
        ],
      );
    }

    return super.visitSelectStatement(e, arg);
  }

  @override
  AstNode? visitBinaryExpression(BinaryExpression e, void arg) {
    // bucket parameter references can only appear as a direct child of an = or
    // IN operator.
    var expandLeft = _expandBucketReference(e.left);
    var expandRight = _expandBucketReference(e.right);

    // Transform a = bucket.b to a = bucket0.b OR a = bucket1.b OR ...
    if (expandLeft != null || expandRight != null) {
      expandLeft ??= [e.left];
      expandRight ??= [e.right];

      final replacementTerms = <BinaryExpression>[];
      for (final left in expandLeft) {
        for (final right in expandRight) {
          replacementTerms.add(
            BinaryExpression(
              transform(left, null) as Expression,
              e.operator,
              transform(right, null) as Expression,
            ),
          );
        }
      }

      return replacementTerms.reduce(
        (a, b) => BinaryExpression(a, Token(TokenType.or, e.span!), b),
      );
    }

    return super.visitBinaryExpression(e, arg);
  }

  List<Expression>? _expandBucketReference(Expression e) {
    if (isDataQuery) {
      if (e case Reference(:final columnName, entityName: 'bucket')) {
        return [
          if (stream.trivialParameters[e.columnName.toLowerCase()]
              case final instantiation?)
            ...instantiation,

          for (var i = 0; i < parameterQueryCount; i++)
            Reference(
              columnName: columnName,
              entityName: _parameterAliasName(parameterQueryCount, i),
            ),
        ];
      }
    }

    return null;
  }
}

String parameterCteName(String definitionName, int total, int index) {
  if (total == 1) {
    return '${definitionName}_param';
  } else {
    return '${definitionName}_param$index';
  }
}

String _parameterAliasName(int total, int index) {
  if (total == 1) {
    return 'bucket';
  } else {
    return 'bucket$index';
  }
}

const _requestFunctions = {
  'parameter': ('connection', 'parameter'),
  'parameters': ('connection', 'parameters'),
  'jwt': ('auth', 'parameters'),
  'user_id': ('auth', 'user_id'),
};

final _engine = SqlEngine(
  EngineOptions(
    version: SqliteVersion.current,
    supportSchemaInFunctionNames: true,
  ),
);

extension on Expression {
  String get resultColumnName {
    return switch (this) {
      Reference(:final columnName) => columnName,
      _ => span!.text,
    };
  }
}
