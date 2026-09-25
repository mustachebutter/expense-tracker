import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/screens/auth_gate.dart';
import 'package:expense_tracker/screens/dashboard.dart';
import 'package:expense_tracker/screens/login.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';
import '../helpers/test_database.dart';

void main()
{
  late AppDatabase db;

  setUp(() => db = createTestDatabase());
  tearDown(() => db.close());

  testWidgets("shows Login when signed out", (tester) async {
    await pumpApp(tester, const AuthGate(), db: db, userId: null);
    await tester.pumpAndSettle();

    expect(find.byType(Login), findsOneWidget);
    expect(find.byType(Dashboard), findsNothing);
  });

  testWidgets("shows the Dashboard and starts a sync for the user when signed in", (tester) async {
    final syncEngine = FakeSyncEngine();

    await pumpApp(tester, const AuthGate(), db: db, userId: userA, syncEngine: syncEngine);
    await tester.pumpAndSettle();

    expect(find.byType(Dashboard), findsOneWidget);
    expect(syncEngine.syncedUserIds, [userA]);
  });
}
