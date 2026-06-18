import 'package:expense_tracker/widgets/panel.dart';
import 'package:flutter/material.dart';

class StreamPanel<T> extends StatelessWidget
{
  final Stream<List<T>> dataStream;
  final Widget Function(BuildContext, T item) elementItemBuilder;
  final ElevatedButton? button;
  final String titleLabel;

  StreamPanel({
    super.key,
    required this.dataStream,
    required this.elementItemBuilder,
    required this.button,
    required this.titleLabel, 
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<T>>(
      stream: dataStream,
      builder: (context, snapshot) {
        final data = snapshot.data ?? [];

        return Panel(
          titleLabel: titleLabel,
          elementItemBuilder: (context, index) {
            return elementItemBuilder(context, data[index]);
          },
          elementCount: data.length,
          button: button,
        );
      }
    );
  }}