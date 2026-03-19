This exposes the [Sync Config editing tools](github.com/powersync-ja/sync-config-editing-tools)
as a package usable from JavaScript.

## Instantiation

This package requires you to load a compiled WebAssembly file, which depends on your target platform.

On Node.JS, resolve and load the WASM file:

```TypeScript
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { instantiate } from "@powersync/sync-config-tools";

const wasmBuffer = readFileSync(
  fileURLToPath(
    import.meta
      .resolve("@powersync/sync-config-tools/compiled.wasm"),
  ),
);

const module = await instantiate(wasmBuffer);
```

For web apps bundled with vite, use [explicit URL imports](https://vite.dev/guide/assets#explicit-url-imports):

```TypeScript
import { instantiate } from "@powersync/sync-config-tools";
import wasmUrl from "@powersync/sync-config-tools/compiled.wasm?url";

const module = await instantiate(fetch(wasmUrl));
```

## Development

To release a new version of this package:

1. Update the `version` entry in `package.json`.
2. Wait for that to get approved and merge to `main`.
3. Trigger the `publish_npm` workflow on the `main` branch.
