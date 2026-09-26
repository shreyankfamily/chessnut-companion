# Companion Online

An independent Android fork of [ChessnutNext](https://github.com/chessnutech/ChessnutNext), focused on playing online with a Chessnut board and the Chessnut Companion. Its landscape interface is designed for the Companion's 1280 × 480 display.

The installed app is **Companion Online**, with Android application ID `io.github.shreyankfamily.companiononline`. It installs alongside the stock Chessnut app. This is a personal fork, not an official Chessnut release.

## What is included

- Lichess matchmaking with **Random / White / Black** selection, friend challenges, and incoming challenges through the official Board API.
- Chess.com play and friend challenges through the existing embedded website integration.
- Automatic screen orientation to your playing color, enlarged ratings, and large clocks on the right during online games.
- A game-start sound, with **Game and match sounds** available in settings.
- Chessnut Bluetooth board connection and the existing board/clock integration.

The launcher exposes online play and board settings only. Puzzle, engine, analysis, training, store, and Chessnut-account routes are not part of this app. Legacy source remains in the repository for shared components and upstream maintenance; this is not a complete removal of every unused source file.

## Install on the Companion through Google Play

This app is delivered through a Google Play **internal testing** release, not by downloading an APK from GitHub. Add the Google account used on the Companion to the release's tester list, open the Play testing link on the device, opt in, and select **Install**. Google Play then supplies the correct signed build and updates.

An internal test can have up to 100 testers and is normally available within minutes. It is the appropriate track for installing this personal app on the Companion. Personal Play developer accounts created after November 13, 2023 need 12 opted-in testers for 14 continuous days before they can publish to the public Production track; that requirement does not prevent internal testing. See Google's [testing requirements](https://support.google.com/googleplay/android-developer/answer/14151465).

After installing, close the stock Chessnut app before connecting your board. If it keeps the Bluetooth connection in the background, stop it from Android's app settings so Companion Online can connect. Open Companion Online, choose **Connect board**, grant Nearby devices/Bluetooth permission, then choose Lichess or Chess.com. Keep the Companion connected to the internet and set its media volume high enough to hear game-start sounds.

The current fork uses Bluetooth for board discovery. Physical board orientation is a separate setting from the screen: the screen follows your online color, while **Physical board auto orientation** controls how the app interprets the connected board.

## Lichess account and games

Choose **Lichess**, then **Authorize Lichess**. In the account dialog, **Create token on Lichess** opens the official token page in your browser. Sign into your normal human Lichess account and create a token with these four permissions:

| Permission | Scope |
| --- | --- |
| Play games with the Board API | `board:play` |
| Read incoming challenges | `challenge:read` |
| Create, accept, and decline challenges | `challenge:write` |
| Read followed players | `follow:read` |

Paste the token into **Personal access token** in the app and choose **Connect Lichess**. The app validates it directly with Lichess and stores it using secure storage on the device; it does not send the token to the Chessnut backend. Never paste a real token into Git, source files, logs, issue reports, or chat. Manage or revoke it from [Lichess personal access tokens](https://lichess.org/account/oauth/token).

Select the time control, rated/casual preference, and **Random**, **White**, or **Black** before searching. For a friend game, use the friend challenge controls to select a followed player or enter a username, choose the game settings, and send the challenge. Your friend must accept it. Incoming challenges appear in the same setup flow. The game screen uses the color actually assigned by Lichess, including when resuming a game.

Lichess requires electronic boards to use its official Board API. Random matchmaking through this API supports rapid, classical, and correspondence games. Blitz is permitted for direct challenges, AI games, and bulk pairings; this fork exposes friend challenges rather than AI play. Bullet and ultrabullet are not supported. The app does not use Vision to bypass these limits. See [Lichess's electronic-board policy](https://lichess.org/page/eboards) and [Board API documentation](https://lichess.org/api#tag/Board).

## Chess.com account and games

Choose **Chess.com** and sign in on the embedded Chess.com website. Use the site's matchmaking controls, or the app's **Challenge a friend** shortcut to open the site's **Play a Friend** picker. You choose the opponent and submit the challenge on Chess.com; opening the picker does not send one.

During a recognized live game on a wide display, the app shows a native board oriented to your color, larger ratings, and the clocks read from Chess.com's page. You can move on the physical board or the displayed board. **Game controls** returns to the website for resigning, draw offers, chat, and other site controls; **Board & clocks** restores the large display.

This retains ChessnutNext's WebView integration and its remotely loaded helper at `https://api.chessnutech.com/static/js/chess-helper.js`. It depends on that service and on Chess.com's page structure. If live-game data or clocks cannot be read, the original website remains available instead of displaying invented clock values. If the friend shortcut cannot find the picker, open **New Game → Play a Friend** on the website.

Chess.com's public API is read-only and cannot send moves. This fork does not replace the existing website integration with a new public live-play API. See [Chess.com's API guidance](https://support.chess.com/en/articles/9650547-what-is-the-pubapi-and-how-do-i-use-it). Changes to Chess.com or the remote helper may require an app update; verify play with your own account and hardware before relying on it for a rated game.

## Android build

The configured build toolchain is:

| Tool | Version |
| --- | --- |
| Flutter | 3.47.5 |
| Dart | 3.13.4, bundled with Flutter |
| Java | JDK 17 |
| Android compile / target SDK | 36 |
| Android minimum SDK | 28 |
| Android NDK | 28.2.13676358 |
| Google Play bundle architecture | ARM64 (`android-arm64`) |

Install Flutter, JDK 17, and the Android SDK/NDK, then configure their normal local paths. `flutter doctor -v` helps identify missing Android tooling. Android SDK license acceptance must be completed by the developer. Android Studio is convenient for installing the SDK components; the commands below run from the repository root.

```bash
GIT_LFS_SKIP_SMUDGE=1 git clone https://github.com/shreyankfamily/chessnut-companion.git
cd chessnut-companion
flutter pub get
flutter build appbundle --release --target-platform android-arm64
```

The release build writes `build/app/outputs/bundle/release/app-release.aab`. Google Play accepts the Android App Bundle and generates the device-specific install for the Companion. It must be signed with the configured release/upload key; debug signing is not accepted by Google Play.

`android/gradle.properties` sets `companionOnline=true`, disabling the native Stockfish, LC0, and camera/Vision builds for this online app. Their large Git LFS engine/model assets are therefore not needed for this configuration. Keep that property enabled for these instructions. The upstream native sources remain available, but changing the property alone does not restore the original multi-mode product.

Firebase initialization and its Android build integration have been removed from this fork. The online launcher does not require Firebase files, a Chessnut account, or the upstream Google/Apple authentication setup. `flutter_secure_storage` is pinned to `10.0.0` for compatibility with the selected stable Android SDK. Keep the checked-in dependency lockfile when reproducing a build.

## Release signing and updates

Use your own local release key for a durable installation. Create it interactively so passwords are not included in shell history:

```bash
keytool -genkeypair -v \
  -keystore android/release-keystore.jks \
  -alias release \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000

cp android/key.properties.example android/key.properties
```

Edit `android/key.properties` locally with `storeFile`, `storePassword`, `keyAlias`, and `keyPassword`. The example's `storeFile=release-keystore.jks` is relative to the `android` directory.

```bash
flutter build appbundle --release --target-platform android-arm64
```

The release build writes `build/app/outputs/bundle/release/app-release.aab`. Upload that signed bundle to Google Play Console's internal-testing track, add the Companion's Google account as a tester, and install through the Play testing link. Release builds require the configured keystore; they do not fall back to debug signing.

Never commit `android/key.properties`, the `.jks`/`.keystore` file, passwords, tokens, or APK/build output. Back up the release key and its credentials securely: future updates must use the same application ID and signing key. Increase the build number in `pubspec.yaml` for later releases. Switching an existing debug installation to a release build uses a different signature and may require uninstalling the debug app, which removes its local settings and saved token.

## Focused validation

After `flutter pub get`, run the tests covering this fork and its online/clock dependencies:

```bash
flutter test --no-pub \
  test/companion_app_test.dart \
  test/companion_online_setup_test.dart \
  test/lichess_personal_token_test.dart \
  test/companion_lichess_game_test.dart \
  test/chess_com_companion_test.dart \
  test/lichess_board_service_test.dart \
  test/android_lichess_clock_test.dart \
  test/android_lichess_landscape_test.dart \
  test/chess_clock_android_landscape_test.dart \
  test/chess_clock_switch_service_test.dart
```

The Chess.com Companion test file includes eight cases covering real-game recognition, invalid/non-game rejection, clock parsing, one alert per game, landscape orientation/layout, accepted/rejected touchscreen moves, and compact layouts at 640 × 240 and 853 × 320 logical pixels. These use controlled WebView/game fixtures; they do not establish successful live service or Bluetooth operation.

The inherited full upstream suite also includes unrelated modes and tests that depend on unavailable private Vision/macOS components. Do not interpret these focused commands as a claim that the entire upstream suite passes. Hardware acceptance still includes sign-in, both colors, friend challenges, board moves, clock synchronization, reconnects, and audible starts on the Companion.

## Upstream and license

The original build instructions are preserved in [docs/UPSTREAM_README.md](docs/UPSTREAM_README.md) as historical upstream documentation. They describe the original multi-platform app and its Firebase/engine setup, not the Companion Online build above.

This fork retains ChessnutNext's [GNU General Public License v3.0](LICENSE). Keep the license and upstream attribution when distributing builds, and make the corresponding source available under the license. Third-party components retain their own licenses.
