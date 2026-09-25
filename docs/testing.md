# Testing

The project has roughly **90 automated tests** covering queries, migrations, sync, providers and screens. This page
explains the approach, the helpers, how to run the suite, and how to add to it.

**Contents**

- [Philosophy](#philosophy)
- [Running tests](#running-tests)
- [Layout](#layout)
- [The helpers](#the-helpers)
- [Patterns with examples](#patterns-with-examples)
- [Gotchas](#gotchas)
- [What is not covered](#what-is-not-covered)
- [Writing a test for a new feature](#writing-a-test-for-a-new-feature)

---

## Philosophy

1. **Use the real database, fake the network.** The risky logic is in SQL queries, migrations and sync rules. Mocks would hide
   those bugs, so tests run against a genuine **in-memory SQLite** database. Only Supabase and other outside services are replaced by fakes.
2. **Every test starts from nothing.** `setUp` creates a fresh empty database and `tearDown` closes it, so tests can't affect each other, and your real `db.sqlite` is never touched.
3. **Providers make swapping easy.** Because the app gets its database, user and sync engine from Riverpod providers, a test can build a
   `ProviderScope` / `ProviderContainer` with test versions using `overrideWithValue`. No production code changes.
4. **Test names read as specifications.** "a newer local edit is kept and uploaded" tells you the rule without opening the file.
5. **Prove the test can fail.** For bug fixes, temporarily reverting the fix should make the new test fail. The regression tests here were checked that way.

## Running tests

| Task | Command |
|---|---|
| Everything | `flutter test` |
| One file | `flutter test test/daos/transactions_dao_test.dart` |
| One test by name | `flutter test --plain-name "clamps billing day"` |
| Analyzer | `flutter analyze` |

## Layout

`test/` mirrors `lib/`:

| Folder | What it covers | Kind |
|---|---|---|
| `test/daos/` | `TransactionsDao` and `CategoriesDao` queries: user scoping, monthly filters, totals, fixed-transaction generation (billing-day clamping, no duplicates, start month, future dates, inactive/deleted/other users' templates), the end-of-month regression | Unit, real DB |
| `test/database/` | Upgrading a **version 1** database (rows kept, `updated_at` and `sync_cursors` added) and a **version 2** database (wrong transaction types repaired) | Migration |
| `test/sync/` | `SyncEngine` against `FakeSyncRemote`: upload and mark synced, an edit *during* an upload isn't lost, one failing table doesn't stop others, incremental pull with cursors, per-user cursors, remote deletes, newer-wins in both directions, two offline devices making one fixed transaction, `nextUpdatedAt` | Unit, real DB + fake server |
| `test/providers/` | `providers_test.dart` (live lists, per-month provider, `TransactionActions`, theme and filter notifiers), `settings_actions_test.dart` (add/update/delete for categories, templates, goals, investments follow the sync rules), `sync_controller_test.dart` (status changes, offline, merged requests, debounce, pending count) | Unit, `ProviderContainer` |
| `test/screens/` | `AuthGate` (login vs dashboard), `Dashboard` (totals, adding, chip filtering, Add Fixed, income category raising income), `Settings` (every panel: add, edit, delete with confirmation, validation, color picker) | Widget |
| `test/widgets/` | Add Transaction form (type from category), `SyncTriggers` and the status button (startup, reconnect, edits, tap feedback), `LedgerList` colors, the Income/Expense toggle's contrast | Widget |
| `test/theme/` | `MoneyColors` contrast ratios, `signedAmount`, icon map, color/hex helpers | Unit |
| `test/helpers/` | Shared fakes and utilities (below) | Support |

## The helpers

All in [`test/helpers/`](../test/helpers).

| Helper | File | What it gives you |
|---|---|---|
| `createTestDatabase()` | `test_database.dart` | A fresh in-memory `AppDatabase` (via `AppDatabase.forTesting`). Uses `closeStreamsSynchronously: true` so no timers are left pending after a widget test. |
| `userA`, `userB` | `test_database.dart` | Two constant user IDs, for "signed-in user" and "someone else". |
| `insertCategory`, `insertTemplate`, `insertTransaction` | `test_database.dart` | Insert a row while spelling out only the fields the test cares about; the rest have sensible defaults. |
| `FakeSyncRemote` | `fake_sync_remote.dart` | An in-memory Supabase implementing `SyncRemote`. Behaves like the real tables after the migration: every write gets a new `server_updated_at`, and `fetchChanges` returns rows since a cursor. Knobs: `seed` (pretend another device uploaded a row), `rows`, `fetchCalls` (assert the cursor was used), `failingTables`, `runDuringNextUpsert` (do something "while the upload is in flight"). **Several databases can share one remote to simulate several devices.** |
| `FakeSyncEngine` | `pump_app.dart` | Stands in for `SyncEngine` in UI tests. Records which user IDs were synced; `failWith` makes syncs fail; `gate` (a `Completer`) makes a sync wait so you can test "already running". |
| `pumpApp(tester, child, db: ...)` | `pump_app.dart` | Builds `ProviderScope` + `MaterialApp` like `main.dart`, with the database, signed-in user, auth stream, sync engine and connectivity replaced. Options: `userId` (`null` = signed out), `syncEngine`, `isOnline`, `connectivity` (a stream to go on/offline mid-test). Makes the fake screen 1400x2400 so the Dashboard has room. |
| `schemaV1` | `schema_v1.dart` | A **frozen** copy of the version 1 `CREATE TABLE` statements for migration tests. **Never edit it**: it must match what is already on users' devices. |

## Patterns with examples

### A DAO test: real SQL, real assertions

```dart
setUp(() async {
  db = createTestDatabase();
  food = await insertCategory(db, name: "Food");
});
tearDown(() => db.close());

test("clamps billing day 31 to the last day of short months", () async {
  await insertTemplate(db, name: "Gym", categoryId: food.id, billingDay: 31, startDate: DateTime(2024, 1, 1));

  await db.transactionsDao.generateFixedTransactionsForMonth(2025, 2, userA);   // 28 days
  await db.transactionsDao.generateFixedTransactionsForMonth(2024, 2, userA);   // leap year

  // ...expect the dates to be Feb 28, 2025 and Feb 29, 2024
});
```

To read the first value of a `Stream` as a plain value: `await dao.watchDashboardMetrics(2025, 3, userA).first`.

### A provider test: a container with overrides

```dart
ProviderContainer createContainer({String? userId = userA}) {
  return ProviderContainer.test(overrides: [
    databaseProvider.overrideWithValue(db),
    currentUserIdProvider.overrideWithValue(userId),   // "signed in" with no Supabase
  ]);
}

test("add stamps the signed in user's id on the new row", () async {
  final container = createContainer();
  await container.read(transactionActionsProvider).add(/* companion without a user id */);
  expect((await db.transactionsDao.getAll()).single.userId, userA);
});
```

`ProviderContainer.test()` disposes itself when the test ends.

### A widget test: tap and type like a user

```dart
testWidgets("adding a transaction makes it appear in the ledger", (tester) async {
  await pumpApp(tester, const Dashboard(), db: db);
  await tester.pumpAndSettle();

  await tester.enterText(find.widgetWithText(TextField, "Transaction Name"), "Coffee");
  await tester.enterText(find.widgetWithText(TextField, "Amount"), "4.50");
  await tester.tap(find.widgetWithText(ElevatedButton, "Add Transaction"));
  await tester.pumpAndSettle();     // lets DB write -> stream -> provider -> rebuild finish

  expect(find.widgetWithText(ListTile, "Coffee"), findsOneWidget);
});
```

- `pumpApp` / `tester.pump()` draw a frame; **time doesn't pass on its own** in a widget test.
- `pumpAndSettle()` keeps drawing frames until nothing is changing.
- `find.text(...)`, `find.widgetWithText(Type, text)` and `find.byType(...)` locate widgets, a bit like CSS selectors.

### A sync test: two devices, one server

```dart
final server = FakeSyncRemote();
final phone  = createTestDatabase();
final laptop = createTestDatabase();
// both SyncEngine(phone, server) and SyncEngine(laptop, server) share one "Supabase"
```

Both devices create the same fixed transaction offline, sync, and the test asserts the server has exactly one row.

### A migration test: a real old database file

The version 2 test builds a database on disk with the old app's schema, closes it, reopens it with the current `AppDatabase`
(which runs `onUpgrade`), and asserts what the upgrade changed and what it left alone.

### An accessibility test: contrast as a number

The Income/Expense toggle test computes the WCAG contrast ratio between the *painted* label color and the segment's
background, and requires at least 4.5:1 in both themes. Without the dark-mode fix it measured 1.2:1. Testing a computed number
catches unreadable text that "does it render?" tests would miss.

## Gotchas

| Symptom | Cause and fix |
|---|---|
| A provider test hangs, or fails with "disposed during loading state" | **Riverpod 3 pauses providers that nothing listens to.** Add `container.listen(provider, (previous, next) {})` before awaiting `.future`. This is also why `autoDispose` providers need a listener. |
| `find.text("Coffee")` finds 2 widgets | The same text appears in more than one place (a text field and a list row, or a summary card and a ledger). Narrow the finder: `find.widgetWithText(ListTile, "Coffee")` or `find.widgetWithText(SummaryCard, "$1000.00")`. |
| A widget test complains about pending timers | Use `createTestDatabase()`, which closes Drift's streams synchronously. |
| Dropdown selection needs two taps | Tap the dropdown to open it, `pumpAndSettle()`, then tap the option (usually `find.text("...").last`, since the closed dropdown also shows the current value). |
| `google_fonts` errors in a test | Tests have no internet. Set `GoogleFonts.config.allowRuntimeFetching = false` in `setUpAll`. |
| Two tests interfere | They share a database. Each test must create its own in `setUp` and close it in `tearDown`. |
| Time-dependent tests | Fixed transactions skip *future* charge dates, so tests that need "already charged" use dates well in the past. |

## What is not covered

- **`Login`**: it calls Google and Supabase directly. Testing it would need those behind replaceable interfaces.
- **`SupabaseSyncRemote`**: the real network implementation (pagination, timeouts). The logic *around* it is tested through `FakeSyncRemote`.
- **Windows URL scheme registration**, and the **real Google flows** on each platform: manual testing only.
- **Row Level Security** on the server: it isn't part of the Flutter tests.

A sensible manual checklist after a release build: sign in, add and delete a transaction, open Settings, toggle the theme,
sign out and back in; then turn the network off, add a transaction (the cloud should show a badge), and turn it back on
(it should sync within a few seconds).

## Writing a test for a new feature

1. **Decide the level.** A new query is a DAO test; new rules around writes are a provider test; a visible behavior is a widget test.
2. **Start with `createTestDatabase()`** and the `insertXxx` helpers.
3. **Override the providers** that reach outside (`databaseProvider`, `currentUserIdProvider`, ...) or use `pumpApp`.
4. **Name the test as a rule**: what should happen, in plain words.
5. **For a bug fix, write the failing test first**, or revert the fix once to make sure the test would have caught it.
6. If you add a **synced table**, add a sync engine test (see the checklist in [Sync](sync.md#adding-a-new-synced-table)); if you change the **schema**, add a migration test.
