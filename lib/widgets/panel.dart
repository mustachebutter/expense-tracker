import 'package:flutter/material.dart';

class Panel extends StatelessWidget {
  final Widget Function(BuildContext, int) elementItemBuilder;
  final int elementCount;
  // ZZZ TODO: Needs to be null
  final ElevatedButton button;
  final String titleLabel;
  // final Function onButtonPressed;
  // final String buttonLabel;
  // final Icon buttonIcon;

  const Panel({ 
    super.key,
    required this.elementItemBuilder,
    required this.elementCount,
    required this.button,
    required this.titleLabel, 
  });

  @override
  Widget build(BuildContext context){
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(titleLabel, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),),
                button,
              ],
            )
          ),

          Divider(height: 1, color: colorScheme.outlineVariant,),
          ListView.separated(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            itemCount: elementCount,
            separatorBuilder: (context, index) => Divider(height: 1, color: colorScheme.outlineVariant,),
            itemBuilder: elementItemBuilder,
          )          
        ],
      ),
    );
  }
}