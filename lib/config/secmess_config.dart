abstract class SecMessConfig {
  static const String appName = 'SecMess';
  static const String homeserverHost = String.fromEnvironment(
    'SECMESS_HOMESERVER_HOST',
    defaultValue: 'secmess.cloudpub.ru',
  );
  static const String homeserverUrl = String.fromEnvironment(
    'SECMESS_HOMESERVER_URL',
    defaultValue: 'https://secmess.cloudpub.ru',
  );

  static const String keygenAuthMePath = '/keygen/auth/me';
  static const String keygenCreatePath = '/keygen/token/create';
  static const String keygenRedeemPath = '/keygen/token/redeem';
  static const String keygenMasterKeyHeader = 'X-Master-Key';
  static const String qrTokenQueryParam = 'token';

  // In token-only auth flow we skip interactive cross-signing bootstrap (UIA),
  // otherwise the setup may hang waiting for unavailable password auth.
  static const bool skipBootstrapCrossSigning = true;

  // MVP scope flags from TZ/TODO.
  static const bool enableSpaces = false;
  static const bool enablePublicSearch = true;
  static const bool enableMultiAccount = false;
  static const bool enableHomeserverSettings = false;
  static const bool enablePasswordChange = false;
  static const bool enableCalls = false;
  static const bool enableInviteContact = false;
  static const bool enforceConfiguredHomeserver = true;

  // Chat scope: keep only text, static photos, emoji and reactions.
  static const bool enableChatStaticImages = true;
  static const bool enableChatEmojiPicker = true;
  static const bool enableChatReactions = true;

  static const bool enableChatVoiceMessages = false;
  static const bool enableChatVideos = false;
  static const bool enableChatFileAttachments = false;
  static const bool enableChatPolls = false;
  static const bool enableChatLocation = false;
  static const bool enableChatStickers = false;
}
