import 'package:expense_tracker/providers/core_providers.dart';
import 'package:expense_tracker/screens/dashboard.dart';
import 'package:expense_tracker/screens/login.dart';
import 'package:expense_tracker/widgets/sync_triggers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthGate extends ConsumerWidget
{
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    if (authState.isLoading && !authState.hasValue)
    {
      return const Scaffold(body: Center(child: CircularProgressIndicator()),);
    }

    final userId = ref.watch(currentUserIdProvider);

    if (userId != null)
    {
      // NOTE: SyncTriggers only exists while someone is signed in, so signing out stops syncing
      return const SyncTriggers(child: Dashboard());
    }

    return const Login();
  }
}
