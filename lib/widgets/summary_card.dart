import 'package:flutter/material.dart';

class SummaryCard extends StatelessWidget
{
  final String title;
  final String amount;
  final IconData icon;
  final Color iconColor;

  const SummaryCard({
    super.key, 
    required this.title,
    required this.amount,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color? amountColor = title == "Cash Flow" ? Colors.green : null;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: iconColor, size:28),
          ),
          const SizedBox(width: 16,),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: const TextStyle(fontSize: 12)),
              Text(amount, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: amountColor)),
            ],
          ),
        ],
      ),
    );
  }
}