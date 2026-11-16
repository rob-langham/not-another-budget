import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';

/// The savings-goal panel: progress against pace, catch-up advice and a bar per month.
class SavingsGoalCard extends StatelessWidget {
  const SavingsGoalCard({super.key, required this.goal});
  final J? goal;

  @override
  Widget build(BuildContext context) {
    final g = goal;
    if (g == null) {
      return CardBox(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Savings goal', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Label('Set a monthly amount and a start date. We track it against the accounts marked "counts towards savings".'),
          const SizedBox(height: 16),
          const _GoalForm(monthly: 50000, start: null),
        ]),
      );
    }
    final status = g['status'] as String;
    final pct = (g['percentOfPace'] as num).toDouble();
    final months = (g['months'] as List).cast<J>();
    final monthly = g['monthlyAmount'] as int;
    final behind = g['behindBy'] as int;
    final catchUp = g['catchUpPerMonth'] as int;
    final left = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('Savings goal', style: Theme.of(context).textTheme.titleLarge),
        switch (status) {
          'behind' => const Pill('Behind pace', tone: Tone.orange),
          'ahead' => const Pill('Ahead of pace', tone: Tone.green),
          _ => const Pill('On track', tone: Tone.green),
        },
      ]),
      const SizedBox(height: 18),
      Label('${money(monthly)} a month, starting ${dLong(g['startDate']).split(' ').skip(1).join(' ')}'),
      const SizedBox(height: 18),
      Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 10, children: [
        Big(moneyWhole(g['saved']), size: 52),
        Padding(padding: const EdgeInsets.only(bottom: 10), child: Label('saved of ${moneyWhole(g['expected'])} expected by today', size: 16)),
      ]),
      const SizedBox(height: 18),
      ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          value: (pct / 100).clamp(0, 1), minHeight: 12, backgroundColor: C.rule,
          color: status == 'behind' ? C.accent : C.green,
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: Label('$pct% of pace')),
        Label('Target ${moneyWhole(g['target'])} by ${dShort(g['targetDate'])}'),
      ]),
      if (behind > 0) ...[
        const SizedBox(height: 18),
        Note(Text.rich(TextSpan(children: [
          TextSpan(text: 'You\'re ${moneyWhole(behind)} behind. ', style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: 'Save an extra ${moneyWhole(catchUp)} a month until ${dShort(g['targetDate'])} to get back on track.'),
        ]))),
      ],
      const SizedBox(height: 18),
      _GoalForm(monthly: monthly, start: g['startDate']),
    ]);
    final chart = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Expanded(child: Text('Saved each month', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
        const _Key(C.green, 'Met goal'),
        const SizedBox(width: 14),
        const _Key(C.accentLight, 'Under goal'),
      ]),
      const SizedBox(height: 18),
      _Bars(months: months, goal: monthly),
    ]);
    return CardBox(child: Responsive(breakpoint: 900, gap: 40, children: [left, chart]));
  }
}

class _Key extends StatelessWidget {
  const _Key(this.color, this.text);
  final Color color;
  final String text;
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [CategoryDot(color), const SizedBox(width: 6), Label(text, size: 12)]);
}

class _Bars extends StatelessWidget {
  const _Bars({required this.months, required this.goal});
  final List<J> months;
  final int goal;
  @override
  Widget build(BuildContext context) {
    final shown = months.length > 12 ? months.sublist(months.length - 12) : months;
    final maxV = [goal * 1.3, ...shown.map((m) => (m['saved'] as int).toDouble())].reduce((a, b) => a > b ? a : b);
    const h = 200.0;
    return Semantics(
      label: 'Bar chart of savings per month against a ${money(goal)} goal',
      child: Column(children: [
        SizedBox(
          height: h,
          child: Stack(children: [
            Positioned(
              left: 0, right: 0, bottom: h * goal / maxV,
              child: Container(height: 2, color: C.ink),
            ),
            Positioned(
              right: 0, bottom: h * goal / maxV + 4,
              child: Container(color: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text('Goal ${moneyWhole(goal)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
            ),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final m in shown) ...[
                Expanded(
                  child: Container(
                    height: (h * ((m['saved'] as int).clamp(0, maxV) / maxV)).toDouble(),
                    decoration: BoxDecoration(
                      color: m['inProgress'] == true ? C.future : (m['metGoal'] == true ? C.green : C.accentLight),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                    ),
                  ),
                ),
                if (m != shown.last) const SizedBox(width: 10),
              ],
            ]),
          ]),
        ),
        const Divider(color: C.field),
        const SizedBox(height: 6),
        Row(children: [
          for (final m in shown) ...[
            Expanded(
              child: Text('${dMonth(m['month'])}\n${moneyWhole(m['saved'])}${m['inProgress'] == true ? '\nso far' : ''}',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: C.label, fontFeatures: tabular)),
            ),
            if (m != shown.last) const SizedBox(width: 10),
          ],
        ]),
      ]),
    );
  }
}

class _GoalForm extends StatefulWidget {
  const _GoalForm({required this.monthly, required this.start});
  final int monthly;
  final String? start;
  @override
  State<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends State<_GoalForm> {
  late final _amount = TextEditingController(text: (widget.monthly / 100).toStringAsFixed(2));
  late DateTime _start = widget.start != null ? DateTime.parse(widget.start!) : DateTime(DateTime.now().year, DateTime.now().month, 1);

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
      SizedBox(width: 160, child: TextField(controller: _amount, decoration: const InputDecoration(labelText: 'Monthly goal', prefixText: '£'), keyboardType: TextInputType.number)),
      SizedBox(
        width: 180,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.calendar_today_outlined, size: 16),
          label: Text('Start ${dShort(isoDate(_start))} ${_start.year}'),
          onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: _start, firstDate: DateTime(2000), lastDate: DateTime(2100));
            if (d != null) setState(() => _start = d);
          },
        ),
      ),
      FilledButton(
        onPressed: () => runAction(context, () async {
          final p = parseMoney(_amount.text);
          if (p == null || p <= 0) throw 'Enter a monthly amount';
          await context.read<Api>().put('/api/goal', {'monthlyAmount': p, 'startDate': isoDate(_start)});
        }, done: 'Savings goal saved'),
        child: Text(widget.start == null ? 'Set goal' : 'Update goal'),
      ),
    ]);
  }
}
