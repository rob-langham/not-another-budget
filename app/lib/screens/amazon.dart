import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';

class AmazonScreen extends StatefulWidget {
  const AmazonScreen({super.key});
  @override
  State<AmazonScreen> createState() => _AmazonScreenState();
}

class _AmazonScreenState extends State<AmazonScreen> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    return Loader<(J, List<J>, List<J>)>(
      load: (api) async => (await api.get('/api/me') as J, (await api.get('/api/receipts') as List).cast<J>(), await api.categories()),
      builder: (context, d, _) {
        final (me, receipts, cats) = d;
        final sel = receipts.where((r) => r['id'] == _selected).firstOrNull ?? receipts.where((r) => r['status'] == 'ready').firstOrNull;
        return PageBody(children: [
          PageHeader(kicker: 'Split one card payment into the items you bought', title: 'Amazon receipts', actions: [
            OutlinedButton(onPressed: () => _paste(context), child: const Text('Paste an order email')),
          ]),
          Responsive(breakpoint: 1000, flex: const [2, 3], children: [
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Your forwarding address', style: sectionTitle),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(10)),
                    child: SelectableText(me['forwardingAddress'], style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
                  )),
                  const SizedBox(width: 10),
                  OutlinedButton(onPressed: () {
                    Clipboard.setData(ClipboardData(text: me['forwardingAddress']));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                  }, child: const Text('Copy')),
                ]),
                const SizedBox(height: 8),
                const Label('Tip: set up an auto-forward rule in your email for order confirmations.'),
                const SizedBox(height: 16),
                for (final (n, t) in const [(1, 'Forward an Amazon order email to the address.'), (2, 'We find the matching card payment by total and date.'), (3, 'Check the items and categories, then save the split.')])
                  Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(children: [
                    CircleAvatar(radius: 12, backgroundColor: C.ink, child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 12))),
                    const SizedBox(width: 10),
                    Expanded(child: Text(t, style: const TextStyle(fontSize: 14))),
                  ])),
              ])),
              const SizedBox(height: 16),
              CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Received emails', style: sectionTitle),
                const SizedBox(height: 6),
                if (receipts.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Label('None yet. Forward or paste an order email.')),
                for (final r in receipts)
                  InkWell(
                    onTap: () => setState(() => _selected = r['id']),
                    child: Container(
                      color: r == sel ? C.subtle : null,
                      child: RowLine(
                        left: TwoLine('Order of ${(r['items'] as List).length} item${(r['items'] as List).length == 1 ? '' : 's'}',
                            '${dDay(r['orderDate'])} · ${r['transaction'] == null ? 'not charged yet' : r['transaction']['accountName']}'),
                        right: Row(mainAxisSize: MainAxisSize.min, children: [
                          switch (r['status']) {
                            'ready' => const Pill('Ready to split', tone: Tone.orange),
                            'saved' => const Pill('Split saved', tone: Tone.green),
                            _ => const Pill('Waiting for payment'),
                          },
                          const SizedBox(width: 12),
                          Num(money(r['total']), bold: true),
                        ]),
                      ),
                    ),
                  ),
              ])),
            ]),
            if (sel == null)
              const CardBox(child: Label('Pick a receipt to split it.'))
            else
              CardBox(child: _SplitEditor(key: ValueKey('${sel['id']}-${sel['status']}'), r: sel, cats: cats)),
          ]),
        ]);
      },
    );
  }

  Future<void> _paste(BuildContext context) async {
    final api = context.read<Api>();
    final text = TextEditingController();
    await showDialog<void>(context: context, builder: (c) => AlertDialog(
      title: const Text('Paste an order email'),
      content: SizedBox(width: 520, child: TextField(controller: text, maxLines: 14, decoration: const InputDecoration(hintText: 'Paste the whole order-confirmation email here'))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(onPressed: () => runAction(c, () async {
          final r = await api.post('/api/receipts', {'text': text.text}) as J;
          if (c.mounted) Navigator.pop(c);
          setState(() => _selected = r['id']);
        }), child: const Text('Add receipt')),
      ],
    ));
  }
}

class _SplitEditor extends StatefulWidget {
  const _SplitEditor({super.key, required this.r, required this.cats});
  final J r;
  final List<J> cats;
  @override
  State<_SplitEditor> createState() => _SplitEditorState();
}

class _SplitEditorState extends State<_SplitEditor> {
  late final List<J> _items = (widget.r['items'] as List).map((i) => Map<String, dynamic>.from(i as Map)).toList();
  late final List<TextEditingController> _amts = [for (final i in _items) TextEditingController(text: ((i['amount'] as int) / 100).toStringAsFixed(2))];

  @override
  Widget build(BuildContext context) {
    final tx = widget.r['transaction'] as J?;
    final total = widget.r['total'] as int;
    final allocated = _items.fold<int>(0, (s, i) => s + (i['amount'] as int));
    final balanced = allocated == total;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Split ${money(total)}', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 6),
      if (tx != null)
        Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Label('Matched to: ${tx['description']} · ${tx['accountName']} · ${dShort(tx['date'])}'),
          const Pill('Matched by total & date', tone: Tone.green),
        ])
      else
        const Label('No matching card payment yet. Import your card statement and we\'ll match it by total and date.'),
      const SizedBox(height: 16),
      for (var n = 0; n < _items.length; n++)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.rule))),
          child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, alignment: WrapAlignment.spaceBetween, children: [
            ConstrainedBox(constraints: const BoxConstraints(minWidth: 200, maxWidth: 300), child: TwoLine(_items[n]['name'], 'Qty ${_items[n]['qty']}')),
            Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 190, child: DropdownButtonFormField<int?>(
                initialValue: _items[n]['categoryId'], isExpanded: true, decoration: const InputDecoration(labelText: 'Category'),
                items: [const DropdownMenuItem(value: null, child: Text('Choose')), for (final c in widget.cats) DropdownMenuItem(value: c['id'] as int, child: Text(c['name']))],
                onChanged: (v) => setState(() => _items[n]['categoryId'] = v),
              )),
              const SizedBox(width: 10),
              SizedBox(width: 110, child: TextField(
                controller: _amts[n], textAlign: TextAlign.right, decoration: const InputDecoration(prefixText: '£'),
                onChanged: (v) => setState(() => _items[n]['amount'] = parseMoney(v) ?? 0),
              )),
            ]),
          ]),
        ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: balanced ? C.greenBg : C.orangeBg, borderRadius: BorderRadius.circular(10)),
        child: Text(balanced ? '✓ Balanced · ${money(allocated)} of ${money(total)} allocated' : '${money(allocated)} of ${money(total)} allocated · ${money(total - allocated)} left',
            style: TextStyle(color: balanced ? C.green : C.orange, fontWeight: FontWeight.w600)),
      ),
      const SizedBox(height: 14),
      Wrap(spacing: 10, runSpacing: 10, children: [
        OutlinedButton(onPressed: () => setState(() {
          _items.add({'name': 'Other', 'qty': 1, 'amount': total - allocated, 'categoryId': null});
          _amts.add(TextEditingController(text: ((total - allocated) / 100).toStringAsFixed(2)));
        }), child: const Text('Add line')),
        FilledButton(
          onPressed: tx == null || !balanced ? null : () => runAction(context, () => context.read<Api>().post('/api/receipts/${widget.r['id']}/save', {'items': _items}), done: 'Split saved'),
          child: Text(widget.r['status'] == 'saved' ? 'Update split' : 'Save split'),
        ),
        TextButton(style: TextButton.styleFrom(foregroundColor: C.orange), onPressed: () => runAction(context, () => context.read<Api>().delete('/api/receipts/${widget.r['id']}')), child: const Text('Delete receipt')),
      ]),
    ]);
  }
}
