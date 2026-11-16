import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../format.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';
import 'savings_goal.dart';

class OverviewScreen extends StatelessWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.read<Nav>();
    return Loader<J>(
      load: (api) async => await api.get('/api/overview') as J,
      builder: (context, o, _) {
        final goal = o['goal'] as J?;
        final accounts = (o['accounts'] as List).cast<J>();
        final coming = (o['comingUp'] as List).cast<J>();
        final latest = (o['latestOutliers'] as List).cast<J>();
        final left = o['leftAfterPlanAndSavings'] as int;
        final catchUp = goal?['catchUpPerMonth'] as int? ?? 0;
        return PageBody(children: [
          PageHeader(kicker: dLong(o['today']), title: 'Overview', actions: [
            OutlinedButton(onPressed: () => nav.go(Section.import), child: const Text('Import transactions')),
            FilledButton(onPressed: () => nav.go(Section.accounts), child: const Text('Accounts')),
          ]),
          SavingsGoalCard(goal: goal),
          TileGrid(children: [
            StatTile(
              label: 'Income this month',
              value: money(o['incomeThisMonth']),
              foot: o['lastIncomeDate'] == null ? null : Align(alignment: Alignment.centerLeft, child: Pill('Received ${dShort(o['lastIncomeDate'])}', tone: Tone.green)),
            ),
            StatTile(
              label: 'Ideal budget',
              value: money(o['budgetPlanned']),
              foot: Label('${money(o['budgetUsed'])} used · ${o['billsToCome']} bills still to come'),
              onTap: () => nav.go(Section.budget),
            ),
            StatTile(
              label: 'Outliers',
              value: money(o['outliersTotal']),
              valueColor: C.orange,
              foot: Label('${o['outliersCount']} payments · 3-month avg ${money(o['outliersAverage'])}'),
              onTap: () => nav.go(Section.outliers),
            ),
            StatTile(
              label: 'Left after plan & savings',
              value: money(left),
              valueColor: left < 0 ? C.orange : C.ink,
              foot: Label(catchUp > 0
                  ? (left >= catchUp ? 'Could cover the ${moneyWhole(catchUp)} catch-up' : 'Not enough for the ${moneyWhole(catchUp)} catch-up')
                  : 'After bills, pots, savings and outliers'),
            ),
          ]),
          Responsive(flex: const [7, 6], children: [
            CardBox(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text('Accounts', style: sectionTitle)),
                  TextButton(onPressed: () => nav.go(Section.accounts), child: const Text('Manage', style: TextStyle(color: C.link))),
                ]),
                if (accounts.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Label('No accounts yet. Add one under Accounts.')),
                for (final a in accounts)
                  RowLine(left: TwoLine(a['name'], _sourceLine(a)), right: Num(money(a['balance']), bold: true)),
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Row(children: [
                    const Expanded(child: Text('Net position', style: TextStyle(fontWeight: FontWeight.w700))),
                    Num(money(o['netPosition']), bold: true),
                  ]),
                ),
              ]),
            ),
            CardBox(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Coming up this week', style: sectionTitle),
                const SizedBox(height: 6),
                if (coming.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Label('Nothing due in the next 7 days.')),
                for (final c in coming)
                  RowLine(left: TwoLine(c['name'], '${dDay(c['date'])}${c['accountName'] != null ? ' · ${c['accountName']}' : ''}'), right: Num(money(c['amount']))),
                const SizedBox(height: 22),
                const Text('Latest outliers', style: TextStyle(fontFamily: display, fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                if (latest.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Label('None this month.')),
                for (final t in latest) RowLine(left: Text(t['merchant']), right: Num(money(-(t['amount'] as int)))),
              ]),
            ),
          ]),
        ]);
      },
    );
  }

  String _sourceLine(J a) {
    final last = a['lastSyncedAt'] as String?;
    return switch (a['source']) {
      'bank_link' => 'Bank link',
      'file_import' => last == null ? 'File import' : 'File import · last file ${dShort(last.substring(0, 10))}',
      _ => 'Manual · from ${dShort(a['openingDate'])}',
    };
  }
}
