import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';

/// Bottom sheet to pick a category. Returns the id, or -1 for "let rules decide".
Future<int?> pickCategory(BuildContext context, List<J> cats, int? current, {bool allowClear = false}) =>
    showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const Padding(padding: EdgeInsets.fromLTRB(24, 0, 24, 8), child: Text('Choose a category', style: TextStyle(fontFamily: display, fontWeight: FontWeight.w700, fontSize: 18))),
          for (final cat in cats)
            ListTile(
              leading: CategoryDot(hex(cat['color']), size: 14),
              title: Text(cat['name']),
              trailing: cat['id'] == current ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(c, cat['id'] as int),
            ),
          if (allowClear) ListTile(leading: const Icon(Icons.auto_fix_high, size: 18), title: const Text('Let my rules decide'), onTap: () => Navigator.pop(c, -1)),
        ]),
      ),
    );

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});
  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _byCategory = false;
  int? _cat;
  String _q = '';
  final _search = TextEditingController();
  int? _openCat;

  String get _ym => '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Loader<(J, List<J>)>(
      deps: [_ym, _cat, _q],
      load: (api) async => (
        await api.get('/api/transactions', {'month': _ym, 'q': _q, 'categoryId': _cat?.toString()}) as J,
        await api.categories(),
      ),
      builder: (context, d, _) {
        final (page, cats) = d;
        final catById = {for (final c in cats) c['id'] as int: c};
        final txs = (page['transactions'] as List).cast<J>();
        final byCat = (page['byCategory'] as List).cast<J>();
        return PageBody(children: [
          PageHeader(kicker: 'All accounts', title: 'Transactions', actions: [
            IconButton(tooltip: 'Previous month', onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)), icon: const Icon(Icons.chevron_left)),
            Padding(padding: const EdgeInsets.only(top: 12), child: Text(dMonthLong(_ym), style: const TextStyle(fontWeight: FontWeight.w600))),
            IconButton(tooltip: 'Next month', onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)), icon: const Icon(Icons.chevron_right)),
          ]),
          TileGrid(minWidth: 180, children: [
            StatTile(label: 'Spent', value: money(page['spent'])),
            StatTile(label: 'Money in', value: money(page['moneyIn'])),
            StatTile(label: 'Moved to savings', value: money(page['movedToSavings'])),
            StatTile(label: 'So far', value: '${page['count']}'),
          ]),
          CardBox(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, alignment: WrapAlignment.spaceBetween, children: [
                Text('Where the money went', style: sectionTitle),
                SegmentedButton<bool>(
                  segments: const [ButtonSegment(value: false, label: Text('By day')), ButtonSegment(value: true, label: Text('By category'))],
                  selected: {_byCategory}, onSelectionChanged: (s) => setState(() => _byCategory = s.first),
                ),
              ]),
              const SizedBox(height: 14),
              Wrap(spacing: 12, runSpacing: 12, children: [
                SizedBox(width: 280, child: TextField(
                  controller: _search,
                  decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 18), hintText: 'Search merchant or item',
                      suffixIcon: _q.isEmpty ? null : IconButton(tooltip: 'Clear search', icon: const Icon(Icons.close, size: 16), onPressed: () { _search.clear(); setState(() => _q = ''); })),
                  onSubmitted: (v) => setState(() => _q = v.trim()),
                )),
                SizedBox(width: 240, child: DropdownButtonFormField<int?>(
                  initialValue: _cat, isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [const DropdownMenuItem(value: null, child: Text('All categories')), for (final c in cats) DropdownMenuItem(value: c['id'] as int, child: Text(c['name']))],
                  onChanged: (v) => setState(() => _cat = v),
                )),
              ]),
              const SizedBox(height: 8),
              if (txs.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: Label('No transactions match. Try another search or category.'))),
              if (!_byCategory) ..._byDay(txs, catById, cats) else ..._byCategoryView(byCat, txs, catById),
            ]),
          ),
        ]);
      },
    );
  }

  List<Widget> _byDay(List<J> txs, Map<int, J> catById, List<J> cats) {
    final groups = <String, List<J>>{};
    for (final t in txs) {
      groups.putIfAbsent(t['date'], () => []).add(t);
    }
    return [
      for (final e in groups.entries) ...[
        Container(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: C.subtle, borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            Expanded(child: Text(dDay(e.key), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
            Num(money(e.value.fold<int>(0, (s, t) => s + (t['amount'] as int))), color: C.label, size: 13),
          ]),
        ),
        for (final t in e.value) TxRow(t: t, catById: catById, cats: cats),
      ],
    ];
  }

  List<Widget> _byCategoryView(List<J> byCat, List<J> txs, Map<int, J> catById) {
    final total = byCat.fold<int>(0, (s, c) => s + (c['total'] as int));
    return [
      if (total > 0)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(height: 14, child: Row(children: [
              for (final c in byCat.where((c) => (c['total'] as int) > 0))
                Expanded(flex: ((c['total'] as int) * 1000 ~/ total).clamp(1, 1000), child: Container(color: hex(c['color']))),
            ])),
          ),
        ),
      for (final c in byCat) ...[
        InkWell(
          onTap: () => setState(() => _openCat = _openCat == c['categoryId'] ? null : c['categoryId']),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.rule))),
            child: Row(children: [
              CategoryDot(hex(c['color']), size: 12),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c['name'], style: const TextStyle(fontWeight: FontWeight.w700)),
                Label('${c['count']} payments${c['budget'] != null ? ' · ${money(c['budget'])} budget' : ''}'),
              ])),
              Num(money(c['total']), bold: true),
              Icon(_openCat == c['categoryId'] ? Icons.expand_less : Icons.expand_more, color: C.label),
            ]),
          ),
        ),
        if (_openCat == c['categoryId'])
          for (final t in txs.where((t) => t['categoryId'] == c['categoryId'] || (t['splits'] as List).any((s) => s['categoryId'] == c['categoryId'])))
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: RowLine(left: TwoLine(t['merchant'], dDay(t['date'])), right: Num(money(t['amount']))),
            ),
      ],
    ];
  }
}

class TxRow extends StatelessWidget {
  const TxRow({super.key, required this.t, required this.catById, required this.cats});
  final J t;
  final Map<int, J> catById;
  final List<J> cats;

  @override
  Widget build(BuildContext context) {
    final api = context.read<Api>();
    final cat = catById[t['categoryId']];
    final splits = (t['splits'] as List).cast<J>();
    final sub = [
      if (t['time'] != null) t['time'],
      t['accountName'],
      if (t['ruleName'] != null) 'rule: ${t['ruleName']}',
      if (t['plannedAs'] != null) 'planned: ${t['plannedAs']}',
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.rule))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(t['merchant'], style: const TextStyle(fontWeight: FontWeight.w700)),
              if (t['isOutlier'] == true) const Pill('Outlier', tone: Tone.orange),
            ]),
            const SizedBox(height: 3),
            Label(sub),
          ])),
          const SizedBox(width: 8),
          if (splits.isNotEmpty)
            Pill('Split · ${splits.length} items', tone: Tone.blue)
          else if (t['awaitingReceipt'] == true)
            const Pill('Waiting for receipt', tone: Tone.blue)
          else
            ActionChip(
              avatar: cat == null ? null : CategoryDot(hex(cat['color'])),
              label: Text(cat?['name'] ?? 'Choose category'),
              onPressed: () async {
                final c = await pickCategory(context, cats, t['categoryId'], allowClear: true);
                if (c == null || !context.mounted) return;
                await runAction(context, () => api.patch('/api/transactions/${t['id']}', c == -1 ? {'clearCategory': true} : {'categoryId': c}));
              },
            ),
          const SizedBox(width: 12),
          SizedBox(width: 96, child: Align(alignment: Alignment.centerRight, child: Num(money(t['amount']), bold: true, color: (t['amount'] as int) > 0 ? C.green : null))),
        ]),
        for (final s in splits)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 6),
            child: Row(children: [
              CategoryDot(catById[s['categoryId']] == null ? C.label : hex(catById[s['categoryId']]!['color'])),
              const SizedBox(width: 8),
              Expanded(child: Label('${s['name']} · ${catById[s['categoryId']]?['name'] ?? 'No category'}')),
              Num(money(s['amount']), color: C.label, size: 13),
            ]),
          ),
      ]),
    );
  }
}
