import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:win32_registry/win32_registry.dart';
import 'package:expense_tracker/providers/settings_providers.dart';
import 'package:expense_tracker/providers/theme_provider.dart';
import 'package:expense_tracker/screens/auth_gate.dart';
import 'package:expense_tracker/theme/money_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async{
  // Ensure Flutter engine is ready before we do networking
  WidgetsFlutterBinding.ensureInitialized();
  registerWindowsProtocol();

  await dotenv.load(fileName: ".env");

  await Supabase.initialize(
    url: dotenv.env["SUPABASE_URL"]!,
    publishableKey: dotenv.env["SUPABASE_ANON_KEY"],
  );
  
  // await signInTestUser();
  // NOTE: Loaded before the app starts so settings can be read without waiting
  final preferences = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      child: TransactionApp()
    )
  );
}

void registerWindowsProtocol()
{
  if (Platform.isWindows)
  {
    try
    {
      print("🪟 Attempting to write to Windows Registry...");
      

      final executablePath = Platform.resolvedExecutable;
      print("📍 Executable path: $executablePath");
      const scheme = 'com.butters.expense-tracker';

      final key = CURRENT_USER.create("Software\\Classes\\$scheme");
      key.setValue("URL Protocol", const RegistryValue.string(""));
      
      final commandKey = key.create("shell\\open\\command");
      commandKey.setValue("", RegistryValue.string('"$executablePath" "%1"'));

      commandKey.close();
      key.close();
    }
    catch (e)
    {
      print("❌ Registry Injection Failed: $e");
    }
  }
}


Future<void> signInTestUser() async {
  final supabase = Supabase.instance.client;
  
  // Check if we are already logged in from a previous session
  if (supabase.auth.currentUser != null) {
    print("Already logged in as: ${supabase.auth.currentUser!.id}");
    return;
  }

  try {
    print("Attempting to log in...");
    await supabase.auth.signInWithPassword(
      email: 'test@abc.com',   // <-- Change to your test user's email
      password: 'testuser',  // <-- Change to your test user's password
    );
    print("SUCCESS! Logged in as: ${supabase.auth.currentUser!.id}");
  } catch (e) {
    print("Login failed: $e");
  }
}
class AppConstants {
  //NOTE: Private constructor prevents anyone from instantiating this class
  AppConstants._();

  static const Map<String, IconData> _iconMap = {
    "attach_money": Icons.attach_money,
    "restaurant": Icons.restaurant,
    "train": Icons.train,
    "videogame_asset": Icons.videogame_asset,
    "shopping_bag": Icons.shopping_bag,
    "electric_bolt": Icons.electric_bolt,
    "health_cross": Symbols.health_cross,
    "home": Icons.home,
    "local_grocery_store": Icons.local_grocery_store,
    "directions_car": Icons.directions_car,
    "local_gas_station": Icons.local_gas_station,
    "flight": Icons.flight,
    "school": Icons.school,
    "pets": Icons.pets,
    "fitness_center": Icons.fitness_center,
    "local_cafe": Icons.local_cafe,
    "card_giftcard": Icons.card_giftcard,
    "smartphone": Icons.smartphone,
    "savings": Icons.savings,
    // NOTE: Keep "more_horiz" last, it's the catch-all at the end of the icon picker
    "more_horiz": Symbols.more_horiz,
  };

  // Every icon a category can use, for the icon picker in the category form
  static List<String> get iconKeys => _iconMap.keys.toList();

  // A new category starts with this color until the user picks another one
  static const String defaultCategoryColorHex = "4CAF50";

  static Icon getIcon(String key, {Color? color})
  {
    return Icon(_iconMap[key] ?? Icons.help_outline, color: color);
  }

  static Color getColorFromHex(String colorHex)
  {
    return Color(int.parse("FF${colorHex.toUpperCase()}", radix: 16));
  }

  // The opposite of getColorFromHex: Color(0xFF4CAF50) -> "4CAF50" (alpha dropped)
  static String colorToHex(Color color)
  {
    return (color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, "0").toUpperCase();
  }

  // Black or white, whichever is readable on top of [background]. Used for a category's
  // icon on its colored circle, since the user can pick any color, light or dark
  static Color onColor(Color background)
  {
    return ThemeData.estimateBrightnessForColor(background) == Brightness.dark ? Colors.white : Colors.black;
  }

  static const Color primaryBlue = Color(0xFF0D47A1);
}


class TransactionApp extends ConsumerWidget {
  TransactionApp({super.key});

  final ThemeData lightTheme = ThemeData(
    textTheme: GoogleFonts.publicSansTextTheme(
      ThemeData.light().textTheme,
    ),
    useMaterial3: true,
    brightness: Brightness.light,
    extensions: const [MoneyColors.light],
    colorScheme: ColorScheme.light(
      primary: Colors.white,
      secondary:Color(0xFFF5F5F5),
      surface: Color(0xFFFAFAFA),
      outline: Colors.grey.shade300,
      outlineVariant: Color(0xFFF0F0F0),
      error: Colors.redAccent,
    ),
    iconTheme: IconThemeData(
      color: Colors.black,
      size: 20,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: Colors.black,
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
    // NOTE: Tabs color the selected tab with colorScheme.primary, which this theme uses as a
    // background color (white), so the selected tab was white on white. Set them explicitly
    tabBarTheme: TabBarThemeData(
      labelColor: Colors.black,
      unselectedLabelColor: Colors.black54,
      indicatorColor: Colors.black,
      dividerColor: Color(0xFFF0F0F0),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      iconColor: Colors.black,
    ),
    // NOTE: Same colors as the selected filter chips. Without this the selected segment
    // uses colorScheme.onSecondaryContainer, which ColorScheme doesn't set to a readable color
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        foregroundColor: Colors.black,
        selectedForegroundColor: Colors.white,
        selectedBackgroundColor: Colors.black54,
      ),
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
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Color(0xFFF5F5F5),
      foregroundColor: Colors.black54
    )
  );

  final ThemeData darkTheme = ThemeData(
    textTheme: GoogleFonts.publicSansTextTheme(
      ThemeData.dark().textTheme,
    ),
    useMaterial3: true,
    brightness: Brightness.dark,
    extensions: const [MoneyColors.dark],
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
    // NOTE: Same reason as the light theme, primary is a dark background color here
    tabBarTheme: TabBarThemeData(
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white60,
      indicatorColor: Colors.white,
      dividerColor: Color(0xFF2A2A2A),
    ),
    // NOTE: Dark mode's selected segment used to get black text on a near-black background
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        foregroundColor: Colors.white,
        selectedForegroundColor: Colors.black,
        selectedBackgroundColor: Colors.white54,
      ),
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
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Color(0xFF1A1A1A),
      foregroundColor: Colors.white
    )
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Transaction Tracker App',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ref.watch(themeModeProvider),
      home: const AuthGate(),
    );
  }
}