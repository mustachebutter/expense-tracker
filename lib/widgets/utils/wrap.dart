import 'package:flutter/material.dart';

class WrapLayout extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final WrapAlignment alignment;

  const WrapLayout(
    {
      super.key,
      required this.children,
      this.spacing = 0,
      this.runSpacing = 0,
      this.alignment = WrapAlignment.center,
    }
  );

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing,
      alignment: alignment,
      children: children,
    );
  }
}