import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/main.dart';
import 'package:expense_tracker/widgets/add_expense_dialog.dart';
import 'package:expense_tracker/widgets/ledger_list.dart';
import 'package:expense_tracker/widgets/panel.dart';
import 'package:expense_tracker/widgets/summary_card.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final TextStyle titleTextStyle = screenWidth < 600
        ? TextStyle(fontSize: 28, fontWeight: FontWeight.bold)
        : TextStyle(fontSize: 32, fontWeight: FontWeight.bold);
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: StreamBuilder<List<FixedExpense>>(
          stream: AppDatabase.instance.watchAllFixedExpenses(),
          builder: (context, snapshot) {
            final fixedExpenses = snapshot.data ?? [];
            
            return SingleChildScrollView(
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
                        "Manage your budgets, tags, and fixed expenses here",
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),

                      SizedBox(height: 20),
                    ],
                  ),
                  // Contents
                  Column(
                    children: [
                      Panel(
                        elementItemBuilder: (context, index) {
                          final categoryKey = AppConstants.categories.keys
                              .elementAt(index);
                          final categoryValue = AppConstants.categories.values
                              .elementAt(index);
                          return Container(
                            color: colorScheme.surface,
                            child: ListTile(
                              leading: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: categoryValue["color"] as Color,
                                  shape: BoxShape.circle,
                                ),
                                child: categoryValue["icon"] as Icon,
                              ),

                              title: Text(categoryKey),

                              trailing: Row(
                                // NOTE: Row is greedy and will likely take up the entire horizontal space
                                // We would need to do MainAxisSize min here to stop it from being greedy
                                // and shrink-wrap to the content inside of it
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    onPressed: () {},
                                    icon: Icon(Icons.edit),
                                  ),
                                  IconButton(
                                    onPressed: () {},
                                    icon: Icon(Icons.delete),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        elementCount: AppConstants.categories.length,
                        button: ElevatedButton.icon(
                          onPressed: () {},
                          label: Text("Add Category"),
                          icon: Icon(Icons.add),
                        ),
                        titleLabel: "Categories",
                      ),

                      SizedBox(height: 20),

                      Panel(
                        elementItemBuilder: (context, index) {
                          final monthlyIncome = AppConstants.monthlyIncome.values
                              .elementAt(index);

                          return ListTile(
                            title: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "\$${monthlyIncome.toStringAsFixed(2)}",
                                  style: TextStyle(
                                    fontWeight: textTheme.displaySmall!.fontWeight,
                                    fontSize: textTheme.displaySmall!.fontSize,
                                  ),
                                ),
                                Text(
                                  "Current Month ${DateTime.now().month}/${DateTime.now().year}",
                                  style: TextStyle(
                                    fontWeight: textTheme.titleSmall!.fontWeight,
                                    fontSize: textTheme.titleSmall!.fontSize,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                        elementCount: AppConstants.monthlyIncome.length,
                        button: ElevatedButton.icon(
                          onPressed: () {},
                          label: Text("Edit"),
                          icon: Icon(Icons.edit),
                        ),
                        titleLabel: "Monthly Income",
                      ),

                      SizedBox(height: 20),

                      Panel(
                        elementItemBuilder: (context, index) {

                          final String investmentName = AppConstants.financialGoals.keys
                              .elementAt(index);
                          final double investmentAmount = AppConstants.financialGoals.values
                              .elementAt(index);

                          return Container(
                            color: colorScheme.surface,
                            child: ListTile(
                              title: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "\$${investmentAmount.toStringAsFixed(2)}",
                                    style: TextStyle(
                                      fontWeight: textTheme.displaySmall!.fontWeight,
                                      fontSize: textTheme.displaySmall!.fontSize,
                                    ),
                                  ),
                                  Text(
                                    "$investmentName Goal",
                                    style: TextStyle(
                                      fontWeight: textTheme.titleSmall!.fontWeight,
                                      fontSize: textTheme.titleSmall!.fontSize,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    onPressed: () {},
                                    icon: Icon(Icons.edit),
                                  ),
                                  IconButton(
                                    onPressed: () {},
                                    icon: Icon(Icons.delete),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        elementCount: AppConstants.financialGoals.length,
                        button: ElevatedButton.icon(
                          onPressed: () {},
                          label: Text("Edit"),
                          icon: Icon(Icons.edit),
                        ),
                        titleLabel: "Savings & Investments",
                      ),

                      SizedBox(height: 20),

                      Panel(
                        elementItemBuilder: (context, index) {
                          final fixedExpense = fixedExpenses.elementAt(index);

                          return Container(
                            color: colorScheme.surface,
                            child: ListTile(
                              title: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "\$${fixedExpense.amount.toStringAsFixed(2)}",
                                    style: TextStyle(
                                      fontWeight: textTheme.displaySmall!.fontWeight,
                                      fontSize: textTheme.displaySmall!.fontSize,
                                    ),
                                  ),
                                  Text(
                                    fixedExpense.name,
                                    style: TextStyle(
                                      fontWeight: textTheme.titleSmall!.fontWeight,
                                      fontSize: textTheme.titleSmall!.fontSize,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    onPressed: () {},
                                    icon: Icon(Icons.edit),
                                  ),
                                  IconButton(
                                    onPressed: () {},
                                    icon: Icon(Icons.delete),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        elementCount: AppConstants.fixedExpenseTemplates.length,
                        button: ElevatedButton.icon(
                          onPressed: () {},
                          label: Text("Edit"),
                          icon: Icon(Icons.edit),
                        ),
                        titleLabel: "Fixed Expenses",
                      ),
                      // Panel(
                      //   elementItemBuilder: elementItemBuilder,
                      //   elements: elements,
                      //   button: button,
                      //   titleLabel: "Fixed Expenses",
                      // ),
                    ],
                  ),
                ],
              ),
            );
          }
        ) 
      ),
    );
  }
}
