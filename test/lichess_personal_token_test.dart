import 'dart:convert';

import 'package:chessnut_flutter_export/services/lichess_board_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const token = 'test_personal_token';
  const scopes = 'board:play,challenge:read,challenge:write,follow:read';

  test('direct sign-in checks required scopes and reads the Lichess account',
      () async {
    final paths = <String>[];
    final service = LichessBoardService(
      token: token,
      httpClient: MockClient((request) async {
        expect(request.url.host, 'lichess.org');
        paths.add(request.url.path);
        if (request.url.path == '/api/token/test') {
          expect(request.method, 'POST');
          expect(request.body, token);
          return http.Response(
              jsonEncode({
                token: {'scopes': scopes}
              }),
              200);
        }
        expect(request.headers['Authorization'], 'Bearer $token');
        return http.Response('{"username":"BoardPlayer"}', 200);
      }),
    );
    expect(await service.validatePersonalToken(), 'BoardPlayer');
    expect(paths, ['/api/token/test', '/api/account']);
    expect(service.lastErrorMessage, isNull);
  });

  test('missing permissions cannot authorize play and do not expose the token',
      () async {
    final service = LichessBoardService(
      token: token,
      httpClient: MockClient((request) async => http.Response(
            jsonEncode({
              token: {'scopes': 'board:play'}
            }),
            200,
          )),
    );
    expect(await service.validatePersonalToken(), isNull);
    expect(service.lastStatusCode, 403);
    expect(service.lastErrorMessage, contains('follow:read'));
    expect(service.lastErrorMessage, isNot(contains(token)));
  });

  test('revoked and invalid tokens are rejected', () async {
    final service = LichessBoardService(
      token: token,
      httpClient: MockClient((request) async => http.Response(
            jsonEncode({token: null}),
            200,
          )),
    );
    expect(await service.validatePersonalToken(), isNull);
    expect(service.lastStatusCode, 401);
    expect(service.lastErrorMessage, contains('revoked'));
  });

  test('server responses never leak token-test response contents', () async {
    final service = LichessBoardService(
      token: token,
      httpClient: MockClient((_) async => http.Response(token, 502)),
    );
    expect(await service.validatePersonalToken(), isNull);
    expect(service.lastErrorMessage, isNot(contains(token)));
  });

  for (final color in ['white', 'black', 'random']) {
    test('public seeks send the selected $color side to Lichess', () async {
      final service = LichessBoardService(
        token: token,
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/board/seek');
          expect(request.bodyFields['color'], color);
          return http.Response('ok', 200);
        }),
      );
      expect(
          await service.createSeek(LichessSeekRequest(
            timeMinutes: 10,
            incrementSeconds: 5,
            color: color,
          )),
          isTrue);
    });
  }
}
