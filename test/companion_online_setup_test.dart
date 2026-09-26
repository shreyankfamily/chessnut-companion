import 'dart:convert';

import 'package:chessnut_flutter_export/l10n/app_strings.dart';
import 'package:chessnut_flutter_export/models/app_models.dart';
import 'package:chessnut_flutter_export/screens/setup_screen.dart';
import 'package:chessnut_flutter_export/services/chessnut_api_client.dart';
import 'package:chessnut_flutter_export/services/board_settings_service.dart';
import 'package:chessnut_flutter_export/services/lichess_credentials_store.dart';
import 'package:chessnut_flutter_export/theme/chessnut_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _MemoryCredentials implements LichessCredentialsStore {
  _MemoryCredentials([this.token]);
  String? token;
  @override
  Future<String?> readToken() async => token;
  @override
  Future<void> writeToken(String value) async => token = value;
  @override
  Future<void> clear() async => token = null;
}

void main() {
  const token = 'test_token';
  const scope = 'board:play,challenge:read,challenge:write,follow:read';
  late List<http.Request> requests;
  late ChessnutApiClient api;

  setUp(() {
    requests = [];
    api = ChessnutApiClient(httpClient: MockClient((request) async {
      requests.add(request);
      expect(request.url.host, 'lichess.org');
      switch (request.url.path) {
        case '/api/token/test':
          return http.Response(
              jsonEncode({
                token: {'scopes': scope}
              }),
              200);
        case '/api/account':
          return http.Response('{"username":"BoardPlayer"}', 200);
        case '/api/rel/following':
          return http.Response('', 200);
        case '/api/challenge':
          return http.Response('{"in":[]}', 200);
        case '/api/challenge/FriendlyKnight':
          return http.Response(
              [
                jsonEncode({
                  'challenge': {
                    'id': 'friend-game',
                    'direction': 'out',
                    'status': 'created',
                    'challenger': {'name': 'BoardPlayer'},
                    'destUser': {'name': 'FriendlyKnight'},
                    'variant': {'key': 'standard'},
                    'speed': 'rapid',
                    'color': request.bodyFields['color'],
                    'timeControl': {'limit': 600, 'increment': 5},
                  }
                }),
                jsonEncode({'done': 'accepted'}),
              ].join('\n'),
              200);
        case '/api/account/playing':
          return http.Response(
              jsonEncode({
                'nowPlaying': [
                  {
                    'gameId': 'active-game',
                    'speed': 'rapid',
                    'color': 'black',
                    'opponent': {'username': 'FriendlyKnight'},
                  }
                ]
              }),
              200);
        case '/api/stream/event':
          return http.Response(
              '{"type":"gameStart","game":{"id":"active-game"}}\n', 200);
        case '/api/board/game/stream/active-game':
          return http.Response(
              jsonEncode({
                'type': 'gameFull',
                'id': 'active-game',
                'rated': true,
                'clock': {'initial': 600000, 'increment': 5000},
                'white': {'name': 'FriendlyKnight'},
                'black': {'name': 'BoardPlayer'},
                'state': {
                  'status': 'started',
                  'moves': 'e2e4',
                  'wtime': 598000,
                  'btime': 600000
                },
              }),
              200);
        case '/api/board/seek':
          return http.Response('ok', 200);
        default:
          return http.Response('Unexpected path', 404);
      }
    }));
  });

  Future<void> pumpSetup(WidgetTester tester, _MemoryCredentials credentials,
      {LaunchGameCallback? onLaunchGame}) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: ChessnutTheme.light(),
      localizationsDelegates: AppStrings.localizationsDelegates,
      home: Scaffold(
          body: OnlineSetupScreen(
        apiClient: api,
        onNavigate: (_) {},
        onSessionUpdated: (_) =>
            fail('Direct sign-in must not use Chessnut sessions'),
        onLaunchGame:
            onLaunchGame ?? (mode, {botConfig, otbConfig, lichessConfig}) {},
        boardSettings: const BoardSettingsState(),
        onBoardSettingsChanged: (_) {},
        directLichessSignIn: true,
        lichessCredentialsStore: credentials,
      )),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> finishLaunch(
      WidgetTester tester, bool Function() launched) async {
    // An async* game stream waits for its nested stream to cancel before the
    // launch callback runs; those completion events need the real event queue.
    for (var i = 0; i < 10 && !launched(); i++) {
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('connects and stores a personal token without a Chessnut account',
      (tester) async {
    final credentials = _MemoryCredentials();
    await pumpSetup(tester, credentials);
    await tester.tap(find.text('Authorize Lichess'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('lichess-personal-token')), token);
    await tester.pump();
    await tester.tap(find.text('Connect Lichess'));
    await tester.pumpAndSettle();
    expect(credentials.token, token);
    expect(api.session, isNull);
    expect(find.textContaining('Signed in as BoardPlayer'), findsOneWidget);
    await tester.tap(find.text('Disconnect Lichess'));
    await tester.pumpAndSettle();
    expect(credentials.token, isNull);
    expect(find.text('Authorize Lichess'), findsOneWidget);
  });

  testWidgets('restores the account and resumes a live game after restart',
      (tester) async {
    LichessGameConfig? launched;
    await pumpSetup(tester, _MemoryCredentials(token),
        onLaunchGame: (mode, {botConfig, otbConfig, lichessConfig}) =>
            launched = lichessConfig);
    await tester.tap(find.text('FriendlyKnight'));
    await finishLaunch(tester, () => launched != null);
    expect(launched?.gameId, 'active-game',
        reason: requests.map((r) => r.url.path).join(', '));
    expect(launched?.lichessName, 'BoardPlayer');
    expect(launched?.timeMinutes, 10);
    expect(launched?.incrementSeconds, 5);
    expect(launched?.rated, true);
  });

  testWidgets('Black selection is submitted in public matchmaking',
      (tester) async {
    LichessGameConfig? launched;
    await pumpSetup(tester, _MemoryCredentials(token),
        onLaunchGame: (mode, {botConfig, otbConfig, lichessConfig}) =>
            launched = lichessConfig);
    await tester.tap(find.text('Black'));
    final start = find.text('Find 10+5 game');
    await tester.ensureVisible(start);
    await tester.tap(start);
    await finishLaunch(tester, () => launched != null);
    final seek = requests.singleWhere((r) => r.url.path == '/api/board/seek');
    expect(seek.bodyFields['color'], 'black');
    expect(launched?.gameId, 'active-game',
        reason: requests.map((r) => r.url.path).join(', '));
  });

  testWidgets('challenges a friend by username with the chosen White side',
      (tester) async {
    LichessGameConfig? launched;
    await pumpSetup(tester, _MemoryCredentials(token),
        onLaunchGame: (mode, {botConfig, otbConfig, lichessConfig}) =>
            launched = lichessConfig);
    await tester.tap(find.text('Friend match'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('lichess-player-username-field')),
        'FriendlyKnight');
    await tester.tap(find.text('White'));
    await tester.pump();
    final start = find.text('Challenge player');
    await tester.ensureVisible(start);
    await tester.tap(start);
    await finishLaunch(tester, () => launched != null);
    final challenge = requests
        .singleWhere((r) => r.url.path == '/api/challenge/FriendlyKnight');
    expect(challenge.bodyFields['color'], 'white');
    expect(challenge.bodyFields['keepAliveStream'], 'true');
    expect(launched?.gameId, 'friend-game');
  });
}
