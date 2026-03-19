import test from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import assert from "node:assert";

import { instantiate } from "@powersync/sync-config-tools";

const wasmBuffer = readFileSync(
  fileURLToPath(
    import.meta.resolve("@powersync/sync-config-tools/compiled.wasm"),
  ),
);

// This implicitly asserts that the declared return type of syncRulesToSyncStreams
// matches the actual value.
function assertEqual<T>(actual: T, expected: T) {
  assert.deepStrictEqual(actual, expected);
}

test("transpiles sync rules", async () => {
  const module = await instantiate(wasmBuffer);
  const source = `
# TODO: Paste your sync rules here, they will get translated to sync streams as you type.
bucket_definitions:
  user_lists: # name for the bucket
    # Parameter Query, selecting a user_id parameter:
    parameters: SELECT request.user_id() as user_id 
    data: # Data Query, selecting data, filtering using the user_id parameter:
      - SELECT * FROM lists WHERE owner_id = bucket.user_id 
`;
  const output = `
# TODO: Paste your sync rules here, they will get translated to sync streams as you type.
config:
  edition: 3
streams:
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    auto_subscribe: true
    queries:
      - SELECT * FROM lists WHERE owner_id = auth.user_id()
`;

  assertEqual(module.syncRulesToSyncStreams(source), {
    type: "success",
    result: output,
  });
});

test("reports errors", async () => {
  const module = await instantiate(wasmBuffer);
  // This has a syntax error (comma after * without another expression).
  const source = `
bucket_definitions:
  user_lists:
    data:
      - SELECT *, FROM lists WHERE owner_id = bucket.user_id 
`;

  assertEqual(module.syncRulesToSyncStreams(source), {
    type: "error",
    diagnostics: [
      {
        startOffset: 63,
        length: 4,
        message:
          'Expected an expression here, but got a reserved keyword. Did you mean to use it as a column? Try wrapping it in double quotes ("FROM").',
      },
    ],
    internalMessage: "Translation failed due to errors in source.",
  });
});
