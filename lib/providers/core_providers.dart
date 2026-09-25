import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/sync_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// NOTE: Everything else reads the DB and Supabase through these providers,
// so tests can swap them out with ProviderScope(overrides: [...])
final databaseProvider = Provider<AppDatabase>((ref) => AppDatabase.instance);

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseProvider).auth.onAuthStateChange;
});

// NOTE: Re-evaluates on every auth event, but only notifies listeners when the id
// actually changes (sign in / sign out), so token refreshes won't rebuild the UI
final currentUserIdProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(supabaseProvider).auth.currentUser?.id;
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  return SyncEngine(ref.watch(databaseProvider), ref.watch(supabaseProvider));
});

extension RequireUserId on Ref
{
  // Use this inside actions (insert/delete) where being logged out is a bug
  String requireUserId()
  {
    final userId = read(currentUserIdProvider);
    if (userId == null) throw StateError("User is not authenticated");
    return userId;
  }
}
