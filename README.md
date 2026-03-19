## Sync Config tools

This repository provides editing support for Sync Configurations (Sync Streams and legacy Sync Rules).

At the moment, this contains a rewriter transforming Sync Rules into equivalent Sync Streams.
In the future, we might add other tools like LSP-like editing services for Sync Streams as well.

## Rewriter

To use the rewriter outside of the dashboard, use `dart run sync_config_tools/bin/rewrite.dart < /path/to/sync/rules.yaml`.

The functionality is exposed as a Dart API under `package:sync_config_tools/sync_rules_to_sync_streams.dart`, but we don't currently publish that package to pub.dev.

## JavaScript package

To be usable in the PowerSync dashboard and CLI, we compile editing tools to WebAssembly using `dart2wasm`.

The outputs of that are wrapped in an ESM package under [`js-package`](./js-package/).
