import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../auth.dart';
import '../config.dart';
import '../theme.dart';
import '../widgets.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  IconData _icon(String c) => switch (c) {
        'google-oauth2' => Icons.g_mobiledata,
        'apple' => Icons.apple,
        'github' => Icons.code,
        'facebook' => Icons.facebook,
        _ => Icons.login,
      };

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final socials = Config.socialConnections.split(',').where((s) => s.contains(':')).map((s) {
      final p = s.split(':');
      return (p[0].trim(), p[1].trim());
    }).toList();
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: CardBox(
              padding: const EdgeInsets.all(32),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Longview', style: TextStyle(fontFamily: display, fontWeight: FontWeight.w700, fontSize: 34)),
                const SizedBox(height: 6),
                const Label('Long-term budgeting: an ideal budget, the outliers, and a savings goal you can keep.', size: 15),
                const SizedBox(height: 28),
                if (!Config.auth0Configured)
                  const Note(Text('Auth0 isn\'t configured. Build with --dart-define=AUTH0_DOMAIN=… and AUTH0_CLIENT_ID=…, '
                      'or DEV_USER=yourname against a backend started with DEV_AUTH=true.'))
                else ...[
                  for (final (conn, label) in socials) ...[
                    OutlinedButton.icon(
                      onPressed: () => auth.login(connection: conn),
                      icon: Icon(_icon(conn), size: 22),
                      label: Text('Continue with $label'),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 6),
                  FilledButton(onPressed: () => auth.login(), child: const Text('More ways to sign in')),
                ],
                if (auth.error != null) ...[const SizedBox(height: 16), Note(Text(auth.error!))],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
