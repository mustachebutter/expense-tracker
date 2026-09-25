# Design decisions

*Why* the app is built the way it is. Each entry has the **context** (the problem), the **decision**, and the
**consequences**, including what it costs.

> **About this page.** These records were reconstructed from the code, its comments and the project's history.
> Where the original motivation isn't written down anywhere, the context describes the *problem the decision solves*
> rather than claiming what anyone was thinking at the time.

**Index**

| Area | Decisions |
|---|---|
| **Foundations** | [1 Offline-first](#1-offline-first-the-local-database-is-what-the-ui-reads) · [2 Drift](#2-drift-for-local-storage) · [3 Riverpod](#3-riverpod-for-state-and-dependency-injection) · [4 Streams drive the UI](#4-the-database-drives-the-ui-through-streamproviders) · [5 Injectable database](#5-the-database-and-supabase-are-providers-not-globals) |
| **Data** | [6 Per-user scoping](#6-every-query-is-scoped-to-a-user) · [7 Actions classes](#7-writes-go-through-actions-classes) · [8 Soft deletes](#8-deletes-are-soft) · [9 Client-side IDs](#9-ids-are-generated-on-the-device) · [10 Enums as ints](#10-enums-are-stored-as-integers) · [11 Category decides type](#11-the-category-decides-whether-a-transaction-is-income-or-expense) · [12 Raw SQL in BaseDao](#12-a-few-generic-operations-use-raw-sql) |
| **Sync** | [13 Two timestamps](#13-two-timestamps-updated_at-and-server_updated_at) · [14 Last write wins](#14-conflicts-last-write-wins-per-row) · [15 Conditional mark-synced](#15-mark-synced-only-if-the-row-is-unchanged) · [16 Pull, generate, push](#16-the-order-pull-then-generate-then-push) · [17 Deterministic IDs](#17-generated-transactions-get-deterministic-ids) · [18 Generate on the client](#18-fixed-transactions-are-generated-on-the-device) · [19 Controller and triggers](#19-one-controller-decides-when-to-sync-a-widget-supplies-the-triggers) · [20 Errors and timeouts](#20-failures-are-isolated-and-requests-time-out) |
| **Auth and config** | [21 Two sign-in flows](#21-two-google-sign-in-flows) · [22 `.env` as an asset](#22-configuration-lives-in-an-env-asset) |
| **UI** | [23 Monthly cards](#23-summary-cards-show-the-current-month) · [24 MoneyColors](#24-money-colors-as-a-themeextension-plus-signs) · [25 Presentational split](#25-presentational-widgets-are-separated-from-data-widgets) |
| **Quality** | [26 Testing approach](#26-tests-use-a-real-database-and-fake-the-network) · [27 Committed generated code](#27-generated-code-is-committed) |

---

## Foundations

### 1. Offline-first: the local database is what the UI reads

**Context.** A budgeting app is used in shops, on trains and in poor signal. A screen that waits on the network feels
broken, and a failed request can lose what the user just typed.

**Decision.** The UI reads and writes only the local SQLite database. Supabase is a *replica* that a background sync
engine reconciles with, never something a screen calls directly.

**Consequences.**
- Instant screens; full functionality offline; the network can fail without the user noticing.
- Cost: real complexity. We need change tracking (`is_synced`, `updated_at`), conflict rules and an engine. Most of
  [Sync](sync.md) exists because of this decision.
- Data on another device can be stale until the next sync.

### 2. Drift for local storage

**Context.** We need relational data (transactions reference categories), month/category queries and sums, and screens that
update themselves when data changes.

**Decision.** Use [Drift](https://drift.simonbinder.eu/), a type-safe SQLite layer for Dart.

**Consequences.**
- Tables are Dart classes; queries are checked by the compiler; `.watch()` gives live streams, the basis of decision 4.
- Migrations are explicit and testable ([Data model](data-model.md#migrations)).
- Cost: a code generation step (`build_runner`) whenever tables or DAOs change.

### 3. Riverpod for state and dependency injection

**Context.** The code originally reached for `AppDatabase.instance`, a `SyncEngine.instance` singleton, a static `AuthService`
and a global `ValueNotifier` for the theme. That made it impossible to test screens without the real database and network,
and left the "signed-in user" scattered around. The first attempt at view models were `ChangeNotifier`s that held no state and never notified.

**Decision.** Move state and dependencies to Riverpod 3. Providers are declared globally as *recipes*; the values live in a
`ProviderScope`, so tests can build a scope with fake values.

**Consequences.**
- Dependencies are explicit and swappable (`overrideWithValue`), which is what makes the test suite practical.
- Provider dependencies form a graph: when the signed-in user changes, everything that depends on it rebuilds automatically
  ([Architecture](architecture.md#riverpod-provider-graph)).
- Cost: a learning curve (`watch` vs `read` vs `listen`, and the `.notifier` split). In Riverpod 3 a provider that nothing listens to is paused, so tests must add a listener (see [Testing](testing.md#gotchas)).
- The code sticks to `Provider`, `StreamProvider` and `Notifier`, which are the long-term API. It avoids `ChangeNotifierProvider`, which Riverpod 3 moved to a legacy import.

### 4. The database drives the UI through StreamProviders

**Context.** After adding a transaction, the totals, ledger and category chips should all refresh without anyone calling "reload".

**Decision.** Expose data as `StreamProvider`s over Drift's `.watch()` queries. Widgets `ref.watch` them; writes just go to the database.

**Consequences.**
- One rule for freshness: *write to the database and the UI follows*, including changes that arrive from sync. A category added on another device shows up on its own.
- Per-month data uses `StreamProvider.autoDispose.family` keyed by a `(year, month)` record, so each month's query exists only while its card is on screen.
- The old dashboard loaded categories once with a `Future`; filter chips were stale until a restart. Streams fixed that.
- Cost: the stream restarts if its inputs (the user) change, which is what we want but means there can be a brief loading state.

### 5. The database and Supabase are providers, not globals

**Context.** Code that calls `AppDatabase.instance` directly can only ever use the real database.

**Decision.** `databaseProvider`, `supabaseProvider`, `syncRemoteProvider` and `syncEngineProvider` are providers, and everything else obtains them with `ref`.

**Consequences.** Tests override them with an in-memory database and fakes. `databaseProvider` does not itself make anything "live" (it always returns the same object); it exists so the database can be replaced. The live updates come from Drift's `.watch()`.

---

## Data

### 6. Every query is scoped to a user

**Context.** Several accounts may sign in on one device, and the local database keeps all of their rows. A query without a user filter would show one person another's data. An early version had exactly this bug (dashboard totals summed everyone's rows).

**Decision.** Every DAO method takes a `userId` and filters on it. Inserts stamp the user, and edits to another user's row are refused.

**Consequences.** Data can't leak between accounts, switching accounts just works, and each user has their own sync cursors. Cost: a `userId` parameter everywhere, and `watchAll`/`getAll` on `BaseDao` must be avoided in UI code because they are unfiltered.

### 7. Writes go through *Actions* classes

**Context.** Sync only works if every write follows the same rules (owned by the user, `updated_at` moved forward, `is_synced` cleared, deletes soft). If each screen wrote to the DAO itself, one forgotten line would silently stop a change from syncing.

**Decision.** One `XxxActions` class per data type (`CategoryActions`, `TransactionActions`, ...) is the only writer. Screens call `add`, `update` and `delete`.

**Consequences.** The rules live in one place per type and are tested once ([`settings_actions_test.dart`](../test/providers/settings_actions_test.dart)). Screens stay free of persistence detail.

### 8. Deletes are soft

**Context.** If a device simply removed a row, other devices could never learn it was deleted (a missing row looks the same as "never downloaded"). A hard-deleted template would also come back on the next pull.

**Decision.** Deleting sets `is_deleted = true` and syncs like any edit; queries hide deleted rows.

**Consequences.** Deletions propagate; the sync engine needs no special case. Cost: deleted rows accumulate forever, and every query must remember to filter `is_deleted`. Deleting a *template* stops future generation but keeps what it already created.

### 9. IDs are generated on the device

**Context.** A row created offline needs an identity before any server has seen it, and two devices offline at once must never pick the same one.

**Decision.** Primary keys are random UUID v4s created by the client (`clientDefault`), not database sequence numbers.

**Consequences.** Offline creation just works and upserting by ID makes uploads idempotent, so retrying is safe. Cost: text keys are larger than integers. See also [17](#17-generated-transactions-get-deterministic-ids).

### 10. Enums are stored as integers

**Decision.** `TransactionType` uses `intEnum`, stored as `0`/`1` locally and on Supabase.

**Consequences.** Compact, and the same in both databases. The enum's *order is part of the data format*: reordering it would silently flip every stored row, so new values must be appended.

### 11. The category decides whether a transaction is income or expense

**Context.** The Add form had no income/expense switch and always saved an *expense*, so a "Salary" transaction was subtracted from your balance and the income total never moved.

**Decision.** A transaction takes its type from its category (a *Salary* category is income). Category type is the single source of truth. A one-time migration (v3) repaired existing rows, and marked them unsynced so the fix also reaches Supabase.

**Consequences.** Fewer inputs, no way for a category and its transactions to disagree. Cost: to record income you need an income category, and the form shows no explicit type.

### 12. A few generic operations use raw SQL

**Context.** Saving pulled rows, marking rows synced and soft-deleting are identical for every table. Typed Drift code would need one copy per table, or awkward generics.

**Decision.** `BaseDao` implements them once with `customSelect` / `customUpdate`, passing `readsFrom` / `updates` so Drift's live queries still refresh.

**Consequences.** One implementation, one test. Cost: these queries use snake_case column names and bypass compile-time checking, so a renamed column would only fail at runtime.

---

## Sync

### 13. Two timestamps: `updated_at` and `server_updated_at`

**Context.** To avoid downloading everything each time, a device asks "what changed since I last looked?". If it used the device-written `updated_at`, a phone offline for a week would upload edits stamped last Tuesday, and other devices, whose cursors are already past Tuesday, would never see them.

**Decision.** Each row has **`updated_at`** (device edit time, used to decide who wins) and **`server_updated_at`** (set by a Postgres trigger when the row *arrives*, used as the download cursor).

**Consequences.** Late uploads are always seen, and cursors are based on one clock (the server's). Cost: a server migration with a trigger and an index; a per-user, per-table cursor stored in `sync_cursors`.

### 14. Conflicts: last write wins, per row

**Context.** Two devices can edit the same row while offline. Something must decide.

**Decision.** The newer `updated_at` wins, for the whole row. On a tie the local edit is kept.

**Consequences.** Simple, predictable, no merge UI. Cost: field-level edits are not merged, and it trusts device clocks ([limitations](sync.md#limitations)). For personal finance data edited by one person on a few devices, real conflicts are rare, so this is a reasonable trade.

### 15. Mark-synced only if the row is unchanged

**Context.** Upload takes time. If the user edits a row during it, the old code wrote back the copy it read before uploading, wiping the edit and marking the row synced. The change was lost and never uploaded.

**Decision.** `markAsSynced` is one statement, `UPDATE ... SET is_synced = 1 WHERE id = ? AND updated_at = ?`. If `updated_at` changed, nothing happens and the row goes up next time.

**Consequences.** No lost edits, and it only touches one flag. Verified by a test that edits a row from inside a fake upload.

### 16. The order: pull, then generate, then push

**Decision.** Download first, then create missing fixed transactions, then upload everything unsynced.

**Why.** Pulling first shows us newer edits from other devices *before* we upload ours, so conflicts resolve on the local side rather than overwriting the server blindly. Generating before pushing means the transactions it creates upload in the same run. Tables go parents before children so a transaction never precedes its category.

### 17. Generated transactions get deterministic IDs

**Context.** Two devices, both offline, both open the app on the 1st and both create "Rent, March". With random IDs that's two rent transactions after syncing.

**Decision.** A generated transaction's ID is a UUID v5 of `templateId:year-month`, so every device computes the same ID for the same template and month.

**Consequences.** The second upload is an upsert of the same row: no duplicate, no coordination. Generated rows made before this change have random IDs, so any duplicates that already exist won't merge.

### 18. Fixed transactions are generated on the device

**Context.** Something has to turn "Rent, day 1" into a transaction every month. A server-side scheduled job would work only online and would need infrastructure.

**Decision.** Generate them locally as a step of every sync. The app catches up on all missed months whenever it runs.

**Consequences.** Works offline, no server code. Cost: months are only created when the app runs, so the number doesn't update while the app is closed; and a template is never back-filled before it existed.

### 19. One controller decides when to sync, a widget supplies the triggers

**Context.** Sync should run on start, reconnect, resume, after edits and periodically, but never twice at once, and it must stop when the user signs out.

**Decision.**
- `SyncController` (a `Notifier`) is the single entry point. It runs one sync at a time; requests during a sync collapse into exactly one follow-up. Edits are debounced by 3 seconds.
- `SyncTriggers` is a widget that lives only under `AuthGate`'s signed-in branch, so its lifecycle hooks and timer exist only while someone is signed in.
- Edits are detected by watching `pendingChangesProvider` **rise**, and ignoring drops, so finishing an upload never triggers another sync.

**Consequences.** No sync storms, no loops, automatic cleanup on sign-out, and the "how" (`SyncEngine`) stays independent of the "when".

### 20. Failures are isolated and requests time out

**Context.** A single bad table or a network hang shouldn't block everything else or freeze sync forever. A hanging request also made every later tap wait behind it.

**Decision.** Each sync step runs in its own `try/catch` and errors are collected into one `SyncException`. Every Supabase request has a 30 s timeout. The status button reports the actual message after each tap.

**Consequences.** Partial progress is kept and unsynced rows retry automatically. Users get an explanation instead of an icon change.

---

## Auth and configuration

### 21. Two Google sign-in flows

**Context.** The native Google account picker is available on mobile but not on Windows or Linux.

**Decision.** On Android/iOS use `google_sign_in` and exchange the ID token with Supabase. On Windows/Linux use Supabase's browser OAuth with a custom URL scheme (`com.butters.expense-tracker://login-callback`). On Windows the scheme is registered in the registry at each start, so it always points at the current executable.

**Consequences.** Native experience on phones and a working desktop login. Cost: two code paths to maintain and test by hand; `Login` is not covered by automated tests.

### 22. Configuration lives in an `.env` asset

**Decision.** `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `WEB_CLIENT_ID` come from a git-ignored `.env`, bundled as an asset and read with `flutter_dotenv`.

**Consequences.** Keys stay out of git and are easy to change per environment. Because it ships in the app, it must only ever hold **public** values. The anon key is fine (Row Level Security protects the data), a `service_role` key would not be.

---

## UI

### 23. Summary cards show the current month

**Context.** The dashboard cards used to add up every transaction ever recorded while still being titled "Monthly Income", so the label and the numbers disagreed, and the numbers didn't match the current month's ledger right below them.

**Decision.** `dashboardMetricsProvider` is keyed by `(year, month)` and the cards show the current month, the same scope as the expanded ledger card beneath them.

**Consequences.** The numbers agree with the ledger. It also makes the per-month provider pattern uniform. The Dashboard's month is fixed to "now" today.

### 24. Money colors as a ThemeExtension, plus signs

**Context.** Plain `Colors.green` on white has a contrast ratio of only about 2.5:1, which is hard to read, and fails entirely for people who can't distinguish red and green.

**Decision.**
- `MoneyColors` is a `ThemeExtension` with a darker green/red for light mode and lighter ones for dark mode; each theme registers its own.
- Amounts also carry an explicit sign (`+$12.00` / `-$12.00`), so color is never the only cue.
- A test checks every color against every background it's drawn on for the WCAG AA text ratio (4.5:1).

**Consequences.** Readable in both themes, checked automatically, and one place to change the palette.

### 25. Presentational widgets are separated from data widgets

**Decision.** `LedgerList` only draws what it is given; `MonthlyLedgerList` reads the providers and passes data down. Likewise `Panel` (drawing) and `AsyncPanel` (adapts an `AsyncValue`).

**Consequences.** The drawing code is easy to test with plain lists and no providers, and data wiring is small and in one spot.

---

## Quality

### 26. Tests use a real database and fake the network

**Context.** Bugs in this app live in SQL queries, migrations and sync rules, exactly what mocks would hide.

**Decision.** Tests run against a real **in-memory SQLite** database. Only the network boundary is faked: a `FakeSyncRemote` (an in-memory Supabase) and a `FakeSyncEngine`. Two `AppDatabase`s sharing one `FakeSyncRemote` simulate two devices. Migrations are tested against a frozen copy of the version 1 schema.

**Consequences.** The tests exercise real behavior, run in seconds, and never touch real data. See [Testing](testing.md).

### 27. Generated code is committed

**Decision.** Drift's `*.g.dart` files are checked in.

**Consequences.** A fresh checkout builds and runs without `build_runner`. Cost: generated diffs appear in pull requests; regenerate after any table or DAO change so they never go stale.
