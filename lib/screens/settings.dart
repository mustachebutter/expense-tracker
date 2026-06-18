import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/main.dart';
import 'package:expense_tracker/widgets/add_expense_dialog.dart';
import 'package:expense_tracker/widgets/ledger_list.dart';
import 'package:expense_tracker/widgets/panel.dart';
import 'package:expense_tracker/widgets/stream_panel.dart';
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
                  StreamPanel<Category>(
                    dataStream: AppDatabase.instance.categoriesDao.watchAllActiveCategories(),
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
                            child: AppConstants.getIcon(item.iconKey),
                          ),

                          title: Text(item.name),

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
                    button: ElevatedButton.icon(
                      onPressed: () {},
                      label: Text("Add Category"),
                      icon: Icon(Icons.add),
                    ),
                    titleLabel: "Categories",
                  ),

                  SizedBox(height: 20),

                  StreamPanel<SavingsGoal>(
                    dataStream: AppDatabase.instance.savingsGoalsDao.watchAvailableSavingsGoals(),
                    elementItemBuilder: (context, item) {
                      return Container(
                        color: colorScheme.surface,
                        child: ListTile(
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "\$${item.targetAmount.toStringAsFixed(2)}",
                                style: TextStyle(
                                  fontWeight: textTheme.displaySmall!.fontWeight,
                                  fontSize: textTheme.displaySmall!.fontSize,
                                ),
                              ),
                              Text(
                                "${item.name} Goal",
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
                    button: ElevatedButton.icon(
                      onPressed: () {},
                      label: Text("Edit"),
                      icon: Icon(Icons.edit),
                    ),
                    titleLabel: "Savings & Investments",
                  ),

                  SizedBox(height: 20),

                  //TODO: Render income templates and expense templates here
                  StreamPanel<Template>(
                    dataStream: AppDatabase.instance.templatesDao.watchAllTemplates(),
                    elementItemBuilder: (context, item) {
                      return Container(
                        color: colorScheme.surface,
                        child: ListTile(
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "\$${item.amount.toStringAsFixed(2)}",
                                style: TextStyle(
                                  fontWeight: textTheme.displaySmall!.fontWeight,
                                  fontSize: textTheme.displaySmall!.fontSize,
                                ),
                              ),
                              Text(
                                item.name,
                                style: TextStyle(
                                  fontWeight: textTheme.titleSmall!.fontWeight,
                                  fontSize: textTheme.titleSmall!.fontSize,
                                ),
                              ),
                              Text(
                                "On day ${item.billingDay} of each month",
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
                    button: ElevatedButton.icon(
                      onPressed: () {},
                      label: Text("Edit"),
                      icon: Icon(Icons.edit),
                    ),
                    titleLabel: "Fixed Transactions",
                  ),

                  SizedBox(height: 20),

                  StreamPanel<Investment>(
                    dataStream: AppDatabase.instance.investmentsDao.watchAvailableInvestments(),
                    elementItemBuilder: (context, item) {
                      return Container(
                        color: colorScheme.surface,
                        child: ListTile(
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "\$${item.amount.toStringAsFixed(2)}",
                                style: TextStyle(
                                  fontWeight: textTheme.displaySmall!.fontWeight,
                                  fontSize: textTheme.displaySmall!.fontSize,
                                ),
                              ),
                              Text(
                                item.name,
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
                    button: ElevatedButton.icon(
                      onPressed: () {},
                      label: Text("Edit"),
                      icon: Icon(Icons.edit),
                    ),
                    titleLabel: "Fixed Transactions",
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
