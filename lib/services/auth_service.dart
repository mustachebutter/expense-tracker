import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService
{
  static String get userId
  {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) throw Exception("User is not authenticated");

    return user.id;
  }
}