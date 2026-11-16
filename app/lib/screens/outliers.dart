import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';
import 'transactions.dart' show pickCategory;

class OutliersScreen extends StatelessWidget {
  const OutliersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Loader<(J, List<J>)>(
      load: (api) async => (await api.get('/api/outliers') as J, await api.categories()),
      builder: (context, d, _) {
        final (o, cats) = d;
        final months = (o['months'] as List).cast<J>();
        final cur = months.first;
        final avg = o['threeMonthAverage'] as int;
        final diff = (cur['total'] as int) - avg;
        final chart = months.reversed.toList();
        final maxV = chart.map((m) => m['total'] as int).fold<int>(1, (a, b) => a > b ? a : b);
        return PageBody(children: [
          const PageHeader(kicker: 'Payments that aren\'t part of your ideal budget', title: 'Outliers'),
          Responsive(flex: const [1, 2], children: [
            CardBox(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Label('${dMonthLong(cur['month']).split(' ').first} so far'),
                const SizedBox(height: 8),
                Big(money(cur['total']), size: 34, color: C.orange),
                const SizedBox(height: 8),
                Label('${money(diff.abs())} ${diff >= 0 ? 'above' : 'below'} your 3-month average', color: C.muted, size: 14),
              ]),
            ),
            CardBox(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Outliers by month', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 12),
                SizedBox(
                  height: 130,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    for (final m in chart) ...[
                      Expanded(
                        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                          Num(moneyWhole(m['total']), size: 12, color: C.label),
                          const SizedBox(height: 6),
                          Container(
                            height: 88.0 * (m['total'] as int) / maxV,
                            decoration: BoxDecoration(color: m == cur ? C.accent : C.accentLight, borderRadius: const BorderRadius.vertical(top: Radius.circular(6))),
                          ),
                          const SizedBox(height: 6),
                          Label(dMonth(m['month']), size: 12),
                        ]),
                      ),
                      if (m != chart.last) const SizedBox(width: 24),
                    ],
                  ]),
                ),
              ]),
            ),
          ]),
          for (final m in months)
            if (m == cur || (m['items'] as List).isNotEmpty) _MonthCard(month: m, current: m == cur, cats: cats),
        ]);
      },
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.month, required this.current, required this.cats});
  final J month;
  final bool current;
  final List<J> cats;
  @override
  Widget build(BuildContext context) {
    final items = (month['items'] as List).cast<J>();
    final decide = items.where((i) => i['state'] == 'needs_decision').length;
    return CardBox(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(dMonthLong(month['month']).split(' ').first, style: sectionTitle)),
          current ? Label('${items.length} payments${decide > 0 ? ' · $decide needs a decision' : ''}') : Num(money(month['total']), bold: true),
        ]),
        if (items.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Label('No outliers. Everything fits the plan.')),
        for (final o in items) _OutlierRow(o: o, cats: cats, actions: current, last: o == items.last),
      ]),
    );
  }
}

class _OutlierRow extends StatelessWidget {
  const _OutlierRow({required this.o, required this.cats, required this.actions, required this.last});
  final J o;
  final List<J> cats;
  final bool actions, last;

  @override
  Widget build(BuildContext context) {
    final api = context.read<Api>();
    final t = o['transaction'] as J;
    final needs = actions && o['state'] == 'needs_decision';
    final sub = '${dDay(t['date'])} · ${t['accountName']}${o['categoryName'] != null ? ' · ${o['categoryName']}' : ''}';
    return Container(
      margin: needs ? const EdgeInsets.symmetric(horizontal: -24) : EdgeInsets.zero,
      padding: EdgeInsets.symmetric(vertical: 16, horizontal: needs ? 24 : 0),
      decoration: BoxDecoration(color: needs ? C.orangeSoft : null, border: last ? null : const Border(bottom: BorderSide(color: C.rule))),
      child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 16, runSpacing: 10, children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 240, maxWidth: 420),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t['merchant'], style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Label(sub),
            if (needs) ...[const SizedBox(height: 4), Label('You\'ve paid for this ${o['seenCount']} times in 6 months.', color: C.orangeInk)],
          ]),
        ),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (actions) needs ? const Pill('Needs a decision', tone: Tone.orange) : const Pill('One-off'),
          if (actions && needs) ...[
            FilledButton(onPressed: () => runAction(context, () => api.post('/api/outliers/${t['id']}/recurring', {'repeat': 'monthly'}), done: 'Added to your ideal budget'), child: const Text('Make it recurring')),
            OutlinedButton(onPressed: () => runAction(context, () => api.post('/api/outliers/${t['id']}/keep')), child: const Text('Keep as one-off')),
          ] else if (actions)
            OutlinedButton(
              onPressed: () async {
                final c = await pickCategory(context, cats, t['categoryId']);
                if (c != null && context.mounted) await runAction(context, () => api.patch('/api/transactions/${t['id']}', {'categoryId': c}));
              },
              child: const Text('Change category'),
            ),
          SizedBox(width: 100, child: Align(alignment: Alignment.centerRight, child: Num(money(-(t['amount'] as int)), bold: true, size: 16))),
        ]),
      ]),
    );
  }
}
