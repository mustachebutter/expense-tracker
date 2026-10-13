import 'package:flutter/material.dart';

// NOTE: Material draws switches, checkboxes, radio buttons, spinners, the text cursor and the
// date picker's selected day in colorScheme.primary. This app uses primary as a background
// color (white in light mode, near black in dark mode), so all of those were invisible:
// white on white, black on black. These give them a real accent instead: black in light
// mode and white in dark mode, the same as the selected filter chips
class ControlThemes
{
  // The "on" color of a control, and the color drawn on top of it (a checkmark, a thumb)
  final Color accent;
  final Color onAccent;
  // The "off" color of a control, visible but quieter than the accent
  final Color inactive;

  const ControlThemes({required this.accent, required this.onAccent, required this.inactive});

  static const ControlThemes light = ControlThemes(accent: Colors.black87, onAccent: Colors.white, inactive: Colors.black45);
  static const ControlThemes dark = ControlThemes(accent: Colors.white, onAccent: Colors.black, inactive: Colors.white54);

  WidgetStateProperty<Color?> _selectedOr(Color selected, Color? other)
  {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return other?.withValues(alpha: 0.38);
      return states.contains(WidgetState.selected) ? selected : other;
    });
  }

  CheckboxThemeData get checkbox => CheckboxThemeData(
    fillColor: _selectedOr(accent, Colors.transparent),
    checkColor: WidgetStatePropertyAll(onAccent),
    side: BorderSide(color: inactive, width: 2),
  );

  RadioThemeData get radio => RadioThemeData(fillColor: _selectedOr(accent, inactive));

  SwitchThemeData get switchTheme => SwitchThemeData(
    thumbColor: _selectedOr(onAccent, inactive),
    trackColor: _selectedOr(accent, Colors.transparent),
    trackOutlineColor: _selectedOr(accent, inactive),
  );

  ProgressIndicatorThemeData get progressIndicator => ProgressIndicatorThemeData(color: accent);

  TextSelectionThemeData get textSelection => TextSelectionThemeData(
    cursorColor: accent,
    selectionColor: Colors.lightBlue.withValues(alpha: 0.4),
    selectionHandleColor: Colors.lightBlue,
  );

  DatePickerThemeData get datePicker => DatePickerThemeData(
    dayBackgroundColor: _selectedOr(accent, null),
    dayForegroundColor: _selectedOr(onAccent, null),
    yearBackgroundColor: _selectedOr(accent, null),
    yearForegroundColor: _selectedOr(onAccent, null),
    todayBackgroundColor: _selectedOr(accent, null),
    todayForegroundColor: _selectedOr(onAccent, accent),
    todayBorder: BorderSide(color: accent),
  );
}
