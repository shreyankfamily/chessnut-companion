import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/app_language.dart';
import 'l10n/app_strings.dart';
import 'models/app_models.dart';
import 'screens/board_connection_screen.dart';
import 'screens/chess_com_webview_screen.dart';
import 'screens/game_room_screen.dart';
import 'screens/setup_screen.dart';
import 'services/app_sound_service.dart';
import 'services/board_background_connection_service.dart';
import 'services/board_settings_service.dart';
import 'services/chess_clock_switch_service.dart';
import 'services/chessnut_api_client.dart';
import 'services/physical_board_gateway.dart';
import 'services/screen_wake_lock_service.dart';
import 'services/universal_ble_board_transport.dart';
import 'theme/chessnut_theme.dart';

/// Independent online-only entry point. No Chessnut account or Firebase setup.
class CompanionOnlineApp extends StatelessWidget {
  const CompanionOnlineApp({this.boardGateway, this.httpClient, super.key});

  final PhysicalBoardGateway? boardGateway;
  final http.Client? httpClient;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Companion Online',
        debugShowCheckedModeBanner: false,
        theme: ChessnutTheme.light(ChessnutVisualTheme.classic, false),
        darkTheme: ChessnutTheme.dark(ChessnutVisualTheme.classic, false),
        themeMode: ThemeMode.dark,
        supportedLocales: AppLanguagePreference.supportedLocales,
        localizationsDelegates: AppStrings.localizationsDelegates,
        home: CompanionOnlineShell(
          boardGateway: boardGateway,
          httpClient: httpClient,
        ),
      );
}

class CompanionOnlineShell extends StatefulWidget {
  const CompanionOnlineShell({this.boardGateway, this.httpClient, super.key});

  final PhysicalBoardGateway? boardGateway;
  final http.Client? httpClient;

  @override
  State<CompanionOnlineShell> createState() => _CompanionOnlineShellState();
}

class _CompanionOnlineShellState extends State<CompanionOnlineShell> {
  late final http.Client _http;
  late final ChessnutApiClient _api;
  late final PhysicalBoardGateway _board;
  late final ChessClockSwitchService _switches;
  StreamSubscription<PhysicalBoardConnectionState>? _connection;
  final _background = const MethodChannelBoardBackgroundConnectionService();
  BoardSettingsState _settings = const BoardSettingsState(
    evaluateLed: false,
    showScorebar: false,
    allowTakeback: false,
    voiceMovesEnabled: false,
  );
  bool _sounds = true;
  bool _connected = false;
  bool _loading = true;
  String _screen = 'Online';
  LichessGameConfig _game = const LichessGameConfig.empty();

  @override
  void initState() {
    super.initState();
    _http = widget.httpClient ?? http.Client();
    _api = ChessnutApiClient(httpClient: _http);
    _board = widget.boardGateway ??
        ChessnutBoardGateway(transport: UniversalBleBoardTransport());
    _switches = ChessClockSwitchService()..initialize();
    _connected = _board.currentState == PhysicalBoardConnectionState.connected;
    _connection = _board.stateStream.listen((state) {
      if (!mounted) return;
      setState(
          () => _connected = state == PhysicalBoardConnectionState.connected);
      _syncKeepAlive();
    });
    unawaited(_loadSettings());
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('companion.boardSettings');
    BoardSettingsState? settings;
    if (saved != null) {
      try {
        settings = BoardSettingsState.fromJson(
            (jsonDecode(saved) as Map).cast<String, dynamic>());
      } on FormatException {
        // Recover from an interrupted or old preferences write.
      } on TypeError {
        // Unknown settings format: use the safe online defaults.
      }
    }
    if (!mounted) return;
    setState(() {
      _settings = _onlineSettings(settings ?? _settings);
      _sounds = prefs.getBool('companion.sounds') ?? true;
      _loading = false;
    });
  }

  BoardSettingsState _onlineSettings(BoardSettingsState settings) =>
      settings.copyWith(
        evaluateLed: false,
        showScorebar: false,
        allowTakeback: false,
        voiceMovesEnabled: false,
      );

  void _changeSettings(BoardSettingsState value) {
    setState(() => _settings = _onlineSettings(value));
    unawaited(SharedPreferences.getInstance().then((prefs) => prefs.setString(
        'companion.boardSettings', jsonEncode(_settings.toJson()))));
  }

  ChessnutBoardModel get _boardModel => ChessnutBoardModel.values.firstWhere(
        (model) => model.name == _board.boardModel.name,
        orElse: () => ChessnutBoardModel.unknown,
      );

  void _syncKeepAlive() => unawaited(_background.setKeepAlive(
        enabled: _connected,
        connected: _connected,
        boardModel: _boardModel,
      ));

  void _go(String route) {
    if (route == 'ConnectBoard') {
      unawaited(Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (pageContext) => Scaffold(
          body: SafeArea(
            child: BoardConnectionScreen(
              gateway: _board,
              enableUsbConnection: false,
              onNavigate: (_) => Navigator.of(pageContext).pop(),
              onConnected: (model, {gateway}) {
                if (Navigator.of(pageContext).canPop()) {
                  Navigator.of(pageContext).pop();
                }
              },
            ),
          ),
        ),
      )));
      return;
    }
    if (route == 'BoardSettings' || route == 'Settings') {
      _showSettings();
      return;
    }
    // The fork has no puzzle, engine, analysis, store, or account routes.
    setState(() => _screen = route == 'ChessCom' ? route : 'Online');
  }

  void _launch(
    GameLaunchMode mode, {
    BotGameConfig? botConfig,
    OtbGameConfig? otbConfig,
    LichessGameConfig? lichessConfig,
  }) {
    if (mode != GameLaunchMode.chesscom &&
        (mode != GameLaunchMode.lichess || lichessConfig?.isReady != true)) {
      return;
    }
    setState(() {
      if (lichessConfig != null) _game = lichessConfig;
      _screen = mode == GameLaunchMode.chesscom ? 'ChessCom' : 'Play';
    });
  }

  Future<void> _showSettings() => showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, refresh) => AlertDialog(
            title: const Text('Online play settings'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SwitchListTile(
                    title: const Text('Game and match sounds'),
                    subtitle: const Text('Beep when your online game starts'),
                    value: _sounds,
                    onChanged: (value) {
                      setState(() => _sounds = value);
                      refresh(() {});
                      unawaited(SharedPreferences.getInstance().then(
                          (prefs) => prefs.setBool('companion.sounds', value)));
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Physical board auto orientation'),
                    subtitle: const Text(
                        'The screen always follows your online color'),
                    value: _settings.autoFlip,
                    onChanged: (value) {
                      _changeSettings(_settings.copyWith(autoFlip: value));
                      refresh(() {});
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.volume_up_outlined),
                    label: const Text('Test match sound'),
                    onPressed: () => const SystemAppSoundService()
                        .play(AppSoundEvent.gameStart),
                  ),
                ]),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Done'),
              )
            ],
          ),
        ),
      );

  @override
  void dispose() {
    unawaited(_connection?.cancel());
    unawaited(_switches.dispose());
    unawaited(_background.setKeepAlive(
        enabled: false, connected: false, boardModel: _boardModel));
    if (widget.boardGateway == null && _board is ChessnutBoardGateway) {
      unawaited(_board.dispose());
    }
    if (widget.httpClient == null) _http.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_screen == 'Play') {
      content = GameRoomScreen(
        key: ValueKey(_game.gameId),
        mode: GameLaunchMode.lichess,
        onlineOnly: true,
        onNavigate: _go,
        lichessConfig: _game,
        apiClient: _api,
        boardGateway: _board,
        boardSettings: _settings,
        onBoardSettingsChanged: _changeSettings,
        clockSwitchService: _switches,
        soundEffectsEnabled: _sounds,
        showBoardCoordinates: true,
        isChessnutClockDevice: true,
      );
    } else if (_screen == 'ChessCom') {
      content = ChessComWebViewScreen(
        onNavigate: _go,
        apiClient: _api,
        boardGateway: _board,
        boardSettings: _settings,
        clockSwitchService: _switches,
        isChessnutClockDevice: true,
        soundEffectsEnabled: _sounds,
      );
    } else {
      content = Column(children: [
        SizedBox(
          height: 50,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              const Icon(Icons.sports_esports_outlined, size: 24),
              const SizedBox(width: 10),
              const Expanded(
                  child: Text('Companion Online',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 20))),
              TextButton.icon(
                onPressed: () => _go('ConnectBoard'),
                icon: Icon(
                    _connected ? Icons.bluetooth_connected : Icons.bluetooth),
                label: Text(
                    _connected ? _boardModel.displayName : 'Connect board'),
              ),
              IconButton(
                tooltip: 'Settings',
                onPressed: _showSettings,
                icon: const Icon(Icons.settings_outlined),
              ),
            ]),
          ),
        ),
        Expanded(
            child: OnlineSetupScreen(
          onNavigate: _go,
          onLaunchGame: _launch,
          apiClient: _api,
          onSessionUpdated: (_) {},
          boardSettings: _settings,
          onBoardSettingsChanged: _changeSettings,
          directLichessSignIn: true,
          isChessnutClockDevice: true,
        )),
      ]);
    }
    return Scaffold(
      body: SafeArea(
        child: ScreenWakeLockScope(
          enabled: _screen != 'Online',
          service: const SystemScreenWakeLockService(),
          child: content,
        ),
      ),
    );
  }
}
