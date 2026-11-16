import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:longview/api.dart';
import 'package:longview/auth.dart';
import 'package:longview/screens/overview.dart';
import 'package:longview/screens/rules.dart';
import 'package:longview/shell.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

const _overview = {
  'today': '2026-11-16',
  'goal': {
    'monthlyAmount': 50000, 'startDate': '2026-03-01', 'targetDate': '2026-12-31', 'target': 500000,
    'saved': 387000, 'expected': 426667, 'percentOfPace': 90.7, 'status': 'behind', 'behindBy': 39667, 'catchUpPerMonth': 19900,
    'months': [
      {'month': '2026-10', 'saved': 42000, 'metGoal': false, 'inProgress': false},
      {'month': '2026-11', 'saved': 16000, 'metGoal': false, 'inProgress': true},
    ],
  },
  'incomeThisMonth': 325000, 'lastIncomeDate': '2026-10-31', 'budgetPlanned': 211299, 'budgetUsed': 176650, 'billsToCome': 4,
  'outliersTotal': 31200, 'outliersCount': 3, 'outliersAverage': 28067, 'leftAfterPlanAndSavings': 32501, 'netPosition': 459732,
  'accounts': [
    {'id': 1, 'name': 'Monzo Current', 'type': 'current', 'source': 'file_import', 'balance': 128450, 'countsTowardsSavings': false,
     'lastSyncedAt': '2026-11-16T10:00:00Z', 'openingBalance': 0, 'openingDate': '2026-01-01', 'lastTransactionDate': '2026-11-16',
     'logo': {'mode': 'automatic', 'resolved': 'letter', 'url': null, 'letter': 'M', 'color': '#4A4E55', 'website': null, 'social': null}},
  ],
  'comingUp': [{'name': 'Gym', 'date': '2026-11-18', 'accountName': 'Monzo', 'amount': 3500}],
  'latestOutliers': [],
};

Api _fakeApi(Map<String, Object> routes) {
  final client = MockClient((req) async {
    final body = routes[req.url.path];
    if (body == null) return http.Response('{"error":"nope"}', 404);
    return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
  });
  return Api(AuthService(), client: client);
}

Widget _host(Api api, Widget child) => MultiProvider(
      providers: [Provider<Api>.value(value: api), ChangeNotifierProvider(create: (_) => Nav())],
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  setUpAll(() => initializeDateFormatting('en_GB'));

  testWidgets('Overview shows the savings goal and catch-up advice', (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(_fakeApi({'/api/overview': _overview}), const OverviewScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Behind pace'), findsOneWidget);
    expect(find.text('£3,870'), findsOneWidget);
    expect(find.textContaining('Save an extra £199 a month'), findsOneWidget);
    expect(find.text('£2,112.99'), findsOneWidget);
    expect(find.text('Could cover the £199 catch-up'), findsOneWidget);
    expect(find.text('Gym'), findsOneWidget);
  });

  testWidgets('Overview works at phone width', (tester) async {
    tester.view.physicalSize = const Size(390, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(_fakeApi({'/api/overview': _overview}), const OverviewScreen()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Savings goal'), findsOneWidget);
  });

  testWidgets('Rules list shows each rule with its category', (tester) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _fakeApi({
      '/api/categories': [
        {'id': 3, 'name': 'Lunch', 'color': '#1E6B4F', 'kind': 'spending'},
      ],
      '/api/rules': [
        {'id': 1, 'name': 'Weekday lunch at Tesco', 'active': true, 'categoryId': 3, 'splitByReceipt': false, 'applyPast': true,
         'conditions': [{'field': 'merchant', 'op': 'contains', 'value': 'Tesco'}], 'summary': 'Merchant contains “Tesco”',
         'match': {'count': 23, 'total': 18435, 'latest': null}},
      ],
    });
    await tester.pumpWidget(_host(api, const RulesScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Weekday lunch at Tesco'), findsOneWidget);
    expect(find.text('Merchant contains “Tesco”'), findsOneWidget);
    expect(find.text('Lunch'), findsNWidgets(2)); // category list + rule pill
  });
}
