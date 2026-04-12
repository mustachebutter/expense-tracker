import 'package:flutter/material.dart';

class SummaryCard extends StatelessWidget
{
  final String title;
  final String amount;
  final IconData icon;
  final Color iconColor;
  final Color amountColor;

  const SummaryCard({
    super.key, 
    required this.title,
    required this.amount,
    required this.icon,
    required this.iconColor,
    required this.amountColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: iconColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: iconColor, size:28),
          ),
          const SizedBox(width: 16,),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              Text(amount, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: amountColor)),
            ],
          ),
        ],
      ),
    );
  }
}