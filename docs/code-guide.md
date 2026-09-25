# Code guide

A tour of the Dart code, class by class. Read it next to the source; each section names the file. For the *why*
behind these choices see [Design decisions](design-decisions.md).

**Contents**

- [Suggested reading order](#suggested-reading-order)
- [`main.dart`](#maindart)
- [`database.dart`](#databasedart)
- [`daos/`](#daos)
- [`providers/`](#providers)
- [`sync_engine.dart`](#sync_enginedart)
- [`screens/`](#screens)
- [`widgets/`](#widgets)
- [`theme/` and `extensions/`](#theme-and-extensions)
- [Walkthroughs](#walkthroughs)
- [Unused or unfinished code](#unused-or-unfinished-code)

---

## Suggested reading order

1. [`lib/database.dart`](../lib/database.dart): the data everything else is about.
2. [`lib/daos/transactions_dao.dart`](../lib/daos/transactions_dao.dart): the richest DAO.
3. [`lib/providers/core_providers.dart`](../lib/providers/core_providers.dart) and
   [`transaction_providers.dart`](../lib/providers/transaction_providers.dart): how data reaches widgets.
4. [`lib/screens/dashboard.dart`](../lib/screens/dashboard.dart): the main screen.
5. [`lib/sync_engine.dart`](../lib/sync_engine.dart), then [Sync](sync.md).

## `main.dart`

[`lib/main.dart`](../lib/main.dart) holds four things:

| Symbol | What it does |
|---|---|
| `main()` | Initialises Flutter, registers the Windows URL scheme, loads `.env`, initialises Supabase, then runs `ProviderScope(child: TransactionApp())`. See [App startup](architecture.md#app-startup). |
| `registerWindowsProtocol()` | On Windows only: writes `HKCU\Software\Classes\com.butters.expense-tracker` so the browser can return the Google OAuth result to the app. Wrapped in `try/catch`; a failure only prints a message. |
| `AppConstants` | A non-instantiable holder (private constructor) for shared UI constants and helpers. |
| `TransactionApp` | A `ConsumerWidget` that builds the `MaterialApp` with the light and dark `ThemeData`, `themeMode: ref.watch(themeModeProvider)` and `AuthGate` as home. |

**`AppConstants` members**

| Member | Purpose |
|---|---|
| `_iconMap` / `iconKeys` | The 20 icons a category may use, keyed by a string (`"restaurant"`). The key, not the icon, is what gets stored in the database. `"more_horiz"` is kept last as the catch-all. |
| `getIcon(key, {color})` | Key to `Icon`; falls back to a help icon for unknown keys. |
| `getColorFromHex` / `colorToHex` | `"4CAF50"` to `Color` and back. Categories store six hex digits without `#` or alpha. |
| `onColor(background)` | Black or white, whichever is readable on top of a user-picked color (`ThemeData.estimateBrightnessForColor`). |
| `defaultCategoryColorHex` | Starting color for a new category. |

`TransactionApp` defines `lightTheme` and `darkTheme`. Each sets the Public Sans text theme, the color scheme,
button/chip/segmented-button/input themes, and registers its own [`MoneyColors`](#theme-and-extensions) through
`extensions: const [MoneyColors.light]` (or `.dark`).

## `database.dart`

[`lib/database.dart`](../lib/database.dart) declares the schema. See [Data model](data-model.md) for every column.

```dart
@DriftDatabase(
  tables: [Categories, Transactions, Templates, SavingsGoals, Investments, SyncCursors],
  daos: [CategoriesDao, TransactionsDao, TemplatesDao, SavingsGoalsDao, InvestmentsDao]
)
class AppDatabase extends _$AppDatabase { ... }
```

| Symbol | Notes |
|---|---|
| `enum TransactionType { income, expense }` | Stored as an int. **Order matters.** |
| Table classes | `Categories`, `Transactions`, `Templates`, `SavingsGoals`, `Investments`, `SyncCursors`. Each extends Drift's `Table`; `id` uses `clientDefault(() => Uuid().v4())`. |
| `AppDatabase.instance` | Lazy singleton. `AppDatabase._internal()` opens the real file through `_openConnection()`. |
| `AppDatabase.forTesting(executor)` | Lets tests pass an in-memory database, so no test touches the real `db.sqlite`. |
| `schemaVersion` / `migration` | Currently version 3. See [Migrations](data-model.md#migrations). |
| `_repairTransactionTypes()` | The one-off SQL fix run when upgrading from below version 3. |
| `nextUpdatedAt(previous)` | Free function: returns "now", or `previous + 1 s` if that is later. **Use it on every local update.** |
| `_openConnection()` | A `LazyDatabase`: the file (`db.sqlite` in the documents folder) opens on the first query, in a background isolate (`NativeDatabase.createInBackground`). |

## `daos/`

A DAO (data access object) is a Drift *accessor* that owns the queries for one table. They all extend
[`BaseDao`](../lib/daos/base_dao.dart) and are declared with `@DriftAccessor(tables: [...])`.

### `BaseDao<T, D>`

| Method | Purpose |
|---|---|
| `insertRow`, `updateRow`, `hardDeleteRow` | Thin wrappers over Drift's insert / replace / delete. |
| `saveServerRows(rows)` | Applies rows downloaded from Supabase, skipping any with a newer unsynced local edit, inside one database transaction. See [Conflicts](sync.md#conflicts-which-edit-wins). |
| `markAsSynced(id, updatedAt)` | `UPDATE ... SET is_synced = 1 WHERE id = ? AND updated_at = ?`: only marks a row synced if it hasn't changed since it was read. |
| `softDeleteById(id, userId)` | Sets `is_deleted`, clears `is_synced`, moves `updated_at` forward. Scoped by user. |
| `watchAll()`, `getAll()` | **Not** filtered by user or deleted state. Used by tests; don't use them in the UI. |

The last four use raw SQL (`customSelect` / `customUpdate`) so one implementation serves every table. They pass `readsFrom` /
`updates` so Drift's live queries still refresh when these statements run.

### The concrete DAOs

Every method takes a `userId`.

| DAO | Methods |
|---|---|
| `CategoriesDao` | `getCategories`, `getActiveCategories`, `watchCategories`, `watchActiveCategories` (active, not deleted, sorted by name), `getUnsynced` |
| `TemplatesDao` | `watchTemplates`, `watchActiveTemplates`, `getUnsynced` |
| `SavingsGoalsDao` | `watchActiveSavingsGoals`, `getUnsynced` |
| `InvestmentsDao` | `watchActiveInvestments`, `getUnsynced` |
| `TransactionsDao` | see below |

### `TransactionsDao`

| Member | Purpose |
|---|---|
| `getTransactionById(id, userId)` | One transaction, only if it belongs to the user. |
| `getEarliestTransactionDate(userId)` | Where fixed-transaction generation starts. |
| `watchDashboardMetrics(year, month, userId)` | Live `DashboardMetrics` for a month, via `selectOnly` with `SUM(...)` filtered by type. |
| `watchVisibleTransactionsWithCategory(year, month, userId)` | A month's transactions joined with categories (`TransactionWithCategory`), newest first. |
| `watchIncomes`, `watchIncomesForMonth` | Income-only live queries. |
| `softDelete(transaction)` | Marks one transaction deleted and unsynced. |
| `generateFixedTransactionsForMonth(year, month, userId)` | Creates missing transactions from templates. See [Fixed transactions](features.md#fixed-transactions). |
| `getUnsynced(userId)` | Feeds the push step. |
| `fixedTransactionId(templateId, year, month)` | *(top-level function)* the deterministic UUID v5. |

Supporting types: `TransactionWithCategory` (a transaction plus its `Category`) and the `DashboardMetrics` record.

## `providers/`

Riverpod providers, one file per area. See [Architecture](architecture.md#riverpod-provider-graph) for the graph and catalogue.
There are two recurring shapes.

**1. A live list**: a `StreamProvider` that watches the user and the database, then a DAO stream.

```dart
final activeCategoriesProvider = StreamProvider<List<Category>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(const []);

  return ref.watch(databaseProvider).categoriesDao.watchActiveCategories(userId);
});
```

**2. An *Actions* class**: the only place that changes rows.

```dart
class CategoryActions
{
  final Ref _ref;
  CategoryActions(this._ref);

  CategoriesDao get _dao => _ref.read(databaseProvider).categoriesDao;

  Future<void> add({required String name, required String colorHex,
                    required String iconKey, required TransactionType type})
  {
    return _dao.insertRow(CategoriesCompanion.insert(
      name: name, colorHex: colorHex, iconKey: iconKey, type: type,
      userId: _ref.requireUserId(),               // the signed in user owns it
    ));
  }

  Future<void> update(Category edited)
  {
    if (edited.userId != _ref.requireUserId()) throw StateError("Can't edit another user's category");
    return _dao.updateRow(edited.copyWith(isSynced: false, updatedAt: nextUpdatedAt(edited.updatedAt)));
  }

  Future<void> delete(String id) => _dao.softDeleteById(id, _ref.requireUserId());
}
```

| File | Contents |
|---|---|
| `core_providers.dart` | `databaseProvider`, `supabaseProvider`, `authStateProvider`, `currentUserIdProvider`, `syncRemoteProvider`, `syncEngineProvider`, and the `Ref.requireUserId()` extension. |
| `category_providers.dart`, `template_providers.dart`, `savings_goal_providers.dart`, `investment_providers.dart` | The live list plus `CategoryActions` / `TemplateActions` / `SavingsGoalActions` / `InvestmentActions`. `TemplateActions.add` starts the template *this month*. |
| `transaction_providers.dart` | `dashboardMetricsProvider` and `monthlyTransactionsProvider` (both `autoDispose.family` keyed by a `YearMonth` record), `ActiveFilterNotifier` / `activeFilterProvider`, and `TransactionActions` (`add`, `softDeleteById`). |
| `theme_provider.dart` | `ThemeModeNotifier` with `toggle()`: flips between dark and light (starts on system). |
| `sync_providers.dart` | `connectivityProvider`, `isOnlineProvider`, `pendingChangesProvider`, `SyncStatus`, `SyncState`, `SyncController` and `syncControllerProvider`. |

`TransactionActions.add` overwrites the companion's `userId` with the signed-in user's, so the UI never needs to know it.
`softDeleteById` returns the deleted `Transaction` so the caller can show its name in a snackbar.

## `sync_engine.dart`

Fully described in [Sync](sync.md). The pieces:

| Symbol | Role |
|---|---|
| `SyncRemote` (abstract) | The server side: `upsert(table, rows)` and `fetchChanges(table, userId, since)`. |
| `SupabaseSyncRemote` | The real one, using `supabase_flutter`. Pages of 1000 rows, 30 s timeouts. |
| `_SyncTable<D>` | Everything needed to sync one table: its DAO, `getUnsynced`, `keyOf`, `toJson`, `fromJson`, plus `pull` and `push`. |
| `SyncEngine` | Holds the `_tables` list and runs the three steps in `runSync`. Constructed as `SyncEngine(db, remote)`. |
| `SyncException` | Aggregates per-step errors: `"Sync failed for pull categories: ..."`. |

`SyncRemote` is an interface on purpose: tests give the engine an in-memory fake, so the real logic can be tested with two simulated devices and no network.

## `screens/`

| Screen | File | Notes |
|---|---|---|
| `Login` | `login.dart` | A `StatefulWidget` with a loading flag. `signInWithGoogle()` chooses between the desktop OAuth redirect and the native flow. It has no navigation code: `AuthGate` reacts to the new session. |
| `AuthGate` | `auth_gate.dart` | A `ConsumerWidget`: spinner, then `SyncTriggers(child: Dashboard())` or `Login()` based on `currentUserIdProvider`. |
| `Dashboard` | `dashboard.dart` | A `ConsumerStatefulWidget`. Watches metrics, categories and the active filter. Builds the layout for narrow or wide screens. `_populateLedgerLists()` builds one `MonthlyLedgerList` per month from the current month back to `_startMonth`. |
| `Settings` | `settings.dart` | A `ConsumerWidget` with four `AsyncPanel`s. `_deleteWithConfirmation` (confirm, delete, snackbar) is shared by all four; `_RowActions` renders the edit/delete buttons. |

## `widgets/`

| Widget | File | What it does |
|---|---|---|
| `AddTransactionDialog` | `add_expense_dialog.dart` | The Add Transaction form. Watches `activeCategoriesProvider`; the saved type comes from the chosen category. It calls back `onTransactionAdded(companion)` and leaves saving to the caller. |
| `LedgerList` | `ledger_list.dart` | A *presentational* widget: given a month's `TransactionWithCategory` list and a filter, it draws the expandable card, totals, Income section and Transactions section. Contains no provider code. |
| `MonthlyLedgerList` | `monthly_ledger_list.dart` | The thin `ConsumerWidget` that feeds `LedgerList` from `monthlyTransactionsProvider` and `activeFilterProvider`. |
| `SummaryCard` | `summary_card.dart` | One dashboard metric: title, formatted amount, icon. |
| `Panel` | `panel.dart` | A titled card with a button and a list of rows (used by Settings). |
| `AsyncPanel<T>` | `async_panel.dart` | `Panel` fed by an `AsyncValue<List<T>>`; keeps showing the previous list while a new one loads. |
| `SyncStatusButton` | `sync_status_button.dart` | The cloud icon; tap to sync and see the result. |
| `SyncTriggers` | `sync_triggers.dart` | Starts syncs on startup, reconnect, resume, edits and a timer. |
| Form dialogs | `forms/category_form_dialog.dart`, `template_form_dialog.dart`, `savings_goal_form_dialog.dart`, `investment_form_dialog.dart` | Each has a `showXxxFormDialog(context, ...)` function (returns `true` if saved) and a `ConsumerStatefulWidget`. Pass the row to edit it (the parameter is `category`, `template`, `goal` or `investment`), or nothing to add. `showTemplateFormDialog` also takes `initialType`, used by the ledger's *Add Fixed* button. |
| `form_helpers.dart` | `forms/form_helpers.dart` | Shared pieces: `amountInputFormatters`, validators `requiredText` / `positiveAmount` / `zeroOrMoreAmount`, `amountText`, `confirmDelete`, `TransactionTypeSelector` (the Income/Expense toggle) and `FormDialogScaffold` (the dialog frame with Cancel and Save, validation and error handling). |

The split between `LedgerList` (pure drawing) and `MonthlyLedgerList` (data) is deliberate: the drawing widget is easy to
test with plain lists, and the data wiring stays in one small place.

## `theme/` and `extensions/`

**[`MoneyColors`](../lib/theme/money_colors.dart)** is a Flutter `ThemeExtension`, the sanctioned way to add custom colors to
`ThemeData`. Each theme registers its own set, and widgets read the right one with `MoneyColors.of(context)`.

| Member | Purpose |
|---|---|
| `income`, `expense` | Green 800 / Red 800 on light; Green 300 / Red 200 on dark |
| `forType(TransactionType)` | Color for a transaction |
| `forBalance(double)` | Green for zero or above, red below (cash flow) |
| `lerp`, `copyWith` | Required by `ThemeExtension`; `lerp` blends colors while the theme animates |
| `signedAmount(amount, type)` | *(top-level)* `"+$12.00"` or `"-$12.00"` |

**[`ListMath.sumBy`](../lib/extensions/number.dart)** is an extension on `List<T>`: `items.sumBy((item) => item.amount)`. The
ledger uses it for its totals.

## Walkthroughs

### Adding a transaction, end to end

1. `Dashboard` shows `AddTransactionDialog`; the user fills it in and taps **Add Transaction**.
2. The dialog finds the selected `Category`, builds a `TransactionsCompanion` (with `type: category.type`, `date: now`) and calls `onTransactionAdded`.
3. `Dashboard` calls `ref.read(transactionActionsProvider).add(companion)`.
4. `TransactionActions.add` stamps `userId` with `requireUserId()` and calls `TransactionsDao.insertRow`.
5. Drift writes the row (`is_synced = false`, `updated_at = now`).
6. Every live query that reads `transactions` re-runs: `dashboardMetricsProvider` and `monthlyTransactionsProvider` emit, so the summary cards and the ledger update.
7. `pendingChangesProvider` also re-runs and its count rises. `SyncTriggers` sees the increase and calls `scheduleSync()`.
8. Three seconds later `SyncController.syncNow()` runs `SyncEngine.runSync`, which uploads the row and marks it synced. The badge on the cloud icon disappears.

### Editing a category

1. Settings: tap the pencil, then `showCategoryFormDialog(context, category: item)` opens `CategoryFormDialog` pre-filled.
2. On Save, `FormDialogScaffold` validates, then runs the form's `_save`, which calls `categoryActionsProvider.update(category.copyWith(...))`.
3. `CategoryActions.update` checks ownership, sets `isSynced: false` and `updatedAt: nextUpdatedAt(...)`, and `updateRow`s it.
4. `activeCategoriesProvider` emits, so Settings, the Add form's dropdown and the filter chips all update together.

### Signing in

1. `Login` calls `signInWithGoogle()`, which either opens the browser (Windows/Linux) or shows the native picker and calls `signInWithIdToken`.
2. Supabase emits an `onAuthStateChange` event; `authStateProvider` forwards it.
3. `currentUserIdProvider` re-evaluates to the new ID; `AuthGate` rebuilds and shows the Dashboard inside `SyncTriggers`.
4. `SyncTriggers` runs the first sync, and every data provider starts streaming that user's rows.

## Unused or unfinished code

For honesty and to avoid confusion when browsing:

| Item | State |
|---|---|
| `lib/widgets/expense_card.dart` | Empty file, not referenced. |
| `lib/widgets/utils/layout_builder.dart` (`ResponsiveLayout`), `lib/widgets/utils/wrap.dart` (`WrapLayout`) | Not referenced anywhere. The Dashboard uses `LayoutBuilder` and `MediaQuery` directly. |
| `signInTestUser()` in `main.dart` | A development helper for signing in with a test email/password. Its call in `main()` is commented out. **Its test credentials are hard-coded in the source; remove them if the repository is public.** |
| `TransactionsDao.watchIncomes` / `watchIncomesForMonth` | Implemented, but no screen uses them yet. |
| Debug `print` calls | A few remain (e.g. in `generateFixedTransactionsForMonth`, the sync steps, `_openConnection`). |
