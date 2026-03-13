import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import 'package:fluffychat/config/secmess_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/new_private_chat/qr_scanner_modal.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/layouts/login_scaffold.dart';
import 'package:fluffychat/widgets/matrix.dart';

class QrLoginPage extends StatefulWidget {
  const QrLoginPage({super.key});

  @override
  State<QrLoginPage> createState() => _QrLoginPageState();
}

class _QrLoginPageState extends State<QrLoginPage> {
  static final RegExp _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{24,256}$');
  static const String _matrixAccessTokenPrefix = 'syt_';
  static const String _whoAmIPath = '/_matrix/client/v3/account/whoami';

  final TextEditingController _tokenController = TextEditingController();
  final FocusNode _tokenFocusNode = FocusNode();
  bool _showTokenLogin = false;
  bool _loading = false;
  String? _errorText;
  String? _statusText;

  @override
  void dispose() {
    _tokenController.dispose();
    _tokenFocusNode.dispose();
    super.dispose();
  }

  Uri get _keygenRedeemUri {
    final base = Uri.parse(SecMessConfig.homeserverUrl);
    return base.replace(path: SecMessConfig.keygenRedeemPath);
  }

  Future<void> _openScanner() async {
    if (_loading) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => QrScannerModal(onScan: _onQrScanned)),
    );
  }

  Future<void> _onQrScanned(String payload) async {
    final token = _extractToken(payload);
    if (token == null) {
      _setError('QR code does not contain a valid invite token.');
      return;
    }
    _tokenController.text = token;
    await _redeemAndLogin(token);
  }

  String? _extractToken(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    final tokenFromQuery = uri?.queryParameters[SecMessConfig.qrTokenQueryParam]
        ?.trim();
    if (tokenFromQuery != null && tokenFromQuery.isNotEmpty) {
      if (_tokenPattern.hasMatch(tokenFromQuery)) {
        return tokenFromQuery;
      }
      return null;
    }

    if (_tokenPattern.hasMatch(trimmed)) {
      return trimmed;
    }

    return null;
  }

  Uri _normalizeHomeserverUri(String? raw) {
    if (SecMessConfig.enforceConfiguredHomeserver) {
      return Uri.parse(SecMessConfig.homeserverUrl);
    }
    if (raw == null || raw.trim().isEmpty) {
      return Uri.parse(SecMessConfig.homeserverUrl);
    }
    final trimmed = raw.trim();
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.scheme.isNotEmpty) {
      return parsed;
    }
    return Uri.https(trimmed, '');
  }

  bool _isMatrixAccessToken(String token) {
    return token.startsWith(_matrixAccessTokenPrefix);
  }

  Future<Map<String, dynamic>> _whoAmI(
    String accessToken, {
    Uri? homeserverUri,
  }) async {
    final homeserver = homeserverUri ?? Uri.parse(SecMessConfig.homeserverUrl);
    final whoAmIUri = homeserver.replace(path: _whoAmIPath);
    final response = await http
        .get(whoAmIUri, headers: {'Authorization': 'Bearer $accessToken'})
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw _QrLoginException(
        'Access token is invalid (${response.statusCode}).',
      );
    }

    final decoded =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final userId = decoded['user_id'] as String?;
    if (userId == null || userId.isEmpty) {
      throw const _QrLoginException('Invalid whoami response from homeserver.');
    }
    return decoded;
  }

  Future<String> _requireDeviceId({
    required String accessToken,
    required Uri homeserver,
    String? currentDeviceId,
  }) async {
    final trimmed = currentDeviceId?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }

    final whoami = await _whoAmI(accessToken, homeserverUri: homeserver);
    final resolved = (whoami['device_id'] as String?)?.trim();
    if (resolved == null || resolved.isEmpty) {
      throw const _QrLoginException(
        'This access token is not bound to a device.',
      );
    }
    return resolved;
  }

  Future<_RedeemResult> _redeemInviteToken(String token) async {
    final body = jsonEncode(<String, String>{'token': token});
    final response = await http
        .post(
          _keygenRedeemUri,
          headers: {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw _QrLoginException(_extractBackendError(response));
    }

    final decoded =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return _RedeemResult.fromJson(decoded);
  }

  String _extractBackendError(http.Response response) {
    final generic = 'Login failed (${response.statusCode}).';
    try {
      final decoded =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final detail = decoded['detail'];
      if (detail is String && detail.trim().isNotEmpty) {
        return detail.trim();
      }
    } catch (_) {
      // Keep the generic fallback.
    }
    return generic;
  }

  Future<void> _redeemAndLogin(String token) async {
    if (_loading) {
      return;
    }

    setState(() {
      _loading = true;
      _errorText = null;
      _statusText = 'Validating token...';
    });

    try {
      String userId;
      String accessToken;
      String deviceId;
      Uri homeserver;

      if (_isMatrixAccessToken(token)) {
        if (!mounted) return;
        setState(() {
          _statusText = 'Checking access token...';
        });
        homeserver = Uri.parse(SecMessConfig.homeserverUrl);
        final whoami = await _whoAmI(token, homeserverUri: homeserver);
        userId = whoami['user_id'] as String;
        accessToken = token;
        deviceId = await _requireDeviceId(
          accessToken: accessToken,
          homeserver: homeserver,
          currentDeviceId: whoami['device_id'] as String?,
        );
      } else {
        final redeemResult = await _redeemInviteToken(token);
        userId = redeemResult.userId;
        accessToken = redeemResult.accessToken;
        homeserver = _normalizeHomeserverUri(redeemResult.homeServer);
        deviceId = await _requireDeviceId(
          accessToken: accessToken,
          homeserver: homeserver,
          currentDeviceId: redeemResult.deviceId,
        );
      }

      if (!mounted) return;
      setState(() {
        _statusText = 'Signing in...';
      });

      final matrix = Matrix.of(context);
      final client = await matrix.getLoginClient();
      await AppSettings.defaultHomeserver.setItem(homeserver.host);
      await client.init(
        newToken: accessToken,
        newUserID: userId,
        newHomeserver: homeserver,
        newDeviceID: deviceId,
        waitForFirstSync: false,
        waitUntilLoadCompletedLoaded: false,
      );

      if (!mounted) return;
      context.go('/backup');
    } on TimeoutException {
      _setError('Timeout while calling the keygen API.');
    } on _QrLoginException catch (error) {
      _setError(error.message);
    } catch (error) {
      _setError(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _statusText = null;
        });
      }
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _errorText = message;
    });
  }

  Future<void> _submitManualToken() async {
    final token = _extractToken(_tokenController.text);
    if (token == null) {
      _setError('Enter a valid invite token.');
      return;
    }
    await _redeemAndLogin(token);
  }

  void _openTokenLogin() {
    if (_showTokenLogin) {
      _tokenFocusNode.requestFocus();
      return;
    }
    setState(() {
      _showTokenLogin = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _tokenFocusNode.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final canScanQr = PlatformInfos.isAndroid || PlatformInfos.isIOS;

    return LoginScaffold(
      appBar: AppBar(title: Text(l10n.signIn)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ElevatedButton.icon(
            onPressed: _loading || !canScanQr ? null : _openScanner,
            icon: const Icon(Icons.qr_code_scanner_outlined),
            label: Text(
              canScanQr
                  ? l10n.scanQrCode
                  : '${l10n.scanQrCode} (Android/iPhone only)',
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _loading ? null : _openTokenLogin,
            child: const Text('Sign in with token'),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: !_showTokenLogin
                ? const SizedBox.shrink()
                : Column(
                    key: const ValueKey('token_login_form'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 16),
                      TextField(
                        controller: _tokenController,
                        focusNode: _tokenFocusNode,
                        readOnly: _loading,
                        decoration: const InputDecoration(
                          labelText: 'Invite token',
                          hintText: 'Paste the token manually',
                          border: OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.go,
                        onSubmitted: (_) => _submitManualToken(),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loading ? null : _submitManualToken,
                        child: const Text('Sign in'),
                      ),
                    ],
                  ),
          ),
          if (_loading) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            if (_statusText != null) ...[
              const SizedBox(height: 8),
              Text(_statusText!),
            ],
          ],
          if (_errorText != null) ...[
            const SizedBox(height: 16),
            Text(_errorText!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ),
    );
  }
}

class _RedeemResult {
  final String userId;
  final String accessToken;
  final String? homeServer;
  final String? deviceId;

  const _RedeemResult({
    required this.userId,
    required this.accessToken,
    this.homeServer,
    this.deviceId,
  });

  factory _RedeemResult.fromJson(Map<String, dynamic> json) {
    final userId = json['user_id'] as String?;
    final accessToken = json['access_token'] as String?;
    if (userId == null ||
        userId.isEmpty ||
        accessToken == null ||
        accessToken.isEmpty) {
      throw const _QrLoginException('Invalid response from the keygen API.');
    }
    return _RedeemResult(
      userId: userId,
      accessToken: accessToken,
      homeServer: json['home_server'] as String?,
      deviceId: json['device_id'] as String?,
    );
  }
}

class _QrLoginException implements Exception {
  final String message;

  const _QrLoginException(this.message);
}
