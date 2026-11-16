import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'api.dart';
import 'shell.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('en_GB');
  runApp(const LongviewApp());
}

class LongviewApp extends StatelessWidget {
  const LongviewApp({super.key, this.api});
  final Api? api;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<Api>(create: (_) => api ?? Api()),
        ChangeNotifierProvider(create: (_) => Nav()),
      ],
      child: MaterialApp(
        title: 'Longview',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const Shell(),
      ),
    );
  }
}
