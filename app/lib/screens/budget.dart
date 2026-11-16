import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});
  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  J? _editing; // scheduled expense being edited, null = new

  String get _ym => '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Loader<(J, List<J>, List<J>, List<J>)>(
      deps: [_ym],
      load: (api) async => (
        await api.get('/api/budget', {'month': _ym}) as J,
        (await api.get('/api/scheduled') as List).cast<J>(),
        await api.categories(),
        await api.accounts(),
      ),
      builder: (context, d, _) {
        final (b, sched, cats, accs) = d;
        final lines = (b['lines'] as List).cast<J>();
        final share = b['shareOfIncome'];
        return PageBody(children: [
          PageHeader(kicker: 'Scheduled and repeating spending · ${dMonthLong(_ym)}', title: 'Ideal budget', actions: [
            IconButton(tooltip: 'Previous month', onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)), icon: const Icon(Icons.chevron_left)),
            IconButton(tooltip: 'Next month', onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)), icon: const Icon(Icons.chevron_right)),
            OutlinedButton(onPressed: () => _suggestions(context), child: const Text('Find repeats from history')),
            FilledButton(onPressed: () => setState(() => _editing = null), child: const Text('Add scheduled expense')),
          ]),
          TileGrid(minWidth: 200, children: [
            StatTile(label: 'Planned this month', value: money(b['planned'])),
            StatTile(label: 'Used so far', value: money(b['used'])),
            StatTile(label: 'Still to come', value: money(b['stillToCome'])),
            StatTile(label: 'Share of income', value: share == null ? '—' : '$share%'),
          ]),
          Responsive(breakpoint: 1100, flex: const [2, 1], children: [
            CardBox(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 8), child: Text('This month\'s plan', style: sectionTitle)),
                if (lines.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Label('Nothing planned yet. Add rent, bills and spending pots, or let us find repeats from your history.')),
                for (final g in const [('bill', 'Fixed bills'), ('yearly', 'Set aside for yearly costs'), ('pot', 'Spending pots')])
                  if (lines.any((l) => l['group'] == g.$1)) ...[
                    Container(color: C.subtle, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Text(g.$2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: C.muted))),
                    for (final l in lines.where((l) => l['group'] == g.$1))
                      _PlanRow(line: l, onEdit: () => setState(() => _editing = sched.firstWhere((s) => s['id'] == l['scheduledId']))),
                  ],
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [const Expanded(child: Text('Total planned', style: TextStyle(fontWeight: FontWeight.w700))), Num(money(b['planned']), bold: true)]),
                ),
              ]),
            ),
            CardBox(child: _ScheduleForm(key: ValueKey(_editing?['id']), initial: _editing, categories: cats, accounts: accs, onDone: () => setState(() => _editing = null))),
          ]),
        ]);
      },
    );
  }

  Future<void> _suggestions(BuildContext context) async {
    final api = context.read<Api>();
    final list = (await api.get('/api/scheduled/suggestions') as List).cast<J>();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Repeats found in your history'),
        content: SizedBox(
          width: 480,
          child: list.isEmpty
              ? const Label('No new repeating payments found in the last 4 months.')
              : ListView(shrinkWrap: true, children: [
                  for (final s in list)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s['name']),
                      subtitle: Text('Seen ${s['seen']} months running · next around ${dShort(s['firstDate'])}'),
                      trailing: FilledButton(
                        onPressed: () => runAction(ctx, () async {
                          await api.post('/api/scheduled', {
                            'name': s['name'], 'amount': s['amount'], 'group': 'bill', 'repeat': s['repeat'],
                            'firstDate': s['firstDate'], 'accountId': s['accountId'], 'matchText': s['name'],
                          });
                          if (ctx.mounted) Navigator.pop(ctx);
                        }, done: 'Added ${s['name']}'),
                        child: Text('Add ${money(s['amount'])}'),
                      ),
                    ),
                ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.line, required this.onEdit});
  final J line;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) {
    final status = line['status'] as String;
    final Widget statusW = switch (status) {
      'paid' => Pill(line['statusText'], tone: Tone.green),
      'overdue' => Pill(line['statusText'], tone: Tone.orange),
      'set_aside' => Pill(line['statusText'], tone: Tone.blue),
      'pot' => _Meter(used: line['used'], of: line['amount']),
      _ => Pill(line['statusText']),
    };
    final sub = <String>[
      line['repeatLabel'],
      if (line['group'] == 'yearly' && line['nextDue'] != null) '${money(line['yearlyAmount'])} renews ${dShort(line['nextDue'])}'
      else if (line['nextDue'] != null && line['group'] == 'bill') 'next ${dShort(line['nextDue'])}',
      if (line['accountName'] != null) line['accountName'],
    ].join(' · ');
    return InkWell(
      onTap: onEdit,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.rule))),
        child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8, spacing: 12, children: [
          ConstrainedBox(constraints: const BoxConstraints(minWidth: 220), child: TwoLine(line['name'], sub)),
          Row(mainAxisSize: MainAxisSize.min, children: [statusW, const SizedBox(width: 16), SizedBox(width: 100, child: Align(alignment: Alignment.centerRight, child: Num(money(line['amount']), bold: true)))]),
        ]),
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({required this.used, required this.of});
  final int used, of;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 120,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(value: of == 0 ? 0 : (used / of).clamp(0, 1), minHeight: 6, backgroundColor: C.rule, color: used > of ? C.accent : C.green),
          ),
        ),
        const SizedBox(width: 10),
        Num(money(used), color: C.label, size: 13),
      ]);
}

const _repeats = [('weekly', 'Weekly'), ('four_weekly', 'Every 4 weeks'), ('monthly', 'Monthly'), ('yearly', 'Yearly'), ('one_off', 'One-off')];

class _ScheduleForm extends StatefulWidget {
  const _ScheduleForm({super.key, required this.initial, required this.categories, required this.accounts, required this.onDone});
  final J? initial;
  final List<J> categories, accounts;
  final VoidCallback onDone;
  @override
  State<_ScheduleForm> createState() => _ScheduleFormState();
}

class _ScheduleFormState extends State<_ScheduleForm> {
  late final J? i = widget.initial;
  late final _name = TextEditingController(text: i?['name'] ?? '');
  late final _amount = TextEditingController(text: i == null ? '' : ((i!['amount'] as int) / 100).toStringAsFixed(2));
  late final _match = TextEditingController(text: i?['matchText'] ?? '');
  late final _count = TextEditingController(text: '${i?['endCount'] ?? 12}');
  late String _group = i?['group'] ?? 'bill';
  late String _repeat = i?['repeat'] ?? 'monthly';
  late String _endType = i?['endType'] ?? 'never';
  late int? _cat = i?['categoryId'];
  late int? _acc = i?['accountId'];
  late DateTime _first = i != null ? DateTime.parse(i!['firstDate']) : DateTime.now();
  late DateTime _endDate = i?['endDate'] != null ? DateTime.parse(i!['endDate']) : DateTime.now().add(const Duration(days: 365));

  int get _monthly {
    final a = parseMoney(_amount.text) ?? 0;
    return switch (_repeat) { 'weekly' => (a * 52 / 12).round(), 'four_weekly' => (a * 13 / 12).round(), 'yearly' => (a / 12).round(), 'monthly' => a, _ => 0 };
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<Api>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(i == null ? 'Add scheduled expense' : 'Edit ${i!['name']}', style: sectionTitle),
      const SizedBox(height: 16),
      SegmentedButton<String>(
        segments: const [ButtonSegment(value: 'bill', label: Text('Bill')), ButtonSegment(value: 'yearly', label: Text('Yearly cost')), ButtonSegment(value: 'pot', label: Text('Spending pot'))],
        selected: {_group},
        onSelectionChanged: (s) => setState(() {
          _group = s.first;
          if (_group == 'pot') _repeat = 'monthly';
          if (_group == 'yearly') _repeat = 'yearly';
        }),
      ),
      const SizedBox(height: 16),
      TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: TextField(controller: _amount, onChanged: (_) => setState(() {}), keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: _group == 'pot' ? 'Monthly allowance' : (_group == 'yearly' ? 'Yearly cost' : 'Amount'), prefixText: '£'))),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<int?>(
            initialValue: _cat,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [const DropdownMenuItem(value: null, child: Text('None')), for (final c in widget.categories) DropdownMenuItem(value: c['id'] as int, child: Text(c['name']))],
            onChanged: (v) => setState(() => _cat = v),
          ),
        ),
      ]),
      if (_group == 'bill') ...[
        const SizedBox(height: 16),
        const Label('Repeats'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (v, l) in _repeats)
            ChoiceChip(label: Text(l), selected: _repeat == v, onSelected: (_) => setState(() => _repeat = v)),
        ]),
      ],
      if (_group != 'pot') ...[
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text('${_group == 'yearly' ? 'Renews' : 'First payment'} ${dShort(isoDate(_first))} ${_first.year}'),
              onPressed: () async {
                final d = await showDatePicker(context: context, initialDate: _first, firstDate: DateTime(2000), lastDate: DateTime(2100));
                if (d != null) setState(() => _first = d);
              },
            ),
          ),
          if (_group == 'bill') ...[
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _endType,
                decoration: const InputDecoration(labelText: 'Ends'),
                items: const [DropdownMenuItem(value: 'never', child: Text('Never')), DropdownMenuItem(value: 'on_date', child: Text('On a date')), DropdownMenuItem(value: 'after_count', child: Text('After a number of payments'))],
                onChanged: (v) => setState(() => _endType = v!),
              ),
            ),
          ],
        ]),
        if (_endType == 'on_date' && _group == 'bill') ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () async {
              final d = await showDatePicker(context: context, initialDate: _endDate, firstDate: _first, lastDate: DateTime(2100));
              if (d != null) setState(() => _endDate = d);
            },
            child: Text('Last payment by ${dShort(isoDate(_endDate))} ${_endDate.year}'),
          ),
        ],
        if (_endType == 'after_count' && _group == 'bill') ...[
          const SizedBox(height: 12),
          TextField(controller: _count, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Number of payments')),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<int?>(
          initialValue: _acc,
          decoration: const InputDecoration(labelText: 'Pay from'),
          items: [const DropdownMenuItem(value: null, child: Text('Any account')), for (final a in widget.accounts) DropdownMenuItem(value: a['id'] as int, child: Text(a['name']))],
          onChanged: (v) => setState(() => _acc = v),
        ),
        if (_group == 'bill') ...[
          const SizedBox(height: 12),
          TextField(controller: _match, decoration: const InputDecoration(labelText: 'Payment text to match (optional)', helperText: 'Defaults to the name. Used to tick it off when the payment arrives.')),
        ],
      ],
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(10)),
        child: Text(
          _group == 'pot' ? 'Spending in this category counts against the allowance each month.'
              : _repeat == 'one_off' ? 'A one-off payment, planned for its month only.'
              : 'Works out to about ${money(_monthly)} a month. Matching payments will tick this off automatically.',
          style: const TextStyle(fontSize: 13, color: C.muted, height: 1.5),
        ),
      ),
      const SizedBox(height: 16),
      Wrap(spacing: 10, runSpacing: 10, children: [
        FilledButton(
          onPressed: () => runAction(context, () async {
            final amount = parseMoney(_amount.text);
            if (_name.text.trim().isEmpty || amount == null || amount <= 0) throw 'Add a name and an amount';
            final body = {
              'name': _name.text.trim(), 'amount': amount, 'categoryId': _cat, 'group': _group,
              'repeat': _group == 'pot' ? 'monthly' : (_group == 'yearly' ? 'yearly' : _repeat),
              'firstDate': _group == 'pot' ? '2000-01-01' : isoDate(_first),
              'endType': _group == 'bill' ? _endType : 'never',
              'endDate': _endType == 'on_date' ? isoDate(_endDate) : null,
              'endCount': _endType == 'after_count' ? int.tryParse(_count.text) : null,
              'accountId': _acc, 'matchText': _match.text.trim().isEmpty ? null : _match.text.trim(),
            };
            if (i == null) {
              await api.post('/api/scheduled', body);
            } else {
              await api.put('/api/scheduled/${i!['id']}', body);
            }
            widget.onDone();
          }, done: 'Saved to ideal budget'),
          child: const Text('Save to ideal budget'),
        ),
        if (i != null) ...[
          OutlinedButton(onPressed: widget.onDone, child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: C.orange),
            onPressed: () => runAction(context, () async { await api.delete('/api/scheduled/${i!['id']}'); widget.onDone(); }, done: 'Removed'),
            child: const Text('Delete'),
          ),
        ],
      ]),
    ]);
  }
}
