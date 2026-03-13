import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/secmess_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/secmess/admin_invite_qr_page.dart';
import 'package:fluffychat/utils/secmess_admin_master_key_cache.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../utils/fluffy_share.dart';
import 'chat_list.dart';

class ClientChooserButton extends StatefulWidget {
  final ChatListController controller;

  const ClientChooserButton(this.controller, {super.key});

  @override
  State<ClientChooserButton> createState() => _ClientChooserButtonState();
}

class _ClientChooserButtonState extends State<ClientChooserButton> {
  static const Set<String> _inviteQrRoles = {
    'admin',
    'super-admin',
    'developer',
  };

  String? _roleResolvedForUser;
  bool _canGenerateInviteQr = false;
  bool _roleLoading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshInviteRole();
  }

  void _refreshInviteRole() {
    final client = Matrix.of(context).client;
    final userId = client.userID;
    final accessToken = client.accessToken;
    if (userId == null || accessToken == null || accessToken.isEmpty) {
      SecMessAdminMasterKeyCache.clear();
      if (_canGenerateInviteQr) {
        setState(() => _canGenerateInviteQr = false);
      }
      return;
    }
    if (_roleLoading || _roleResolvedForUser == userId) {
      return;
    }
    _roleResolvedForUser = userId;
    _roleLoading = true;
    _canGenerateInviteQr = false;
    unawaited(_loadInviteRole(client, userId, accessToken));
  }

  Future<void> _loadInviteRole(
    Client client,
    String userId,
    String accessToken,
  ) async {
    final uri = Uri.parse(
      SecMessConfig.homeserverUrl,
    ).replace(path: SecMessConfig.keygenAuthMePath);

    var canGenerate = false;
    try {
      final response = await http
          .get(uri, headers: {'Authorization': 'Bearer $accessToken'})
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final decoded =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final role = (decoded['role'] as String?)?.trim().toLowerCase();
        canGenerate = role != null && _inviteQrRoles.contains(role);
      }
    } catch (_) {
      canGenerate = false;
    }

    if (!mounted) return;
    final activeUserId = Matrix.of(context).client.userID;
    if (activeUserId != userId) {
      _roleLoading = false;
      return;
    }
    setState(() {
      _canGenerateInviteQr = canGenerate;
      _roleLoading = false;
    });
    if (!canGenerate) {
      SecMessAdminMasterKeyCache.clear();
    }
  }

  List<PopupMenuEntry<Object>> _bundleMenuItems(BuildContext context) {
    final matrix = Matrix.of(context);
    final bundles = matrix.accountBundles.keys.toList()
      ..sort(
        (a, b) => a!.isValidMatrixId == b!.isValidMatrixId
            ? 0
            : a.isValidMatrixId && !b.isValidMatrixId
            ? -1
            : 1,
      );
    return <PopupMenuEntry<Object>>[
      PopupMenuItem(
        value: SettingsAction.newGroup,
        child: Row(
          children: [
            const Icon(Icons.group_add_outlined),
            const SizedBox(width: 18),
            Text(L10n.of(context).createGroup),
          ],
        ),
      ),
      PopupMenuItem(
        value: SettingsAction.setStatus,
        child: Row(
          children: [
            const Icon(Icons.edit_outlined),
            const SizedBox(width: 18),
            Text(L10n.of(context).setStatus),
          ],
        ),
      ),
      if (SecMessConfig.enableInviteContact)
        PopupMenuItem(
          value: SettingsAction.invite,
          child: Row(
            children: [
              Icon(Icons.adaptive.share_outlined),
              const SizedBox(width: 18),
              Text(L10n.of(context).inviteContact),
            ],
          ),
        ),
      PopupMenuItem(
        value: SettingsAction.archive,
        child: Row(
          children: [
            const Icon(Icons.archive_outlined),
            const SizedBox(width: 18),
            Text(L10n.of(context).archive),
          ],
        ),
      ),
      if (Matrix.of(context).backgroundPush?.firebaseEnabled != true)
        PopupMenuItem(
          value: SettingsAction.support,
          child: Row(
            children: [
              const Icon(Icons.favorite, color: Colors.red),
              const SizedBox(width: 18),
              Text(L10n.of(context).donate),
            ],
          ),
        ),
      if (_canGenerateInviteQr)
        const PopupMenuItem(
          value: SettingsAction.generateInviteQr,
          child: Row(
            children: [
              Icon(Icons.qr_code_2_outlined),
              SizedBox(width: 18),
              Text('Generate QR code'),
            ],
          ),
        ),
      PopupMenuItem(
        value: SettingsAction.settings,
        child: Row(
          children: [
            const Icon(Icons.settings_outlined),
            const SizedBox(width: 18),
            Text(L10n.of(context).settings),
          ],
        ),
      ),
      const PopupMenuDivider(),
      for (final bundle in bundles) ...[
        if (matrix.accountBundles[bundle]!.length != 1 ||
            matrix.accountBundles[bundle]!.single!.userID != bundle)
          PopupMenuItem(
            value: null,
            child: Column(
              crossAxisAlignment: .start,
              mainAxisSize: .min,
              children: [
                Text(
                  bundle!,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.titleMedium!.color,
                    fontSize: 14,
                  ),
                ),
                const Divider(height: 1),
              ],
            ),
          ),
        ...matrix.accountBundles[bundle]!
            .whereType<Client>()
            .where((client) => client.isLogged())
            .map(
              (client) => PopupMenuItem(
                value: client,
                child: FutureBuilder<Profile?>(
                  future: client.fetchOwnProfile(),
                  builder: (context, snapshot) => Row(
                    children: [
                      Avatar(
                        mxContent: snapshot.data?.avatarUrl,
                        name:
                            snapshot.data?.displayName ??
                            client.userID!.localpart,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          snapshot.data?.displayName ??
                              client.userID!.localpart!,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => widget.controller
                            .editBundlesForAccount(client.userID, bundle),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
      if (SecMessConfig.enableMultiAccount)
        PopupMenuItem(
          value: SettingsAction.addAccount,
          child: Row(
            children: [
              const Icon(Icons.person_add_outlined),
              const SizedBox(width: 18),
              Text(L10n.of(context).addAccount),
            ],
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final matrix = Matrix.of(context);

    var clientCount = 0;
    matrix.accountBundles.forEach((key, value) => clientCount += value.length);
    return FutureBuilder<Profile>(
      future: matrix.client.isLogged() ? matrix.client.fetchOwnProfile() : null,
      builder: (context, snapshot) => Material(
        clipBehavior: Clip.hardEdge,
        borderRadius: BorderRadius.circular(99),
        color: Colors.transparent,
        child: PopupMenuButton<Object>(
          popUpAnimationStyle: FluffyThemes.isColumnMode(context)
              ? AnimationStyle.noAnimation
              : null, // https://github.com/flutter/flutter/issues/167180
          onSelected: (o) => _clientSelected(o, context),
          itemBuilder: _bundleMenuItems,
          child: Center(
            child: Avatar(
              mxContent: snapshot.data?.avatarUrl,
              name:
                  snapshot.data?.displayName ?? matrix.client.userID?.localpart,
              size: 32,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _clientSelected(Object object, BuildContext context) async {
    if (object is Client) {
      widget.controller.setActiveClient(object);
      SecMessAdminMasterKeyCache.clear();
      _roleResolvedForUser = null;
      _roleLoading = false;
      if (_canGenerateInviteQr) {
        setState(() => _canGenerateInviteQr = false);
      }
      _refreshInviteRole();
    } else if (object is String) {
      widget.controller.setActiveBundle(object);
      SecMessAdminMasterKeyCache.clear();
      _roleResolvedForUser = null;
      _roleLoading = false;
      if (_canGenerateInviteQr) {
        setState(() => _canGenerateInviteQr = false);
      }
      _refreshInviteRole();
    } else if (object is SettingsAction) {
      switch (object) {
        case SettingsAction.addAccount:
          if (!SecMessConfig.enableMultiAccount) {
            return;
          }
          final consent = await showOkCancelAlertDialog(
            context: context,
            title: L10n.of(context).addAccount,
            message: L10n.of(context).enableMultiAccounts,
            okLabel: L10n.of(context).next,
            cancelLabel: L10n.of(context).cancel,
          );
          if (consent != OkCancelResult.ok) return;
          context.go('/rooms/settings/addaccount');
          break;
        case SettingsAction.newGroup:
          context.go('/rooms/newgroup');
          break;
        case SettingsAction.invite:
          if (!SecMessConfig.enableInviteContact) {
            return;
          }
          FluffyShare.shareInviteLink(context);
          break;
        case SettingsAction.support:
          launchUrlString(AppConfig.donationUrl);
          break;
        case SettingsAction.settings:
          context.go('/rooms/settings');
          break;
        case SettingsAction.archive:
          context.go('/rooms/archive');
          break;
        case SettingsAction.setStatus:
          widget.controller.setStatus();
          break;
        case SettingsAction.generateInviteQr:
          final accessToken = Matrix.of(context).client.accessToken;
          if (accessToken == null || accessToken.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Missing access token')),
            );
            return;
          }
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AdminInviteQrPage(accessToken: accessToken),
            ),
          );
          break;
      }
    }
  }
}

enum SettingsAction {
  addAccount,
  newGroup,
  setStatus,
  invite,
  support,
  generateInviteQr,
  settings,
  archive,
}
