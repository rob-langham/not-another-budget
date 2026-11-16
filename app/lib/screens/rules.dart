import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';

const _fields = {'merchant': 'Merchant', 'description': 'Description', 'amount': 'Amount', 'day_of_week': 'Day of week', 'time': 'Time of payment', 'account': 'Account'};
const _textOps = {'contains': 'contains', 'is': 'is', 'starts_with': 'starts with', 'is_one_of': 'is one of'};
const _amountOps = {'less_than': 'less than', 'more_than': 'more than', 'equals': 'equals'};
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _palette = ['#7A4FB0', '#2F5BB7', '#1E6B4F', '#B4530A', '#2A8A8A', '#8C5A2B', '#5A6ACF', '#C23B5A', '#6B6F76', '#9C4FA8', '#A07A1E', '#16181D'];

class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Loader<(List<J>, List<J>)>(
      load: (api) async => (await api.categories(), (await api.get('/api/rules') as List).cast<J>()),
      builder: (context, d, _) {
        final (cats, rules) = d;
        final catById = {for (final c in cats) c['id']: c};
        final api = context.read<Api>();
        return PageBody(children: [
          PageHeader(kicker: 'Your own categories, filled in automatically', title: 'Categories & rules', actions: [
            FilledButton(onPressed: () => editRule(context, null, cats), child: const Text('New rule')),
          ]),
          Responsive(breakpoint: 1000, flex: const [1, 2], children: [
            CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Categories', style: sectionTitle),
              const SizedBox(height: 8),
              for (final c in cats)
                InkWell(
                  onTap: () => _editCategory(context, c),
                  child: RowLine(
                    left: Row(children: [CategoryDot(hex(c['color']), size: 12), const SizedBox(width: 10), Text(c['name'])]),
                    right: c['kind'] == 'spending' ? const Icon(Icons.edit_outlined, size: 16, color: C.label) : Label(c['kind'], size: 12),
                  ),
                ),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: () => _editCategory(context, null), child: const Text('Add category')),
            ])),
            CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [Expanded(child: Text('Rules', style: sectionTitle)), Label('${rules.length} rules · first match wins')]),
              const SizedBox(height: 8),
              if (rules.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Label('No rules yet. A rule sets the category of matching payments automatically.')),
              for (final r in rules)
                Opacity(
                  opacity: r['active'] == true ? 1 : .55,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.rule))),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r['name'], style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Label(r['summary']),
                        const SizedBox(height: 6),
                        r['splitByReceipt'] == true
                            ? const Pill('Split by receipt', tone: Tone.blue)
                            : Pill(catById[r['categoryId']]?['name'] ?? 'No category'),
                      ])),
                      Switch(value: r['active'] == true, onChanged: (v) => runAction(context, () => api.put('/api/rules/${r['id']}', {...r, 'active': v}))),
                      const SizedBox(width: 6),
                      OutlinedButton(onPressed: () => editRule(context, r, cats), child: const Text('Edit')),
                    ]),
                  ),
                ),
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerLeft, child: OutlinedButton(onPressed: () => editRule(context, null, cats), child: const Text('Add a rule'))),
            ])),
          ]),
        ]);
      },
    );
  }

  Future<void> _editCategory(BuildContext context, J? c) async {
    final api = context.read<Api>();
    final name = TextEditingController(text: c?['name'] ?? '');
    var color = c?['color'] ?? _palette.first;
    var kind = c?['kind'] ?? 'spending';
    await showDialog<void>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => AlertDialog(
      title: Text(c == null ? 'Add category' : 'Edit category'),
      content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(initialValue: kind, decoration: const InputDecoration(labelText: 'Counts as'),
          items: const [DropdownMenuItem(value: 'spending', child: Text('Spending')), DropdownMenuItem(value: 'income', child: Text('Income')),
            DropdownMenuItem(value: 'savings', child: Text('Savings')), DropdownMenuItem(value: 'transfer', child: Text('Transfer (ignored)'))],
          onChanged: (v) => set(() => kind = v!)),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in _palette)
            Semantics(
              button: true, label: 'Colour $p', selected: p == color,
              child: InkWell(onTap: () => set(() => color = p), child: Container(width: 32, height: 32,
                  decoration: BoxDecoration(color: hex(p), borderRadius: BorderRadius.circular(8), border: Border.all(color: p == color ? C.ink : Colors.transparent, width: 3)))),
            ),
        ]),
      ])),
      actions: [
        if (c != null) TextButton(style: TextButton.styleFrom(foregroundColor: C.orange), onPressed: () => runAction(ctx, () async {
          await api.delete('/api/categories/${c['id']}');
          if (ctx.mounted) Navigator.pop(ctx);
        }), child: const Text('Delete')),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => runAction(ctx, () async {
          final body = {'name': name.text.trim(), 'color': color, 'kind': kind};
          c == null ? await api.post('/api/categories', body) : await api.put('/api/categories/${c['id']}', body);
          if (ctx.mounted) Navigator.pop(ctx);
        }), child: const Text('Save')),
      ],
    )));
  }
}

Future<void> editRule(BuildContext context, J? rule, List<J> cats) {
  final api = context.read<Api>();
  final wide = MediaQuery.sizeOf(context).width >= 700;
  final editor = Provider<Api>.value(value: api, child: RuleEditor(rule: rule, cats: cats));
  if (wide) return showDialog<void>(context: context, builder: (_) => Dialog(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: editor)));
  return showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true, builder: (_) => editor);
}

class RuleEditor extends StatefulWidget {
  const RuleEditor({super.key, required this.rule, required this.cats});
  final J? rule;
  final List<J> cats;
  @override
  State<RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<RuleEditor> {
  late final _name = TextEditingController(text: widget.rule?['name'] ?? '');
  late final List<J> _conds = [for (final c in (widget.rule?['conditions'] as List? ?? [])) Map<String, dynamic>.from(c as Map)];
  late int? _cat = widget.rule?['categoryId'];
  late bool _split = widget.rule?['splitByReceipt'] == true;
  late bool _past = widget.rule?['applyPast'] ?? true;
  J? _preview;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _refresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (_conds.isEmpty) { if (mounted) setState(() => _preview = null); return; }
      try {
        final p = await context.read<Api>().post('/api/rules/preview', {'conditions': _conds}) as J;
        if (mounted) setState(() => _preview = p);
      } catch (_) {}
    });
  }

  J _fresh(String f) => switch (f) {
        'amount' => {'field': f, 'op': 'less_than', 'value': ''},
        'day_of_week' => {'field': f, 'days': <String>[]},
        'time' => {'field': f, 'from': '09:00', 'to': '17:00'},
        _ => {'field': f, 'op': f == 'account' ? 'is' : 'contains', 'value': ''},
      };

  void _upd(VoidCallback f) { setState(f); _refresh(); }

  Widget _condRow(int i) {
    final c = _conds[i];
    final f = c['field'] as String;
    Widget valueField(String key, String hint, {double w = 200}) => SizedBox(width: w, child: TextFormField(
          initialValue: c[key] ?? '', decoration: InputDecoration(hintText: hint),
          onChanged: (v) => _upd(() => c[key] = v),
        ));
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: C.subtle, borderRadius: BorderRadius.circular(10), border: Border.all(color: C.border)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(width: 170, child: DropdownButtonFormField<String>(
            key: ValueKey('f$i$f'), initialValue: f, isExpanded: true,
            items: [for (final e in _fields.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => _upd(() => _conds[i] = _fresh(v!)),
          )),
          if (f == 'amount') ...[
            SizedBox(width: 130, child: DropdownButtonFormField<String>(initialValue: c['op'], items: [for (final e in _amountOps.entries) DropdownMenuItem(value: e.key, child: Text(e.value))], onChanged: (v) => _upd(() => c['op'] = v))),
            valueField('value', '£20.00', w: 120),
          ] else if (f == 'day_of_week')
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final d in _days)
                FilterChip(label: Text(d), selected: (c['days'] as List).contains(d), onSelected: (on) => _upd(() {
                  final l = List<String>.from(c['days'] as List);
                  on ? l.add(d) : l.remove(d);
                  l.sort((a, b) => _days.indexOf(a) - _days.indexOf(b));
                  c['days'] = l;
                })),
            ])
          else if (f == 'time') ...[
            const Text('between'), valueField('from', '11:00', w: 90), const Text('and'), valueField('to', '15:00', w: 90),
          ] else ...[
            SizedBox(width: 140, child: DropdownButtonFormField<String>(initialValue: c['op'], items: [for (final e in _textOps.entries) DropdownMenuItem(value: e.key, child: Text(e.value))], onChanged: (v) => _upd(() => c['op'] = v))),
            valueField('value', c['op'] == 'is_one_of' ? 'Shell, BP, Esso' : 'Tesco'),
          ],
        ])),
        IconButton(tooltip: 'Remove condition', onPressed: () => _upd(() => _conds.removeAt(i)), icon: const Icon(Icons.close, size: 18)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<Api>();
    final r = widget.rule;
    final p = _preview;
    final latest = p?['latest'] as J?;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Label(r == null ? 'New rule' : 'Edit rule'),
        Text(r == null ? 'Sort payments automatically' : r['name'], style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Rule name')),
        const SizedBox(height: 18),
        const Text('When all of these match', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (_conds.isEmpty) const Padding(padding: EdgeInsets.only(bottom: 8), child: Label('No conditions yet. Add one to say which payments this rule catches.')),
        for (var i = 0; i < _conds.length; i++) _condRow(i),
        Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: () => _upd(() => _conds.add(_fresh('merchant'))), icon: const Icon(Icons.add, size: 18), label: const Text('Add condition'))),
        const SizedBox(height: 18),
        DropdownButtonFormField<int?>(
          initialValue: _split ? -1 : _cat, decoration: const InputDecoration(labelText: 'Then set category to'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Choose a category')),
            for (final c in widget.cats) DropdownMenuItem(value: c['id'] as int, child: Text(c['name'])),
            const DropdownMenuItem(value: -1, child: Text('Split by receipt')),
          ],
          onChanged: (v) => setState(() { _split = v == -1; _cat = v == -1 ? null : v; }),
        ),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: _past, onChanged: (v) => setState(() => _past = v), title: const Text('Also apply to past transactions')),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(10)),
          child: p == null
              ? const Label('Add a condition to see which payments match.')
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Matches ${p['count']} past transactions', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Label('${money(p['total'])} in total${latest == null ? '' : ' · latest: ${latest['merchant']}, ${dDay(latest['date'])}${latest['time'] != null ? ' ${latest['time']}' : ''}, ${money(-(latest['amount'] as int))}'}'),
                ]),
        ),
        const SizedBox(height: 18),
        Wrap(alignment: WrapAlignment.spaceBetween, runSpacing: 10, children: [
          if (r != null)
            TextButton(style: TextButton.styleFrom(foregroundColor: C.orange), onPressed: () => runAction(context, () async {
              await api.delete('/api/rules/${r['id']}');
              if (context.mounted) Navigator.pop(context);
            }, done: 'Rule deleted'), child: const Text('Delete rule')),
          Wrap(spacing: 10, children: [
            OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: () => runAction(context, () async {
              final body = {'name': _name.text.trim(), 'active': r?['active'] ?? true, 'categoryId': _cat, 'splitByReceipt': _split, 'applyPast': _past, 'conditions': _conds};
              r == null ? await api.post('/api/rules', body) : await api.put('/api/rules/${r['id']}', body);
              if (context.mounted) Navigator.pop(context);
            }, done: 'Rule saved'), child: Text(r == null ? 'Create rule' : 'Save rule')),
          ]),
        ]),
      ]),
    );
  }
}
