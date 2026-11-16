import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../config.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';

const accountTypes = [('current', 'Current'), ('savings', 'Savings'), ('credit_card', 'Credit card'), ('cash', 'Cash'), ('loan', 'Loan'), ('investment', 'Investment')];

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});
  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    return Loader<List<J>>(
      load: (api) => api.accounts(),
      builder: (context, accs, _) {
        final sel = accs.where((a) => a['id'] == _selected).firstOrNull ?? accs.firstOrNull;
        final net = accs.fold<int>(0, (s, a) => s + (a['balance'] as int));
        final list = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final a in accs) ...[
            _AccountTile(a: a, selected: a == sel, onTap: () => setState(() => _selected = a['id'])),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          const CardBox(child: _NewAccountForm()),
        ]);
        return PageBody(children: [
          PageHeader(kicker: '${accs.length} accounts · net ${money(net)}', title: 'Accounts'),
          Responsive(breakpoint: 1000, flex: const [2, 3], children: [
            list,
            if (sel == null) const CardBox(child: Label('Add your first account to get started.')) else _Detail(key: ValueKey(sel['id']), a: sel),
          ]),
        ]);
      },
    );
  }
}

class AccountLogo extends StatelessWidget {
  const AccountLogo(this.a, {super.key, this.size = 40});
  final J a;
  final double size;
  @override
  Widget build(BuildContext context) {
    final logo = a['logo'] as J;
    var url = logo['url'] as String?;
    final letter = Container(
      width: size, height: size, alignment: Alignment.center,
      decoration: BoxDecoration(color: hex(logo['color']), borderRadius: BorderRadius.circular(size / 4)),
      child: Text(logo['letter'], style: TextStyle(color: Colors.white, fontFamily: display, fontWeight: FontWeight.w700, fontSize: size * .4)),
    );
    if (url == null) return Semantics(label: 'Letter icon', child: letter);
    final api = context.read<Api>();
    if (url.startsWith('/')) url = '${Config.apiBaseUrl}$url';
    return FutureBuilder<Map<String, String>>(
      future: url.startsWith(Config.apiBaseUrl) ? api.headers() : Future.value(const {}),
      builder: (context, h) => !h.hasData
          ? letter
          : ClipRRect(
              borderRadius: BorderRadius.circular(size / 4),
              child: Image.network(url!, headers: h.data, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => letter),
            ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.a, required this.selected, required this.onTap});
  final J a;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (a['source']) { 'bank_link' => ('Bank link', Tone.green), 'file_import' => ('File import', Tone.blue), _ => ('Manual', Tone.grey) };
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: selected ? C.ink : C.border, width: selected ? 2 : 1)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            AccountLogo(a),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a['name'], style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Pill(label, tone: tone),
            ])),
            Num(money(a['balance']), bold: true),
          ]),
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({super.key, required this.a});
  final J a;
  @override
  Widget build(BuildContext context) {
    final api = context.read<Api>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CardBox(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(alignment: WrapAlignment.spaceBetween, runSpacing: 12, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a['name'], style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Label('${accountTypes.firstWhere((t) => t.$1 == a['type'], orElse: () => (a['type'], a['type'])).$2} · opening ${money(a['openingBalance'])} on ${dShort(a['openingDate'])}'),
            ]),
            Wrap(spacing: 8, children: [
              OutlinedButton(onPressed: () => _settings(context), child: const Text('Settings')),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: C.orange),
                onPressed: () async {
                  final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
                    title: Text('Delete ${a['name']}?'),
                    content: const Text('This removes the account and all of its transactions. It can\'t be undone.'),
                    actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete'))],
                  ));
                  if (ok == true && context.mounted) await runAction(context, () => api.delete('/api/accounts/${a['id']}'), done: 'Account deleted');
                },
                child: const Text('Delete'),
              ),
            ]),
          ]),
          const SizedBox(height: 16),
          Loader<List<J>>(
            deps: [a['balance']],
            load: (api) async => (await api.get('/api/accounts/${a['id']}/balances', {'days': '14'}) as List).cast<J>(),
            builder: (context, days, _) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingTextStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.label),
                columns: const [DataColumn(label: Text('DAY')), DataColumn(label: Text('BALANCE SOURCE')), DataColumn(label: Text('CALCULATED'), numeric: true), DataColumn(label: Text('END-OF-DAY BALANCE'), numeric: true)],
                rows: [
                  for (final d in days)
                    DataRow(
                      color: WidgetStatePropertyAll(d['overridden'] == true ? C.orangeSoft : null),
                      cells: [
                        DataCell(Text(dDay(d['date']), style: TextStyle(fontWeight: d['overridden'] == true ? FontWeight.w700 : null))),
                        DataCell(d['overridden'] == true ? const Pill('Overridden by you', tone: Tone.orange) : (d['note'] == 'Opening balance' ? const Pill('Opening balance', tone: Tone.blue) : const Pill('Calculated'))),
                        DataCell(Num(money(d['calculated']), color: C.label, strike: d['overridden'] == true)),
                        DataCell(Num(money(d['balance']), bold: true)),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      CardBox(child: _LogoCard(a: a)),
      const SizedBox(height: 16),
      CardBox(child: _OverrideForm(a: a)),
      if (a['source'] == 'manual') ...[const SizedBox(height: 16), CardBox(child: _ManualTxForm(a: a))],
    ]);
  }

  Future<void> _settings(BuildContext context) async {
    final api = context.read<Api>();
    final name = TextEditingController(text: a['name']);
    final opening = TextEditingController(text: ((a['openingBalance'] as int) / 100).toStringAsFixed(2));
    var savings = a['countsTowardsSavings'] as bool;
    var type = a['type'] as String;
    await showDialog<void>(context: context, builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
      title: const Text('Account settings'),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Account name')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(initialValue: type, decoration: const InputDecoration(labelText: 'Type'),
            items: [for (final t in accountTypes) DropdownMenuItem(value: t.$1, child: Text(t.$2))], onChanged: (v) => set(() => type = v!)),
        const SizedBox(height: 12),
        TextField(controller: opening, decoration: const InputDecoration(labelText: 'Opening balance', prefixText: '£')),
        CheckboxListTile(contentPadding: EdgeInsets.zero, value: savings, onChanged: (v) => set(() => savings = v!), title: const Text('Count towards savings goal')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(onPressed: () => runAction(c, () async {
          await api.patch('/api/accounts/${a['id']}', {'name': name.text, 'type': type, 'countsTowardsSavings': savings, 'openingBalance': parseMoney(opening.text) ?? 0});
          if (c.mounted) Navigator.pop(c);
        }), child: const Text('Save')),
      ],
    )));
  }
}

class _LogoCard extends StatefulWidget {
  const _LogoCard({required this.a});
  final J a;
  @override
  State<_LogoCard> createState() => _LogoCardState();
}

class _LogoCardState extends State<_LogoCard> {
  late final J logo = widget.a['logo'];
  late String _mode = logo['mode'];
  late final _site = TextEditingController(text: logo['website'] ?? '');
  late final _social = TextEditingController(text: logo['social'] ?? '');

  @override
  Widget build(BuildContext context) {
    final api = context.read<Api>();
    final used = switch (logo['resolved']) { 'upload' => 'your uploaded image', 'website' => 'the website icon', 'social' => 'the social profile picture', _ => 'a letter icon' };
    Widget opt(String v, String title, Widget sub) => RadioListTile<String>(
          value: v, contentPadding: EdgeInsets.zero,
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)), subtitle: sub,
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('Account logo', style: sectionTitle)),
        if (logo['mode'] == 'automatic') const Pill('Found automatically', tone: Tone.green),
      ]),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [AccountLogo(widget.a, size: 64), const SizedBox(width: 14), Expanded(child: TwoLine(widget.a['name'], 'Using: $used'))]),
      ),
      const SizedBox(height: 8),
      RadioGroup<String>(
        groupValue: _mode,
        onChanged: (v) => setState(() => _mode = v!),
        child: Column(children: [
          opt('automatic', 'Automatic', const Label('Tries each source below in order and uses the first one found')),
          opt('website', 'Website', TextField(controller: _site, decoration: const InputDecoration(hintText: 'monzo.com'))),
          opt('social', 'Social profile picture', TextField(controller: _social, decoration: const InputDecoration(hintText: '@monzo'))),
          opt('upload', 'Upload an image', const Label('PNG, JPG or SVG, square works best')),
          opt('letter', 'Letter icon', const Label('First letter on a colour')),
        ]),
      ),
      const Label('Automatic order: uploaded image → website icon → social profile picture → letter icon.'),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        FilledButton(
          onPressed: () => runAction(context, () async {
            if (_mode == 'upload') {
              final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['png', 'jpg', 'jpeg', 'svg']);
              if (f == null) return;
              final ext = (f.extension ?? 'png').toLowerCase();
              await api.uploadLogo(widget.a['id'], await f.xFile.readAsBytes(), ext == 'svg' ? 'image/svg+xml' : (ext == 'png' ? 'image/png' : 'image/jpeg'));
            }
            await api.patch('/api/accounts/${widget.a['id']}', {'logoMode': _mode, 'logoWebsite': _site.text, 'logoSocial': _social.text});
          }, done: 'Logo saved'),
          child: Text(_mode == 'upload' ? 'Choose image…' : 'Save'),
        ),
      ]),
    ]);
  }
}

class _OverrideForm extends StatefulWidget {
  const _OverrideForm({required this.a});
  final J a;
  @override
  State<_OverrideForm> createState() => _OverrideFormState();
}

class _OverrideFormState extends State<_OverrideForm> {
  DateTime _day = DateTime.now();
  final _bal = TextEditingController();
  final _note = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final api = context.read<Api>();
    final id = widget.a['id'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Override balance on a day', style: sectionTitle),
      const SizedBox(height: 8),
      const Label('Use this when your bank shows a different figure. Every day after this one is recalculated from the new balance.'),
      const SizedBox(height: 14),
      Wrap(spacing: 12, runSpacing: 12, children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.calendar_today_outlined, size: 16),
          label: Text(dDay(isoDate(_day))),
          onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime.parse(widget.a['openingDate']), lastDate: DateTime.now());
            if (d != null) setState(() => _day = d);
          },
        ),
        SizedBox(width: 200, child: TextField(controller: _bal, keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true), decoration: const InputDecoration(labelText: 'Balance at end of day', prefixText: '£'))),
      ]),
      const SizedBox(height: 12),
      TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note (optional)')),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        FilledButton(onPressed: () => runAction(context, () async {
          final b = parseMoney(_bal.text);
          if (b == null) throw 'Enter the balance';
          await api.put('/api/accounts/$id/overrides', {'date': isoDate(_day), 'balance': b, 'note': _note.text.isEmpty ? null : _note.text});
        }, done: 'Override saved'), child: const Text('Save override')),
        OutlinedButton(onPressed: () => runAction(context, () => api.delete('/api/accounts/$id/overrides/${isoDate(_day)}'), done: 'Override removed'), child: const Text('Remove override')),
      ]),
    ]);
  }
}

class _ManualTxForm extends StatefulWidget {
  const _ManualTxForm({required this.a});
  final J a;
  @override
  State<_ManualTxForm> createState() => _ManualTxFormState();
}

class _ManualTxFormState extends State<_ManualTxForm> {
  final _m = TextEditingController();
  final _amt = TextEditingController();
  bool _out = true;
  DateTime _day = DateTime.now();
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Add a transaction', style: sectionTitle),
        const SizedBox(height: 12),
        TextField(controller: _m, decoration: const InputDecoration(labelText: 'What for')),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(width: 160, child: TextField(controller: _amt, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount', prefixText: '£'))),
          SegmentedButton<bool>(segments: const [ButtonSegment(value: true, label: Text('Money out')), ButtonSegment(value: false, label: Text('Money in'))], selected: {_out}, onSelectionChanged: (s) => setState(() => _out = s.first)),
          OutlinedButton(onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime(2000), lastDate: DateTime.now());
            if (d != null) setState(() => _day = d);
          }, child: Text(dDay(isoDate(_day)))),
        ]),
        const SizedBox(height: 12),
        Align(alignment: Alignment.centerLeft, child: FilledButton(onPressed: () => runAction(context, () async {
          final p = parseMoney(_amt.text);
          if (_m.text.trim().isEmpty || p == null) throw 'Add a description and amount';
          await context.read<Api>().post('/api/transactions', {'accountId': widget.a['id'], 'date': isoDate(_day), 'merchant': _m.text.trim(), 'amount': _out ? -p.abs() : p.abs()});
          _m.clear(); _amt.clear();
        }, done: 'Added'), child: const Text('Add transaction'))),
      ]);
}

class _NewAccountForm extends StatefulWidget {
  const _NewAccountForm();
  @override
  State<_NewAccountForm> createState() => _NewAccountFormState();
}

class _NewAccountFormState extends State<_NewAccountForm> {
  final _name = TextEditingController();
  final _site = TextEditingController();
  final _bal = TextEditingController(text: '0.00');
  String _type = 'current';
  String _source = 'file_import';
  bool _savings = false;
  DateTime _asOf = DateTime.now();

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Add an account', style: sectionTitle),
        const SizedBox(height: 6),
        const Label('Import a bank file into it, or add transactions and balances yourself.'),
        const SizedBox(height: 14),
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'file_import', label: Text('File import')), ButtonSegment(value: 'manual', label: Text('Manual'))],
          selected: {_source}, onSelectionChanged: (s) => setState(() => _source = s.first),
        ),
        const SizedBox(height: 12),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Account name')),
        const SizedBox(height: 12),
        TextField(controller: _site, decoration: const InputDecoration(labelText: 'Logo — website (optional)', hintText: 'nsandi.com')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(initialValue: _type, decoration: const InputDecoration(labelText: 'Type'),
            items: [for (final t in accountTypes) DropdownMenuItem(value: t.$1, child: Text(t.$2))], onChanged: (v) => setState(() => _type = v!)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: _bal, decoration: const InputDecoration(labelText: 'Opening balance', prefixText: '£'))),
          const SizedBox(width: 12),
          Expanded(child: OutlinedButton(onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: _asOf, firstDate: DateTime(2000), lastDate: DateTime.now());
            if (d != null) setState(() => _asOf = d);
          }, child: Text('As of ${dShort(isoDate(_asOf))}'))),
        ]),
        CheckboxListTile(contentPadding: EdgeInsets.zero, value: _savings, onChanged: (v) => setState(() => _savings = v!), title: const Text('Count towards savings goal')),
        FilledButton(onPressed: () => runAction(context, () async {
          if (_name.text.trim().isEmpty) throw 'Give the account a name';
          await context.read<Api>().post('/api/accounts', {
            'name': _name.text.trim(), 'type': _type, 'source': _source, 'openingBalance': parseMoney(_bal.text) ?? 0,
            'openingDate': isoDate(_asOf), 'countsTowardsSavings': _savings, 'logoWebsite': _site.text.trim(),
          });
          _name.clear(); _site.clear();
        }, done: 'Account added'), child: const Text('Add account')),
      ]);
}
