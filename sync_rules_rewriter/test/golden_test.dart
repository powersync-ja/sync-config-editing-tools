import 'package:sync_rules_rewriter/sync_rules_rewriter.dart';
import 'package:test/test.dart';

void main() {
  test('simple', () {
    expect(
      syncRulesToSyncStreams('''
bucket_definitions:
  user_lists:
    parameters: SELECT request.user_id() as user_id
    data:
      - SELECT * FROM lists WHERE lists.owner_id = bucket.user_id
'''),
      '''
config:
  edition: 3
streams:
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    auto_subscribe: true
    queries:
      - SELECT * FROM lists WHERE lists.owner_id = auth.user_id()
''',
    );
  });

  test('existing config', () {
    expect(
      syncRulesToSyncStreams('''
bucket_definitions:
  a:
    data:
      - SELECT * FROM users

config:
  # preserved comment
  edition: 1
'''),
      '''
config:
  # preserved comment
  edition: 3
streams:
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    auto_subscribe: true
    queries:
      - SELECT * FROM users
''',
    );
  });

  test('existing stream', () {
    expect(
      syncRulesToSyncStreams('''
config:
  edition: 2
bucket_definitions:
  a:
    data: SELECT * FROM a
streams:
  b:
    query: SELECT * FROM b
'''),
      '''
config:
  edition: 3
streams:
  b:
    query: SELECT * FROM b
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    auto_subscribe: true
    queries:
      - SELECT * FROM a
''',
    );
  });

  test('priorities from yaml', () {
    expect(
      syncRulesToSyncStreams('''
bucket_definitions:
  a:
    priority: 2
    data: SELECT * FROM a
  b:
    data: SELECT * FROM b
'''),
      '''
config:
  edition: 3
streams:
  # These Sync Streams have been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams_prio_2:
    priority: 2
    auto_subscribe: true
    queries:
      - SELECT * FROM a
  migrated_to_streams_prio_3:
    auto_subscribe: true
    queries:
      - SELECT * FROM b
''',
    );
  });

  test('priority from sql', () {
    expect(
      syncRulesToSyncStreams('''
bucket_definitions:
  a:
    parameters: SELECT 1 AS _priority, request.user_id() as user;
    data: SELECT * FROM a WHERE owner = bucket.user
'''),
      '''
config:
  edition: 3
streams:
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    priority: 1
    auto_subscribe: true
    queries:
      - SELECT * FROM a WHERE owner = auth.user_id()
''',
    );
  });

  test('multiple parameter queries', () {
    expect(
      syncRulesToSyncStreams('''
bucket_definitions:
  user_lists:
    parameters:
      - SELECT id as list_id FROM lists WHERE owner_id = request.user_id()
      - SELECT list_id FROM user_lists WHERE user_lists.user_id = request.user_id()
    data:
      - SELECT * FROM lists WHERE lists.id = bucket.list_id
      - SELECT * FROM todos WHERE todos.list_id = bucket.list_id
'''),
      '''
config:
  edition: 3
streams:
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    auto_subscribe: true
    with:
      user_lists_param0: SELECT id AS list_id FROM lists WHERE owner_id = auth.user_id()
      user_lists_param1: SELECT list_id FROM user_lists WHERE user_lists.user_id = auth.user_id()
    queries:
      - "SELECT lists.* FROM lists,user_lists_param0 AS bucket0,user_lists_param1 AS bucket1 WHERE lists.id = bucket0.list_id OR lists.id = bucket1.list_id"
      - "SELECT todos.* FROM todos,user_lists_param0 AS bucket0,user_lists_param1 AS bucket1 WHERE todos.list_id = bucket0.list_id OR todos.list_id = bucket1.list_id"
''',
    );
  });

  test('yaml string syntax', () {
    expect(
      syncRulesToSyncStreams('''
bucket_definitions:
  owned_lists:
    parameters: |
        SELECT id as list_id FROM lists WHERE
           owner_id = request.user_id()
    data:
      - SELECT * FROM lists WHERE lists.id = bucket.list_id
      - SELECT * FROM todos WHERE todos.list_id = bucket.list_id
'''),
      '''
config:
  edition: 3
streams:
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    auto_subscribe: true
    with:
      owned_lists_param: SELECT id AS list_id FROM lists WHERE owner_id = auth.user_id()
    queries:
      - "SELECT lists.* FROM lists,owned_lists_param AS bucket WHERE lists.id = bucket.list_id"
      - "SELECT todos.* FROM todos,owned_lists_param AS bucket WHERE todos.list_id = bucket.list_id"
''',
    );
  });

  test('merges multiple bucket definitions into a single stream', () {
    expect(
      syncRulesToSyncStreams('''
bucket_definitions:
  lists:
    data:
      - SELECT * FROM lists
  todos:
    data:
      - SELECT * FROM todos
'''),
      '''
config:
  edition: 3
streams:
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    auto_subscribe: true
    queries:
      # Translated from "lists" bucket definition.
      - SELECT * FROM lists
      # Translated from "todos" bucket definition.
      - SELECT * FROM todos
''',
    );
  });

  group('quoted identifiers', () {
    test('are preserved', () {
      expect(
        syncRulesToSyncStreams('''
bucket_definitions:
  a:
    data:
      - SELECT "userLists"."order" FROM "userLists"
'''),
        contains('SELECT "userLists"."order" FROM "userLists"'),
      );
    });

    test('mixed', () {
      expect(
        syncRulesToSyncStreams('''
bucket_definitions:
  a:
    data:
      - SELECT "userLists".ownerId FROM "userLists"
'''),
        contains('SELECT "userLists".ownerId FROM "userLists"'),
      );
    });

    test('with schema reference', () {
      expect(
        syncRulesToSyncStreams('''
bucket_definitions:
  a:
    data:
      - SELECT "other"."userLists"."ownerId" FROM "other"."userLists"
'''),
        contains(
          'SELECT "other"."userLists"."ownerId" FROM "other"."userLists"',
        ),
      );
    });

    test('with alias on table', () {
      expect(
        syncRulesToSyncStreams('''
bucket_definitions:
  a:
    data:
      - SELECT "BarBaz".id FROM items AS "BarBaz"
'''),
        contains('SELECT "BarBaz".id FROM items AS "BarBaz"'),
      );
    });

    test('with alias on column', () {
      expect(
        syncRulesToSyncStreams('''
bucket_definitions:
  a:
    data:
      - SELECT id AS "CreatedAt" FROM lists
'''),
        contains('SELECT id AS "CreatedAt" FROM lists'),
      );
    });

    test('on reference in where clause', () {
      expect(
        syncRulesToSyncStreams('''
bucket_definitions:
  a:
    data:
      - SELECT "ownerId" FROM lists WHERE "ownerId" = 1
'''),
        contains('SELECT "ownerId" FROM lists WHERE "ownerId" = 1'),
      );
    });

    test('on star column', () {
      expect(
        syncRulesToSyncStreams('''
bucket_definitions:
  a:
    data:
      - SELECT "BarBaz".* FROM items AS "BarBaz"
'''),
        contains('SELECT "BarBaz".* FROM items AS "BarBaz"'),
      );
    });

    test('remain quoted when default table is injected', () {
      expect(
        syncRulesToSyncStreams('''
bucket_definitions:
  a:
    parameters:
      - SELECT id AS list_id FROM lists
    data:
      - SELECT "OwnerId" FROM "Items" AS "BarBaz" WHERE "OwnerId" = bucket.list_id
'''),
        contains(
          '"SELECT \\"BarBaz\\".\\"OwnerId\\" FROM \\"Items\\" AS \\"BarBaz\\",a_param AS bucket WHERE \\"BarBaz\\".\\"OwnerId\\" = bucket.list_id"',
        ),
      );
    });

    test('remain quoted when * is injected', () {
      expect(
        syncRulesToSyncStreams('''
bucket_definitions:
  a:
    parameters:
      - SELECT id AS list_id FROM lists
    data:
      - SELECT * FROM items AS "BarBaz" WHERE id = bucket.list_id
'''),
        contains(
          '"SELECT \\"BarBaz\\".* FROM items AS \\"BarBaz\\",a_param AS bucket WHERE \\"BarBaz\\".id = bucket.list_id"',
        ),
      );
    });
  });
}
