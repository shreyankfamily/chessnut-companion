import 'dart:async';
import 'package:chessnut_flutter_export/companion_app.dart';
import 'package:chessnut_flutter_export/services/physical_board_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Companion opens online only and fits its 1280x480 display',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(CompanionOnlineApp(
      boardGateway: _Board(),
      httpClient: MockClient((_) async => http.Response('{}', 404)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Companion Online'), findsOneWidget);
    expect(find.text('Lichess'), findsWidgets);
    expect(find.text('Chess.com'), findsOneWidget);
    expect(find.text('Connect board'), findsOneWidget);
    expect(find.text('Puzzles'), findsNothing);
    expect(find.text('Analysis'), findsNothing);
    expect(find.text('Play bot'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Game and match sounds'), findsOneWidget);
    await tester.tap(find.text('Game and match sounds'));
    await tester.pumpAndSettle();
    expect((await SharedPreferences.getInstance()).getBool('companion.sounds'),
        isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

class _Board extends PhysicalBoardGateway {
  @override
  PhysicalBoardModel get boardModel => PhysicalBoardModel.air;
  @override
  Stream<PhysicalBoardConnectionState> get stateStream => const Stream.empty();
  @override
  Stream<String> get boardFenStream => const Stream.empty();
  @override
  Future<bool> connect() async => false;
  @override
  Future<void> disconnect() async {}
  @override
  Future<bool> write(List<int> command, {bool withoutResponse = false}) async =>
      true;
}
