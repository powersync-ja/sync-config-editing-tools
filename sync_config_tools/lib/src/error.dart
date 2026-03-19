import 'package:source_span/source_span.dart';

final class DiagnosticMessage {
  final FileSpan span;
  final String message;

  DiagnosticMessage(this.span, this.message);
}

final class TranslationFailedException implements Exception {
  final List<DiagnosticMessage> diagnostics;

  TranslationFailedException(this.diagnostics);

  @override
  String toString() {
    final buffer = StringBuffer('Translation failed:\n');
    for (final diagnostics in diagnostics) {
      buffer.writeln(diagnostics.span.message(diagnostics.message));
    }

    return buffer.toString();
  }
}
