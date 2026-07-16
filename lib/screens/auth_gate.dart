import 'package:expense_tracker/main.dart';
import 'package:expense_tracker/screens/dashboard.dart';
import 'package:expense_tracker/screens/login.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthGate extends StatelessWidget
{
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
        {
          return const Scaffold(body: Center(child: CircularProgressIndicator()),);
        }

        final session = snapshot.data?.session;

        if (session != null)
        {
          return Dashboard();
        }

        return Login();
      },
    );
  }
}
