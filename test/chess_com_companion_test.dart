import 'dart:convert';

import 'package:chessnut_flutter_export/models/app_models.dart';
import 'package:chessnut_flutter_export/screens/chess_com_webview_screen.dart';
import 'package:chessnut_flutter_export/services/app_sound_service.dart';
import 'package:chessnut_flutter_export/services/chess_com_live_snapshot.dart';
import 'package:chessnut_flutter_export/services/chess_clock_switch_service.dart';
import 'package:chessnut_flutter_export/services/chessnut_api_client.dart';
import 'package:chessnut_flutter_export/widgets/chess_board.dart';
import 'package:dartchess/dartchess.dart' as dc;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object?> game({String id = '123456', String result = '*'}) => {
      'playingAs': 'b',
      'whiteClock': '10:00',
      'blackClock': '09:57',
      'pgn': '[Event "Live Chess"]\n'
          '[Site "https://www.chess.com/game/live/$id"]\n'
          '[White "Opponent"]\n[Black "MyAccount"]\n'
          '[WhiteElo "1842"]\n[BlackElo "1901"]\n'
          '[Result "$result"]\n\n$result',
    };

void main() {
  test('detects a matched live game before the first move', () {
    final snapshot = ChessComLiveSnapshot.fromJavaScript(jsonEncode(game()))!;
    expect(snapshot.gameId, '123456');
    expect(snapshot.localPlayerIsWhite, isFalse);
    expect(snapshot.whiteRating, 1842);
    expect(snapshot.blackClock, '09:57');
  });

  test('rejects lobby, spectators, finished games, puzzles and malformed data',
      () {
    expect(ChessComLiveSnapshot.fromJavaScript(null), isNull);
    expect(ChessComLiveSnapshot.fromJavaScript(true), isNull);
    expect(ChessComLiveSnapshot.fromJavaScript('not json'), isNull);
    expect(ChessComLiveSnapshot.fromJavaScript(game(result: '1-0')), isNull);
    expect(ChessComLiveSnapshot.fromJavaScript({...game(), 'playingAs': null}),
        isNull);
    final lobby = game();
    lobby['pgn'] = (lobby['pgn'] as String)
        .replaceAll('https://www.chess.com/game/live/123456', 'Chess.com');
    expect(ChessComLiveSnapshot.fromJavaScript(lobby), isNull);
    final analysis = game();
    analysis['pgn'] = (analysis['pgn'] as String)
        .replaceAll('/game/live/123456', '/analysis/game/live/123456');
    expect(ChessComLiveSnapshot.fromJavaScript(analysis), isNull);
  });

  test('handles double-encoded results and refuses fabricated clock values',
      () {
    final snapshot = ChessComLiveSnapshot.fromJavaScript(
      jsonEncode(jsonEncode({...game(), 'whiteClock': 'Searching...'})),
    )!;
    expect(snapshot.whiteClock, isNull);
    expect(snapshot.blackClock, '09:57');
  });

  test('announces each game once across reconnects and rematches', () {
    final tracker = ChessComGameStartTracker();
    final first = ChessComLiveSnapshot.fromJavaScript(game())!;
    final second = ChessComLiveSnapshot.fromJavaScript(game(id: '987654'))!;
    expect(tracker.shouldAnnounce(first), isTrue);
    expect(tracker.shouldAnnounce(first), isFalse);
    expect(tracker.shouldAnnounce(second), isTrue);
    expect(tracker.shouldAnnounce(first), isFalse);
  });

  testWidgets('Companion shows Black at bottom and alerts only on real matches',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final adapter = _Adapter();
    final sounds = _Sounds();
    final clock = ChessClockSwitchService(enableUsbButtons: false);
    addTearDown(clock.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChessComWebViewScreen(
          onNavigate: (_) {},
          apiClient: ChessnutApiClient(
            httpClient: MockClient((_) async => http.Response('', 200)),
          ),
          webViewAdapter: adapter,
          clockSwitchService: clock,
          soundService: sounds,
          gameStartTracker: ChessComGameStartTracker(),
          isChessnutClockDevice: true,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(sounds.events, isEmpty);
    expect(find.byKey(const ValueKey('chesscom-companion-game')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('chesscom-challenge-friend')));
    await tester.pump();
    expect(adapter.scripts, contains(chessComOpenFriendPickerScript));

    adapter.snapshot = game();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(sounds.events, [AppSoundEvent.gameStart]);
    expect(find.text('1842'), findsOneWidget);
    expect(find.text('1901'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);
    expect(find.text('09:57'), findsOneWidget);
    expect(
      tester
          .widget<InteractiveChessBoard>(find.byType(InteractiveChessBoard))
          .flipped,
      isTrue,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('chesscom-game-controls')));
    await tester.pump();
    expect(find.byKey(const ValueKey('chesscom-show-clocks')), findsOneWidget);
    expect(find.byKey(const ValueKey('fake-webview')), findsOneWidget);

    adapter.snapshot = null;
    await tester.pump(const Duration(seconds: 1));
    adapter.snapshot = game();
    await tester.pump(const Duration(seconds: 1));
    expect(sounds.events, [AppSoundEvent.gameStart]);
    adapter.snapshot = game(id: '234567');
    await tester.pump(const Duration(seconds: 1));
    expect(sounds.events, [AppSoundEvent.gameStart, AppSoundEvent.gameStart]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('touch moves use the bridge and rejected moves restore the board',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final adapter = _Adapter()..snapshot = {...game(), 'playingAs': 'w'};
    final sounds = _Sounds();
    final clock = ChessClockSwitchService(enableUsbButtons: false);
    addTearDown(clock.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChessComWebViewScreen(
          onNavigate: (_) {},
          apiClient: ChessnutApiClient(
            httpClient: MockClient((_) async => http.Response('', 200)),
          ),
          webViewAdapter: adapter,
          clockSwitchService: clock,
          soundService: sounds,
          soundEffectsEnabled: false,
          gameStartTracker: ChessComGameStartTracker(),
          isChessnutClockDevice: true,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(sounds.events, isEmpty);

    // A declined browser move must not leave an optimistic board position.
    adapter.acceptMoves = false;
    await tester
        .tapAt(tester.getCenter(find.byKey(const ValueKey('square-e2'))));
    await tester.pump();
    await tester
        .tapAt(tester.getCenter(find.byKey(const ValueKey('square-e4'))));
    await tester.pump();
    await tester.pump();
    expect(adapter.scripts, contains('window.makeUCIMove("e2e4")'));
    expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('square-e2')))
            .properties
            .label,
        'e2 wp');
    expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('square-e4')))
            .properties
            .label,
        'e4 empty');

    adapter.acceptMoves = true;
    await tester
        .tapAt(tester.getCenter(find.byKey(const ValueKey('square-e2'))));
    await tester.pump();
    await tester
        .tapAt(tester.getCenter(find.byKey(const ValueKey('square-e4'))));
    await tester.pump();
    await tester.pump();
    expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('square-e4')))
            .properties
            .label,
        'e4 wp');
    final moveCalls = adapter.scripts
        .where((s) => s.startsWith('window.makeUCIMove('))
        .length;
    await tester
        .tapAt(tester.getCenter(find.byKey(const ValueKey('square-e7'))));
    await tester.pump();
    await tester
        .tapAt(tester.getCenter(find.byKey(const ValueKey('square-e5'))));
    await tester.pump();
    expect(
        adapter.scripts
            .where((s) => s.startsWith('window.makeUCIMove('))
            .length,
        moveCalls);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in const [Size(640, 240), Size(853, 320)]) {
    testWidgets(
        'Companion clocks stay prominent at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final adapter = _Adapter()..snapshot = game();
      final clock = ChessClockSwitchService(enableUsbButtons: false);
      addTearDown(clock.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChessComWebViewScreen(
            onNavigate: (_) {},
            apiClient: ChessnutApiClient(
              httpClient: MockClient((_) async => http.Response('', 200)),
            ),
            webViewAdapter: adapter,
            clockSwitchService: clock,
            soundService: _Sounds(),
            gameStartTracker: ChessComGameStartTracker(),
            isChessnutClockDevice: true,
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.text('1842'), findsOneWidget);
      expect(find.text('1901'), findsOneWidget);
      expect(find.text('10:00'), findsOneWidget);
      expect(find.text('09:57'), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final player in ['local', 'opponent']) {
        final panel = tester
            .getSize(find.byKey(ValueKey('chesscom-clock-panel-$player')));
        final face =
            tester.getSize(find.byKey(ValueKey('chesscom-clock-face-$player')));
        // Clock digits retain most of each card, even at Android's higher
        // display densities; ratings and controls must not crowd them out.
        expect(panel.width, greaterThan(size.width * 0.4));
        expect(face.height, greaterThan(panel.height * 0.5));
        expect(face.height, greaterThanOrEqualTo(40));
      }
      expect(
          tester
              .getSize(find.byKey(const ValueKey('chesscom-game-controls')))
              .height,
          lessThanOrEqualTo(32));
      await tester.tap(find.byKey(const ValueKey('chesscom-game-controls')));
      await tester.pump();
      expect(
          find.byKey(const ValueKey('chesscom-show-clocks')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

class _Sounds extends AppSoundService {
  final events = <AppSoundEvent>[];
  @override
  Future<void> play(AppSoundEvent event) async => events.add(event);
}

class _Adapter implements ChessComWebViewAdapter {
  Map<String, Object?>? snapshot;
  String currentFen = chessnutStandardStartFen;
  bool acceptMoves = true;
  final scripts = <String>[];
  @override
  bool get isReady => true;
  @override
  Future<void> initialize({
    required Uri initialUrl,
    required VoidCallback onPageStarted,
    required Future<void> Function() onPageFinished,
    required VoidCallback onRecoverRequested,
  }) async {
    onPageStarted();
    await onPageFinished();
  }

  @override
  Future<Object?> runJavaScript(String script) async {
    scripts.add(script);
    if (script == chessComLiveSnapshotScript) return snapshot;
    if (script == 'window.getCurrentFEN()') return currentFen;
    if (script == 'window.getCurrentPGN()') return null;
    if (script.startsWith('window.makeUCIMove(')) {
      if (!acceptMoves) return false;
      final uci = jsonDecode(
              script.substring('window.makeUCIMove('.length, script.length - 1))
          as String;
      currentFen = loadDartChessPosition(currentFen)
          .play(dc.NormalMove.fromUci(uci))
          .fen;
    }
    return true;
  }

  @override
  Widget build() => const SizedBox(key: ValueKey('fake-webview'));
  @override
  Future<void> injectTextScaleGuard() async {}
  @override
  Future<void> reload() async {}
  @override
  Future<void> dispose() async {}
}
