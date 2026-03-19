import 'dart:convert';

import 'package:source_span/source_span.dart';
import 'package:yaml_edit/yaml_edit.dart';
import 'package:yaml/yaml.dart';

import 'src/error.dart';
import 'src/pending_stream.dart';

export 'src/error.dart';

/// Translates sync rules with bucket definitions to equivalent sync streams.
String syncRulesToSyncStreams(String syncRules, {Uri? uri}) {
  final editor = YamlEditor(syncRules);
  final file = SourceFile.fromString(syncRules, url: uri);

  FileSpan yamlSpan(YamlNode node) {
    return file.span(node.span.start.offset, node.span.end.offset);
  }

  FileSpan yamlContentSpan(YamlScalar node) {
    final all = yamlSpan(node);
    FileSpan removePrefix(String prefix) {
      final index = all.text.indexOf(prefix);
      return all.subspan(index + 1);
    }

    FileSpan removeQuotes(String quote) {
      final index = all.text.indexOf(quote);
      final end = all.text.lastIndexOf(quote);
      return all.subspan(index + 1, end);
    }

    switch (node.style) {
      case .FOLDED:
        return removePrefix('>');
      case .LITERAL:
        return removePrefix('|');
      case .SINGLE_QUOTED:
        return removeQuotes("'");
      case .DOUBLE_QUOTED:
        return removeQuotes('"');
      case .PLAIN:
      case .ANY:
      default:
        return all;
    }
  }

  final diagnostics = <DiagnosticMessage>[];

  final buckets = editor.parseAt([
    'bucket_definitions',
  ], orElse: () => _nullSentinel);
  if (buckets.value is! Map) {
    return syncRules; // No buckets to translate
  }

  final syncStreams = SyncStreamsCollection();
  var hasDefinitionWithFailedTranslation = false;

  (buckets.value as Map).forEach((name, value) {
    final parameters = editor.parseAt([
      'bucket_definitions',
      name,
      'parameters',
    ], orElse: () => _nullSentinel);
    final data = editor.parseAt([
      'bucket_definitions',
      name,
      'data',
    ], orElse: () => _nullSentinel);
    final priority = editor.parseAt([
      'bucket_definitions',
      name,
      'priority',
    ], orElse: () => _nullSentinel);

    final pending = TranslationContext(
      name as String,
      diagnostics,
      switch (priority.value) {
        num i => i.toInt(),
        _ => 3,
      },
    );

    if (parameters.value is String) {
      pending.addParameter(yamlContentSpan(parameters as YamlScalar));
    } else if (parameters.value case List(:final length)) {
      for (var i = 0; i < length; i++) {
        final parameter = editor.parseAt([
          'bucket_definitions',
          name,
          'parameters',
          i,
        ]);

        if (parameter.value is String) {
          pending.addParameter(yamlContentSpan(parameter as YamlScalar));
        }
      }
    }

    if (data.value is String) {
      pending.addData(yamlContentSpan(data as YamlScalar));
    } else if (data.value case List(:final length)) {
      for (var i = 0; i < length; i++) {
        final data = editor.parseAt(['bucket_definitions', name, 'data', i]);

        if (data.value is String) {
          pending.addData(yamlContentSpan(data as YamlScalar));
        }
      }
    } else {
      hasDefinitionWithFailedTranslation = true;
      return;
    }

    syncStreams.addTranslatedStream(pending);
  });

  if (diagnostics.isNotEmpty) {
    throw TranslationFailedException(diagnostics);
  }

  var hasStreamsInYaml =
      editor.parseAt(['streams'], orElse: () => _nullSentinel) != _nullSentinel;

  final streams = syncStreams.pendingStreams.values.toList();
  if (streams.isNotEmpty) {
    if (editor.parseAt(['config'], orElse: () => _nullSentinel) !=
        _nullSentinel) {
      editor.update(['config', 'edition'], 3);
    } else {
      editor.update(['config'], wrapAsYamlNode({'edition': 3}));
    }

    if (!hasDefinitionWithFailedTranslation) {
      editor.remove(['bucket_definitions']);
    }

    for (final stream in streams) {
      if (hasDefinitionWithFailedTranslation) {
        // We can't remove bucket_definitions because we were unable to
        // translate them all. But remove mapped definitions.
        for (final (bucketName, _) in stream.queriesByDefinition) {
          editor.remove(['bucket_definitions', bucketName]);
        }
      }

      final dataQueries = stream.allQueries.toList();
      final streamInYaml = wrapAsYamlNode(
        collectionStyle: CollectionStyle.BLOCK,
        {
          if (stream.priority != 3) 'priority': stream.priority,
          // Bucket definitions always have a single subscription.
          'auto_subscribe': true,
          if (stream.ctes.isNotEmpty)
            'with': wrapAsYamlNode({
              for (final MapEntry(:key, :value) in stream.ctes.entries)
                key: value,
            }),
          // Even if the stream only has a single query, we want to write it as
          // a list so that users can easily add more.
          'queries': wrapAsYamlNode(dataQueries),
        },
      );

      final name = syncStreams.nameForStream(stream);
      if (hasStreamsInYaml) {
        editor.update(['streams', name], streamInYaml);
      } else {
        editor.update([
          'streams',
        ], wrapAsYamlNode(collectionStyle: .BLOCK, {name: streamInYaml}));
        hasStreamsInYaml = true;
      }
    }
  }

  final rendered = editor.toString();
  return _attachCommentsToRenderedYaml(syncStreams, rendered);
}

/// The `yaml_edit` package doesn't let us add comments, so we parse the
/// generated yaml and manually insert links to Sync Streams documentation as
/// comments.
String _attachCommentsToRenderedYaml(
  SyncStreamsCollection generatedStreams,
  String yamlWithSyncStreams,
) {
  final lines = const LineSplitter().convert(yamlWithSyncStreams);
  final parsed = loadYamlNode(yamlWithSyncStreams);
  YamlMap? streams;

  if (parsed is YamlMap) {
    final loadedStreams = parsed['streams'];
    if (loadedStreams is YamlMap && loadedStreams.style == .BLOCK) {
      streams = loadedStreams;
    }
  }

  if (streams == null) {
    // Can't add comments due to some broken yaml structure.
    return yamlWithSyncStreams;
  }

  // This simple offset assumes insertCommentAtOffset is called for lines from
  // top-to-bottom, which is the case because we iterate over streams in order.
  var addedLines = 0;
  void insertCommentAtOffset(int line, int column, List<String> commentLines) {
    final indent = ' ' * column;
    final index = line + addedLines;

    lines.insertAll(index, commentLines.map((line) => '$indent# $line'));
    addedLines += commentLines.length;
  }

  void commentBeforeNode(YamlNode node, List<String> commentLines) {
    final start = node.span.start;
    insertCommentAtOffset(start.line, start.column, commentLines);
  }

  for (final (i, stream) in generatedStreams.pendingStreams.values.indexed) {
    final name = generatedStreams.nameForStream(stream);

    // Link to documentation before the first stream.
    if (i == 0) {
      for (final key in streams.nodes.keys) {
        if (key is YamlScalar && key.value == name) {
          final prefix = generatedStreams.pendingStreams.length == 1
              ? 'This Sync Stream has'
              : 'These Sync Streams have';

          commentBeforeNode(key, [
            '$prefix been translated from bucket definitions. There may be more efficient ways to express these queries.',
            'You can add additional queries to this list if you need them.',
            'For details, see the documentation: https://docs.powersync.com/sync/streams/overview',
          ]);
          break;
        }
      }
    }

    if (stream.queriesByDefinition.length > 1) {
      // We've merged multiple bucket definitions into a single sync stream. Add
      // comments explaining which queries came from which original definition.
      final streamInYaml = streams.nodes[name];
      if (streamInYaml is! YamlMap) continue;
      final queriesInYaml = streamInYaml.nodes['queries'];
      if (queriesInYaml is! YamlList ||
          queriesInYaml.style != CollectionStyle.BLOCK) {
        continue;
      }

      var offset = 0;
      for (final (originalName, queries) in stream.queriesByDefinition) {
        if (queriesInYaml.nodes.length <= offset) {
          break;
        }

        final start = queriesInYaml.nodes[offset].span.start;
        // We can't use start.column here, because that gives us the starting
        // position of the scalar when we want the `-` of the list as a
        // position.
        final originalLine = lines[start.line + addedLines];
        insertCommentAtOffset(start.line, originalLine.indexOf('-'), [
          'Translated from "$originalName" bucket definition.',
        ]);

        offset += queries.length;
      }
    }
  }

  lines.add('');
  return lines.join('\n');
}

final _nullSentinel = wrapAsYamlNode(null);
