import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CategoryViewModel extends ChangeNotifier
{
  final _dao = AppDatabase.instance.categoriesDao;

  Stream<List<Category>> get activeCategories
  {
    return _dao.watchAllActiveCategoriesForUser(AuthService.userId);
  }
}