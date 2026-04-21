import 'package:flutter/material.dart';
import 'package:expense_tracker/screens/dashboard.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const ExpenseApp());
}

class AppColors {
  //NOTE: Private constructor prevents anyone from instantiating this class
  AppColors._();

  static const Color primaryBlue = Color(0xFF0D47A1);
  static const Map<String, Map<String, Object>> categories = {
    "Food": {
      "icon": Icon(Icons.restaurant),
      "color": Color(0xFF00E6C4),
    },
    "Transport": {
      "icon": Icon(Icons.train),
      "color": Colors.green,
    },
    "Entertainment": {
      "icon": Icon(Icons.videogame_asset),
      "color": Colors.blue,
    },
    "Shopping": {
      "icon": Icon(Icons.shopping_bag),
      "color": Colors.orange,
    },
    "Utility": {
      "icon": Icon(Icons.electric_bolt),
      "color": Colors.deepPurpleAccent,
    },
    "Health": {
      "icon": Icon(Symbols.health_cross),
      "color": Colors.red,
    },
    "Other": {
      "icon": Icon(Symbols.more_horiz),
      "color": Colors.grey,
    },
  };

}
class ExpenseApp extends StatefulWidget {
  const ExpenseApp({super.key});

  @override
  State<ExpenseApp> createState() => ExpenseAppState();
}

class ExpenseAppState extends State<ExpenseApp> {
  ThemeMode _currentMode = ThemeMode.light;
  // ElevatedButton


  final ThemeData lightTheme = ThemeData(
    textTheme: GoogleFonts.publicSansTextTheme(
      ThemeData.light().textTheme,
    ),
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.light(
      primary: Colors.white,
      secondary:Color(0xFFF5F5F5),
      surface: Color(0xFFFAFAFA),
      outline: Colors.grey.shade300,
      outlineVariant: Color(0xFFF0F0F0),
      error: Colors.redAccent,
    ),
    iconTheme: IconThemeData(
      color: Colors.grey,
      size: 20,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: Colors.grey,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        iconColor: Colors.black,
        iconSize: 16,
        foregroundColor: Colors.black,
        textStyle: TextStyle(
          fontWeight: FontWeight.w500
        )
      )
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4),),
        iconColor: Colors.black,
        iconSize: 16,
        foregroundColor: Colors.black,
        backgroundColor: Color(0xFFF5F5F5),
        textStyle: TextStyle(
          fontWeight: FontWeight.w500
        )
      )
    ),
    // NOTE: This is for old dropdownMenu with no "Data" in the class name
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(),
      labelStyle: TextStyle(
        color: Colors.grey
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.black54),
        borderRadius: BorderRadius.circular(8),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.lightBlue, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    // NOTE: This dropdownMenu is for the Material 3 new dropdown menu
    dropdownMenuTheme: DropdownMenuThemeData(),
    expansionTileTheme: ExpansionTileThemeData(
      iconColor: Colors.black,
    ),
    chipTheme: ChipThemeData(
      selectedColor: Colors.black54,
      labelStyle: TextStyle(
        color: WidgetStateColor.resolveWith((Set<WidgetState> states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return Colors.black;
        })
      )
    ),
  );

  final ThemeData darkTheme = ThemeData(
    textTheme: GoogleFonts.publicSansTextTheme(
      ThemeData.dark().textTheme,
    ),
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
      primary: Color(0xFF1E1E1E),
      secondary:Color(0xFF1A1A1A),
      surface: Color(0xFF121212),
      outline: Color(0xFF333333),
      outlineVariant: Color(0xFF2A2A2A),
      error: Colors.redAccent,
    ),
    iconTheme: IconThemeData(
      color: Colors.white,
      size: 20,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    ),
    textButtonTheme: TextButtonThemeData(
      // NOTE: When styling this, don't put the color in the textStyle,
      // always use foregroundColor for the button style. Otherwise the button
      // and the text will fight on which color to use and break the ripple anim
      style: TextButton.styleFrom(
        iconColor: Colors.white,
        iconSize: 16,
        foregroundColor: Colors.white,
        // NOTE: TextStyle should only be used for sizing/weight
        textStyle: TextStyle(
          fontWeight: FontWeight.w500
        )
      )
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        iconColor: Colors.white,
        iconSize: 16,
        foregroundColor: Colors.white,
        textStyle: TextStyle(
          fontWeight: FontWeight.w500
        )
      )
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(),
      labelStyle: TextStyle(
        color: Colors.blueGrey
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white54),
        borderRadius: BorderRadius.circular(8),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.lightBlueAccent, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      iconColor: Colors.white,
    ),
    chipTheme: ChipThemeData(
      selectedColor: Colors.white54,
      labelStyle: TextStyle(
        color: WidgetStateColor.resolveWith((Set<WidgetState> states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.black;
          }
          return Colors.white;
        })
      )
    ),
  );

  void _toggleTheme() {
    setState(() {
      _currentMode = _currentMode == ThemeMode.light
        ? ThemeMode.dark
        : ThemeMode.light;
    });
  }

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Expense Tracker App',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: _currentMode,
      home: Dashboard(onThemeToggle: _toggleTheme,),
      );
  }
}