import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'auth.dart';
import 'screens/accounts.dart';
import 'screens/amazon.dart';
import 'screens/budget.dart';
import 'screens/import.dart';
import 'screens/outliers.dart';
import 'screens/overview.dart';
import 'screens/rules.dart';
import 'screens/transactions.dart';
import 'theme.dart';

enum Section {
  overview('Overview', Icons.space_dashboard_outlined),
  transactions('Transactions', Icons.receipt_long_outlined),
  budget('Ideal budget', Icons.event_repeat_outlined),
  outliers('Outliers', Icons.trending_up),
  accounts('Accounts', Icons.account_balance_outlined),
  import('Import', Icons.upload_file_outlined),
  amazon('Amazon receipts', Icons.shopping_bag_outlined),
  rules('Categories & rules', Icons.rule_outlined);

  const Section(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Lets any screen jump to another section (like the design's links between pages).
class Nav extends ChangeNotifier {
  Section current = Section.overview;
  void go(Section s) {
    current = s;
    notifyListeners();
  }
}

class Shell extends StatelessWidget {
  const Shell({super.key});

  Widget _page(Section s) => switch (s) {
        Section.overview => const OverviewScreen(),
        Section.transactions => const TransactionsScreen(),
        Section.budget => const BudgetScreen(),
        Section.outliers => const OutliersScreen(),
        Section.accounts => const AccountsScreen(),
        Section.import => const ImportScreen(),
        Section.amazon => const AmazonScreen(),
        Section.rules => const RulesScreen(),
      };

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<Nav>();
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final body = KeyedSubtree(key: ValueKey(nav.current), child: _page(nav.current));
    if (wide) {
      return Scaffold(body: Row(children: [const SizedBox(width: 240, child: _SideNav()), Expanded(child: body)]));
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: C.side,
        foregroundColor: Colors.white,
        title: const Text('Longview', style: TextStyle(fontFamily: display, fontWeight: FontWeight.w700)),
      ),
      drawer: const Drawer(backgroundColor: C.side, child: SafeArea(child: _SideNav(inDrawer: true))),
      body: body,
    );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({this.inDrawer = false});
  final bool inDrawer;
  @override
  Widget build(BuildContext context) {
    final nav = context.watch<Nav>();
    final auth = context.watch<AuthService>();
    return Container(
      color: C.side,
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, 20),
          child: Text('Longview', style: TextStyle(fontFamily: display, fontWeight: FontWeight.w700, fontSize: 22, color: Colors.white)),
        ),
        for (final s in Section.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: nav.current == s ? C.sideOn : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  nav.go(s);
                  if (inDrawer) Navigator.of(context).pop();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  child: Row(children: [
                    Icon(s.icon, size: 18, color: nav.current == s ? Colors.white : C.sideText),
                    const SizedBox(width: 10),
                    Text(s.label,
                        style: TextStyle(
                            fontSize: 15,
                            color: nav.current == s ? Colors.white : C.sideText,
                            fontWeight: nav.current == s ? FontWeight.w600 : FontWeight.w400)),
                  ]),
                ),
              ),
            ),
          ),
        const Spacer(),
        if (auth.displayName != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(auth.displayName!, style: const TextStyle(color: C.sideText, fontSize: 13), overflow: TextOverflow.ellipsis),
          ),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: C.sideText, alignment: Alignment.centerLeft, minimumSize: const Size(44, 44)),
          onPressed: auth.logout,
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('Sign out'),
        ),
      ]),
    );
  }
}
