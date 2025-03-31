// yakushiin_player
// @CreateTime    : 2025/03/28 21:57
// @Author        : Luckykeeper
// @Email         : luckykeeper@luckykeeper.site
// @Project       : yakushiin_player

import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yakushiin_player/model/runtime.dart';
import 'package:yakushiin_player/model/yakushiin_logger.dart';
import 'package:yakushiin_player/page/settings_page.dart';
import 'package:yakushiin_player/page/sync_page.dart';
import 'package:yakushiin_player/page/welcome_page.dart';
import 'package:yakushiin_player/page/yakushiin_player.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  await yakushiinRuntimeEnvironment.init();
  final savedThemeMode = await AdaptiveTheme.getThemeMode();
  if (yakushiinRuntimeEnvironment.isDesktopPlatform) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(680, 720),
      minimumSize: Size(680, 720),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  MediaKit.ensureInitialized();
  await yakushiinLoggerInstance.loggerInit();
  runApp(ProviderScope(child: YakushiinPlayer(savedThemeMode: savedThemeMode)));
}

class YakushiinPlayer extends ConsumerWidget {
  final AdaptiveThemeMode? savedThemeMode;
  const YakushiinPlayer({super.key, this.savedThemeMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final botToastBuilder = BotToastInit();
    final smartDailogBuilder = FlutterSmartDialog.init();
    return AdaptiveTheme(
      light: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: Colors.cyan,
          surfaceContainerLow: Color(0xFFF2FBFC),
        ),
      ),
      dark: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Colors.cyan,
          surfaceContainerLow: Color(0xFF152324),
        ),
      ),
      initial: savedThemeMode ?? AdaptiveThemeMode.system,
      builder:
          (theme, darkTheme) => MaterialApp(
            // 新版的颜色问题 - Breaking Change
            // https://docs.flutter.dev/release/breaking-changes/new-color-scheme-roles
            // 过渡方案：手动指定颜色，使版本间效果接近一致
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('zh')],
            theme: theme,
            darkTheme: darkTheme,
            navigatorObservers: [
              BotToastNavigatorObserver(),
              FlutterSmartDialog.observer,
            ],
            builder: (context, child) {
              child = botToastBuilder(context, child);
              child = smartDailogBuilder(context, child);
              return child;
            },

            routes: {
              "/": (context) => const WelcomePage(),
              "/syncPlayList": (context) => const SyncPlayListPage(),
              "/settings": (context) => const SettingsPage(),
              "/yakushiinPlayer": (context) => const YakushiinPlayerPage(),
            },
          ),
      debugShowFloatingThemeButton: true,
    );
  }
}
