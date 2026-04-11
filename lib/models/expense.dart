class Expense
{
  final String id;
  final String label;
  final double fixedAmount;
  double variableAmount;
  final DateTime date;
  final List<String> tags;
  bool isEditing = false;

  Expense({
    required this.id,
    required this.label,
    required this.fixedAmount,
    this.variableAmount = 0.0,
    required this.date,
    required this.tags,
  });

  double get total => fixedAmount + variableAmount;
}