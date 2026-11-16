import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';

const _uses = {
  'date': 'Date', 'time': 'Time', 'description': 'Description', 'merchant': 'Merchant', 'amount': 'Amount',
  'money_out': 'Money out', 'money_in': 'Money in', 'balance': 'Balance check', 'reference': 'Reference (stops duplicates)',
  'notes': 'Notes', 'bank_category': 'Bank\'s category (hint)', 'skip': 'Don\'t import',
};
const _reasons = {'name': 'Matched by name', 'saved_layout': 'From saved layout', 'unique_values': 'Every value is different', 'unsure': 'Not sure — we suggest skipping it'};

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});
  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  int? _account;
  String? _content;
  J? _parsed;
  List<J> _mapping = [];
  String _dateFormat = 'dmy';
  String _sign = 'positive_in';
  bool _remember = true;
  bool _busy = false;

  Future<void> _pick(Api api) async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['csv', 'txt', 'tsv']);
    if (f == null) return;
    final text = utf8.decode(await f.xFile.readAsBytes(), allowMalformed: true);
    _content = text;
    await _parse(api, f.name);
  }

  Future<void> _parse(Api api, String name) async {
    setState(() => _busy = true);
    try {
      final r = await api.post('/api/import/parse', {'accountId': _account, 'fileName': name, 'content': _content}) as J;
      setState(() {
        _parsed = r;
        _mapping = (r['mapping'] as List).cast<J>().map((m) => Map<String, dynamic>.from(m)).toList();
        _dateFormat = r['dateFormat'];
        _sign = r['signConvention'];
      });
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<Api>();
    return Loader<List<J>>(
      load: (api) => api.accounts(),
      builder: (context, accs, _) {
        final importable = accs.where((a) => a['source'] != 'bank_link').toList();
        _account ??= importable.firstOrNull?['id'];
        final step = _parsed == null ? 1 : 2;
        return PageBody(children: [
          const PageHeader(kicker: 'Bank files', title: 'Import'),
          CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 24, runSpacing: 8, children: [
              _Step(1, 'Upload', done: step > 1, on: step == 1),
              _Step(2, 'Check matches', done: false, on: step == 2),
              const _Step(3, 'Import', done: false, on: false),
            ]),
            const SizedBox(height: 20),
            if (importable.isEmpty)
              const Label('Add an account first (Accounts → Add an account), then import its CSV file here.')
            else ...[
              Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(width: 280, child: DropdownButtonFormField<int>(
                  initialValue: _account, isExpanded: true, decoration: const InputDecoration(labelText: 'Import into'),
                  items: [for (final a in importable) DropdownMenuItem(value: a['id'] as int, child: Text(a['name']))],
                  onChanged: (v) => setState(() { _account = v; _parsed = null; }),
                )),
                FilledButton.icon(
                  onPressed: _busy ? null : () => runAction(context, () => _pick(api)),
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: Text(_parsed == null ? 'Upload a CSV file' : 'Replace file'),
                ),
                if (_busy) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ]),
              const SizedBox(height: 8),
              const Label('CSV exports from any bank or card work. We read the column names and match them for you.'),
            ],
          ])),
          if (_parsed != null) ..._check(context, api),
          const _Examples(),
        ]);
      },
    );
  }

  List<Widget> _check(BuildContext context, Api api) {
    final p = _parsed!;
    final headers = (p['headers'] as List).cast<String>();
    final rows = (p['sampleRows'] as List).map((r) => (r as List).cast<String>()).toList();
    final preview = (p['preview'] as List).cast<J>();
    final unsure = _mapping.where((m) => m['confident'] != true).length;
    final errors = (p['errors'] as List).cast<String>();
    return [
      CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [const Pill('CSV', tone: Tone.blue), const SizedBox(width: 10), Expanded(child: TwoLine(p['fileName'], '${p['totalRows']} rows · ${headers.length} columns'))]),
        const SizedBox(height: 14),
        Note(Text('We read the ${headers.length} column names from your file and matched ${headers.length - unsure} automatically.'
            '${p['usedSavedLayout'] == true ? ' It looks like the layout you saved last time.' : ''}'
            '${unsure > 0 ? ' Check the one${unsure > 1 ? 's' : ''} marked in orange, then continue.' : ''}')),
        const SizedBox(height: 16),
        Wrap(spacing: 12, runSpacing: 12, children: [
          SizedBox(width: 260, child: DropdownButtonFormField<String>(
            initialValue: _dateFormat, decoration: InputDecoration(labelText: 'Date format', helperText: p['dateExample'] == null ? null : 'Found dates like “${p['dateExample']}”'),
            items: const [DropdownMenuItem(value: 'dmy', child: Text('Day / month / year')), DropdownMenuItem(value: 'mdy', child: Text('Month / day / year')), DropdownMenuItem(value: 'ymd', child: Text('Year-month-day'))],
            onChanged: (v) => setState(() => _dateFormat = v!),
          )),
          if (_mapping.any((m) => m['use'] == 'amount'))
            SizedBox(width: 260, child: DropdownButtonFormField<String>(
              initialValue: _sign, decoration: const InputDecoration(labelText: 'Money in or out'),
              items: const [DropdownMenuItem(value: 'positive_in', child: Text('Positive = money in')), DropdownMenuItem(value: 'positive_out', child: Text('Positive = money out'))],
              onChanged: (v) => setState(() => _sign = v!),
            )),
        ]),
        const SizedBox(height: 20),
        const Text('Your file, with our matches on top', style: TextStyle(fontWeight: FontWeight.w600)),
        const Label('First rows · scroll sideways for more'),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: const TableBorder(horizontalInside: BorderSide(color: C.rule)),
            children: [
              TableRow(children: [
                for (var i = 0; i < _mapping.length; i++)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 12, 10),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: _mapping[i]['confident'] == true ? C.subtle : C.orangeSoft, borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _mapping[i]['confident'] == true ? C.border : C.accentLight)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        DropdownButton<String>(
                          value: _mapping[i]['use'], isDense: true, underline: const SizedBox(),
                          items: [for (final e in _uses.entries) DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)))],
                          onChanged: (v) => setState(() { _mapping[i]['use'] = v; _mapping[i]['confident'] = true; _mapping[i]['reason'] = 'you'; }),
                        ),
                        Text(_mapping[i]['confident'] == true ? '✓ ${_reasons[_mapping[i]['reason']] ?? 'Chosen by you'}' : '! ${_reasons['unsure']}',
                            style: TextStyle(fontSize: 11, color: _mapping[i]['confident'] == true ? C.green : C.orange)),
                      ]),
                    ),
                  ),
              ]),
              TableRow(decoration: const BoxDecoration(color: C.subtle), children: [
                for (final h in headers) Padding(padding: const EdgeInsets.all(8), child: Text(h, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
              ]),
              for (final r in rows)
                TableRow(children: [
                  for (var i = 0; i < headers.length; i++) Padding(padding: const EdgeInsets.all(8), child: Text(i < r.length ? r[i] : '', style: const TextStyle(fontSize: 13, fontFeatures: tabular))),
                ]),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text('Preview — how these rows will be imported', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        for (final r in preview)
          RowLine(
            left: TwoLine(r['merchant'], '${dShort(r['date'])} · ${r['categoryName'] ?? 'No rule matched'}'),
            right: Row(mainAxisSize: MainAxisSize.min, children: [
              r['duplicate'] == true ? const Pill('Already imported · skip') : const Pill('New', tone: Tone.green),
              const SizedBox(width: 12),
              SizedBox(width: 96, child: Align(alignment: Alignment.centerRight, child: Num(money(r['amount'], signed: true), bold: true))),
            ]),
          ),
        if (errors.isNotEmpty) ...[const SizedBox(height: 12), Note(Text('${errors.length} rows can\'t be read: ${errors.take(3).join('; ')}'))],
        const SizedBox(height: 12),
        CheckboxListTile(contentPadding: EdgeInsets.zero, value: _remember, onChanged: (v) => setState(() => _remember = v!), title: const Text('Remember these matches for this account')),
        Wrap(spacing: 10, children: [
          OutlinedButton(onPressed: () => setState(() => _parsed = null), child: const Text('Back')),
          FilledButton(
            onPressed: _busy ? null : () => runAction(context, () async {
              setState(() => _busy = true);
              try {
                final r = await api.post('/api/import/commit', {
                  'accountId': _account, 'content': _content, 'mapping': _mapping, 'dateFormat': _dateFormat, 'signConvention': _sign, 'rememberLayout': _remember,
                }) as J;
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imported ${r['imported']} rows · skipped ${r['duplicates']} already imported'
                    '${(r['receiptsMatched'] as int) > 0 ? ' · matched ${r['receiptsMatched']} receipts' : ''}')));
                setState(() { _parsed = null; _content = null; });
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            }),
            child: Text('Import ${p['newRows']} new rows'),
          ),
        ]),
      ])),
    ];
  }
}

class _Step extends StatelessWidget {
  const _Step(this.n, this.label, {required this.done, required this.on});
  final int n;
  final String label;
  final bool done, on;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(radius: 13, backgroundColor: done || on ? C.ink : C.greyBg,
            child: Text(done ? '✓' : '$n', style: TextStyle(fontSize: 12, color: done || on ? Colors.white : C.label, fontWeight: FontWeight.w700))),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on || done ? C.ink : C.label)),
      ]);
}

class _Examples extends StatelessWidget {
  const _Examples();
  @override
  Widget build(BuildContext context) {
    Widget ex(String title, String sub, List<(String, String)> m) => CardBox(
          color: C.subtle,
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Label(sub),
            const SizedBox(height: 10),
            for (final (a, b) in m) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('$a → $b', style: const TextStyle(fontSize: 13))),
          ]),
        );
    return CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Examples of files we can match', style: sectionTitle),
      const SizedBox(height: 4),
      const Label('Banks name their columns differently. These made-up examples show how each layout gets matched.'),
      const SizedBox(height: 14),
      TileGrid(minWidth: 240, children: [
        ex('One amount column', 'A minus sign means money in, or money out, depending on the bank', const [('Date', 'Date'), ('Description', 'Description'), ('Amount', 'Amount')]),
        ex('Separate in and out columns', 'Two columns, one of them blank on each row', const [('Transaction Date', 'Date'), ('Details', 'Description'), ('Paid out', 'Money out'), ('Paid in', 'Money in'), ('Balance', 'Balance check')]),
        ex('Date and time apart', 'Time is kept, so rules like “11:00–15:00” still work', const [('Date', 'Date'), ('Time', 'Time'), ('Name', 'Merchant'), ('Category', 'Bank\'s category (hint)'), ('Value', 'Amount')]),
      ]),
    ]));
  }
}
