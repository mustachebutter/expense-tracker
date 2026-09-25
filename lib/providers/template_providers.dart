import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/providers/core_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final activeTemplatesProvider = StreamProvider<List<Template>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(const []);

  return ref.watch(databaseProvider).templatesDao.watchActiveTemplates(userId);
});
