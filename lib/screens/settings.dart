import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/main.dart';
import 'package:expense_tracker/providers/category_providers.dart';
import 'package:expense_tracker/providers/investment_providers.dart';
import 'package:expense_tracker/providers/savings_goal_providers.dart';
import 'package:expense_tracker/providers/template_providers.dart';
import 'package:expense_tracker/widgets/async_panel.dart';
import 'package:expense_tracker/widgets/forms/category_form_dialog.dart';
import 'package:expense_tracker/widgets/forms/form_helpers.dart';
import 'package:expense_tracker/widgets/forms/investment_form_dialog.dart';
import 'package:expense_tracker/widgets/forms/savings_goal_form_dialog.dart';
import 'package:expense_tracker/widgets/forms/template_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Settings extends ConsumerWidget {
  const Settings({super.key});

  // Asks first, deletes, then confirms with a snackbar
  Future<void> _deleteWithConfirmation(
    BuildContext context, {
    required String kind,
    required String name,
    required String consequence,
    required Future<void> Function() delete,
  }) async
  {
    final confirmed = await confirmDelete(
      context,
      title: "Delete $kind?",
      message: "\"$name\" will be deleted on all your devices. $consequence",
    );
    if (!confirmed) return;

    await delete();
    if (context.mounted)
    {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Deleted $name")));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final TextStyle titleTextStyle = screenWidth < 600
        ? TextStyle(fontSize: 28, fontWeight: FontWeight.bold)
        : TextStyle(fontSize: 32, fontWeight: FontWeight.bold);
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final TextStyle amountStyle = TextStyle(
      fontWeight: textTheme.displaySmall!.fontWeight,
      fontSize: textTheme.displaySmall!.fontSize,
    );
    final TextStyle detailStyle = TextStyle(
      fontWeight: textTheme.titleSmall!.fontWeight,
      fontSize: textTheme.titleSmall!.fontSize,
    );
    final categories = ref.watch(activeCategoriesProvider);
    final savingsGoals = ref.watch(activeSavingsGoalsProvider);
    final templates = ref.watch(activeTemplatesProvider);
    final investments = ref.watch(activeInvestmentsProvider);

    // Used to show each fixed transaction's category name
    final categoryNames = {
      for (final category in categories.value ?? <Category>[]) category.id: category.name,
    };

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Manage Settings", style: titleTextStyle),
                  const Text(
                    "Manage your budgets, tags, and fixed transactions here",
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),

                  SizedBox(height: 20),
                ],
              ),
              // Contents
              Column(
                children: [
                  AsyncPanel<Category>(
                    asyncData: categories,
                    elementItemBuilder: (context, item) {
                      return Container(
                        color: colorScheme.surface,
                        child: ListTile(
                          leading: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppConstants.getColorFromHex(item.colorHex),
                              shape: BoxShape.circle,
                            ),
                            child: AppConstants.getIcon(
                              item.iconKey,
                              color: AppConstants.onColor(AppConstants.getColorFromHex(item.colorHex)),
                            ),
                          ),

                          title: Text(item.name),
                          subtitle: Text(item.type == TransactionType.income ? "Income" : "Expense"),

                          trailing: _RowActions(
                            name: item.name,
                            onEdit: () => showCategoryFormDialog(context, category: item),
                            onDelete: () => _deleteWithConfirmation(
                              context,
                              kind: "category",
                              name: item.name,
                              consequence: "Transactions that already use it keep it.",
                              delete: () => ref.read(categoryActionsProvider).delete(item.id),
                            ),
                          ),
                        ),
                      );
                    },
                    button: ElevatedButton.icon(
                      onPressed: () => showCategoryFormDialog(context),
                      label: Text("Add Category"),
                      icon: Icon(Icons.add),
                    ),
                    titleLabel: "Categories",
                  ),

                  SizedBox(height: 20),

                  AsyncPanel<SavingsGoal>(
                    asyncData: savingsGoals,
                    elementItemBuilder: (context, item) {
                      return Container(
                        color: colorScheme.surface,
                        child: ListTile(
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("\$${item.targetAmount.toStringAsFixed(2)}", style: amountStyle),
                              Text("${item.name} Goal", style: detailStyle),
                              Text("\$${item.currentSavedAmount.toStringAsFixed(2)} saved so far", style: detailStyle),
                            ],
                          ),
                          trailing: _RowActions(
                            name: item.name,
                            onEdit: () => showSavingsGoalFormDialog(context, goal: item),
                            onDelete: () => _deleteWithConfirmation(
                              context,
                              kind: "savings goal",
                              name: item.name,
                              consequence: "",
                              delete: () => ref.read(savingsGoalActionsProvider).delete(item.id),
                            ),
                          ),
                        ),
                      );
                    },
                    button: ElevatedButton.icon(
                      onPressed: () => showSavingsGoalFormDialog(context),
                      label: Text("Add Goal"),
                      icon: Icon(Icons.add),
                    ),
                    titleLabel: "Savings Goals",
                  ),

                  SizedBox(height: 20),

                  AsyncPanel<Template>(
                    asyncData: templates,
                    elementItemBuilder: (context, item) {
                      final String type = item.type == TransactionType.income ? "Income" : "Expense";
                      final String? categoryName = categoryNames[item.categoryId];

                      return Container(
                        color: colorScheme.surface,
                        child: ListTile(
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("\$${item.amount.toStringAsFixed(2)}", style: amountStyle),
                              Text(item.name, style: detailStyle),
                              Text(
                                [type, ?categoryName, "day ${item.billingDay} of each month"].join(" · "),
                                style: detailStyle,
                              ),
                            ],
                          ),
                          trailing: _RowActions(
                            name: item.name,
                            onEdit: () => showTemplateFormDialog(context, template: item),
                            onDelete: () => _deleteWithConfirmation(
                              context,
                              kind: "fixed transaction",
                              name: item.name,
                              consequence: "Transactions it already added stay, it just won't add new ones.",
                              delete: () => ref.read(templateActionsProvider).delete(item.id),
                            ),
                          ),
                        ),
                      );
                    },
                    button: ElevatedButton.icon(
                      onPressed: () => showTemplateFormDialog(context),
                      label: Text("Add Fixed"),
                      icon: Icon(Icons.add),
                    ),
                    titleLabel: "Fixed Transactions",
                  ),

                  SizedBox(height: 20),

                  AsyncPanel<Investment>(
                    asyncData: investments,
                    elementItemBuilder: (context, item) {
                      return Container(
                        color: colorScheme.surface,
                        child: ListTile(
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("\$${item.amount.toStringAsFixed(2)}", style: amountStyle),
                              Text(item.name, style: detailStyle),
                            ],
                          ),
                          trailing: _RowActions(
                            name: item.name,
                            onEdit: () => showInvestmentFormDialog(context, investment: item),
                            onDelete: () => _deleteWithConfirmation(
                              context,
                              kind: "investment",
                              name: item.name,
                              consequence: "",
                              delete: () => ref.read(investmentActionsProvider).delete(item.id),
                            ),
                          ),
                        ),
                      );
                    },
                    button: ElevatedButton.icon(
                      onPressed: () => showInvestmentFormDialog(context),
                      label: Text("Add Investment"),
                      icon: Icon(Icons.add),
                    ),
                    titleLabel: "Investments",
                  ),
                ],
              ),
            ],
          ),
        )
      ),
    );
  }
}

// The edit + delete buttons at the end of every row
class _RowActions extends StatelessWidget
{
  final String name;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RowActions({required this.name, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Row(
      // NOTE: Row is greedy and will likely take up the entire horizontal space
      // We would need to do MainAxisSize min here to stop it from being greedy
      // and shrink-wrap to the content inside of it
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: "Edit $name",
          onPressed: onEdit,
          icon: Icon(Icons.edit),
        ),
        IconButton(
          tooltip: "Delete $name",
          onPressed: onDelete,
          icon: Icon(Icons.delete),
        ),
      ],
    );
  }
}
