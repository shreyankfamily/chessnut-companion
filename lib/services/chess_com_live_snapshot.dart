import 'dart:convert';

/// Reads only the current game and clocks from the existing Chess.com page.
/// The game methods are also used by Chessnut's upstream chess-helper.js.
/// A starting-position FEN alone must never be treated as a matched game.
const chessComLiveSnapshotScript = r'''
(() => {
  try {
    const board = document.querySelector('chess-board, wc-chess-board');
    const game = board && board.game;
    if (!game || typeof game.getPlayingAs !== 'function' ||
        typeof game.getPGN !== 'function') return null;
    const mode = typeof game.getMode === 'function' ? game.getMode() : null;
    if (mode && mode.name === 'analysis') return null;
    if (!/^\/play\/online(?:\/|$)/.test(location.pathname) &&
        !/^\/game\/live\//.test(location.pathname)) return null;
    const playingAs = game.getPlayingAs();
    if (!['w', 'b', 'white', 'black'].includes(playingAs)) return null;
    const clock = color => {
      const element = document.querySelector('.clock-' + color + ' [role="timer"]');
      return element ? element.textContent.trim() : null;
    };
    return JSON.stringify({
      pgn: game.getPGN(), playingAs,
      whiteClock: clock('white'), blackClock: clock('black')
    });
  } catch (_) { return null; }
})()
''';

/// Opens Chess.com's own friend picker. This never sends a challenge itself.
const chessComOpenFriendPickerScript = r'''
(() => {
  const icon = document.querySelector('.new-game-secondaryCta img[alt="hand-shake"]');
  const button = icon && icon.closest('button');
  if (!button || button.disabled) return false;
  button.click();
  return true;
})()
''';

class ChessComLiveSnapshot {
  const ChessComLiveSnapshot({
    required this.gameId,
    required this.localPlayerIsWhite,
    required this.whiteName,
    required this.blackName,
    required this.pgn,
    this.whiteRating,
    this.blackRating,
    this.whiteClock,
    this.blackClock,
  });

  final String gameId;
  final bool localPlayerIsWhite;
  final String whiteName;
  final String blackName;
  final String pgn;
  final int? whiteRating;
  final int? blackRating;
  // These are the site's displayed times, never a second independent clock.
  final String? whiteClock;
  final String? blackClock;

  static ChessComLiveSnapshot? fromJavaScript(Object? value) {
    try {
      for (var depth = 0; depth < 3 && value is String; depth++) {
        value = jsonDecode(value);
      }
      if (value is! Map) return null;
      final pgn = value['pgn'];
      if (pgn is! String) return null;
      String header(String key) =>
          RegExp('^\\[$key\\s+"([^"\\r\\n]*)"\\]\\s*\$', multiLine: true)
              .firstMatch(pgn)
              ?.group(1)
              ?.trim() ??
          '';
      final white = header('White');
      final black = header('Black');
      final side = value['playingAs'];
      if (!const ['w', 'b', 'white', 'black'].contains(side) ||
          white.isEmpty ||
          black.isEmpty ||
          white == '?' ||
          black == '?' ||
          header('Result') != '*') {
        return null;
      }

      String? gameId;
      for (final key in const ['Link', 'URL', 'GameUrl', 'Site']) {
        final uri = Uri.tryParse(header(key));
        if (uri == null ||
            !const ['www.chess.com', 'chess.com'].contains(uri.host)) {
          continue;
        }
        final match =
            RegExp(r'^/game/live/([a-zA-Z0-9-]+)/?$').firstMatch(uri.path);
        if (match != null) {
          gameId = match.group(1);
          break;
        }
      }
      if (gameId == null) return null;

      String? clock(Object? raw) {
        if (raw is! String) return null;
        final time = raw.trim();
        return RegExp(
                    r'^\d{1,3}:\d{2}(?::\d{2})?(?:\.\d{1,2})?$|^\d{1,2}\.\d{1,2}$')
                .hasMatch(time)
            ? time
            : null;
      }

      return ChessComLiveSnapshot(
        gameId: gameId,
        localPlayerIsWhite: side == 'w' || side == 'white',
        whiteName: white,
        blackName: black,
        pgn: pgn,
        whiteRating: int.tryParse(header('WhiteElo')),
        blackRating: int.tryParse(header('BlackElo')),
        whiteClock: clock(value['whiteClock']),
        blackClock: clock(value['blackClock']),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Kept for the app session so page reloads and reopening the same game are quiet.
class ChessComGameStartTracker {
  static final session = ChessComGameStartTracker();
  final Set<String> _seen = {};

  bool shouldAnnounce(ChessComLiveSnapshot snapshot) {
    if (!_seen.add(snapshot.gameId)) return false;
    if (_seen.length > 128) _seen.remove(_seen.first);
    return true;
  }
}
