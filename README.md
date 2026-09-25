# Expense Tracker

An **offline-first** personal finance app built with Flutter. Track income and spending, set up
recurring "fixed" transactions (rent, salary, subscriptions), and keep everything in sync across
your devices through Supabase, without ever needing a connection to use the app.

> Everything you see in the app reads from a local SQLite database, so it opens instantly and
> works on a plane. Changes upload in the background whenever the network is available.

## Highlights

- **Works offline.** Add, edit and delete without a connection. A cloud icon in the app bar shows
  how many changes are waiting and syncs on tap.
- **Monthly ledger.** Transactions are grouped by month, with income, spending and cash flow for
  each one, and a category filter.
- **Fixed transactions.** Define rent or a salary once (name, amount, day of the month) and the app
  creates the transaction for every month automatically.
- **Categories you control.** Pick a name, icon, color, and whether it is income or an expense.
  The category decides how a transaction counts.
- **Savings goals and investments** tracked alongside your budget.
- **Multi-device sync** with conflict handling: two devices editing the same row resolve to the
  newest edit, and nothing is lost if an edit happens while an upload is in flight.
- **Google sign-in** on mobile and desktop, one account = one private set of data.
- **Light and dark themes**, with green/red money colors that stay readable on both.

## Documentation

| Read this | To learn about |
|---|---|
| [Features and workflows](docs/features.md) | What the app does, screen by screen, and how each flow works |
| [Tech sheet](docs/tech-sheet.md) | Stack, dependencies, configuration, commands, folder layout |
| [Architecture](docs/architecture.md) | Layers, the Riverpod provider graph, data flow and app startup |
| [Data model](docs/data-model.md) | Every table and column, local and on Supabase, plus migrations |
| [Sync engine](docs/sync.md) | How offline-first sync works, conflict rules, and how to add a synced table |
| [Code guide](docs/code-guide.md) | A tour of the Dart code, class by class |
| [Design decisions](docs/design-decisions.md) | *Why* it was built this way, with the trade-offs |
| [Testing](docs/testing.md) | How the test suite works and how to write new tests |

## Quick start

**Prerequisites:** Flutter (Dart SDK `^3.11.4`), a Supabase project, and a Google OAuth client.

1. **Install packages**
   ```bash
   flutter pub get
   ```
2. **Create a `.env` file** in the project root (it is git-ignored, and bundled as an asset):
   ```env
   SUPABASE_URL=https://<your-project>.supabase.co
   SUPABASE_ANON_KEY=<your publishable / anon key>
   WEB_CLIENT_ID=<your Google web client id>
   ```
3. **Prepare Supabase.** Run
   [`supabase/migrations/20260924000000_offline_sync.sql`](supabase/migrations/20260924000000_offline_sync.sql)
   once in the Supabase SQL Editor. Without it the app still works offline, but every sync fails.
   See the [tech sheet](docs/tech-sheet.md#supabase-setup) for the full setup.
4. **Run it**
   ```bash
   flutter run
   ```
5. **Run the tests**
   ```bash
   flutter test
   ```

Generated files (`*.g.dart`) are committed. You only need to regenerate them after changing a table
or DAO:

```bash
dart run build_runner build --delete-conflicting-outputs
```

## Project status and known limitations

This is an actively developed personal project. Things that are intentionally simple today:

- Transactions can be **added and deleted, but not edited**, and are dated "now" when created.
- The Dashboard lists months from **March 2026** up to the current month (a fixed start).
- The chosen light/dark theme is **not remembered** between launches.
- Savings goals and investments are standalone lists, not yet linked to transactions.

The full list, with context, is in [Features and workflows](docs/features.md#known-limitations).
