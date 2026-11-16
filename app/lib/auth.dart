import 'package:auth0_flutter/auth0_flutter.dart';
import 'package:auth0_flutter/auth0_flutter_web.dart';
import 'package:flutter/foundation.dart';

import 'config.dart';

/// Signs people in with Auth0. Social providers (Google, Apple, GitHub...) are Auth0 "connections";
/// passing `connection` skips the Universal Login chooser and goes straight to that provider.
class AuthService extends ChangeNotifier {
  AuthService() {
    if (Config.auth0Configured) {
      if (kIsWeb) {
        _web = Auth0Web(Config.auth0Domain, Config.auth0ClientId);
      } else {
        _mobile = Auth0(Config.auth0Domain, Config.auth0ClientId);
      }
    }
  }

  Auth0? _mobile;
  Auth0Web? _web;
  Credentials? _creds;
  bool ready = false;
  String? error;

  bool get signedIn => Config.useDevAuth || _creds != null;
  String? get displayName => Config.useDevAuth ? Config.devUser : (_creds?.user.name ?? _creds?.user.email);
  String? get pictureUrl => _creds?.user.pictureUrl?.toString();

  /// Restores a session on start-up (and finishes a web redirect login).
  Future<void> init() async {
    try {
      if (Config.useDevAuth) return;
      if (_web != null) {
        _creds = await _web!.onLoad(audience: _audience, useRefreshTokens: true);
      } else if (_mobile != null && await _mobile!.credentialsManager.hasValidCredentials()) {
        _creds = await _mobile!.credentialsManager.credentials();
      }
    } catch (e) {
      error = '$e';
    } finally {
      ready = true;
      notifyListeners();
    }
  }

  String? get _audience => Config.auth0Audience.isEmpty ? null : Config.auth0Audience;

  Future<void> login({String? connection}) async {
    error = null;
    final params = <String, String>{'connection': ?connection};
    try {
      if (_web != null) {
        await _web!.loginWithRedirect(audience: _audience, redirectUrl: Uri.base.origin, parameters: params);
        return; // the page reloads; init() picks the session up
      }
      if (_mobile == null) throw StateError('Auth0 is not configured. See README → Auth0 setup.');
      _creds = await _mobile!.webAuthentication(scheme: Config.auth0Scheme).login(audience: _audience, parameters: params);
    } on WebAuthenticationException catch (e) {
      if (e.code != 'a0.authentication_canceled' && e.code != 'USER_CANCELLED') error = e.message;
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      if (_web != null) {
        await _web!.logout(returnToUrl: Uri.base.origin);
      } else if (_mobile != null) {
        await _mobile!.webAuthentication(scheme: Config.auth0Scheme).logout();
      }
    } catch (_) {}
    _creds = null;
    notifyListeners();
  }

  /// A fresh access token for the API (renewed with the refresh token when it is close to expiring).
  Future<String?> accessToken() async {
    if (Config.useDevAuth) return 'dev:${Config.devUser}';
    try {
      if (_web != null) {
        _creds = await _web!.credentials(audience: _audience);
      } else if (_mobile != null) {
        _creds = await _mobile!.credentialsManager.credentials(minTtl: 60);
      }
    } catch (_) {
      _creds = null;
      notifyListeners();
    }
    return _creds?.accessToken;
  }
}
