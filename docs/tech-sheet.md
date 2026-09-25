# Tech sheet

A quick reference for the stack, dependencies, configuration and day-to-day commands.

**Contents**

- [At a glance](#at-a-glance)
- [Dependencies](#dependencies)
- [Platforms](#platforms)
- [Configuration](#configuration)
- [Supabase setup](#supabase-setup)
- [Commands](#commands)
- [Folder layout](#folder-layout)
- [Code generation](#code-generation)
- [App icon](#app-icon)

---

## At a glance

| | |
|---|---|
| **Framework** | Flutter (Material 3) |
| **Language** | Dart, SDK `^3.11.4` |
| **State management** | Riverpod 3 (`flutter_riverpod ^3.4.3`) |
| **Local database** | SQLite through Drift (`drift ^2.33.0`) |
| **Backend** | Supabase: Postgres, Auth and Row Level Security (`supabase_flutter ^2.12.4`) |
| **Auth** | Google sign-in (`google_sign_in ^7.2.0`) + Supabase Auth |
| **Architecture** | Offline-first: UI reads only the local database; a sync engine reconciles with Supabase |
| **Tests** | `flutter_test`, in-memory SQLite, fakes for Supabase (roughly 90 tests) |
| **Static analysis** | `flutter_lints` |

## Dependencies

### Runtime

| Package | Version | What it is used for |
|---|---|---|
| `flutter_riverpod` | ^3.4.3 | State management and dependency injection ([Architecture](architecture.md#riverpod-provider-graph)) |
| `drift` | ^2.33.0 | Type-safe SQLite: tables, queries, live streams, migrations |
| `sqlite3_flutter_libs` | ^0.6.0+eol | Bundles the SQLite native library for mobile and desktop |
| `path_provider` | ^2.1.5 | Finds the documents folder where `db.sqlite` is stored |
| `path` | ^1.9.1 | Joins file paths |
| `supabase_flutter` | ^2.12.4 | Supabase client: auth, database access, session persistence |
| `google_sign_in` | ^7.2.0 | Native Google sign-in on mobile |
| `flutter_dotenv` | ^6.0.1 | Loads `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `WEB_CLIENT_ID` from `.env` |
| `connectivity_plus` | ^7.3.1 | Detects whether the device has a network connection |
| `uuid` | ^4.5.3 | Random (v4) row IDs and deterministic (v5) IDs for generated fixed transactions |
| `intl` | ^0.20.2 | Date formatting (e.g. `MMMM yyyy`) |
| `google_fonts` | ^8.0.2 | The Public Sans typeface |
| `material_symbols_icons` | ^4.2928.1 | A few extra icons (health cross, "more") |
| `flutter_colorpicker` | ^1.1.0 | The color wheel in the category form |
| `app_links` | ^7.0.0 | Deep link support for the desktop OAuth redirect (not imported directly by app code) |
| `win32_registry` | ^3.0.3 | Registers the `com.butters.expense-tracker://` URL scheme on Windows |
| `cupertino_icons` | ^1.0.8 | Default Flutter icon font |

### Development

| Package | What it is used for |
|---|---|
| `drift_dev` + `build_runner` | Generate the `*.g.dart` files for tables and DAOs |
| `flutter_launcher_icons` | Generates every platform's app icon from one image |
| `flutter_lints` | The recommended lint set |
| `flutter_test` | Unit and widget tests |

> `pubspec.lock` is listed in `.gitignore` (`*.lock`), so exact transitive versions are resolved fresh
> on each machine. Consider committing it for an app if you want reproducible builds.

## Platforms

Flutter platform folders exist for Android, iOS, macOS, Windows, Linux and web. Sign-in has two paths:

| Platforms | Sign-in path |
|---|---|
| Android, iOS (and macOS, web, which take the same branch in code) | Native `google_sign_in`, then `signInWithIdToken` |
| Windows, Linux | Browser OAuth with a custom URL scheme redirect |

On **Windows**, `registerWindowsProtocol()` in [`main.dart`](../lib/main.dart) writes the URL scheme to
`HKEY_CURRENT_USER\Software\Classes\com.butters.expense-tracker` at every start, pointing at the
current executable, so the browser can hand the login result back to the app.

## Configuration

### `.env`

Create it in the project root. It is **git-ignored**, and declared as a Flutter asset in
`pubspec.yaml`, so it is bundled into the app and loaded at startup (`dotenv.load`).

```env
SUPABASE_URL=https://<your-project>.supabase.co
SUPABASE_ANON_KEY=<publishable / anon key>
WEB_CLIENT_ID=<Google OAuth *web* client id>
```

| Key | Used by |
|---|---|
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | `Supabase.initialize` in `main()` |
| `WEB_CLIENT_ID` | `GoogleSignIn.initialize(serverClientId: ...)` on the native sign-in path |

> **Security note.** Because `.env` is an asset, its values ship inside the app binary. That is fine for
> the *publishable/anon* key, which is designed to be public and is protected by Row Level Security.
> **Never put a `service_role` key in this file.**

### Where the local data lives

The SQLite file is `db.sqlite` in the platform's documents directory
([`_openConnection`](../lib/database.dart)). The path is printed to the console when the database first opens.

## Supabase setup

1. Create a Supabase project and enable the **Google** provider under *Authentication*.
2. Make sure the tables `categories`, `templates` and `transactions` exist with the columns listed in
   [Data model: Supabase tables](data-model.md#supabase-tables), each with **Row Level Security** so users
   only access their own rows. (These three were created in the Supabase dashboard and are not part of the
   migrations in this repo.)
3. Run [`supabase/migrations/20260924000000_offline_sync.sql`](../supabase/migrations/20260924000000_offline_sync.sql)
   in the **SQL Editor**. It:
   - adds `updated_at` and `server_updated_at` to every synced table,
   - installs a trigger that sets `server_updated_at = now()` on every insert or update,
   - adds an index on `(user_id, server_updated_at)`,
   - creates `savings_goals` and `investments` (with RLS policies).
4. Optionally run the sanity check at the bottom of that file to find categories uploaded without a `type`.

## Commands

| Task | Command |
|---|---|
| Install packages | `flutter pub get` |
| Run the app | `flutter run` (add `-d windows`, `-d chrome`, or a device id) |
| Run all tests | `flutter test` |
| Run one test file | `flutter test test/daos/transactions_dao_test.dart` |
| Run one test by name | `flutter test --plain-name "clamps billing day"` |
| Static analysis | `flutter analyze` |
| Regenerate Drift code | `dart run build_runner build --delete-conflicting-outputs` |
| Regenerate app icons | `python tool/make_app_icon.py` then `dart run flutter_launcher_icons` |

## Folder layout

```text
expense-tracker/
├── lib/
│   ├── main.dart                 App entry point, AppConstants, light/dark themes
│   ├── database.dart             Drift tables, enums, AppDatabase, migrations
│   ├── sync_engine.dart          Offline-first sync (pull, generate, push)
│   ├── daos/                     One Drift accessor per table (+ BaseDao)
│   ├── providers/                Riverpod providers and "Actions" classes
│   ├── screens/                  Login, AuthGate, Dashboard, Settings
│   ├── widgets/                  Reusable UI: ledger, panels, forms/, sync widgets
│   ├── theme/                    MoneyColors theme extension
│   └── extensions/               Small helpers (List.sumBy)
├── test/                         Mirrors lib/: daos, database, providers, screens, sync, theme, widgets
│   └── helpers/                  In-memory DB, fake Supabase, fake sync engine, pumpApp
├── supabase/migrations/          SQL to run on the server
├── tool/make_app_icon.py         Draws the app icon
├── assets/icon/                  Generated icon images
└── docs/                         This documentation
```

## Code generation

Drift generates `database.g.dart` and one `*.g.dart` per DAO. **They are committed**, so a fresh checkout
builds without running `build_runner`. Run it again whenever you:

- add, remove or change a table or column in `database.dart`, or
- add a DAO or change its `@DriftAccessor(tables: [...])` list.

If you change a table, also bump `schemaVersion` and add a step to `onUpgrade`
(see [Migrations](data-model.md#migrations)).

## App icon

The icon (a wallet with bills and a gold clasp on deep blue) is drawn by
[`tool/make_app_icon.py`](../tool/make_app_icon.py) with Pillow. It writes the source images into
`assets/icon/` (a full icon plus separate foreground/background layers for Android's adaptive icons) and
the multi-size Windows `.ico`. Then `dart run flutter_launcher_icons` generates the Android, iOS, macOS and
web sizes from the config at the bottom of `pubspec.yaml`.

Windows is deliberately excluded from `flutter_launcher_icons` (`windows: generate: false`), because that
tool writes only a 256 px icon, while the script writes every size from 16 px up so the taskbar icon
stays sharp.

> After running `flutter_launcher_icons`, check `git status`: the package can rewrite
> `ios/Runner.xcodeproj/project.pbxproj` with an invalid value for
> `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS`. Revert that file if it shows up.
