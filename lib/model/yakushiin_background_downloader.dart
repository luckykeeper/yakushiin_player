// yakushiin_player
// @CreateTime    : 2026/09/04
// @Author        : Luckykeeper
// @Email         : luckykeeper@luckykeeper.site
// @Project       : yakushiin_player

import 'dart:async';
import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:yakushiin_player/model/gateway_associate/noa_player_v2_msg.dart';
import 'package:yakushiin_player/model/gateway_associate/noa_player_v2_playlist.dart';
import 'package:yakushiin_player/model/runtime.dart';
import 'package:yakushiin_player/model/version.dart';
import 'package:yakushiin_player/model/yakushiin_logger.dart';
import 'package:yakushiin_player/theme/font.dart';

/// 下载器状态快照，供同步页 UI 监听
class YakushiinDownloadState {
  final bool running;
  final String nowHandlingName;
  final double? downloadProgress;
  final int doneCount;
  final int totalCount;
  final String message;
  final bool success;

  const YakushiinDownloadState({
    this.running = false,
    this.nowHandlingName = "N/a",
    this.downloadProgress,
    this.doneCount = 0,
    this.totalCount = 0,
    this.message = "",
    this.success = false,
  });

  YakushiinDownloadState copyWith({
    bool? running,
    String? nowHandlingName,
    double? downloadProgress,
    bool clearDownloadProgress = false,
    int? doneCount,
    int? totalCount,
    String? message,
    bool? success,
  }) {
    return YakushiinDownloadState(
      running: running ?? this.running,
      nowHandlingName: nowHandlingName ?? this.nowHandlingName,
      downloadProgress:
          clearDownloadProgress ? null : (downloadProgress ?? this.downloadProgress),
      doneCount: doneCount ?? this.doneCount,
      totalCount: totalCount ?? this.totalCount,
      message: message ?? this.message,
      success: success ?? this.success,
    );
  }
}

/// 全局后台下载器（单例）
///
/// 下载流程不依赖任何页面 State：
/// - 点击同步后离开同步页 / 播放页听歌 / 应用退到后台，下载都会继续；
/// - Android 端通过 flutter_local_notifications 启动 dataSync 前台服务，
///   下载进度在通知栏实时更新；
/// - 单个文件下载失败后自动重试，直到成功为止。
class YakushiinBackgroundDownloader {
  YakushiinBackgroundDownloader._();

  static final YakushiinBackgroundDownloader instance =
      YakushiinBackgroundDownloader._();

  static const int _notificationIdRunning = 20260904;
  static const String _channelId = "yakushiin_download";
  static const String _channelName = "歌曲下载";
  static const Duration _retryDelay = Duration(seconds: 5);

  final ValueNotifier<YakushiinDownloadState> progressNotifier =
      ValueNotifier<YakushiinDownloadState>(const YakushiinDownloadState());

  bool _running = false;
  bool get isRunning => _running;

  FlutterLocalNotificationsPlugin? _notifications;
  int _lastNotifiedProgress = -1;
  DateTime _lastToastTime = DateTime.now();

  /// 初始化通知（仅 Android），失败不影响下载功能本身
  Future<void> _initNotifications() async {
    if (!yakushiinRuntimeEnvironment.isAndroidPlatform) {
      return;
    }
    if (_notifications != null) {
      return;
    }
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      await plugin.initialize(settings: const InitializationSettings(android: androidInit));
      final android = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        try {
          await android.requestNotificationsPermission();
        } catch (e) {
          yakushiinLogger.w("请求通知权限失败:$e");
        }
        await android.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: 'YakushiinPlayer 歌曲与字幕下载进度',
            importance: Importance.low,
          ),
        );
      }
      _notifications = plugin;
      yakushiinLogger.i("下载通知初始化完成");
    } catch (e) {
      yakushiinLogger.e("下载通知初始化失败:$e");
      _notifications = null;
    }
  }

  AndroidNotificationDetails _runningNotificationDetails(int progress) {
    return AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'YakushiinPlayer 歌曲与字幕下载进度',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: 1000,
      progress: progress.clamp(0, 1000),
      indeterminate: false,
      autoCancel: false,
    );
  }

  Future<void> _startForegroundService(String title, String body) async {
    final android = _notifications?.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    try {
      await android.startForegroundService(
        id: _notificationIdRunning,
        title: title,
        body: body,
        notificationDetails: _runningNotificationDetails(0),
        foregroundServiceTypes: {AndroidServiceForegroundType.foregroundServiceTypeDataSync},
      );
    } catch (e) {
      yakushiinLogger.e("启动下载前台服务失败:$e");
    }
  }

  /// 节流更新通知栏进度（每 1% 更新一次）
  Future<void> _updateNotificationProgress(String title, String body) async {
    final state = progressNotifier.value;
    if (state.totalCount <= 0) return;
    final overall =
        ((state.doneCount + (state.downloadProgress ?? 0)) / state.totalCount *
                1000)
            .floor();
    if (overall == _lastNotifiedProgress) return;
    _lastNotifiedProgress = overall;
    final android = _notifications?.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    try {
      await android.show(
        id: _notificationIdRunning,
        title: title,
        body: body,
        notificationDetails: _runningNotificationDetails(overall),
      );
    } catch (e) {
      // 通知更新失败不影响下载
    }
  }

  Future<void> _finishNotification(String title, String body) async {
    final android = _notifications?.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    try {
      await android.stopForegroundService();
      await android.cancel(id: _notificationIdRunning);
      await android.show(
        id: _notificationIdRunning + 1,
        title: title,
        body: body,
        notificationDetails: const AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'YakushiinPlayer 歌曲与字幕下载进度',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      );
    } catch (e) {
      yakushiinLogger.e("下载完成通知失败:$e");
    }
  }

  void _updateState(YakushiinDownloadState state) {
    progressNotifier.value = state;
  }

  /// 限频弹提示（避免重试风暴刷屏）
  void _throttledToast(String title, {bool error = true}) {
    final now = DateTime.now();
    if (now.difference(_lastToastTime) < const Duration(seconds: 5)) {
      return;
    }
    _lastToastTime = now;
    BotToast.showSimpleNotification(
      duration: const Duration(seconds: 3),
      hideCloseButton: false,
      backgroundColor: error ? Colors.pink[200] : Colors.green[300],
      title: title,
      titleStyle: styleFontSimkai,
    );
  }

  /// 单文件下载（带无限重试，直到成功）
  Future<bool> _downloadWithRetry(String url, String md5, String name) async {
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        await _downloadOnce(url, md5, name);
        if (attempt > 1) {
          yakushiinLogger.i("下载重试成功:$name (第 $attempt 次尝试)");
        }
        return true;
      } catch (e) {
        yakushiinLogger.e("下载失败（第 $attempt 次尝试）:$name => $url 失败:$e");
        _updateState(
          progressNotifier.value.copyWith(
            nowHandlingName: "⛔$name 下载失败，自动重试中（第 $attempt 次失败）...",
            downloadProgress: 0,
          ),
        );
        _throttledToast("⛔$name 下载失败，将自动重试（第 $attempt 次）");
        await Future.delayed(_retryDelay);
      }
    }
  }

  /// 单次下载尝试，失败抛异常交由重试逻辑处理
  Future<void> _downloadOnce(String url, String md5, String name) async {
    yakushiinLogger.i("下载文件:$url<=>>$md5 开始");
    final yakushiinRequestClient = Dio();
    if (!await yakushiinRuntimeEnvironment.cacheDir.exists()) {
      await yakushiinRuntimeEnvironment.cacheDir.create(recursive: true);
    }
    final downloadCacheFile = File(
      "${yakushiinRuntimeEnvironment.cacheDir.path}${Platform.pathSeparator}$md5",
    );
    yakushiinLogger.i("目标位置:${downloadCacheFile.path}");
    if (await downloadCacheFile.exists()) {
      yakushiinLogger.i("删除缓存文件夹内的未完成缓存文件:${downloadCacheFile.path}");
      await downloadCacheFile.delete();
    }
    await yakushiinRequestClient.download(
      url,
      downloadCacheFile.path,
      queryParameters: yakushininPlayerUserAgentMap,
      onReceiveProgress: (int received, int total) {
        if (total <= 0) return;
        _updateState(
          progressNotifier.value.copyWith(
            downloadProgress: received / total,
          ),
        );
        _updateNotificationProgress(
          "YakushiinPlayer 下载中",
          progressNotifier.value.nowHandlingName,
        );
      },
    );
    if (!await yakushiinRuntimeEnvironment.musicDir.exists()) {
      await yakushiinRuntimeEnvironment.musicDir.create(recursive: true);
    }
    await downloadCacheFile.copy(
      "${yakushiinRuntimeEnvironment.musicDir.path}${Platform.pathSeparator}$md5",
    );
    await downloadCacheFile.delete();
    yakushiinLogger.i("下载文件:$url<=>>$md5 完成");
  }

  /// 主流程：拉取歌单 -> 落库 -> 后台逐个下载（自动重试） -> 清理
  ///
  /// 立即返回，流程在后台执行，进度通过 [progressNotifier] 暴露。
  /// 返回 false 表示未启动（已在同步中或网关拉取失败）。
  Future<bool> startSync() async {
    if (_running) {
      yakushiinLogger.w("已有同步任务在运行，忽略本次请求");
      return false;
    }
    _running = true;
    _lastNotifiedProgress = -1;
    _updateState(
      const YakushiinDownloadState(
        running: true,
        nowHandlingName: "正在从网关拉取歌单信息...",
        message: "",
      ),
    );

    // 后台执行完整流程，不阻塞调用方 UI
    unawaited(_runSync());
    return true;
  }

  Future<void> _runSync() async {
    var ok = false;
    String failMessage = "";
    try {
      await _initNotifications();
      await _startForegroundService(
        "YakushiinPlayer 下载中",
        "正在从网关拉取歌单信息...",
      );

      final v2Msg = await NoaPlayerV2Msg().getNoaHandlerVideoListV2();
      if (!v2Msg.isSuccess) {
        failMessage =
            "从网关拉取歌单信息失败！服务器返回：${v2Msg.statusCode} | ${v2Msg.statusMessage}";
        yakushiinLogger.e("⛔$failMessage");
        _updateState(
          progressNotifier.value.copyWith(
            running: false,
            success: false,
            message: failMessage,
          ),
        );
        await _finishNotification("⛔同步失败", failMessage);
        BotToast.showSimpleNotification(
          duration: const Duration(seconds: 3),
          hideCloseButton: false,
          backgroundColor: Colors.pink[200],
          title: "⛔$failMessage",
          titleStyle: styleFontSimkai,
        );
        return;
      }

      var gatewayMusicTotalInt = 0;
      for (var playList in v2Msg.playList!) {
        gatewayMusicTotalInt += playList.musicList!.length;
      }
      yakushiinLogger.i("网关歌曲清单数量:$gatewayMusicTotalInt");

      // 原子化写入歌单，避免 clear+逐条add 长窗口及中途退出导致丢失
      try {
        final box = yakushiinRuntimeEnvironment.dataEngineForV2PlayList;
        final putMap = <String, NoaPlayerV2PlayList>{
          for (var p in v2Msg.playList!)
            if (p.playListName != null && p.playListName!.isNotEmpty)
              p.playListName!: p
        };
        await box.clear();
        await box.putAll(putMap);
        yakushiinLogger.i("同步写入歌单 ${putMap.length} 个，当前总数 ${box.length}");
      } catch (e) {
        failMessage = "同步写入歌单失败：$e";
        yakushiinLogger.e("⛔$failMessage");
        _updateState(
          progressNotifier.value.copyWith(
            running: false,
            success: false,
            message: failMessage,
          ),
        );
        await _finishNotification("⛔同步失败", failMessage);
        BotToast.showSimpleNotification(
          duration: const Duration(seconds: 3),
          hideCloseButton: false,
          backgroundColor: Colors.pink[200],
          title: "⛔$failMessage",
          titleStyle: styleFontSimkai,
        );
        return;
      }

      // 统计需要下载的文件总数（音乐 + 字幕）
      var totalCount = 0;
      for (var playList in v2Msg.playList!) {
        for (var music in playList.musicList!) {
          totalCount++;
          if (music.subTitleMd5 != null && music.subTitleMd5!.isNotEmpty) {
            totalCount++;
          }
        }
      }
      var doneCount = 0;
      _updateState(
        progressNotifier.value.copyWith(
          totalCount: totalCount,
          doneCount: 0,
          message: "",
        ),
      );

      var aborted = false;
      outer:
      for (var i = 0; i < v2Msg.playList!.length; i++) {
        for (var music in v2Msg.playList![i].musicList!) {
          // 音乐
          var thisMusicVideoFile = File(
            "${yakushiinRuntimeEnvironment.musicDir.path}${Platform.pathSeparator}${music.videoMd5}",
          );
          if (!await thisMusicVideoFile.exists()) {
            _updateState(
              progressNotifier.value.copyWith(
                nowHandlingName: "【音乐】：=> ${music.videoName}",
                downloadProgress: 0,
              ),
            );
            final downloadOk = await _downloadWithRetry(
              "${music.videoUrl}",
              "${music.videoMd5}",
              "${music.videoName}",
            );
            if (!downloadOk) {
              aborted = true;
              break outer;
            }
          }
          doneCount++;
          _updateState(
            progressNotifier.value.copyWith(
              doneCount: doneCount,
              clearDownloadProgress: true,
            ),
          );

          // 字幕
          if (music.subTitleMd5 != null && music.subTitleMd5!.isNotEmpty) {
            var thisMusicSubTitleFile = File(
              "${yakushiinRuntimeEnvironment.musicDir.path}${Platform.pathSeparator}${music.subTitleMd5}",
            );
            if (!await thisMusicSubTitleFile.exists()) {
              _updateState(
                progressNotifier.value.copyWith(
                  nowHandlingName:
                      "【字幕】：=> ${music.videoName}-${music.subTitleName}",
                  downloadProgress: 0,
                ),
              );
              final downloadOk = await _downloadWithRetry(
                "${music.subTitleUrl}",
                "${music.subTitleMd5}",
                "${music.videoName}-${music.subTitleName}",
              );
              if (!downloadOk) {
                aborted = true;
                break outer;
              }
            }
            doneCount++;
            _updateState(
              progressNotifier.value.copyWith(
                doneCount: doneCount,
                clearDownloadProgress: true,
              ),
            );
          }
        }
      }

      if (aborted) {
        // 理论上不会走到这里（重试直到成功），兜底处理
        failMessage = "同步中止：存在无法下载的文件";
        _updateState(
          progressNotifier.value.copyWith(
            running: false,
            success: false,
            message: failMessage,
          ),
        );
        await _finishNotification("⛔同步失败", failMessage);
        return;
      }

      // 清空缓存文件夹
      if (await yakushiinRuntimeEnvironment.cacheDir.exists()) {
        await yakushiinRuntimeEnvironment.cacheDir.delete(recursive: true);
      }
      if (!await yakushiinRuntimeEnvironment.cacheDir.exists()) {
        await yakushiinRuntimeEnvironment.cacheDir.create();
      }
      // 清空没有 md5 索引的文件
      var matchMusicMd5Count = 0;
      var matchSubTitleMd5Count = 0;
      var matchDeleteCount = 0;
      var files = yakushiinRuntimeEnvironment.musicDir.listSync();
      for (var file in files) {
        if (file is File && await file.exists()) {
          var md5Matched = false;
          for (var playList in v2Msg.playList!) {
            for (var i = 0; i < playList.musicList!.length; i++) {
              if (file.path ==
                  "${yakushiinRuntimeEnvironment.musicDir.path}${Platform.pathSeparator}${playList.musicList![i].videoMd5!}") {
                matchMusicMd5Count++;
                md5Matched = true;
                break;
              }
              if (file.path ==
                  "${yakushiinRuntimeEnvironment.musicDir.path}${Platform.pathSeparator}${playList.musicList![i].subTitleMd5!}") {
                matchSubTitleMd5Count++;
                md5Matched = true;
                break;
              }
            }
          }
          if (!md5Matched) {
            yakushiinLogger.w("删除游离索引文件:${file.path}");
            matchDeleteCount++;
            await file.delete();
          }
        }
      }
      yakushiinLogger.i("音乐匹配计数:$matchMusicMd5Count");
      yakushiinLogger.i("字幕匹配计数:$matchSubTitleMd5Count");
      yakushiinLogger.i("游离删除计数:$matchDeleteCount");

      ok = true;
      _updateState(
        progressNotifier.value.copyWith(
          running: false,
          success: true,
          nowHandlingName: "全部处理完成!",
          clearDownloadProgress: true,
          message: "全部同步完成",
        ),
      );
      await _finishNotification("✅全部同步完成", "本地歌单已经成功和网关同步啦~");
      BotToast.showSimpleNotification(
        duration: const Duration(seconds: 3),
        hideCloseButton: false,
        backgroundColor: Colors.green[300],
        title: "✅全部同步完成！",
        titleStyle: styleFontSimkai,
      );
    } catch (e) {
      failMessage = "同步流程异常：$e";
      yakushiinLogger.e("⛔$failMessage");
      _updateState(
        progressNotifier.value.copyWith(
          running: false,
          success: false,
          message: failMessage,
        ),
      );
      await _finishNotification("⛔同步失败", failMessage);
      BotToast.showSimpleNotification(
        duration: const Duration(seconds: 3),
        hideCloseButton: false,
        backgroundColor: Colors.pink[200],
        title: "⛔$failMessage",
        titleStyle: styleFontSimkai,
      );
    } finally {
      _running = false;
      yakushiinLogger.i("同步任务结束 ok:$ok $failMessage");
    }
  }
}
