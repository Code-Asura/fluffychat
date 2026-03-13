import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pretty_qr_code/pretty_qr_code.dart';

import 'package:fluffychat/config/secmess_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/secmess_admin_master_key_cache.dart';

class AdminInviteQrPage extends StatefulWidget {
  final String accessToken;

  const AdminInviteQrPage({required this.accessToken, super.key});

  @override
  State<AdminInviteQrPage> createState() => _AdminInviteQrPageState();
}

class _AdminInviteQrPageState extends State<AdminInviteQrPage> {
  bool _loading = true;
  String? _qrPayload;
  String? _error;

  Uri get _createUri {
    final base = Uri.parse(SecMessConfig.homeserverUrl);
    return base.replace(path: SecMessConfig.keygenCreatePath);
  }

  @override
  void initState() {
    super.initState();
    _generateQr();
  }

  String _extractBackendError(http.Response response) {
    final generic = 'Unable to generate QR (${response.statusCode}).';
    try {
      final decoded =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final detail = decoded['detail'];
      if (detail is String && detail.trim().isNotEmpty) {
        return detail.trim();
      }
    } catch (_) {
      // Keep generic fallback.
    }
    return generic;
  }

  bool _isMasterKeyError(String errorText) {
    final lowered = errorText.toLowerCase();
    return lowered.contains('master key');
  }

  Future<String?> _ensureMasterKey() async {
    final cached = SecMessAdminMasterKeyCache.value;
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    final controller = TextEditingController();
    final key = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Master key required'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Master key',
            border: OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.of(context).pop(controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (key == null || key.trim().isEmpty) {
      return null;
    }

    SecMessAdminMasterKeyCache.set(key);
    return SecMessAdminMasterKeyCache.value;
  }

  Future<void> _generateQr() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final masterKey = await _ensureMasterKey();
      if (masterKey == null || masterKey.isEmpty) {
        throw const _AdminInviteQrException('Master key is required.');
      }

      final response = await http
          .post(
            _createUri,
            headers: {
              'Authorization': 'Bearer ${widget.accessToken}',
              SecMessConfig.keygenMasterKeyHeader: masterKey,
              'Content-Type': 'application/json',
            },
            body: '{}',
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) {
        final message = _extractBackendError(response);
        if (response.statusCode == 401 && _isMasterKeyError(message)) {
          SecMessAdminMasterKeyCache.clear();
        }
        throw _AdminInviteQrException(message);
      }

      final decoded =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final payload = decoded['qr_payload'] as String?;
      if (payload == null || payload.trim().isEmpty) {
        throw const _AdminInviteQrException(
          'Keygen response has no qr_payload.',
        );
      }

      if (!mounted) return;
      setState(() {
        _qrPayload = payload;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _error = 'Timeout while generating QR.';
      });
    } on _AdminInviteQrException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Generate QR code'),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_loading) ...[
                  const CircularProgressIndicator.adaptive(),
                  const SizedBox(height: 12),
                  const Text('Generating QR...'),
                ] else if (_error != null) ...[
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _generateQr,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ] else if (_qrPayload != null) ...[
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 320,
                      maxHeight: 320,
                    ),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF101010),
                            width: 2,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x22000000),
                              blurRadius: 16,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: PrettyQrView.data(
                            data: _qrPayload!,
                            decoration: const PrettyQrDecoration(
                              shape: PrettyQrSmoothSymbol(
                                color: Color(0xFF000000),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  label: Text(l10n.close),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminInviteQrException implements Exception {
  final String message;

  const _AdminInviteQrException(this.message);
}
