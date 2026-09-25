import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_gate.dart'; // Wherever you saved your signInWithGoogle() function

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  bool _isLoading = false;

  Future<void> signInWithGoogle() async
  {
    try
    {

      if (!kIsWeb && (Platform.isWindows || Platform.isLinux))
      {
        await Supabase.instance.client.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: "com.butters.expense-tracker://login-callback",
        );
      }
      else
      {
          await dotenv.load(fileName: ".env");
          final webClientId = dotenv.env["WEB_CLIENT_ID"];
          final GoogleSignIn googleSignIn = GoogleSignIn.instance;

          await googleSignIn.initialize
          (
            serverClientId: webClientId,
          );

          final googleUser = await googleSignIn.authenticate();

          final googleAuthentication = googleUser.authentication;
          final googleIdToken = googleAuthentication.idToken;

          // NOTE: Use this for extra permissions (Drive, Calendar, etc.)
          final scopes = <String>["email", "profile"];
          final googleAuthorization = await googleUser.authorizationClient.authorizationForScopes(scopes)
            ?? await googleUser.authorizationClient.authorizeScopes(scopes);
          final accessToken = googleAuthorization.accessToken;
          
          if (accessToken == null || googleIdToken == null) throw "Missing tokens";

          await Supabase.instance.client.auth.signInWithIdToken(
            provider: OAuthProvider.google,
            idToken: googleIdToken,
            accessToken: accessToken,
          );

          print("✅ Google Sign-In Successful!");
          
        }
      }
    catch (e)
    {
      print("❌ Error: $e");
    } 
  }

  // A wrapper function to handle the loading UI state
  Future<void> _handleGoogleLogin() async {
    setState(() => _isLoading = true);
    
    try {
      // Call the Google v7+ function we wrote earlier!
      await signInWithGoogle(); 
      // Note: We don't need Navigator.push() here! 
      // The AuthGate will see the successful login and swap the screen for us.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Login Failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.account_balance_wallet, size: 80, color: Colors.blueAccent),
              const SizedBox(height: 24),
              const Text(
                "Expense Tracker",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                "Sign in to sync your budget offline.",
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 48),

              // The Google Sign-In Button
              _isLoading 
                ? const CircularProgressIndicator()
                : ElevatedButton.icon(
                    onPressed: _handleGoogleLogin,
                    // icon: Image.network(
                    //   'https://upload.wikimedia.org/wikipedia/commons/c/c1/Google_%22G%22_logo.svg',
                    //   height: 24,
                    // ), // Or use an asset image if you downloaded the Google logo
                    label: const Text(
                      "Sign in with Google",
                      style: TextStyle(fontSize: 16, color: Colors.black87),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}