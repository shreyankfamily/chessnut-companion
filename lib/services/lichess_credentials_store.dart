import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Personal Lichess credentials never pass through the Chessnut backend.
abstract interface class LichessCredentialsStore {
  Future<String?> readToken();
  Future<void> writeToken(String token);
  Future<void> clear();
}

class SecureLichessCredentialsStore implements LichessCredentialsStore {
  const SecureLichessCredentialsStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;
  static const _key = 'companion_online_lichess_token';

  @override
  Future<String?> readToken() => _storage.read(key: _key);

  @override
  Future<void> writeToken(String token) =>
      _storage.write(key: _key, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
