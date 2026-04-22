import 'package:flutter/material.dart';

class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget desktop;
  final double maxWidth;

  const ResponsiveLayout({super.key, required this.mobile, required this.desktop, this.maxWidth = 600.0});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) 
      {
        if (constraints.maxWidth < maxWidth) 
        {
          return mobile;
        }
        else
        {
          return desktop;
        }
      },
    );
  }
}