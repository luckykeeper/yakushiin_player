// yakushiin_player
// @CreateTime    : 2025/03/28 23:52
// @Author        : Luckykeeper
// @Email         : luckykeeper@luckykeeper.site
// @Project       : yakushiin_player

import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3：StateProvider 移入 legacy 库（保持原有用法不变）
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:geolocator/geolocator.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pedometer/pedometer.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:weather/weather.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yakushiin_player/model/gateway_associate/noa_player_v2_playlist.dart';
import 'package:yakushiin_player/model/runtime.dart';
import 'package:yakushiin_player/model/version.dart';
import 'package:yakushiin_player/model/yakushiin_background_player.dart';
import 'package:yakushiin_player/model/yakushiin_logger.dart';import 'package:yakushiin_player/model/yakushiin_windows_feature_window_pin_top.dart';
import 'package:yakushiin_player/theme/font.dart';
import 'package:yakushiin_player/yakushiin_widgets/clock.dart';
import 'package:yakushiin_player/yakushiin_widgets/weather_icon.dart';

class YakushiinPlayerPage extends ConsumerStatefulWidget {
  const YakushiinPlayerPage({super.key});

  @override
  ConsumerState<YakushiinPlayerPage> createState() =>
      _YakushiinPlayerPageState();
}

class _YakushiinPlayerPageState extends ConsumerState<YakushiinPlayerPage> {
  String nowPlayingMusicName = "N/A";
  String nextPlayingMusicName = "N/A";
  Duration nowPlayingDurationTotal = Duration.zero;
  Duration nowPlayingDurationCurrent = Duration.zero;
  Duration nowBufferedDuration = Duration.zero; // 当前缓存信息
  bool nowBufferStatus = false; // 当前缓存状态
  bool nowPlayingStatus = false; // 当前播放状态
  AudioDevice nowPlayingAudioDevice = AudioDevice("", "");
  List<AudioDevice> nowPlayingAudioDevicesAvailable = [];
  PlaylistMode nowPlayingPlaylistMode = PlaylistMode.loop;
  AudioParams nowPlayingAudioParams = AudioParams();
  VideoParams nowPlayingVideoParams = VideoParams();
  double? nowPlayingAudioBitrate;
  int nowUsingSubTitleIndex = 0;
  int nowPlayingIndex = 0;
  final nowPlayingIndexProvider = StateProvider<int>((ref) => 0);
  double currentVolumePlayer = 100;
  double currentVolumeSystem = 0;
  Timer? checkPlayListEndTimer;
  Timer? checkPlayingMusicEndTimer;

  // 歌单持久化并发锁，避免 clear+add 非原子导致的 3->2 丢失
  bool _isPersistingPlayList = false;

  // 电视模式，调整上下键的默认行为
  bool tvMode = false;

  // 默认启用防误触模式
  bool denyPopFlag = true;

  // 硬件音频
  AudioStream _audioStream = AudioStream.music;
  AudioSessionCategory? _audioSessionCategory;

  // 计步器
  late Stream<StepCount> _stepCountStream;
  late Stream<PedestrianStatus> _pedestrianStatusStream;
  String pedometerStatus = "unknown";
  int pedometerStep = 0;
  DateTime pedometerTimeStampStepChanged = DateTime.now();
  DateTime pedometerTimeStampStatusChanged = DateTime.now();

  // 页面底部日志显示区域
  final logAreaScrollController = ScrollController();

  void initPedometerPlatformState() {
    _pedestrianStatusStream = Pedometer.pedestrianStatusStream;
    _stepCountStream = Pedometer.stepCountStream;

    _stepCountStream.listen(onStepCount).onError(onStepCountError);

    _pedestrianStatusStream
        .listen(onPedestrianStatusChanged)
        .onError(onPedestrianStatusError);
  }

  void onStepCount(StepCount event) {
    pedometerStep = event.steps;
    pedometerTimeStampStepChanged = event.timeStamp;
  }

  void onPedestrianStatusChanged(PedestrianStatus event) {
    pedometerStatus = event.status;
    pedometerTimeStampStatusChanged = event.timeStamp;
  }

  void onPedestrianStatusError(Object error) {
    yakushiinLogger.e("onPedestrianStatusError:$error");
  }

  void onStepCountError(Object error) {
    yakushiinLogger.e("onStepCountError:$error");
  }

  MediaItem _currentMediaItem() {
    final playlist = ref.read(currentPlayList);
    final index = ref.read(nowPlayingIndexProvider);
    final music = playlist.musicList![index];
    return MediaItem(
      id: music.videoUrl ?? '',
      title: music.videoName ?? '未知',
      duration: nowPlayingDurationTotal,
    );
  }

  // 定位
  Timer? getLocationAndWeatherTimer;
  // 通知栏推送
  Timer? updateNotificationBarTimer;
  late LocationSettings locationSettings;

  Position? currentPosition;

  // 该平台/系统设置下永远拿不到定位（如 PC 端位置服务未开启、权限被永久拒绝）时
  // 置为 true 并停止定时重试；权限只是暂时未授予时保持 false，按原逻辑继续重试
  bool locationUnavailableStopRetry = false;

  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      yakushiinLogger.e('位置服务已被禁用');
      return Future.error('位置服务已被禁用');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        yakushiinLogger.e('位置权限已被阻止');
        return Future.error('位置权限已被阻止');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      yakushiinLogger.e('位置权限已经被永久禁止');
      return Future.error('位置权限已经被永久禁止');
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: locationSettings,
    );
  }

  // 天气
  String yakushiinWeatherApiKey = "";
  Weather? currentWeather;
  Future<void> getCurrentLocationAndWeather() async {
    try {
      yakushiinWeatherApiKey =
          yakushiinRuntimeEnvironment.dataEngineForGatewaySetting
              .getAt(0)!
              .weatherApiToken;
    } catch (e) {
      yakushiinLogger.w("尚未设置天气 API Key ，无法获取天气信息");
      return;
    }
    if (yakushiinWeatherApiKey.isEmpty) {
      yakushiinLogger.w("尚未设置天气 API Key ，无法获取天气信息");
      return;
    }
    yakushiinLogger.i("调用：获取定位和天气");
    try {
      currentPosition = await _determinePosition();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      // 进入页面尝试后判断：平台本身无法获取定位时，取消定时器，不再定时尝试
      if (_isLocationUnavailable(e)) {
        locationUnavailableStopRetry = true;
        getLocationAndWeatherTimer?.cancel();
        getLocationAndWeatherTimer = null;
        yakushiinLogger.w("当前平台无法获取定位（$e），已停止定时获取定位与天气");
        BotToast.showSimpleNotification(
          duration: const Duration(seconds: 2),
          hideCloseButton: false,
          backgroundColor: Colors.pink[200],
          title: "⛔当前平台无法获取定位，已停止定时获取:$e",
          titleStyle: styleFontSimkai,
        );
        return;
      }
      yakushiinLogger.e("获取定位信息异常:$e");
      try {
        currentPosition = await Geolocator.getLastKnownPosition();
      } catch (e) {
        yakushiinLogger.w("暂时无法获取定位:$e");
        BotToast.showSimpleNotification(
          duration: const Duration(seconds: 2),
          hideCloseButton: false,
          backgroundColor: Colors.pink[200],
          title: "⛔暂时无法获取定位:$e",
          titleStyle: styleFontSimkai,
        );
        return;
      }
    }
    yakushiinLogger.d("currentPosition:$currentPosition");

    WeatherFactory yakushiinWeatherFactory = WeatherFactory(
      yakushiinWeatherApiKey,
      language: Language.CHINESE_SIMPLIFIED,
    );
    if (currentPosition != null) {
      try {
        currentWeather = await yakushiinWeatherFactory.currentWeatherByLocation(
          currentPosition!.latitude,
          currentPosition!.longitude,
        );
        yakushiinLogger.d("currentWeather:$currentWeather");
      } catch (e) {
        yakushiinLogger.e("获取天气信息异常:$e");
        BotToast.showSimpleNotification(
          duration: const Duration(seconds: 2),
          hideCloseButton: false,
          backgroundColor: Colors.pink[200],
          title: "⛔获取天气信息异常:$e",
          titleStyle: styleFontSimkai,
        );
      }
    } else {
      BotToast.showSimpleNotification(
        duration: const Duration(seconds: 2),
        hideCloseButton: false,
        backgroundColor: Colors.pink[200],
        title: "⛔获取天气信息异常:无法获取当前位置",
        titleStyle: styleFontSimkai,
      );
    }
    if (mounted) {
      setState(() {});
    }
  }

  // Anime4K 超分（bloc97/Anime4K v4.0.1 官方预设链）
  // 链中文件名与 assets/shaders/ 一致，运行时解压到应用支持目录后交给 mpv 加载
  static const List<String> _anime4kShaderFiles = [
    "Anime4K_Clamp_Highlights.glsl",
    "Anime4K_Restore_CNN_S.glsl",
    "Anime4K_Restore_CNN_M.glsl",
    "Anime4K_Restore_CNN_VL.glsl",
    "Anime4K_Restore_CNN_Soft_S.glsl",
    "Anime4K_Restore_CNN_Soft_M.glsl",
    "Anime4K_Restore_CNN_Soft_VL.glsl",
    "Anime4K_Upscale_CNN_x2_S.glsl",
    "Anime4K_Upscale_CNN_x2_M.glsl",
    "Anime4K_Upscale_CNN_x2_VL.glsl",
    "Anime4K_Upscale_Denoise_CNN_x2_M.glsl",
    "Anime4K_Upscale_Denoise_CNN_x2_VL.glsl",
    "Anime4K_AutoDownscalePre_x2.glsl",
    "Anime4K_AutoDownscalePre_x4.glsl",
  ];
  static const Map<String, List<String>> _anime4kPresets = {
    // 模式A：Restore -> Upscale -> Upscale，适合 1080p 动画
    "A_HQ": [
      "Anime4K_Clamp_Highlights.glsl",
      "Anime4K_Restore_CNN_VL.glsl",
      "Anime4K_Upscale_CNN_x2_VL.glsl",
      "Anime4K_AutoDownscalePre_x2.glsl",
      "Anime4K_AutoDownscalePre_x4.glsl",
      "Anime4K_Upscale_CNN_x2_M.glsl",
    ],
    // 模式B：Restore_Soft -> Upscale -> Upscale，适合 720p 动画
    "B_HQ": [
      "Anime4K_Clamp_Highlights.glsl",
      "Anime4K_Restore_CNN_Soft_VL.glsl",
      "Anime4K_Upscale_CNN_x2_VL.glsl",
      "Anime4K_AutoDownscalePre_x2.glsl",
      "Anime4K_AutoDownscalePre_x4.glsl",
      "Anime4K_Upscale_CNN_x2_M.glsl",
    ],
    // 模式C：Upscale_Denoise -> Upscale，适合无劣化片源
    "C_HQ": [
      "Anime4K_Clamp_Highlights.glsl",
      "Anime4K_Upscale_Denoise_CNN_x2_VL.glsl",
      "Anime4K_AutoDownscalePre_x2.glsl",
      "Anime4K_AutoDownscalePre_x4.glsl",
      "Anime4K_Upscale_CNN_x2_M.glsl",
    ],
    // 低配 GPU 档位（Fast）
    "A_Fast": [
      "Anime4K_Clamp_Highlights.glsl",
      "Anime4K_Restore_CNN_M.glsl",
      "Anime4K_Upscale_CNN_x2_M.glsl",
      "Anime4K_AutoDownscalePre_x2.glsl",
      "Anime4K_AutoDownscalePre_x4.glsl",
      "Anime4K_Upscale_CNN_x2_S.glsl",
    ],
    "B_Fast": [
      "Anime4K_Clamp_Highlights.glsl",
      "Anime4K_Restore_CNN_Soft_M.glsl",
      "Anime4K_Upscale_CNN_x2_M.glsl",
      "Anime4K_AutoDownscalePre_x2.glsl",
      "Anime4K_AutoDownscalePre_x4.glsl",
      "Anime4K_Upscale_CNN_x2_S.glsl",
    ],
    "C_Fast": [
      "Anime4K_Clamp_Highlights.glsl",
      "Anime4K_Upscale_Denoise_CNN_x2_M.glsl",
      "Anime4K_AutoDownscalePre_x2.glsl",
      "Anime4K_AutoDownscalePre_x4.glsl",
      "Anime4K_Upscale_CNN_x2_S.glsl",
    ],
  };

  // 当前 Anime4K 设置档位：off / Fast / HQ（设置页只保存档位，A/B/C 模式按视频分辨率动态决定）
  String _anime4kQuality = "off";
  // 当前已应用的组合键（如 "A_HQ"），避免重复设置
  String _anime4kAppliedKey = "";
  // 显示在调试信息视频参数区域的当前状态
  String anime4kStatus = "关闭";

  // 按视频高度动态决定 A/B/C 模式：≥1000(1080p)→A，≥640(720p)→B，其余(480p 等)→C
  String _anime4kModeByHeight(int height) {
    if (height >= 1000) {
      return "A";
    }
    if (height >= 640) {
      return "B";
    }
    return "C";
  }

  // 把 assets 里的着色器解压到应用支持目录（幂等，已存在则跳过），返回目录路径（正斜杠）
  Future<String?> _extractAnime4KShaders() async {
    try {
      final targetDir = Directory(
        "${yakushiinRuntimeEnvironment.appSupportDirectory.path}${Platform.pathSeparator}shaders",
      );
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      for (final name in _anime4kShaderFiles) {
        final data = await rootBundle.load("assets/shaders/$name");
        final target = File("${targetDir.path}${Platform.pathSeparator}$name");
        if (!await target.exists()) {
          await target.writeAsBytes(data.buffer.asUint8List(), flush: true);
        }
      }
      return targetDir.path.replaceAll("\\", "/");
    } catch (e) {
      yakushiinLogger.e("提取 Anime4K 着色器失败:$e");
      return null;
    }
  }

  // 根据当前设置档位与视频分辨率，应用/切换/清除 Anime4K 着色器
  // 注意：mpv 的 glsl-shaders 列表分隔符 Windows 为 `;`，Unix 系（Android/Linux/macOS）为 `:`
  Future<void> _updateAnime4kShaders() async {
    // mpv 的 glsl-shaders 是「路径列表」，列表分隔符随平台变化：
    // 由路径分隔符推导——Windows（\）为 `;`，Unix 系（/）为 `:`
    final listSeparator = Platform.pathSeparator == '\\' ? ";" : ":";
    // 每次调用时读取设置档位（兼容旧版 A_HQ/B_HQ 等取值），保证进入页面/设置变更后即生效
    final rawAnime4kMode =
        yakushiinRuntimeEnvironment.dataEngineForGatewaySetting
            .getAt(0)
            ?.anime4kMode ??
        "off";
    _anime4kQuality =
        rawAnime4kMode == "off"
            ? "off"
            : rawAnime4kMode.endsWith("Fast")
            ? "Fast"
            : "HQ";
    try {
      if (_anime4kQuality == "off") {
        if (_anime4kAppliedKey.isNotEmpty) {
          await (yakushiinPlayer.platform as NativePlayer).setProperty(
            "glsl-shaders",
            "",
          );
          _anime4kAppliedKey = "";
          yakushiinLogger.i("Anime4K 已关闭");
        }
        if (mounted) {
          setState(() => anime4kStatus = "关闭");
        }
        return;
      }
      final height = yakushiinPlayer.state.height ?? 0;
      if (height <= 0) {
        // 尚未获取到视频分辨率，等待 height 流再触发
        return;
      }
      final key = "${_anime4kModeByHeight(height)}_$_anime4kQuality";
      if (key == _anime4kAppliedKey) {
        return;
      }
      final chain = _anime4kPresets[key];
      if (chain == null) {
        return;
      }
      final dir = await _extractAnime4KShaders();
      if (dir == null) {
        return;
      }
      final shaders = chain.map((s) => "$dir/$s").join(listSeparator);
      await (yakushiinPlayer.platform as NativePlayer).setProperty(
        "glsl-shaders",
        shaders,
      );
      _anime4kAppliedKey = key;
      final statusText =
          "模式${_anime4kModeByHeight(height)}（${height}p，${_anime4kQuality == "HQ" ? "高质量" : "快速"}）";
      if (mounted) {
        setState(() => anime4kStatus = statusText);
      }
      yakushiinLogger.i("Anime4K 已切换：$statusText（视频高度 $height）");
    } catch (e) {
      yakushiinLogger.e("应用 Anime4K 着色器失败:$e");
    }
  }

  // mpv 磁盘缓存是否已设置（只需设置一次，必须在首次 open 之前）
  bool _mpvCacheFileApplied = false;

  // 设置 mpv 磁盘缓存指向应用缓存目录，避免每个视频报 "Failed to create file cache"
  Future<void> _ensureMpvCacheFile() async {
    if (_mpvCacheFileApplied) {
      return;
    }
    try {
      final mpvCacheFile =
          "${yakushiinRuntimeEnvironment.appCacheDirectory.path}${Platform.pathSeparator}mpv-cache.dump";
      await (yakushiinPlayer.platform as NativePlayer).setProperty(
        "cache-file",
        mpvCacheFile,
      );
      _mpvCacheFileApplied = true;
    } catch (e) {
      yakushiinLogger.w("设置 mpv 磁盘缓存文件失败:$e");
    }
  }

  // 判断是否属于「该平台/系统设置下永远拿不到定位」的情况：
  // 1、PC 端位置服务未开启（Windows 桌面端常见，重试也不会成功）
  // 2、定位权限被系统永久拒绝（不再弹授权框，重试无意义）
  // 权限只是暂时未授予（denied，可弹系统授权框）等可恢复情况不在此列，继续按原逻辑定时重试
  bool _isLocationUnavailable(Object e) {
    final msg = e.toString();
    if (msg.contains("位置权限已经被永久禁止")) {
      return true;
    }
    if (msg.contains("位置服务已被禁用") &&
        yakushiinRuntimeEnvironment.isDesktopPlatform) {
      return true;
    }
    // geolocator_windows 的 PlatformException：Windows 定位服务未运行/无法启动
    if (msg.contains("RequestAccess failed") ||
        msg.contains("Geolocation Service") ||
        msg.contains("无法启动服务")) {
      return true;
    }
    return false;
  }

  // 运行日志按级别染色：DEBUG/TRACE 灰色，WARNING 黄色，ERROR/FATAL/WTF 红色，INFO 白色
  Color yakushiinLogLineColor(String line, BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (line.contains("[DEBUG]") || line.contains("[TRACE]")) {
      return dark ? const Color(0xFF9E9E9E) : const Color(0xFF616161);
    }
    if (line.contains("[WARNING]") || line.contains("[WARN]")) {
      return dark ? const Color(0xFFFFEB3B) : const Color(0xFF8A6D00);
    }
    if (line.contains("[ERROR]") ||
        line.contains("[FATAL]") ||
        line.contains("[WTF]")) {
      return dark ? const Color(0xFFFF5252) : const Color(0xFFC62828);
    }
    // INFO 及其他
    return dark ? Colors.white : Colors.black87;
  }

  late Player yakushiinPlayer = Player(
    configuration: PlayerConfiguration(
      title: 'YakushiinPlayer',
      // mpv 日志级别（error/warn/info/v/debug/trace），接入运行日志展示
      logLevel: MPVLogLevel.info,
      // 解复用缓冲（demuxer-max-bytes / demuxer-max-back-bytes）
      // 默认 32MB，4K60 高码率（约 40Mbps）下仅约 6 秒，提高到 128MB 保证在线播放流畅
      bufferSize: 128 * 1024 * 1024,
      ready: () {
        yakushiinLogger.i('yakushiinPlayer 初始化完成');
      },
    ),
  );
  late VideoController yakushiinPlayerController = VideoController(
    yakushiinPlayer,
    configuration: const VideoControllerConfiguration(
      enableHardwareAcceleration: true,
    ),
  );

  Future<void> playSkipToNext() async {
    if (nowPlayingIndex + 1 == ref.watch(currentPlayList).musicList?.length) {
      // 播放列表尾
      await yakushiinPlayer.jump(0);
    } else {
      await yakushiinPlayer.next();
    }
  }

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    initPedometerPlatformState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (Platform.isIOS) {
        await _loadIOSAudioSessionCategory();
      }
      if (Platform.isAndroid) {
        await _loadAndroidAudioStream();
      }
    });

    // 电视模式配置
    tvMode =
        yakushiinRuntimeEnvironment.dataEngineForGatewaySetting
            .getAt(0)
            ?.tvMode ??
        false;

    FlutterVolumeController.addListener((volume) {
      setState(() {
        currentVolumeSystem = volume;
      });
    });

    // 定位与天气
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 100,
        forceLocationManager: true,
        intervalDuration: const Duration(seconds: 10),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: "应用将持续在后台运行并获取位置",
          notificationTitle: "YakushiinPlayer",
          enableWakeLock: true,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.fitness,
        distanceFilter: 100,
        pauseLocationUpdatesAutomatically: true,
        showBackgroundLocationIndicator: false,
      );
    } else if (kIsWeb) {
      locationSettings = WebSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 100,
        maximumAge: Duration(minutes: 5),
      );
    } else {
      locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 100,
      );
    }

    getCurrentLocationAndWeather();
    getLocationAndWeatherTimer = Timer.periodic(Duration(minutes: 30), (
      timer,
    ) async {
      yakushiinLogger.i("定时器:获取一次定位与天气");
      await getCurrentLocationAndWeather();
    });

    // 接入 mpv (media_kit) 日志到运行日志区域
    yakushiinPlayer.stream.log.listen((PlayerLog log) {
      final text = log.text.trim();
      if (text.isEmpty) {
        return;
      }
      // 单行展示，超长截断，避免刷爆日志缓冲
      final singleLine = text.replaceAll("\n", " ").replaceAll("\r", " ");
      final truncated =
          singleLine.length > 300
              ? "${singleLine.substring(0, 300)}..."
              : singleLine;
      final message = "[mpv:${log.level}][${log.prefix}] $truncated";
      if (log.level == "error") {
        yakushiinLogger.e(message);
      } else if (log.level == "warn") {
        yakushiinLogger.w(message);
      } else {
        yakushiinLogger.d(message);
      }
    });

    // 视频分辨率变化时（切歌/切换清晰度）动态切换 Anime4K 模式
    yakushiinPlayer.stream.height.listen((_) {
      _updateAnime4kShaders();
    });

    // 2. 获取 AudioHandler
    final handler = yakushiinBackgroundPlayerHandler;

    // 3. 注册回调
    handler.onPlay = () async {
      yakushiinLogger.i("AudioService => onPlay!");
      await yakushiinPlayer.play(); // 如果已经暂停，这会恢复播放
      handler.updatePlaybackState(playing: true, newItem: _currentMediaItem());
    };

    handler.onPause = () async {
      yakushiinLogger.i("AudioService => onPause!");
      await yakushiinPlayer.pause(); // 如果正在播放，这会暂停
      handler.updatePlaybackState(
        playing: false,
        newItem: _currentMediaItem(), // 传入当前项，防止空白
      );
    };
    handler.onNext = () => playSkipToNext();
    handler.onPrevious = () => yakushiinPlayer.previous();

    updateNotificationBarTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) {
      if (!mounted) return;
      handler.updatePlaybackState(
        playing: yakushiinPlayer.state.playing,
        position: yakushiinPlayer.state.position,
        bufferedPosition: nowBufferedDuration,
        newItem: MediaItem(
          id:
              ref
                  .read(currentPlayList)
                  .musicList![ref.read(nowPlayingIndexProvider)]
                  .videoUrl ??
              '',
          title:
              ref
                  .read(currentPlayList)
                  .musicList![ref.read(nowPlayingIndexProvider)]
                  .videoName ??
              '未知',
          artist:
              "YakushiinPlayer By Luckykeeper => ${(nowPlayingDurationCurrent.inSeconds / 60).floor().toString().padLeft(2, '0')}:${(nowPlayingDurationCurrent.inSeconds % 60).floor().toString().padLeft(2, '0')}/${(nowPlayingDurationTotal.inSeconds / 60).floor().toString().padLeft(2, '0')}:${(nowPlayingDurationTotal.inSeconds % 60).floor().toString().padLeft(2, '0')}",
          duration: yakushiinPlayer.state.duration,
        ),
      );
    });

    Timer(Duration(milliseconds: 100), () async {
      await FlutterVolumeController.updateShowSystemUI(true);
      // 获取保存的 index
      int lastPlayedIndex = 0;
      for (var i = 0; i < ref.watch(currentPlayList).musicList!.length; i++) {
        if (ref.watch(currentPlayList).musicList![i].nowPlaying) {
          lastPlayedIndex = i;
        }
      }
      Playlist yakushiinPlayList = Playlist([], index: lastPlayedIndex);

      if (ref
              .watch(currentPlayList)
              .musicList!
              .first
              .videoMd5!
              .contains("http://") ||
          ref
              .watch(currentPlayList)
              .musicList!
              .first
              .videoMd5!
              .contains("https://")) {
        // 在线播放
        for (var video in ref.watch(currentPlayList).musicList!) {
          yakushiinPlayList.medias.add(
            Media(
              "${video.videoMd5}",
              httpHeaders: {
                HttpHeaders.userAgentHeader: yakushininPlayerUserAgent,
              },
              extras: {"title": "${video.videoName}"},
            ),
          );
        }
      } else {
        // 本地播放
        for (var video in ref.watch(currentPlayList).musicList!) {
          yakushiinPlayList.medias.add(
            Media(
              "${yakushiinRuntimeEnvironment.musicDir.path}${Platform.pathSeparator}${video.videoMd5}",
              httpHeaders: {
                HttpHeaders.userAgentHeader: yakushininPlayerUserAgent,
              },
            ),
          );
        }
      }

      // 首次打开播放列表前设置 mpv 磁盘缓存，确保首曲即生效
      await _ensureMpvCacheFile();
      yakushiinPlayer.open(yakushiinPlayList);
      yakushiinPlayer.stream.playing.listen((bool playing) {
        if (mounted) {
          setState(() {
            nowPlayingStatus = playing;
          });

          if (yakushiinRuntimeEnvironment.isDesktopPlatform) {
            String status = playing ? "正在播放" : "已暂停";
            windowManager.setTitle(
              "YakushiinPlayer By Luckykeeper - $status : $nowPlayingMusicName",
            );
          }
        }
      });

      yakushiinPlayer.stream.playlist.listen((Playlist playList) async {
        yakushiinLogger.i(
          "当前播放 ${playList.index}-${ref.watch(currentPlayList).musicList![playList.index].videoName}",
        );
        nowPlayingMusicName =
            "${ref.watch(currentPlayList).musicList![playList.index].videoName}";
        if (playList.index + 1 < ref.watch(currentPlayList).musicList!.length) {
          nextPlayingMusicName =
              "${ref.watch(currentPlayList).musicList![playList.index + 1].videoName}";
        } else {
          nextPlayingMusicName =
              "${ref.watch(currentPlayList).musicList![0].videoName}";
        }
        // 加载字幕（如果有）
        // 注意：必须按「当前歌曲」判断在线/本地，不能用 musicList.first——
        // 每首歌的字幕下载状态不同（URL=未下载在线播放，md5=已下载本地播放）
        final currentMusic =
            ref.watch(currentPlayList).musicList![playList.index];
        final subTitleTarget = currentMusic.subTitleMd5 ?? "";
        if (subTitleTarget.isNotEmpty) {
          if (subTitleTarget.startsWith("http://") ||
              subTitleTarget.startsWith("https://")) {
            // 在线字幕（该歌曲字幕未下载，直接使用 URL）
            yakushiinLogger.i("设置字幕(在线):$subTitleTarget");
            await yakushiinPlayer.setSubtitleTrack(
              SubtitleTrack.uri(
                subTitleTarget,
                title: "${currentMusic.subTitleName}",
                language: "${currentMusic.subTitleLang}",
              ),
            );
          } else {
            // 本地字幕（该歌曲字幕已下载，md5 为文件名）
            final localSubPath =
                "${yakushiinRuntimeEnvironment.musicDir.path}${Platform.pathSeparator}$subTitleTarget";
            yakushiinLogger.i("设置字幕(本地):$localSubPath");
            await yakushiinPlayer.setSubtitleTrack(
              SubtitleTrack.uri(
                localSubPath,
                title: "${currentMusic.subTitleName}",
                language: "${currentMusic.subTitleLang}",
              ),
            );
          }
        } else {
          // 没有字幕的清掉所有字幕
          // yakushiinLogger.d("没有字幕，清除掉当前字幕轨");
          await yakushiinPlayer.setSubtitleTrack(SubtitleTrack.no());
        }

        // 更新当前播放位置
        nowPlayingIndex = playList.index;
        ref.read(nowPlayingIndexProvider.notifier).state = playList.index;

        // 应用相对音量：把当前歌曲的 volumeRatio 配置到软件音量
        // volumeRatio 以 100 为基准（100 = 不增不减），兼容旧数据按 100 处理
        final double volumeRatio =
            ref.read(currentPlayList).musicList![playList.index].volumeRatio;
        final double appliedVolume = volumeRatio <= 0 ? 100 : volumeRatio;
        await yakushiinPlayer.setVolume(appliedVolume);
        yakushiinLogger.i(
          "应用相对音量:$appliedVolume ($nowPlayingMusicName)",
        );

        // 更新播放状态到数据库
        for (var i = 0; i < ref.read(currentPlayList).musicList!.length; i++) {
          ref.read(currentPlayList).musicList![i].nowPlaying = false;
        }
        ref.read(currentPlayList).musicList![playList.index].nowPlaying = true;

        // 仅本地（离线）会话回写数据库：
        // 在线会话的内存歌单中 videoMd5/subTitleMd5 存的是 URL（welcome 页设置），
        // 回写会把本地数据库的 md5 全部覆盖成 URL，导致下次「本地离线播放」误判为在线播放
        final firstVideoMd5 =
            ref.read(currentPlayList).musicList!.first.videoMd5 ?? "";
        if (firstVideoMd5.startsWith("http://") ||
            firstVideoMd5.startsWith("https://")) {
          yakushiinLogger.d("在线播放会话，跳过回写数据库（避免 URL 污染本地数据）");
          return;
        }
        // 修复：原 clear+add 非原子且并发不安全，偶现 3->2 丢失
        // 现改为以 playListName 为 key 的原子 put，并加锁防止并发写
        if (_isPersistingPlayList) {
          yakushiinLogger.w("跳过本次回写，上一回写未完成，避免并发丢失");
          if (mounted) setState(() {});
          return;
        }
        _isPersistingPlayList = true;
        try {
          final box = yakushiinRuntimeEnvironment.dataEngineForV2PlayList;
          final currentList = ref.read(currentPlayList);
          final key = currentList.playListName;
          if (key == null || key.isEmpty) {
            yakushiinLogger.w("回写跳过：playListName 为空");
            return;
          }
          // 兼容旧数据：旧版使用 int 自增 key，新版使用 playListName 字符串 key
          // 若存在同名旧 int key 条目，删除旧条目避免重复计数
          final keysToDelete = <dynamic>[];
          for (var k in box.keys) {
            if (k == key) continue;
            final item = box.get(k);
            if (item != null && item.playListName == key && k is int) {
              keysToDelete.add(k);
            }
          }
          final toSave = NoaPlayerV2PlayList(
            id: currentList.id,
            playListName: currentList.playListName,
            musicList: currentList.musicList,
          );
          await box.put(key, toSave);
          for (var k in keysToDelete) {
            await box.delete(k);
            yakushiinLogger.i("清理旧 int key $k 的同名歌单 $key");
          }
          yakushiinLogger.i("回写数据库完成，当前播放列表数量：${box.length}，当前歌单：$key");
        } catch (e, st) {
          yakushiinLogger.e("回写数据库失败：$e\n$st");
        } finally {
          _isPersistingPlayList = false;
        }

        if (mounted) {
          setState(() {});
        }
      });

      yakushiinPlayer.stream.duration.listen((Duration duration) {
        if (mounted) {
          setState(() {
            nowPlayingDurationTotal = duration;
          });
        }
      });

      yakushiinPlayer.stream.audioDevices.listen((List<AudioDevice> devices) {
        if (mounted) {
          setState(() {
            nowPlayingAudioDevicesAvailable = devices;
          });
        }
      });

      yakushiinPlayer.stream.buffer.listen((Duration buffer) {
        if (mounted) {
          setState(() {
            nowBufferedDuration = buffer;
          });
        }
      });

      yakushiinPlayer.stream.audioParams.listen((AudioParams audioParams) {
        if (mounted) {
          setState(() {
            nowPlayingAudioParams = audioParams;
          });
        }
      });

      yakushiinPlayer.stream.videoParams.listen((VideoParams videoParams) {
        if (mounted) {
          setState(() {
            nowPlayingVideoParams = videoParams;
          });
        }
      });

      yakushiinPlayer.stream.buffering.listen((bool bufferingStatus) {
        if (mounted) {
          setState(() {
            nowBufferStatus = bufferingStatus;
          });
        }
      });

      yakushiinPlayer.stream.audioBitrate.listen((double? audioBitrate) {
        if (mounted) {
          setState(() {
            nowPlayingAudioBitrate = audioBitrate;
          });
        }
      });

      yakushiinPlayer.stream.volume.listen((double volume) {
        if (mounted) {
          setState(() {
            currentVolumePlayer = volume;
          });
        }
      });

      yakushiinPlayer.stream.playlistMode.listen((PlaylistMode playListMode) {
        if (mounted) {
          setState(() {
            nowPlayingPlaylistMode = playListMode;
          });
        }
      });

      yakushiinPlayer.stream.position.listen((Duration position) {
        if (mounted) {
          setState(() {
            nowPlayingDurationCurrent = position;
          });
        }
        // 播放结束但是不能自动下一曲卡住时候的处理
        // 条件：①即将播放结束 ②当前播放不是不是列表循环
        if ((nowPlayingDurationTotal - nowPlayingDurationCurrent <
                Durations.short4) &&
            (nowPlayingDurationCurrent > Durations.long4) &&
            (nowPlayingPlaylistMode.name == "loop")) {
          // 起一个计时器，如果2秒之后没有切到下一首，就手动切一下，如果是最后一首，就切到第一首
          checkPlayingMusicEndTimer ??= Timer(
            Duration(milliseconds: 1),
            () async {
              yakushiinLogger.d(
                "定时器启动: $nowPlayingMusicName 播放结束=>($nowPlayingDurationCurrent==$nowPlayingDurationTotal)",
              );
              if (!mounted) {
                checkPlayingMusicEndTimer?.cancel();
                return;
              }
              Timer(Duration(seconds: 2), () async {
                if (!mounted) {
                  checkPlayingMusicEndTimer?.cancel();
                  return;
                }
                if ((nowPlayingDurationTotal - nowPlayingDurationCurrent <
                        Durations.short4) &&
                    (nowPlayingDurationCurrent > Durations.long4)) {
                  if (nowPlayingIndex + 1 ==
                      ref.watch(currentPlayList).musicList?.length) {
                    // 播放列表尾
                    yakushiinLogger.d("播放将结束回调=>播放列表尾置头");
                    await yakushiinPlayer.jump(0);
                  } else {
                    yakushiinLogger.d("播放将结束回调=>下一曲");
                    await yakushiinPlayer.next();
                  }
                }
                checkPlayingMusicEndTimer?.cancel();
                checkPlayingMusicEndTimer = null;
              });
            },
          );
        }
      });

      yakushiinPlayer.stream.audioDevice.listen((AudioDevice device) {
        if (mounted) {
          setState(() {
            nowPlayingAudioDevice = device;
          });
        }
      });

      yakushiinPlayer.stream.error.listen((String error) {
        yakushiinLogger.e("播放器发生错误：$error");
        checkPlayingMusicEndTimer?.cancel();
        checkPlayingMusicEndTimer = null;
      });
    });
  }

  Future<void> _loadIOSAudioSessionCategory() async {
    final category = await FlutterVolumeController.getIOSAudioSessionCategory();
    if (category != null) {
      setState(() {
        _audioSessionCategory = category;
      });
    }
  }

  Future<void> _loadAndroidAudioStream() async {
    final audioStream = await FlutterVolumeController.getAndroidAudioStream();
    if (audioStream != null) {
      setState(() {
        _audioStream = _audioStream;
      });
    }
  }

  // Future<AudioStream?> _pickAndroidAudioStream(BuildContext context) async {
  //   return await showModalBottomSheet(
  //     context: context,
  //     builder: (context) {
  //       return ListView.builder(
  //         shrinkWrap: true,
  //         itemCount: AudioStream.values.length,
  //         itemBuilder: (_, index) {
  //           return ListTile(
  //             title: Text(AudioStream.values[index].name),
  //             onTap: () {
  //               Navigator.of(context).maybePop(AudioStream.values[index]);
  //             },
  //           );
  //         },
  //       );
  //     },
  //   );
  // }

  // Future<AudioSessionCategory?> _pickIOSAudioSessionCategory(
  //   BuildContext context,
  // ) async {
  //   return await showModalBottomSheet(
  //     context: context,
  //     builder: (context) {
  //       return ListView.builder(
  //         shrinkWrap: true,
  //         itemCount: AudioSessionCategory.values.length,
  //         itemBuilder: (_, index) {
  //           return ListTile(
  //             title: Text(AudioSessionCategory.values[index].name),
  //             onTap: () {
  //               Navigator.of(
  //                 context,
  //               ).maybePop(AudioSessionCategory.values[index]);
  //             },
  //           );
  //         },
  //       );
  //     },
  //   );
  // }

  @override
  void dispose() {
    WakelockPlus.disable();
    logAreaScrollController.dispose();
    try {
      yakushiinPlayer.dispose();
    } catch (e) {
      yakushiinLogger.e("dispose yakushiinPlayer Failed:$e");
    }
    FlutterVolumeController.removeListener();
    getLocationAndWeatherTimer?.cancel();
    updateNotificationBarTimer?.cancel();
    checkPlayListEndTimer?.cancel();
    checkPlayingMusicEndTimer?.cancel();
    if (yakushiinRuntimeEnvironment.isDesktopPlatform) {
      windowManager.setTitle("YakuShiinPlayer By Luckykeeper");
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          // 阻止正常的返回逻辑
          return;
        } else {
          if (denyPopFlag) {
            BotToast.showSimpleNotification(
              duration: const Duration(seconds: 2),
              hideCloseButton: false,
              backgroundColor: Colors.pink[200],
              title: "⛔当前处于防误触模式，屏蔽返回",
              titleStyle: styleFontSimkai,
            );
          } else {
            if (context.mounted) {
              Navigator.pop(context);
            }
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: GestureDetector(
            child: Row(
              children: [
                Text("YakushiinPlayer - 播放页", style: styleFontSimkai),
                const Expanded(child: Text("")),
              ],
            ),
            onPanStart: (details) {
              if (yakushiinRuntimeEnvironment.isDesktopPlatform) {
                windowManager.startDragging();
              }
            },
            onDoubleTap: () async {
              if (yakushiinRuntimeEnvironment.isDesktopPlatform) {
                bool isMaximized = await windowManager.isMaximized();
                if (!isMaximized) {
                  windowManager.maximize();
                } else {
                  windowManager.unmaximize();
                }
              }
            },
          ),
          backgroundColor: Colors.cyan,
        ),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Text(
                    "艾玛酱音乐播放器ヾ(≧▽≦*)o",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      fontFamily: fontSimkaiFamily,
                    ),
                  ),
                ],
              ),
              const Divider(),
              ExcludeSemantics(
                child: Column(
                  children: [
                    Text(
                      "当前播放列表:${ref.watch(currentPlayList).playListName} (${nowPlayingIndex + 1}/${ref.watch(currentPlayList).musicList?.length})",
                      style: styleFontSimkaiBoldLarge,
                    ),
                  ],
                ),
              ),
              const Divider(),
              ExcludeSemantics(
                child: Column(
                  children: [
                    SizedBox(
                      height: 50,
                      child: Text(
                        "当前音乐：$nowPlayingMusicName",
                        style: styleFontSimkaiBoldLarge,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              ExcludeSemantics(
                child: Column(
                  children: [
                    SizedBox(
                      height: 30,
                      child: Text(
                        "下一曲：$nextPlayingMusicName",
                        style: styleFontSimkaiBoldLarge,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              ExcludeSemantics(
                child: Column(
                  children: [
                    Text(
                      "播放进度=>当前: $nowPlayingDurationCurrent / 总: $nowPlayingDurationTotal / ${(nowPlayingDurationTotal - (nowPlayingDurationCurrent)).inSeconds} 秒",
                      style: styleFontSimkaiBoldLarge,
                    ),
                  ],
                ),
              ),
              const Divider(),
              ExcludeSemantics(
                child: Column(
                  children: [
                    Text(
                      "播放模式：${nowPlayingPlaylistMode.name == "loop"
                          ? "列表循环"
                          : nowPlayingPlaylistMode.name == "single"
                          ? "单曲循环"
                          : nowPlayingPlaylistMode.name} | 设备音量： ${(currentVolumeSystem * 100).round()} | 软件音量: $currentVolumePlayer",
                      style: styleFontSimkaiBoldLarge,
                    ),
                  ],
                ),
              ),
              const Divider(),
              ExcludeSemantics(
                child: Row(
                  mainAxisAlignment:
                      yakushiinRuntimeEnvironment.isDesktopPlatform
                          ? MainAxisAlignment.spaceEvenly
                          : MainAxisAlignment.spaceBetween,
                  children: [
                    if (!yakushiinRuntimeEnvironment.isDesktopPlatform)
                      if (pedometerStep != 0)
                        Row(
                          children: [
                            Icon(
                              pedometerStatus == 'walking'
                                  ? Icons.directions_walk
                                  : pedometerStatus == 'stopped'
                                  ? Icons.accessibility_new
                                  : Icons.error,
                              size: 40,
                            ),
                            VerticalDivider(),
                            Column(
                              children: [
                                Text(
                                  "当前运动状态:",
                                  style: styleFontSimkaiCyanBoldLarge,
                                ),
                                Text(
                                  pedometerStatus,
                                  style: styleFontSimkaiBoldLarge,
                                ),
                              ],
                            ),
                            VerticalDivider(),
                            Column(
                              children: [
                                Text(
                                  "开机以来步数:",
                                  style: styleFontSimkaiCyanBoldLarge,
                                ),
                                Text(
                                  "$pedometerStep",
                                  style: styleFontSimkaiBoldLarge,
                                ),
                              ],
                            ),
                          ],
                        ),
                    if (!yakushiinRuntimeEnvironment.isDesktopPlatform)
                      VerticalDivider(),
                    // 移动端组件
                    if (!yakushiinRuntimeEnvironment.isDesktopPlatform)
                      if (currentWeather != null)
                        Row(
                          children: [
                            Column(
                              children: [
                                Text(
                                  "${currentWeather?.areaName}",
                                  style: styleFontSimkaiCyanBoldLarge,
                                ),
                                Text(
                                  "${currentWeather?.weatherDescription}",
                                  style: styleFontSimkaiBoldLarge,
                                ),
                              ],
                            ),
                            VerticalDivider(),
                            Column(
                              children: [
                                Text(
                                  "${currentWeather?.temperature?.celsius?.toInt()}℃",
                                  style: styleFontSimkaiBoldLarge,
                                ),
                                Text(
                                  "${currentWeather?.humidity?.toInt()}%",
                                  style: styleFontSimkaiBoldLarge,
                                ),
                                Text(
                                  "${currentWeather?.windSpeed?.toInt()} m/s",
                                  style: styleFontSimkaiBoldLarge,
                                ),
                              ],
                            ),
                            VerticalDivider(),
                            Column(
                              children: [
                                SizedBox(
                                  width: 50,
                                  height: 50,
                                  child: WeatherIconWidget(
                                    iconCode: "${currentWeather?.weatherIcon}",
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                    // PC 端组件
                    if (yakushiinRuntimeEnvironment.isDesktopPlatform)
                      if (currentWeather != null)
                        Row(
                          children: [
                            Text(
                              "${currentWeather?.areaName}",
                              style: styleFontSimkaiCyanBoldExtraLarge,
                            ),
                            VerticalDivider(),

                            Text(
                              "${currentWeather?.weatherDescription}",
                              style: styleFontSimkaiBoldExtraLarge,
                            ),
                            VerticalDivider(),
                            Row(
                              children: [
                                Text(
                                  "${currentWeather?.temperature?.celsius?.toInt()}℃",
                                  style: styleFontSimkaiBoldExtraLarge,
                                ),
                                VerticalDivider(),
                                Text(
                                  "${currentWeather?.humidity?.toInt()}%",
                                  style: styleFontSimkaiBoldExtraLarge,
                                ),
                                VerticalDivider(),
                                Text(
                                  "${currentWeather?.windSpeed?.toInt()} m/s",
                                  style: styleFontSimkaiBoldExtraLarge,
                                ),
                              ],
                            ),
                            VerticalDivider(),
                            Column(
                              children: [
                                SizedBox(
                                  width: 50,
                                  height: 50,
                                  child: WeatherIconWidget(
                                    iconCode: "${currentWeather?.weatherIcon}",
                                  ),
                                ),
                              ],
                            ),
                            VerticalDivider(),
                            Clock(
                              clockTextStyle: styleFontSimkaiCyanBoldExtraLarge,
                            ),
                          ],
                        ),
                  ],
                ),
              ),
              // 天气与计步均无内容时（如 PC 端拿不到定位），隐藏这一行与多余的分隔线
              if (!(yakushiinRuntimeEnvironment.isDesktopPlatform
                      ? currentWeather == null
                      : (pedometerStep == 0 && currentWeather == null)))
                const Divider(),
              yakushiinRuntimeEnvironment.isDesktopPlatform
                  ? MaterialDesktopVideoControlsTheme(
                    normal: MaterialDesktopVideoControlsThemeData(
                      keyboardShortcuts: {
                        // 1. 覆盖左方向键：修复进度溢出问题
                        LogicalKeySet(LogicalKeyboardKey.arrowLeft): () {
                          final pos = yakushiinPlayer.state.position; // 使用实时位置
                          final newPos = pos - const Duration(seconds: 5);
                          yakushiinPlayer.seek(
                            newPos < Duration.zero ? Duration.zero : newPos,
                          );
                        },
                        // 2. 覆盖右方向键：防止快进溢出
                        LogicalKeySet(LogicalKeyboardKey.arrowRight): () {
                          final pos = yakushiinPlayer.state.position;
                          final dur = yakushiinPlayer.state.duration;
                          final newPos = pos + const Duration(seconds: 5);
                          yakushiinPlayer.seek(
                            newPos > (dur - const Duration(seconds: 2))
                                ? dur
                                : newPos,
                          );
                        },

                        // 3. 根据 tvMode 覆盖上下方向键
                        if (tvMode) ...{
                          LogicalKeySet(LogicalKeyboardKey.arrowUp): () {
                            yakushiinPlayer.previous();
                          },
                          LogicalKeySet(LogicalKeyboardKey.arrowDown): () {
                            yakushiinPlayer.next();
                          },
                        } else ...{
                          // 非电视模式：恢复默认的音量调节
                          LogicalKeySet(LogicalKeyboardKey.arrowUp): () {
                            final vol = yakushiinPlayer.state.volume + 5;
                            yakushiinPlayer.setVolume(vol > 100 ? 100 : vol);
                          },
                          LogicalKeySet(LogicalKeyboardKey.arrowDown): () {
                            final vol = yakushiinPlayer.state.volume - 5;
                            yakushiinPlayer.setVolume(vol < 0 ? 0 : vol);
                          },
                        },

                        // 空格：播放/暂停
                        LogicalKeySet(LogicalKeyboardKey.space): () {
                          yakushiinPlayer.playOrPause();
                        },
                        // F：切换全屏
                        LogicalKeySet(LogicalKeyboardKey.keyF): () {
                          if (isFullscreen(context)) {
                            exitFullscreen(context);
                          } else {
                            enterFullscreen(context);
                          }
                        },
                        // Esc：退出全屏
                        LogicalKeySet(LogicalKeyboardKey.escape): () {
                          exitFullscreen(context);
                        },
                        // J：后退10秒
                        LogicalKeySet(LogicalKeyboardKey.keyJ): () {
                          final pos = yakushiinPlayer.state.position;
                          final newPos = pos - const Duration(seconds: 10);
                          yakushiinPlayer.seek(
                            newPos < Duration.zero ? Duration.zero : newPos,
                          );
                        },
                        // L：前进10秒
                        LogicalKeySet(LogicalKeyboardKey.keyL): () {
                          final pos = yakushiinPlayer.state.position;
                          final dur = yakushiinPlayer.state.duration;
                          final newPos = pos + const Duration(seconds: 10);
                          yakushiinPlayer.seek(newPos > dur ? dur : newPos);
                        },
                        // 数字键 0-9 快速定位
                        LogicalKeySet(LogicalKeyboardKey.digit0):
                            () => yakushiinPlayer.seek(Duration.zero),
                        LogicalKeySet(LogicalKeyboardKey.digit1):
                            () => yakushiinPlayer.seek(
                              yakushiinPlayer.state.duration * 0.1,
                            ),
                        LogicalKeySet(LogicalKeyboardKey.digit2):
                            () => yakushiinPlayer.seek(
                              yakushiinPlayer.state.duration * 0.2,
                            ),
                        LogicalKeySet(LogicalKeyboardKey.digit3):
                            () => yakushiinPlayer.seek(
                              yakushiinPlayer.state.duration * 0.3,
                            ),
                        LogicalKeySet(LogicalKeyboardKey.digit4):
                            () => yakushiinPlayer.seek(
                              yakushiinPlayer.state.duration * 0.4,
                            ),
                        LogicalKeySet(LogicalKeyboardKey.digit5):
                            () => yakushiinPlayer.seek(
                              yakushiinPlayer.state.duration * 0.5,
                            ),
                        LogicalKeySet(LogicalKeyboardKey.digit6):
                            () => yakushiinPlayer.seek(
                              yakushiinPlayer.state.duration * 0.6,
                            ),
                        LogicalKeySet(LogicalKeyboardKey.digit7):
                            () => yakushiinPlayer.seek(
                              yakushiinPlayer.state.duration * 0.7,
                            ),
                        LogicalKeySet(LogicalKeyboardKey.digit8):
                            () => yakushiinPlayer.seek(
                              yakushiinPlayer.state.duration * 0.8,
                            ),
                        LogicalKeySet(LogicalKeyboardKey.digit9):
                            () => yakushiinPlayer.seek(
                              yakushiinPlayer.state.duration * 0.9,
                            ),
                      },
                      hideMouseOnControlsRemoval: true,
                      topButtonBarMargin: EdgeInsets.only(left: 5),
                      topButtonBar: [
                        Expanded(
                          child: Consumer(
                            // 👈 关键：让此区域独立监听 Riverpod
                            builder: (context, ref, _) {
                              final playlist = ref.watch(currentPlayList);
                              final index = ref.watch(nowPlayingIndexProvider);
                              final videoName =
                                  playlist.musicList![index].videoName;
                              return Text(
                                "$videoName",
                                style: styleFontSimkaiCyan,
                                overflow: TextOverflow.clip,
                                maxLines: 5,
                              );
                            },
                          ),
                        ),
                      ],
                      buttonBarButtonSize: 24.0,
                      buttonBarButtonColor: Colors.white,
                      seekBarPositionColor: const Color.fromARGB(
                        255,
                        77,
                        208,
                        225,
                      ),
                      seekBarThumbColor: Color.fromARGB(255, 77, 208, 225),
                    ),
                    fullscreen: MaterialDesktopVideoControlsThemeData(
                      keyboardShortcuts: {
                        // 1. 覆盖左方向键：修复进度溢出问题
                        LogicalKeySet(LogicalKeyboardKey.arrowLeft): () {
                          final pos = yakushiinPlayer.state.position; // 使用实时位置
                          final newPos = pos - const Duration(seconds: 5);
                          yakushiinPlayer.seek(
                            newPos < Duration.zero ? Duration.zero : newPos,
                          );
                        },
                        // 2. 覆盖右方向键：防止快进溢出
                        LogicalKeySet(LogicalKeyboardKey.arrowRight): () {
                          final pos = yakushiinPlayer.state.position;
                          final dur = yakushiinPlayer.state.duration;
                          final newPos = pos + const Duration(seconds: 5);
                          yakushiinPlayer.seek(
                            newPos > (dur - const Duration(seconds: 2))
                                ? dur
                                : newPos,
                          );
                        },

                        // 3. 根据 tvMode 覆盖上下方向键
                        if (tvMode) ...{
                          LogicalKeySet(LogicalKeyboardKey.arrowUp): () {
                            yakushiinPlayer.previous();
                          },
                          LogicalKeySet(LogicalKeyboardKey.arrowDown): () {
                            yakushiinPlayer.next();
                          },
                        } else ...{
                          // 非电视模式：恢复默认的音量调节
                          LogicalKeySet(LogicalKeyboardKey.arrowUp): () {
                            final vol = yakushiinPlayer.state.volume + 5;
                            yakushiinPlayer.setVolume(vol > 100 ? 100 : vol);
                          },
                          LogicalKeySet(LogicalKeyboardKey.arrowDown): () {
                            final vol = yakushiinPlayer.state.volume - 5;
                            yakushiinPlayer.setVolume(vol < 0 ? 0 : vol);
                          },
                        },

                        // 空格：播放/暂停
                        LogicalKeySet(LogicalKeyboardKey.space): () {
                          yakushiinPlayer.playOrPause();
                        },
                        // F：切换全屏
                        LogicalKeySet(LogicalKeyboardKey.keyF): () {
                          if (isFullscreen(context)) {
                            exitFullscreen(context);
                          } else {
                            enterFullscreen(context);
                          }
                        },
                        // Esc：退出全屏
                        LogicalKeySet(LogicalKeyboardKey.escape): () {
                          exitFullscreen(context);
                        },
                        // J：后退10秒
                        LogicalKeySet(LogicalKeyboardKey.keyJ): () {
                          final pos = yakushiinPlayer.state.position;
                          final newPos = pos - const Duration(seconds: 10);
                          yakushiinPlayer.seek(
                            newPos < Duration.zero ? Duration.zero : newPos,
                          );
                        },
                        // L：前进10秒
                        LogicalKeySet(LogicalKeyboardKey.keyL): () {
                          final pos = yakushiinPlayer.state.position;
                          final dur = yakushiinPlayer.state.duration;
                          final newPos = pos + const Duration(seconds: 10);
                          yakushiinPlayer.seek(newPos > dur ? dur : newPos);
                        },
                        // 数字键 0-9 快速定位
                        LogicalKeySet(LogicalKeyboardKey.digit0):
                            () => yakushiinPlayer.seek(Duration.zero),
                        LogicalKeySet(LogicalKeyboardKey.digit1):
                            () => yakushiinPlayer.seek(
                              yakushiinPlayer.state.duration * 0.1,
                            ),
                        LogicalKeySet(LogicalKeyboardKey.digit2):
                            () => yakushiinPlayer.seek(
                              yakushiinPlayer.state.duration * 0.2,
                            ),
                        LogicalKeySet(LogicalKeyboardKey.digit3):
                            () => yakushiinPlayer.seek(
                              yakushiinPlayer.state.duration * 0.3,
                            ),
                        LogicalKeySet(LogicalKeyboardKey.digit4):
                            () => yakushiinPlayer.seek(
                              yakushiinPlayer.state.duration * 0.4,
                            ),
                        LogicalKeySet(LogicalKeyboardKey.digit5):
                            () => yakushiinPlayer.seek(
                              yakushiinPlayer.state.duration * 0.5,
                            ),
                        LogicalKeySet(LogicalKeyboardKey.digit6):
                            () => yakushiinPlayer.seek(
                              yakushiinPlayer.state.duration * 0.6,
                            ),
                        LogicalKeySet(LogicalKeyboardKey.digit7):
                            () => yakushiinPlayer.seek(
                              yakushiinPlayer.state.duration * 0.7,
                            ),
                        LogicalKeySet(LogicalKeyboardKey.digit8):
                            () => yakushiinPlayer.seek(
                              yakushiinPlayer.state.duration * 0.8,
                            ),
                        LogicalKeySet(LogicalKeyboardKey.digit9):
                            () => yakushiinPlayer.seek(
                              yakushiinPlayer.state.duration * 0.9,
                            ),
                      },
                      hideMouseOnControlsRemoval: true,
                      displaySeekBar: true,
                      automaticallyImplySkipNextButton: true,
                      automaticallyImplySkipPreviousButton: true,
                      seekBarPositionColor: Color.fromARGB(255, 77, 208, 225),
                      seekBarThumbColor: Color.fromARGB(255, 77, 208, 225),
                      seekBarMargin: EdgeInsets.only(bottom: 10),
                      bottomButtonBarMargin: EdgeInsets.only(
                        left: 16.0,
                        right: 8.0,
                        bottom: 10,
                      ),
                      topButtonBarMargin: EdgeInsets.only(left: 5),
                      topButtonBar: [
                        Expanded(
                          child: Consumer(
                            // 👈 关键：让此区域独立监听 Riverpod
                            builder: (context, ref, _) {
                              final playlist = ref.watch(currentPlayList);
                              final index = ref.watch(nowPlayingIndexProvider);
                              final videoName =
                                  playlist.musicList![index].videoName;
                              return Text(
                                "$videoName",
                                style: styleFontSimkaiCyan,
                                overflow: TextOverflow.clip,
                                maxLines: 5,
                              );
                            },
                          ),
                        ),
                        Clock(
                          clockTextStyle: styleFontSimkaiCyanBoldExtraLarge,
                        ),
                      ],
                      bottomButtonBar: [
                        MaterialDesktopSkipPreviousButton(),
                        MaterialDesktopPlayOrPauseButton(),
                        MaterialDesktopSkipNextButton(),
                        MaterialDesktopVolumeButton(),
                        MaterialDesktopPositionIndicator(
                          style: styleFontSimkai,
                        ),
                        Spacer(),
                        MaterialDesktopFullscreenButton(),
                      ],
                    ),
                    child: Builder(
                      builder: (context) {
                        return ExcludeSemantics(
                          child: SafeArea(
                            child: SizedBox(
                              width: MediaQuery.of(context).size.width,
                              height:
                                  MediaQuery.of(context).size.width *
                                  9.0 /
                                  16.0,
                              child: Video(
                                controller: yakushiinPlayerController,
                                subtitleViewConfiguration:
                                    const SubtitleViewConfiguration(
                                      style: TextStyle(
                                        height: 1.4,
                                        fontSize: 60.0,
                                        letterSpacing: 0.0,
                                        wordSpacing: 0.0,
                                        color: Color(0xffffffff),
                                        fontWeight: FontWeight.normal,
                                        fontFamily: fontSimkaiFamily,
                                        backgroundColor: Color(0xaa000000),
                                        overflow: TextOverflow.clip,
                                      ),
                                      textAlign: TextAlign.center,
                                      padding: EdgeInsets.fromLTRB(
                                        16.0,
                                        24.0,
                                        16.0,
                                        0.0,
                                      ),
                                    ),
                                pauseUponEnteringBackgroundMode: false,
                                resumeUponEnteringForegroundMode: false,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  )
                  : MaterialVideoControlsTheme(
                    normal: MaterialVideoControlsThemeData(
                      brightnessGesture: true,
                      topButtonBarMargin: EdgeInsets.only(left: 5),
                      topButtonBar: [
                        Expanded(
                          child: Consumer(
                            // 👈 关键：让此区域独立监听 Riverpod
                            builder: (context, ref, _) {
                              final playlist = ref.watch(currentPlayList);
                              final index = ref.watch(nowPlayingIndexProvider);
                              final videoName =
                                  playlist.musicList![index].videoName;
                              return Text(
                                "$videoName",
                                style: styleFontSimkaiCyan,
                                overflow: TextOverflow.clip,
                                maxLines: 5,
                              );
                            },
                          ),
                        ),
                      ],
                      buttonBarButtonSize: 24.0,
                      buttonBarButtonColor: Colors.white,
                      seekBarPositionColor: const Color.fromARGB(
                        255,
                        77,
                        208,
                        225,
                      ),
                      seekBarThumbColor: Color.fromARGB(255, 77, 208, 225),
                    ),
                    fullscreen: MaterialVideoControlsThemeData(
                      brightnessGesture: true,
                      displaySeekBar: true,
                      automaticallyImplySkipNextButton: true,
                      automaticallyImplySkipPreviousButton: true,
                      seekBarPositionColor: Color.fromARGB(255, 77, 208, 225),
                      seekBarThumbColor: Color.fromARGB(255, 77, 208, 225),
                      seekBarMargin: EdgeInsets.only(bottom: 10),
                      bottomButtonBarMargin: EdgeInsets.only(
                        left: 16.0,
                        right: 8.0,
                        bottom: 10,
                      ),
                      topButtonBarMargin: EdgeInsets.only(left: 5),
                      topButtonBar: [
                        Expanded(
                          child: Consumer(
                            // 👈 关键：让此区域独立监听 Riverpod
                            builder: (context, ref, _) {
                              final playlist = ref.watch(currentPlayList);
                              final index = ref.watch(nowPlayingIndexProvider);
                              final videoName =
                                  playlist.musicList![index].videoName;
                              return Text(
                                "$videoName",
                                style: styleFontSimkaiCyan,
                                overflow: TextOverflow.clip,
                                maxLines: 5,
                              );
                            },
                          ),
                        ),
                      ],
                      bottomButtonBar: [
                        MaterialPositionIndicator(style: styleFontSimkai),
                        Spacer(),
                        MaterialFullscreenButton(),
                      ],
                    ),
                    child: Builder(
                      builder: (context) {
                        return ExcludeSemantics(
                          child: SafeArea(
                            child: SizedBox(
                              width: MediaQuery.of(context).size.width,
                              height:
                                  MediaQuery.of(context).size.width *
                                  9.0 /
                                  16.0,
                              child: Video(
                                controller: yakushiinPlayerController,
                                subtitleViewConfiguration:
                                    const SubtitleViewConfiguration(
                                      style: TextStyle(
                                        height: 1.4,
                                        fontSize: 60.0,
                                        letterSpacing: 0.0,
                                        wordSpacing: 0.0,
                                        color: Color(0xffffffff),
                                        fontWeight: FontWeight.normal,
                                        fontFamily: fontSimkaiFamily,
                                        backgroundColor: Color(0xaa000000),
                                        overflow: TextOverflow.clip,
                                      ),
                                      textAlign: TextAlign.center,
                                      padding: EdgeInsets.fromLTRB(
                                        16.0,
                                        24.0,
                                        16.0,
                                        0.0,
                                      ),
                                    ),
                                pauseUponEnteringBackgroundMode: false,
                                resumeUponEnteringForegroundMode: false,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      await yakushiinPlayer.previous();
                    },
                    label: Text("上一曲", style: styleFontSimkai),
                    icon: Icon(Icons.skip_previous_rounded),
                  ),
                  nowPlayingStatus
                      ? ElevatedButton.icon(
                        onPressed: () async {
                          await yakushiinPlayer.playOrPause();
                        },
                        label: Text("暂停", style: styleFontSimkai),
                        icon: Icon(Icons.pause_rounded),
                      )
                      : ElevatedButton.icon(
                        onPressed: () async {
                          await yakushiinPlayer.playOrPause();
                        },
                        label: Text("播放", style: styleFontSimkai),
                        icon: Icon(Icons.play_arrow_rounded),
                      ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      // if (nowPlayingIndex + 1 ==
                      //     ref.watch(currentPlayList).musicList?.length) {
                      //   // 播放列表尾
                      //   await yakushiinPlayer.jump(0);
                      // } else {
                      //   await yakushiinPlayer.next();
                      // }
                      await playSkipToNext();
                    },
                    label: Text("下一曲", style: styleFontSimkai),
                    icon: Icon(Icons.skip_next),
                  ),
                ],
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      await FlutterVolumeController.lowerVolume(
                        null,
                        stream: AudioStream.music,
                      );
                    },
                    label: Text("音量（硬） -", style: styleFontSimkai),
                    icon: Icon(Icons.volume_down_rounded),
                  ),
                  ElevatedButton.icon(
                    onPressed:
                        denyPopFlag
                            ? null
                            : () async {
                              await FlutterVolumeController.toggleMute(
                                stream: AudioStream.music,
                              );
                            },
                    label: Text("静音（硬）", style: styleFontSimkai),
                    icon: Icon(Icons.volume_mute_rounded),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await FlutterVolumeController.raiseVolume(
                        null,
                        stream: AudioStream.music,
                      );
                    },
                    label: Text("音量（硬） +", style: styleFontSimkai),
                    icon: Icon(Icons.volume_up_rounded),
                  ),
                ],
              ),
              const Divider(),
              // 软件音量现在由歌曲的 volumeRatio（相对音量）控制，不再提供手动调整按钮
              // 从头播放按钮已移动到下方「当前歌单 / 防误触」一行中
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      await yakushiinPlayer.setPlaylistMode(PlaylistMode.loop);
                      BotToast.showSimpleNotification(
                        duration: const Duration(seconds: 2),
                        hideCloseButton: false,
                        backgroundColor: Colors.blue,
                        title: "♻播放模式已调整到列表循环！",
                        titleStyle: styleFontSimkai,
                      );
                    },
                    label: Text("循环播放", style: styleFontSimkai),
                    icon: Icon(Icons.repeat_rounded),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await yakushiinPlayer.setPlaylistMode(
                        PlaylistMode.single,
                      );
                      BotToast.showSimpleNotification(
                        duration: const Duration(seconds: 2),
                        hideCloseButton: false,
                        backgroundColor: Colors.yellow,
                        title: "❤播放模式已调整到单曲循环！",
                        titleStyle: styleFontSimkai,
                      );
                    },
                    label: Text("单曲循环", style: styleFontSimkai),
                    icon: Icon(Icons.looks_one_rounded),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        await Clipboard.setData(
                          ClipboardData(
                            text:
                                "YakushiinPlayer Music Share By Luckykeeper:${Platform.lineTerminator}${ref.watch(currentPlayList).musicList![nowPlayingIndex].videoName}${Platform.lineTerminator}${ref.watch(currentPlayList).musicList![nowPlayingIndex].videoShareUrl}",
                          ),
                        );
                        BotToast.showSimpleNotification(
                          duration: const Duration(seconds: 1),
                          hideCloseButton: false,
                          backgroundColor: Colors.green[300],
                          title: "✅复制成功",
                          titleStyle: styleFontSimkai,
                        );
                      } catch (e) {
                        BotToast.showSimpleNotification(
                          duration: const Duration(seconds: 1),
                          hideCloseButton: false,
                          backgroundColor: Colors.pink[300],
                          title: "⛔复制失败:$e",
                          titleStyle: styleFontSimkai,
                        );
                      }
                    },
                    onLongPress: () async {
                      try {
                        await Clipboard.setData(
                          ClipboardData(
                            text:
                                "YakushiinPlayer Music Share By Luckykeeper:${Platform.lineTerminator}------${Platform.lineTerminator}MusicInfo⬇${Platform.lineTerminator}Name: ${ref.watch(currentPlayList).musicList![nowPlayingIndex].videoName}${Platform.lineTerminator}Url: ${ref.watch(currentPlayList).musicList![nowPlayingIndex].videoShareUrl}${Platform.lineTerminator}------${Platform.lineTerminator}SubTitleInfo(.srt)⬇${Platform.lineTerminator}SubTitleLanguage: ${ref.watch(currentPlayList).musicList![nowPlayingIndex].subTitleLang} / ${ref.watch(currentPlayList).musicList![nowPlayingIndex].subTitleName}${Platform.lineTerminator}SubTitleUrl: ${ref.watch(currentPlayList).musicList![nowPlayingIndex].subTitleUrl}",
                          ),
                        );
                        BotToast.showSimpleNotification(
                          duration: const Duration(seconds: 1),
                          hideCloseButton: false,
                          backgroundColor: Colors.green[300],
                          title: "✅带字幕链接复制成功",
                          titleStyle: styleFontSimkai,
                        );
                      } catch (e) {
                        BotToast.showSimpleNotification(
                          duration: const Duration(seconds: 1),
                          hideCloseButton: false,
                          backgroundColor: Colors.pink[200],
                          title: "⛔带字幕链接复制失败:$e",
                          titleStyle: styleFontSimkai,
                        );
                      }
                    },
                    label: Text("复制链接", style: styleFontSimkai),
                    icon: Icon(Icons.copy_rounded),
                  ),
                ],
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      final playlist = ref.read(currentPlayList);
                      final currentIndex = nowPlayingIndex;
                      const double buttonHeight = 32.0; // 按钮自身高度
                      const double gapHeight = 10.0; // 项间距
                      const double itemExtent =
                          buttonHeight + gapHeight; // 总项高 42.0

                      final scrollController = ScrollController();

                      showDialog(
                        context: context,
                        builder: (ctx) {
                          return AlertDialog(
                            title: Text(
                              "当前歌单：${playlist.playListName} (${currentIndex + 1}/${playlist.musicList!.length})",
                            ),
                            content: SizedBox(
                              width: double.maxFinite,
                              child: ListView.builder(
                                controller: scrollController,
                                itemCount: playlist.musicList!.length,
                                itemExtent: itemExtent, // 每个项占用固定高度
                                itemBuilder: (context, index) {
                                  final isNowPlaying = index == currentIndex;
                                  return Column(
                                    children: [
                                      // 按钮固定在 32 高度内
                                      SizedBox(
                                        height: buttonHeight,
                                        child: ElevatedButton(
                                          style: ButtonStyle(
                                            backgroundColor:
                                                isNowPlaying
                                                    ? WidgetStateProperty.all(
                                                      Colors.grey[300],
                                                    )
                                                    : null,
                                            padding: WidgetStateProperty.all(
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 0,
                                              ),
                                            ),
                                          ),
                                          onPressed: () {
                                            yakushiinPlayer.jump(index);
                                            Navigator.of(context).pop();
                                          },
                                          child: Row(
                                            children: [
                                              Text(
                                                "${index + 1}",
                                                style: styleFontSimkai,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  playlist
                                                          .musicList![index]
                                                          .videoName ??
                                                      '',
                                                  style: styleFontSimkai,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      // 间距
                                      const SizedBox(height: gapHeight),
                                    ],
                                  );
                                },
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                child: const Text("返回"),
                              ),
                            ],
                          );
                        },
                      );

                      // 自动滚动到当前歌曲
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!scrollController.hasClients) return;
                        final viewportHeight =
                            scrollController.position.viewportDimension;
                        final targetOffset =
                            (currentIndex * itemExtent) - viewportHeight * 0.2;
                        final clampedOffset = targetOffset.clamp(
                          scrollController.position.minScrollExtent,
                          scrollController.position.maxScrollExtent,
                        );
                        scrollController.jumpTo(clampedOffset);
                      });
                    },
                    label: Text("当前歌单", style: styleFontSimkai),
                    icon: Icon(Icons.list_rounded),
                  ),

                  ElevatedButton.icon(
                    onPressed:
                        denyPopFlag
                            ? null
                            : () async {
                              yakushiinPlayer.jump(0);
                            },
                    label: Text("从头播放", style: styleFontSimkai),
                    icon: Icon(Icons.fast_rewind_rounded),
                  ),

                  ElevatedButton.icon(
                    onPressed: () async {
                      BotToast.showSimpleNotification(
                        duration: const Duration(seconds: 2),
                        hideCloseButton: false,
                        backgroundColor: Colors.yellow,
                        title: "⚠防误触模式需要长按交互",
                        titleStyle: styleFontSimkai,
                      );
                    },
                    onLongPress: () async {
                      setState(() {
                        denyPopFlag = !denyPopFlag;
                      });
                      if (denyPopFlag) {
                        BotToast.showSimpleNotification(
                          duration: const Duration(seconds: 2),
                          hideCloseButton: false,
                          backgroundColor: Colors.pink[200],
                          title: "⛔防误触模式已启动",
                          titleStyle: styleFontSimkai,
                        );
                      } else {
                        BotToast.showSimpleNotification(
                          duration: const Duration(seconds: 1),
                          hideCloseButton: false,
                          backgroundColor: Colors.green[300],
                          title: "✅防误触模式已关闭",
                          titleStyle: styleFontSimkai,
                        );
                      }
                    },
                    label: Text(
                      denyPopFlag ? "防误触（锁）" : "防误触（解锁）",
                      style: styleFontSimkai,
                    ),
                    icon: Icon(
                      denyPopFlag
                          ? Icons.lock_rounded
                          : Icons.lock_open_rounded,
                    ),
                  ),
                ],
              ),
              if (yakushiinRuntimeEnvironment.isDesktopPlatform)
                const Divider(),
              if (yakushiinRuntimeEnvironment.isDesktopPlatform)
                Text("PC 端专属功能：👇", style: styleFontSimkai),
              if (yakushiinRuntimeEnvironment.isDesktopPlatform)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [PinWindowButton()],
                ),
              const Divider(),
              ExcludeSemantics(
                child: Column(
                  children: [Text("以下是调试信息:", style: styleFontSimkaiCyanBold)],
                ),
              ),
              const Divider(),
              ExcludeSemantics(
                child: Column(
                  children: [
                    Text("tvMode: $tvMode", style: styleFontSimkaiBoldLarge),
                  ],
                ),
              ),
              const Divider(),
              ExcludeSemantics(
                child: Column(
                  children: [
                    Text(
                      "当前缓存状态: $nowBufferStatus",
                      style: styleFontSimkaiBoldLarge,
                    ),
                  ],
                ),
              ),
              const Divider(),
              ExcludeSemantics(
                child: Column(
                  children: [
                    Text(
                      "当前缓存位置:$nowBufferedDuration",
                      style: styleFontSimkaiBoldLarge,
                    ),
                  ],
                ),
              ),
              const Divider(),
              ExcludeSemantics(
                child: Column(
                  children: [
                    Text(
                      "当前视频参数: 硬解 ${nowPlayingVideoParams.hwPixelformat} | 软解 ${nowPlayingVideoParams.pixelformat} | 宽 ${nowPlayingVideoParams.w} | 高 ${nowPlayingVideoParams.h} | 方向 ${nowPlayingVideoParams.rotate} | 修正宽 ${nowPlayingVideoParams.dw} | 修正高 ${nowPlayingVideoParams.dh} | Anime4K: $anime4kStatus",
                      style: styleFontSimkaiBoldLarge,
                    ),
                  ],
                ),
              ),
              const Divider(),
              ExcludeSemantics(
                child: Column(
                  children: [
                    Text(
                      "当前音频参数: 格式 ${nowPlayingAudioParams.format} | 通道数 ${nowPlayingAudioParams.channelCount} | 通道 ${nowPlayingAudioParams.channels} | 采样率 ${nowPlayingAudioParams.sampleRate}",
                      style: styleFontSimkaiBoldLarge,
                    ),
                  ],
                ),
              ),
              const Divider(),
              ExcludeSemantics(
                child: Column(
                  children: [
                    Text(
                      "当前输出设备:${nowPlayingAudioDevice.name}-${nowPlayingAudioDevice.description}",
                      style: styleFontSimkaiBoldLarge,
                    ),
                  ],
                ),
              ),
              const Divider(),
              ExcludeSemantics(
                child: Column(
                  children: [
                    Text(
                      "可用输出设备:${nowPlayingAudioDevicesAvailable.toString()}",
                      style: styleFontSimkaiBoldLarge,
                    ),
                  ],
                ),
              ),
              const Divider(),
              ExcludeSemantics(
                child: Column(
                  children: [
                    if (Platform.isAndroid)
                      Text(
                        'Audio Stream: $_audioStream',
                        style: styleFontSimkaiBoldLarge,
                      ),
                    if (Platform.isIOS)
                      Text(
                        'Audio Session Category: $_audioSessionCategory',
                        style: styleFontSimkaiBoldLarge,
                      ),
                  ],
                ),
              ),
              const Divider(),
              ExcludeSemantics(
                child: Column(
                  children: [
                    Text(
                      "计步:当前状态=> $pedometerStatus | 状态改变时间=>$pedometerTimeStampStatusChanged",
                      style: styleFontSimkaiBoldLarge,
                    ),
                  ],
                ),
              ),
              const Divider(),
              ExcludeSemantics(
                child: Column(
                  children: [
                    Text(
                      "计步:步数=> $pedometerStep | 状态改变时间=>$pedometerTimeStampStepChanged",
                      style: styleFontSimkaiBoldLarge,
                    ),
                  ],
                ),
              ),
              const Divider(),
              ExcludeSemantics(
                child: Column(
                  children: [
                    Text(
                      "定位:精度=> ${locationSettings.accuracy} | 经度=>${currentPosition == null ? "unknown" : currentPosition?.longitude} | 纬度=>${currentPosition == null ? "unknown" : currentPosition?.latitude}",
                      style: styleFontSimkaiBoldLarge,
                    ),
                  ],
                ),
              ),
              const Divider(),
              ExcludeSemantics(
                child: Column(
                  children: [
                    Text(
                      "天气: 国家=>${currentWeather == null ? "unknown" : currentWeather?.country} | 位置=> ${currentWeather == null ? "unknown" : currentWeather?.areaName} | 日期=> ${currentWeather == null ? "unknown" : currentWeather?.date}",
                      style: styleFontSimkaiBoldLarge,
                    ),
                  ],
                ),
              ),
              const Divider(),
              ExcludeSemantics(
                child: Column(
                  children: [
                    Text(
                      "天气: 描述=>${currentWeather == null ? "unknown" : currentWeather?.weatherDescription} | 温度=> ${currentWeather == null ? "unknown" : currentWeather?.temperature} | 湿度=> ${currentWeather == null ? "unknown" : currentWeather?.humidity}",
                      style: styleFontSimkaiBoldLarge,
                    ),
                  ],
                ),
              ),
              const Divider(),
              ExcludeSemantics(
                child: Column(
                  children: [
                    Text(
                      "运行日志（最新在最上，最多显示 ${YakushiinLogBuffer.maxLines} 行）：",
                      style: styleFontSimkaiCyanBold,
                    ),
                  ],
                ),
              ),
              // 日志显示区域：限制高度不撑爆页面，内部可滚动，防止日志刷屏卡顿
              // 宽度始终占满应用宽度（不随文本内容伸缩）
              Container(
                height: 220,
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.black
                      : Colors.grey[200],
                  border: Border.all(color: Colors.cyan, width: 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ValueListenableBuilder<String>(
                  valueListenable: yakushiinLogBuffer.text,
                  builder: (context, logText, _) {
                    final baseStyle = const TextStyle(
                      fontSize: 11,
                      height: 1.3,
                      fontFamily: 'monospace',
                    );
                    // 按行拆分并按日志级别染色（Windows 换行为 \r\n，需去掉 \r）
                    final lineSpans =
                        logText.isEmpty
                            ? <TextSpan>[
                              TextSpan(
                                text: "暂无日志",
                                style: baseStyle.copyWith(
                                  color: const Color(0xFF30FF30),
                                ),
                              ),
                            ]
                            : logText
                                .split("\n")
                                .map(
                                  (line) => TextSpan(
                                    text: "${line.replaceAll('\r', '')}\n",
                                    style: baseStyle.copyWith(
                                      color: yakushiinLogLineColor(
                                        line,
                                        context,
                                      ),
                                    ),
                                  ),
                                )
                                .toList();
                    return SingleChildScrollView(
                      controller: logAreaScrollController,
                      child: SelectableText.rich(
                        TextSpan(style: baseStyle, children: lineSpans),
                      ),
                    );
                  },
                ),
              ),
              const Divider(),
            ],
          ),
        ),
      ),
    );
  }
}
