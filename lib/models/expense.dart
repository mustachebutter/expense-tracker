class Expense
{
  final String id;
  final String label;
  final double fixedAmount;
  double variableAmount;
  final List<String> tags;

  Expense({
    required this.id,
    required this.label,
    required this.fixedAmount,
    this.variableAmount = 0.0,
    required this.tags,
  });

  double get total => fixedAmount + variableAmount;
}