import 'package:expense_tracker/widgets/panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AsyncPanel<T> extends StatelessWidget
{
  // NOTE: Pass ref.watch(someStreamProvider) here
  final AsyncValue<List<T>> asyncData;
  final Widget Function(BuildContext, T item) elementItemBuilder;
  final ElevatedButton? button;
  final String titleLabel;

  const AsyncPanel({
    super.key,
    required this.asyncData,
    required this.elementItemBuilder,
    required this.button,
    required this.titleLabel,
  });

  @override
  Widget build(BuildContext context) {
    // NOTE: value keeps showing the previous list while a new one loads
    final data = asyncData.value ?? [];

    return Panel(
      titleLabel: titleLabel,
      elementItemBuilder: (context, index) {
        return elementItemBuilder(context, data[index]);
      },
      elementCount: data.length,
      button: button,
    );
  }
}
