import 'package:flutter/material.dart';
import 'package:expense_tracker/screens/dashboard.dart';

void main() {
  runApp(const ExpenseApp());
}

class ExpenseApp extends StatelessWidget {
  const ExpenseApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Expense Tracker App',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardColor: const Color(0xFF1E1E1E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF448AFF),
          secondary: Color(0xFF00E676),
        ),
        useMaterial3: true,
        // colorSchemeSeed: Colors.blue,
      ),
      home: const Dashboard(),
      );
  }
}