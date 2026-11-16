import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'api.dart';
import 'auth.dart';
import 'screens/login.dart';
import 'shell.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('en_GB');
  final auth = AuthService();
  runApp(LongviewApp(auth: auth));
  await auth.init();
}

class LongviewApp extends StatelessWidget {
  const LongviewApp({super.key, required this.auth, this.api});
  final AuthService auth;
  final Api? api;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        Provider<Api>(create: (_) => api ?? Api(auth)),
        ChangeNotifierProvider(create: (_) => Nav()),
      ],
      child: MaterialApp(
        title: 'Longview',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const _Gate(),
      ),
    );
  }
}

class _Gate extends StatelessWidget {
  const _Gate();
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    if (!auth.ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return auth.signedIn ? const Shell() : const LoginScreen();
  }
}
