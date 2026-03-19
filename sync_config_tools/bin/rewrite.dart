import 'dart:io';

import 'package:sync_config_tools/sync_rules_to_sync_streams.dart';

/// Usage: `dart run bin/rewrite.dart < /path/to/sync/rules.yaml`.
void main() async {
  final input = StringBuffer();
  await stdin.transform(systemEncoding.decoder).forEach(input.write);

  print(syncRulesToSyncStreams(input.toString()));
}
