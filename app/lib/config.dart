/// Build-time settings. Pass with --dart-define, e.g.
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080 \
///     --dart-define=AUTH0_DOMAIN=your-tenant.eu.auth0.com \
///     --dart-define=AUTH0_CLIENT_ID=abc123 \
///     --dart-define=AUTH0_AUDIENCE=https://api.longview.app
class Config {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8080');
  static const auth0Domain = String.fromEnvironment('AUTH0_DOMAIN');
  static const auth0ClientId = String.fromEnvironment('AUTH0_CLIENT_ID');
  static const auth0Audience = String.fromEnvironment('AUTH0_AUDIENCE');

  /// Custom URL scheme for the mobile callback. Must match the Android manifest placeholder
  /// and the "Allowed Callback URLs" in Auth0.
  static const auth0Scheme = String.fromEnvironment('AUTH0_SCHEME', defaultValue: 'app.longview');

  /// Local development only: skip Auth0 and sign in as this user against a backend running with DEV_AUTH=true.
  static const devUser = String.fromEnvironment('DEV_USER');

  /// Social connections shown as buttons. Names must match the connection names in Auth0
  /// (Authentication → Social). Format: "connection:Label,connection:Label".
  static const socialConnections = String.fromEnvironment(
    'AUTH0_CONNECTIONS',
    defaultValue: 'google-oauth2:Google,apple:Apple,github:GitHub',
  );

  static bool get useDevAuth => devUser.isNotEmpty;
  static bool get auth0Configured => auth0Domain.isNotEmpty && auth0ClientId.isNotEmpty;
}
