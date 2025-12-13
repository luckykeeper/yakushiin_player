// yakushiin_player
// @CreateTime    : 2025/03/28 23:52
// @Author        : Luckykeeper
// @Email         : luckykeeper@luckykeeper.site
// @Project       : yakushiin_player

import 'dart:async';
import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:geolocator/geolocator.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pedometer/pedometer.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:weather/weather.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yakushiin_player/model/gateway_associate/noa_player_v2_msg.dart';
import 'package:yakushiin_player/model/gateway_associate/noa_player_v2_playlist.dart';
import 'package:yakushiin_player/model/runtime.dart';
import 'package:yakushiin_player/model/version.dart';
import 'package:yakushiin_player/model/yakushiin_logger.dart';
import 'package:yakushiin_player/theme/font.dart';
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
  double currentVolumePlayer = 100;
  double currentVolumeSystem = 0;
  Timer? checkPlayListEndTimer;
  Timer? checkPlayingMusicEndTimer;

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

  // 定位
  Timer? getLocationAndWeatherTimer;
  late LocationSettings locationSettings;

  Position? currentPosition;

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

  late Player yakushiinPlayer = Player(
    configuration: PlayerConfiguration(
      title: 'YakushiinPlayer',
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

      yakushiinPlayer.open(yakushiinPlayList);
      yakushiinPlayer.stream.playing.listen((bool playing) {
        if (mounted) {
          setState(() {
            nowPlayingStatus = playing;
          });
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
        if (ref.watch(currentPlayList).musicList![playList.index].subTitleMd5 !=
            null) {
          if (ref
              .watch(currentPlayList)
              .musicList![playList.index]
              .subTitleMd5!
              .isNotEmpty) {
            if (ref
                    .watch(currentPlayList)
                    .musicList!
                    .first
                    .subTitleMd5!
                    .contains("http://") ||
                ref
                    .watch(currentPlayList)
                    .musicList!
                    .first
                    .subTitleMd5!
                    .contains("https://")) {
              // 在线字幕
              yakushiinLogger.i(
                "设置字幕:${ref.watch(currentPlayList).musicList![playList.index].subTitleMd5!}",
              );
              await yakushiinPlayer.setSubtitleTrack(
                SubtitleTrack.uri(
                  ref
                      .watch(currentPlayList)
                      .musicList![playList.index]
                      .subTitleMd5!,
                  title:
                      "${ref.watch(currentPlayList).musicList![playList.index].subTitleName}",
                  language:
                      "${ref.watch(currentPlayList).musicList![playList.index].subTitleLang}",
                ),
              );
            } else {
              // 本地字幕
              yakushiinLogger.i(
                "设置字幕:${yakushiinRuntimeEnvironment.musicDir.path}${Platform.pathSeparator}${ref.watch(currentPlayList).musicList![playList.index].subTitleMd5!}",
              );
              await yakushiinPlayer.setSubtitleTrack(
                SubtitleTrack.uri(
                  "${yakushiinRuntimeEnvironment.musicDir.path}${Platform.pathSeparator}${ref.watch(currentPlayList).musicList![playList.index].subTitleMd5!}",
                  title:
                      "${ref.watch(currentPlayList).musicList![playList.index].subTitleName}",
                  language:
                      "${ref.watch(currentPlayList).musicList![playList.index].subTitleLang}",
                ),
              );
            }
          } else {
            // 没有字幕的清掉所有字幕
            // yakushiinLogger.d("没有字幕，清除掉当前字幕轨");
            await yakushiinPlayer.setSubtitleTrack(SubtitleTrack.no());
          }
        } else {
          // 没有字幕的清掉所有字幕
          // yakushiinLogger.d("没有字幕，清除掉当前字幕轨");
          await yakushiinPlayer.setSubtitleTrack(SubtitleTrack.no());
        }
        // 更新播放状态到数据库
        for (var i = 0; i < ref.read(currentPlayList).musicList!.length; i++) {
          ref.read(currentPlayList).musicList![i].nowPlaying = false;
        }
        ref.read(currentPlayList).musicList![playList.index].nowPlaying = true;
        NoaPlayerV2Msg localPlayList = NoaPlayerV2Msg(playList: []);
        yakushiinLogger.d(
          "歌单数量：${yakushiinRuntimeEnvironment.dataEngineForV2PlayList.length}",
        );
        for (
          var i = 0;
          i < yakushiinRuntimeEnvironment.dataEngineForV2PlayList.length;
          i++
        ) {
          var thisList = yakushiinRuntimeEnvironment.dataEngineForV2PlayList
              .getAt(i);
          if (thisList != null) {
            // 播放列表名称同名，则取当前播放列表状态写回数据库
            yakushiinLogger.d("回写数据库，遍历播放列表=>${thisList.playListName}");
            if (thisList.playListName ==
                ref.watch(currentPlayList).playListName) {
              localPlayList.playList!.add(ref.watch(currentPlayList));
            } else {
              localPlayList.playList!.add(thisList);
            }
          }
        }
        await yakushiinRuntimeEnvironment.dataEngineForV2PlayList.clear();
        for (var playList in localPlayList.playList!) {
          await yakushiinRuntimeEnvironment.dataEngineForV2PlayList.add(
            playList,
          );
        }
        nowPlayingIndex = playList.index;
        yakushiinLogger.i(
          "回写数据库，当前播放位置=>${playList.index}-$nowPlayingMusicName 成功",
        );
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
    try {
      yakushiinPlayer.dispose();
    } catch (e) {
      yakushiinLogger.e("dispose yakushiinPlayer Failed:$e");
    }
    FlutterVolumeController.removeListener();
    getLocationAndWeatherTimer?.cancel();
    checkPlayListEndTimer?.cancel();
    checkPlayingMusicEndTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            Column(
              children: [
                Text(
                  "当前播放列表:${ref.watch(currentPlayList).playListName} (${nowPlayingIndex + 1}/${ref.watch(currentPlayList).musicList?.length == null ? "N/a" : ref.watch(currentPlayList).musicList!.length})",
                  style: styleFontSimkaiBoldLarge,
                ),
              ],
            ),
            const Divider(),
            Column(
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
            const Divider(),
            Column(
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
            const Divider(),
            Column(
              children: [
                Text(
                  "播放进度=>当前: $nowPlayingDurationCurrent / 总: $nowPlayingDurationTotal / ${(nowPlayingDurationTotal - (nowPlayingDurationCurrent)).inSeconds} 秒",
                  style: styleFontSimkaiBoldLarge,
                ),
              ],
            ),
            const Divider(),
            Column(
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
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
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
                          Text("当前运动状态:", style: styleFontSimkaiCyanBoldLarge),
                          Text(
                            pedometerStatus,
                            style: styleFontSimkaiBoldLarge,
                          ),
                        ],
                      ),
                      VerticalDivider(),
                      Column(
                        children: [
                          Text("开机以来步数:", style: styleFontSimkaiCyanBoldLarge),
                          Text(
                            "$pedometerStep",
                            style: styleFontSimkaiBoldLarge,
                          ),
                        ],
                      ),
                    ],
                  ),
                VerticalDivider(),
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
              ],
            ),
            const Divider(),
            SafeArea(
              child: SizedBox(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.width * 9.0 / 16.0,
                child: Video(
                  controller: yakushiinPlayerController,
                  subtitleViewConfiguration: const SubtitleViewConfiguration(
                    style: TextStyle(
                      height: 1.4,
                      fontSize: 60.0,
                      letterSpacing: 0.0,
                      wordSpacing: 0.0,
                      color: Color(0xffffffff),
                      fontWeight: FontWeight.normal,
                      fontFamily: fontSimkaiFamily,
                      backgroundColor: Color(0xaa000000),
                    ),
                    textAlign: TextAlign.center,
                    padding: EdgeInsets.fromLTRB(16.0, 24.0, 16.0, 0.0),
                  ),
                  pauseUponEnteringBackgroundMode: true,
                  resumeUponEnteringForegroundMode: true,
                ),
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
                    if (nowPlayingIndex + 1 ==
                        ref.watch(currentPlayList).musicList?.length) {
                      // 播放列表尾
                      await yakushiinPlayer.jump(0);
                    } else {
                      await yakushiinPlayer.next();
                    }
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
                  onPressed: () async {
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    currentVolumePlayer - 5 < 0
                        ? await yakushiinPlayer.setVolume(0)
                        : await yakushiinPlayer.setVolume(
                          currentVolumePlayer - 5,
                        );
                  },
                  label: Text("音量（软） -", style: styleFontSimkai),
                  icon: Icon(Icons.volume_down_rounded),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    yakushiinPlayer.jump(0);
                  },
                  label: Text("从头播放", style: styleFontSimkai),
                  icon: Icon(Icons.fast_rewind_rounded),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    currentVolumePlayer + 5 > 100
                        ? await yakushiinPlayer.setVolume(100)
                        : await yakushiinPlayer.setVolume(
                          currentVolumePlayer + 5,
                        );
                  },
                  label: Text("音量（软） +", style: styleFontSimkai),
                  icon: Icon(Icons.volume_up_rounded),
                ),
              ],
            ),
            const Divider(),
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
                    await yakushiinPlayer.setPlaylistMode(PlaylistMode.single);
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
                        backgroundColor: Colors.green[300],
                        title: "⛔复制失败:$e",
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
            Column(
              children: [Text("以下是调试信息:", style: styleFontSimkaiCyanBold)],
            ),
            const Divider(),
            Column(
              children: [
                Text(
                  "当前缓存状态: $nowBufferStatus",
                  style: styleFontSimkaiBoldLarge,
                ),
              ],
            ),
            const Divider(),
            Column(
              children: [
                Text(
                  "当前缓存位置:$nowBufferedDuration",
                  style: styleFontSimkaiBoldLarge,
                ),
              ],
            ),
            const Divider(),
            Column(
              children: [
                Text(
                  "当前视频参数: 硬解 ${nowPlayingVideoParams.hwPixelformat} | 软解 ${nowPlayingVideoParams.pixelformat} | 宽 ${nowPlayingVideoParams.w} | 高 ${nowPlayingVideoParams.h} | 方向 ${nowPlayingVideoParams.rotate} | 修正宽 ${nowPlayingVideoParams.dw} | 修正高 ${nowPlayingVideoParams.dh}",
                  style: styleFontSimkaiBoldLarge,
                ),
              ],
            ),
            const Divider(),
            Column(
              children: [
                Text(
                  "当前音频参数: 格式 ${nowPlayingAudioParams.format} | 通道数 ${nowPlayingAudioParams.channelCount} | 通道 ${nowPlayingAudioParams.channels} | 采样率 ${nowPlayingAudioParams.sampleRate}",
                  style: styleFontSimkaiBoldLarge,
                ),
              ],
            ),
            const Divider(),
            Column(
              children: [
                Text(
                  "当前输出设备:${nowPlayingAudioDevice.name}-${nowPlayingAudioDevice.description}",
                  style: styleFontSimkaiBoldLarge,
                ),
              ],
            ),
            const Divider(),
            Column(
              children: [
                Text(
                  "可用输出设备:${nowPlayingAudioDevicesAvailable.toString()}",
                  style: styleFontSimkaiBoldLarge,
                ),
              ],
            ),
            const Divider(),
            Column(
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
            const Divider(),
            Column(
              children: [
                Text(
                  "计步:当前状态=> $pedometerStatus | 状态改变时间=>$pedometerTimeStampStatusChanged",
                  style: styleFontSimkaiBoldLarge,
                ),
              ],
            ),
            const Divider(),
            Column(
              children: [
                Text(
                  "计步:步数=> $pedometerStep | 状态改变时间=>$pedometerTimeStampStepChanged",
                  style: styleFontSimkaiBoldLarge,
                ),
              ],
            ),
            const Divider(),
            Column(
              children: [
                Text(
                  "定位:精度=> ${locationSettings.accuracy} | 经度=>${currentPosition == null ? "unknown" : currentPosition?.longitude} | 纬度=>${currentPosition == null ? "unknown" : currentPosition?.latitude}",
                  style: styleFontSimkaiBoldLarge,
                ),
              ],
            ),
            const Divider(),
            Column(
              children: [
                Text(
                  "天气: 国家=>${currentWeather == null ? "unknown" : currentWeather?.country} | 位置=> ${currentWeather == null ? "unknown" : currentWeather?.areaName} | 日期=> ${currentWeather == null ? "unknown" : currentWeather?.date}",
                  style: styleFontSimkaiBoldLarge,
                ),
              ],
            ),
            const Divider(),
            Column(
              children: [
                Text(
                  "天气: 描述=>${currentWeather == null ? "unknown" : currentWeather?.weatherDescription} | 温度=> ${currentWeather == null ? "unknown" : currentWeather?.temperature} | 湿度=> ${currentWeather == null ? "unknown" : currentWeather?.humidity}",
                  style: styleFontSimkaiBoldLarge,
                ),
              ],
            ),
            const Divider(),
          ],
        ),
      ),
    );
  }
}
