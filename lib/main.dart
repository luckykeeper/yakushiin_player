// yakushiin_player
// @CreateTime    : 2025/03/28 21:57
// @Author        : Luckykeeper
// @Email         : luckykeeper@luckykeeper.site
// @Project       : yakushiin_player

import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yakushiin_player/model/runtime.dart';
import 'package:yakushiin_player/model/yakushiin_background_player.dart';
import 'package:yakushiin_player/model/yakushiin_logger.dart';
import 'package:yakushiin_player/page/settings_page.dart';
import 'package:yakushiin_player/page/sync_page.dart';
import 'package:yakushiin_player/page/welcome_page.dart';
import 'package:yakushiin_player/page/yakushiin_player.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  await yakushiinRuntimeEnvironment.init();

  // 配置音频会话（必须在 MediaKit 初始化之前）
  final session = await AudioSession.instance;
  await session.configure(AudioSessionConfiguration.music());
  //  // 配置 AudioSession
  //   final session = await AudioSession.instance;
  //   await session.configure(AudioSessionConfiguration(
  //     // 音频类型为播放
  //     avAudioSessionCategory: AVAudioSessionCategory.playback,
  //     // iOS 选项：允许混响，但不允许其他应用打断
  //     avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth,
  //     // Android 音频属性：媒体播放，允许混响
  //     androidAudioAttributes: const AndroidAudioAttributes(
  //       contentType: AndroidAudioContentType.music,
  //       flags: AndroidAudioFlags.none,
  //       usage: AndroidAudioUsage.media,
  //     ),
  //     // Android 音频焦点策略：请求焦点，允许混响，自动暂停/恢复
  //     androidAudioFocusGainType: AndroidAudioFocusGainType.gain,ad
  //     androidWillPauseWhenDucked: true, // 如果希望 ducking 时暂停而不是降低音量，设为 true
  //   ));

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
  await yakushiinLoggerInstance.loggerInit();
  // if (yakushiinRuntimeEnvironment.isAndroidPlatform) {
  //   await FlutterBackground.hasPermissions;
  // final androidConfig = FlutterBackgroundAndroidConfig(
  //   notificationTitle: "YakuShiinPlayer",
  //   notificationText: "播放器正在后台播放音乐",
  //   notificationImportance: AndroidNotificationImportance.high,
  // );
  // bool result = await FlutterBackground.initialize(
  //   androidConfig: androidConfig,
  // );
  // yakushiinLogger.i("后台服务初始化结果：$result");
  // bool hasPermissions = await FlutterBackground.hasPermissions;
  // yakushiinLogger.i("后台服务权限：$hasPermissions");
  // if (result) {
  //   bool result = await FlutterBackground.enableBackgroundExecution();
  //   yakushiinLogger.i("后台服务启动结果：$result");
  //   yakushiinLogger.i(
  //     "后台服务启动验证：${FlutterBackground.isBackgroundExecutionEnabled}",
  //   );
  // }
  // }
  yakushiinBackgroundPlayerHandler = await AudioService.init(
    builder: () => MediaKitAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'site.luckykeeper.yakushiin_player',
      androidNotificationChannelName: 'YakushiinPlayer',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      // 可以添加更多配置，如通知图标等
      // androidNotificationIcon: 'mipmap/ic_launcher',
    ),
  );
  MediaKit.ensureInitialized();
  //  yakushiinBackgroundPlayerHandler = await AudioService.init(
  //   builder: () => AudioPlayerHandler(),
  //   config: const AudioServiceConfig(
  //     androidNotificationChannelId: 'com.ryanheise.myapp.channel.audio',
  //     androidNotificationChannelName: 'Audio playback',
  //     androidNotificationOngoing: true,
  //   ),
  // );
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
