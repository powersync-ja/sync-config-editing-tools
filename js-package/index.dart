import 'dart:js_interop';
// ignore: import_internal_library
import 'dart:_wasm';

import 'package:source_span/source_span.dart';
import 'package:sync_config_tools/sync_rules_to_sync_streams.dart' as rewrite;

void main() {
  // Not called, we just want the convert export.
}

// Note: These exports and types must be kept in sync with index.d.ts
@anonymous
extension type DiagnosticMessage._(JSObject _) implements JSObject {
  external factory DiagnosticMessage({
    required int startOffset,
    required int length,
    required String message,
  });

  factory DiagnosticMessage.fromDart(rewrite.DiagnosticMessage message) {
    final FileSpan(:start, :length) = message.span;
    return DiagnosticMessage(
      startOffset: start.offset,
      length: length,
      message: message.message,
    );
  }
}

extension type CompilerError._(JSObject _) implements JSObject {
  external factory CompilerError({
    /// Must always be 'error'.
    required String type,
    required JSArray<DiagnosticMessage> diagnostics,
    required String internalMessage,
  });
}

extension type TranslatedSyncStreams._(JSObject _) implements JSObject {
  external factory TranslatedSyncStreams({
    /// Must always be 'success'.
    required String type,
    required String result,
  });
}

@pragma('wasm:export', 'syncRulesToSyncStreams')
WasmExternRef? convert(WasmExternRef arg) {
  final input = (arg.toJS as JSString).toDart;
  JSObject result;

  try {
    result = TranslatedSyncStreams(
      type: 'success',
      result: rewrite.syncRulesToSyncStreams(input),
    );
  } on rewrite.TranslationFailedException catch (e) {
    // Emit diagnostics so that embedders can display errors in sources.

    result = CompilerError(
      type: 'error',
      diagnostics: [
        for (final diagnostic in e.diagnostics)
          DiagnosticMessage.fromDart(diagnostic),
      ].toJS,
      internalMessage: 'Translation failed due to errors in source.',
    );
  } catch (e, s) {
    result = CompilerError(
      type: 'error',
      diagnostics: JSArray(),
      internalMessage: 'Internal compiler error: $e\n$s',
    );
  }

  return externRefForJSAny(result);
}
