import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chessnut_flutter_export/l10n/localized_material.dart';
import 'package:chessnut_flutter_export/models/app_models.dart';
import 'package:chessnut_flutter_export/screens/game_room_screen.dart';
import 'package:chessnut_flutter_export/services/app_sound_service.dart';
import 'package:chessnut_flutter_export/services/board_settings_service.dart';
import 'package:chessnut_flutter_export/services/bot_engine_adapter.dart';
import 'package:chessnut_flutter_export/services/chessnut_api_client.dart';
import 'package:chessnut_flutter_export/theme/chessnut_theme.dart';
import 'package:chessnut_flutter_export/widgets/chess_board.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  String? copiedText;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    copiedText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    for (final name in [
      'chessnut/clock_hid/events',
      'com.llfbandit.record/messages',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), (_) async => null);
    }
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final density in [1.5, 2.0]) {
    testWidgets('Companion clocks fit at Android density $density',
        (tester) async {
      final client = _GameClient();
      final sounds = _Sounds();
      _companionViewport(tester);
      tester.view.devicePixelRatio = density;
      await tester.pumpWidget(_room(client, sounds, companionDevice: true));
      await tester.pump();
      client.emitFull(localBlack: true);
      await tester.pump();
      await tester.pump();
      final width = 1280 / density;
      final height = 480 / density;
      final board = tester.getRect(find.byType(InteractiveChessBoard));
      expect(_board(tester).flipped, isTrue);
      expect(board.height, greaterThan(height * 0.6));
      expect(board.bottom, lessThanOrEqualTo(height));
      for (final position in ['top', 'bottom']) {
        final time = tester.getRect(
          find.byKey(ValueKey('game-clock-$position-time')),
        );
        expect(time.left, greaterThan(board.right));
        expect(
            time.width / (width - board.right), inInclusiveRange(0.43, 0.55));
        expect(time.height, greaterThan(30));
        expect(time.right, lessThanOrEqualTo(width));
        expect(time.bottom, lessThanOrEqualTo(height));
        final rating = tester.widget<Text>(
          find.byKey(ValueKey('game-clock-$position-rating')),
        );
        expect(rating.style!.fontSize, greaterThanOrEqualTo(18));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('Companion shows Black at bottom with large ratings and clocks',
      (tester) async {
    final client = _GameClient();
    final sounds = _Sounds();
    final engine = _UnusedEngine();
    _companionViewport(tester);
    if (const bool.fromEnvironment('COMPANION_PREVIEW')) {
      await tester.runAsync(() async {
        final manifest =
            jsonDecode(await rootBundle.loadString('FontManifest.json'))
                as List;
        for (final family in manifest.cast<Map<String, dynamic>>()) {
          final loader = FontLoader(family['family'] as String);
          for (final font in (family['fonts'] as List).cast<Map>()) {
            loader.addFont(rootBundle.load(font['asset'] as String));
          }
          await loader.load();
        }
      });
    }
    await tester.pumpWidget(_room(
      client,
      sounds,
      allowPhysicalFlip: false,
      engine: engine,
    ));
    await tester.pump();
    expect(sounds.events, isEmpty, reason: 'Waiting for the match is silent.');

    client.emitFull(localBlack: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_board(tester).flipped, isTrue);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('game-clock-bottom-name')))
          .data,
      'CompanionPlayer',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('game-clock-top-name')))
          .data,
      'Opponent',
    );
    for (final position in ['top', 'bottom']) {
      final rating = tester.widget<Text>(
        find.byKey(ValueKey('game-clock-$position-rating')),
      );
      expect(rating.style!.fontSize, greaterThanOrEqualTo(26));
      final time = find.byKey(ValueKey('game-clock-$position-time'));
      final text = tester.widget<Text>(
        find.descendant(of: time, matching: find.byType(Text)),
      );
      expect(text.style!.fontSize, greaterThanOrEqualTo(70));
      final clockRect = tester.getRect(time);
      final boardRect = tester.getRect(find.byType(InteractiveChessBoard));
      final rightSideWidth = 1280 - boardRect.right;
      expect(clockRect.left, greaterThan(boardRect.right));
      expect(clockRect.width / rightSideWidth, inInclusiveRange(0.43, 0.55));
      expect(clockRect.height, greaterThanOrEqualTo(100));
      expect(clockRect.bottom, lessThanOrEqualTo(480));
    }
    expect(sounds.events, [AppSoundEvent.gameStart]);
    expect(engine.requests, 0);
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('COMPANION_PREVIEW')) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('companion-preview')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = File('build/previews/companion-lichess.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Duplicate and reconnect packets keep orientation and start once',
      (tester) async {
    final client = _GameClient();
    final sounds = _Sounds();
    _companionViewport(tester);
    await tester.pumpWidget(_room(client, sounds));
    await tester.pump();
    client.emitFull(localBlack: true);
    await tester.pump();
    await tester.pump();
    expect(_board(tester).flipped, isTrue);

    await tester.tap(find.byTooltip('Flip'));
    await tester.pump();
    expect(_board(tester).flipped, isFalse);
    client.emitFull(localBlack: true);
    client.emitState();
    await tester.pump();
    expect(_board(tester).flipped, isFalse,
        reason: 'A repeated player identity preserves manual orientation.');
    unawaited(client.disconnect());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(client.streamsOpened, 2);
    client.emitFull(localBlack: true);
    await tester.pump();
    await tester.pump();
    expect(_board(tester).flipped, isFalse);
    expect(
        sounds.events.where((e) => e == AppSoundEvent.gameStart), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('A new game resolves White and announces its own start',
      (tester) async {
    final client = _GameClient();
    final sounds = _Sounds();
    _companionViewport(tester);
    await tester.pumpWidget(_room(client, sounds));
    await tester.pump();
    client.emitFull(localBlack: true);
    await tester.pump();
    await tester.pump();
    await tester.pumpWidget(_room(client, sounds, gameId: 'next-game'));
    await tester.pump();
    client.emitFull(localBlack: false, gameId: 'next-game');
    await tester.pump();
    await tester.pump();
    expect(_board(tester).flipped, isFalse);
    expect(
        sounds.events.where((e) => e == AppSoundEvent.gameStart), hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Finished games do not announce start or offer offline modes',
      (tester) async {
    final client = _GameClient();
    final sounds = _Sounds();
    _companionViewport(tester);
    await tester.pumpWidget(_room(client, sounds));
    await tester.pump();
    client.emitFull(localBlack: false, status: 'resign');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(sounds.events.where((e) => e == AppSoundEvent.gameStart), isEmpty);
    expect(find.text('Play again'), findsOneWidget);
    expect(find.text('Main menu'), findsOneWidget);
    expect(find.text('Analyze game'), findsNothing);
    expect(find.text('Bot game settings'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
    debugDefaultTargetPlatformOverride = null;
  });

  for (final onlineOnly in [true, false]) {
    testWidgets(
        'Copy PGN never exposes the access token (onlineOnly=$onlineOnly)',
        (tester) async {
      final client = _GameClient();
      _companionViewport(tester);
      await tester.pumpWidget(_room(client, _Sounds(), onlineOnly: onlineOnly));
      await tester.pump();
      client.emitFull(localBlack: false);
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('More'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Copy PGN'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(copiedText, contains('[LichessGameId "companion-game"]'));
      expect(copiedText, isNot(contains('LichessToken')));
      expect(copiedText, isNot(contains('test-token')));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      client.close();
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('Share live URL copies the game link without leaving live play',
      (tester) async {
    final client = _GameClient();
    final routes = <String>[];
    _companionViewport(tester);
    await tester.pumpWidget(_room(client, _Sounds(), onNavigate: routes.add));
    await tester.pump();
    client.emitFull(localBlack: true);
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byTooltip('More'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Share live URL'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(copiedText, 'https://lichess.org/companion-game');
    expect(routes, isEmpty);
    expect(find.byType(InteractiveChessBoard), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    client.close();
    debugDefaultTargetPlatformOverride = null;
  });
}

void _companionViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 480);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

InteractiveChessBoard _board(WidgetTester tester) =>
    tester.widget<InteractiveChessBoard>(find.byType(InteractiveChessBoard));

Widget _room(
  _GameClient client,
  _Sounds sounds, {
  String gameId = 'companion-game',
  bool allowPhysicalFlip = true,
  bool onlineOnly = true,
  bool companionDevice = false,
  ValueChanged<String>? onNavigate,
  BotEngineAdapter? engine,
}) =>
    MaterialApp(
      theme: ChessnutTheme.light(),
      home: RepaintBoundary(
        key: const ValueKey('companion-preview'),
        child: Scaffold(
          body: GameRoomScreen(
            onNavigate: onNavigate ?? (_) {},
            mode: GameLaunchMode.lichess,
            onlineOnly: onlineOnly,
            isChessnutClockDevice: companionDevice,
            apiClient: ChessnutApiClient(httpClient: client),
            lichessConfig: LichessGameConfig(
              gameId: gameId,
              token: 'test-token',
              lichessName: 'CompanionPlayer',
            ),
            boardSettings: BoardSettingsState(allowFlip: allowPhysicalFlip),
            appSoundService: sounds,
            botEngine: engine,
          ),
        ),
      ),
    );

class _Sounds extends AppSoundService {
  final List<AppSoundEvent> events = [];

  @override
  Future<void> play(AppSoundEvent event) async => events.add(event);
}

class _UnusedEngine extends BotEngineAdapter {
  int requests = 0;

  @override
  Future<void> prepare({required BotGameConfig config}) async => requests++;

  @override
  Future<BotMoveResult?> bestMove({
    required String fen,
    required BotGameConfig config,
    List<String> moveHistory = const [],
  }) async {
    requests++;
    return null;
  }
}

class _GameClient extends http.BaseClient {
  StreamController<List<int>>? _controller;
  int streamsOpened = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.startsWith('/api/board/game/stream/')) {
      streamsOpened++;
      _controller = StreamController<List<int>>();
      return http.StreamedResponse(_controller!.stream, 200);
    }
    return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
  }

  void emitFull({
    required bool localBlack,
    String gameId = 'companion-game',
    String status = 'started',
  }) {
    final local = {
      'id': 'companionplayer',
      'name': 'CompanionPlayer',
      'rating': 1812
    };
    final opponent = {'id': 'opponent', 'name': 'Opponent', 'rating': 1924};
    _emit({
      'type': 'gameFull',
      'id': gameId,
      'initialFen': 'startpos',
      'white': localBlack ? opponent : local,
      'black': localBlack ? local : opponent,
      'clock': {'initial': 600000, 'increment': 5000},
      'state': {
        'moves': '',
        'status': status,
        'wtime': 600000,
        'btime': 600000,
        if (status == 'resign') 'winner': 'white',
      },
    });
  }

  void emitState() => _emit({
        'type': 'gameState',
        'moves': '',
        'status': 'started',
        'wtime': 600000,
        'btime': 600000,
      });

  void _emit(Map<String, Object> event) =>
      _controller!.add(utf8.encode('${jsonEncode(event)}\n'));

  Future<void> disconnect() => _controller!.close();

  @override
  void close() {
    unawaited(_controller?.close());
    super.close();
  }
}
