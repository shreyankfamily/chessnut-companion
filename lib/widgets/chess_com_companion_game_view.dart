import 'dart:math' as math;
import 'package:dartchess/dartchess.dart' as dc;

import '../l10n/localized_material.dart';
import '../services/chess_com_live_snapshot.dart';
import 'chess_board.dart';

/// A readable view over the live WebView. The page remains mounted underneath,
/// including its clock, game controls, and physical-board bridge.
class ChessComCompanionGameView extends StatelessWidget {
  const ChessComCompanionGameView({
    required this.snapshot,
    required this.fen,
    required this.onGameControls,
    required this.onMove,
    this.movesEnabled = true,
    this.boardVersion = 0,
    super.key,
  });

  final ChessComLiveSnapshot snapshot;
  final String fen;
  final VoidCallback onGameControls;
  final ValueChanged<ChessBoardMove> onMove;
  final bool movesEnabled;
  final int boardVersion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final compact = constraints.maxHeight < 340;
          final edgePadding = compact ? 6.0 : 12.0;
          final boardSize = math.min(
            constraints.maxHeight - edgePadding * 2,
            (constraints.maxWidth - edgePadding * 2) * 0.48,
          );
          final whiteToMove = ChessBoardState.fromFen(fen).whiteToMove;
          Widget player(bool white) => _PlayerClock(
                name: white ? snapshot.whiteName : snapshot.blackName,
                rating: white ? snapshot.whiteRating : snapshot.blackRating,
                clock: white ? snapshot.whiteClock : snapshot.blackClock,
                active: white == whiteToMove,
                local: white == snapshot.localPlayerIsWhite,
                compact: compact,
              );
          return Padding(
            padding: EdgeInsets.all(edgePadding),
            child: Row(
              children: [
                SizedBox.square(
                  key: const ValueKey('chesscom-companion-board'),
                  dimension: boardSize,
                  child: InteractiveChessBoard(
                    key: ValueKey(boardVersion),
                    size: boardSize,
                    initialFen: fen,
                    flipped: !snapshot.localPlayerIsWhite,
                    showCoordinates: true,
                    interactionEnabled: movesEnabled,
                    enabledColors: {
                      snapshot.localPlayerIsWhite
                          ? dc.Side.white
                          : dc.Side.black,
                    },
                    showLegalTargets: false,
                    onMove: onMove,
                  ),
                ),
                SizedBox(width: compact ? 12 : 20),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: player(!snapshot.localPlayerIsWhite)),
                      SizedBox(height: compact ? 4 : 8),
                      Expanded(child: player(snapshot.localPlayerIsWhite)),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: compact ? 32 : 40,
                        child: TextButton.icon(
                          key: const ValueKey('chesscom-game-controls'),
                          onPressed: onGameControls,
                          style: compact
                              ? TextButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  minimumSize: const Size(0, 32),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                )
                              : null,
                          icon:
                              Icon(Icons.tune_rounded, size: compact ? 18 : 20),
                          label: const Text('Game controls'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _PlayerClock extends StatelessWidget {
  const _PlayerClock({
    required this.name,
    required this.rating,
    required this.clock,
    required this.active,
    required this.local,
    required this.compact,
  });

  final String name;
  final int? rating;
  final String? clock;
  final bool active;
  final bool local;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey('chesscom-clock-panel-${local ? 'local' : 'opponent'}'),
      width: double.infinity,
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 18, vertical: compact ? 6 : 8),
      decoration: BoxDecoration(
        color:
            active ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(compact ? 12 : 18),
        border: active ? Border.all(color: scheme.primary, width: 2) : null,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$name${local ? ' · You' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: compact ? 16 : 20,
                      height: compact ? 1.1 : null,
                      fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(width: compact ? 6 : 12),
              Text(
                rating?.toString() ?? '—',
                style: TextStyle(
                    fontSize: compact ? 20 : 32,
                    height: compact ? 1.1 : null,
                    fontWeight: FontWeight.w800),
              ),
            ],
          ),
          Expanded(
            child: Center(
              key: ValueKey(
                  'chesscom-clock-face-${local ? 'local' : 'opponent'}'),
              child: FittedBox(
                fit: BoxFit.contain,
                child: Text(
                  clock ?? '—:—',
                  style: const TextStyle(
                    fontSize: 112,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
