class SecMessAdminMasterKeyCache {
  static String? _masterKey;

  static String? get value => _masterKey;

  static void set(String key) {
    _masterKey = key.trim();
  }

  static void clear() {
    _masterKey = null;
  }
}
