import 'package:flutter/material.dart';

// A text field that suggests places already used (e.g. "Sydney" after typing "sy"), so the
// same place is spelled the same way each time and the location filters group it together
class PlaceField extends StatefulWidget
{
  final String label;
  final IconData icon;
  final TextEditingController controller;
  final List<String> suggestions;

  const PlaceField({
    super.key,
    required this.label,
    required this.icon,
    required this.controller,
    required this.suggestions,
  });

  @override
  State<PlaceField> createState() => _PlaceFieldState();
}

class _PlaceFieldState extends State<PlaceField>
{
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (value) {
        final typed = value.text.trim().toLowerCase();
        if (typed.isEmpty) return const [];
        return widget.suggestions.where((place) {
          final lower = place.toLowerCase();
          // Don't suggest exactly what's already there
          return lower.contains(typed) && lower != typed;
        });
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(labelText: widget.label, prefixIcon: Icon(widget.icon)),
          textCapitalization: TextCapitalization.words,
          onFieldSubmitted: (_) => onSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 360),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  for (final option in options)
                    ListTile(
                      dense: true,
                      title: Text(option),
                      onTap: () => onSelected(option),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
