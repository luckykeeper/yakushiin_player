// yakushiin_player
// @CreateTime    : 2025/03/28 22:22
// @Author        : Luckykeeper
// @Email         : luckykeeper@luckykeeper.site
// @Project       : yakushiin_player

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:yakushiin_player/model/runtime.dart';

var yakushiinLogger = Logger(
  // 必须显式使用 ProductionFilter：默认的 DevelopmentFilter 在 Release 构建
  // （无 assert）下会吞掉全部日志，导致运行日志区域与本地日志文件均为空
  filter: ProductionFilter(),
  printer: PrettyPrinter(
    methodCount: 2,
    errorMethodCount: 8,
    lineLength: 120,
    colors: true,
    printEmojis: true,
    dateTimeFormat: DateTimeFormat.dateAndTime,
  ),
  output: MultiOutput([
    ConsoleOutput(),
    yakushiinLoggerInstance,
    yakushiinLogBuffer,
  ]),
);

var yakushiinLoggerInstance = YakushiinLogger();

/// 内存日志缓冲（供播放页日志区域展示，最新在最上，限制最大行数防卡顿）
var yakushiinLogBuffer = YakushiinLogBuffer();

class YakushiinLogBuffer extends LogOutput {
  /// 缓冲区最大行数，超出后丢弃最旧的日志
  static const int maxLines = 200;

  /// 合并刷新间隔，避免高频日志频繁触发 UI 重建
  static const Duration flushInterval = Duration(milliseconds: 300);

  /// 当前缓冲的日志文本（最新在最上），UI 通过 ValueListenableBuilder 监听
  final ValueNotifier<String> text = ValueNotifier<String>("");

  final List<String> _lines = [];
  final List<String> _pending = [];
  Timer? _flushTimer;

  @override
  void output(OutputEvent event) {
    final eventTime = event.origin.time;
    final timeText =
        "${eventTime.hour.toString().padLeft(2, '0')}:"
        "${eventTime.minute.toString().padLeft(2, '0')}:"
        "${eventTime.second.toString().padLeft(2, '0')}";
    final levelText = event.origin.level.name.toUpperCase();
    final errorText = event.origin.error == null
        ? ""
        : " | ${event.origin.error}";
    final line = "[$timeText][$levelText] ${event.origin.message}$errorText";
    // 最新日志插到最前面
    _pending.insert(0, line);
    _flushTimer ??= Timer(flushInterval, _flush);
  }

  void _flush() {
    _flushTimer = null;
    if (_pending.isEmpty) {
      return;
    }
    _lines.insertAll(0, _pending);
    _pending.clear();
    if (_lines.length > maxLines) {
      _lines.removeRange(maxLines, _lines.length);
    }
    text.value = _lines.join(Platform.lineTerminator);
  }
}

class YakushiinLogger extends LogOutput {
  File? yakushiinLogFile;
  bool enabledWriteLocal = false;
  Future<void> loggerInit() async {
    yakushiinLogger.i(
      "isDesktop:${yakushiinRuntimeEnvironment.isDesktopPlatform}",
    );
    yakushiinLogger.i(
      "running on ${Platform.operatingSystem} | ${Platform.operatingSystemVersion} | ${Platform.version}",
    );
    yakushiinLogger.i(
      "hwInfo: ${Platform.localHostname} | ${Platform.localeName} | ${Platform.numberOfProcessors}",
    );
    try {
      yakushiinLogger.i(
        "应用文件夹文档位置：${yakushiinRuntimeEnvironment.appDocumentsDirectory.uri}",
      );
      yakushiinLogger.i(
        "应用文件夹支持目录位置：${yakushiinRuntimeEnvironment.appSupportDirectory.uri}",
      );
      yakushiinLogger.i(
        "应用文件夹缓存目录位置：${yakushiinRuntimeEnvironment.appCacheDirectory.uri}",
      );
      // yakushiinLogger.i(
      //   "应用文件夹外部存储目录位置：${yakushiinRuntimeEnvironment.externalStorageDirectory?.uri}",
      // );
      yakushiinLogger.i(
        "运行时主存储目录位置：${yakushiinRuntimeEnvironment.mainDirectory.uri}",
      );
      var thisYakushiinLogFile = File(
        "${yakushiinRuntimeEnvironment.mainDirectory.path}${Platform.pathSeparator}yakushiinLogger.log",
      );
      yakushiinLogger.i("日志文件的存储位置:${thisYakushiinLogFile.uri}");
      if (await thisYakushiinLogFile.exists()) {
        await thisYakushiinLogFile.delete();
      }
      yakushiinLogFile = await thisYakushiinLogFile.create(recursive: true);
      enabledWriteLocal = true;
      yakushiinLogger.i("日志输出初始化完成 | ${Platform.operatingSystemVersion}");
      yakushiinLogger.i(
        "isDesktop:${yakushiinRuntimeEnvironment.isDesktopPlatform}",
      );
      yakushiinLogger.i(
        "running on ${Platform.operatingSystem} | ${Platform.operatingSystemVersion} | ${Platform.version}",
      );
      yakushiinLogger.i(
        "hwInfo: ${Platform.localHostname} | ${Platform.localeName} | ${Platform.numberOfProcessors}",
      );
      yakushiinLogger.i("日志文件的存储位置:${thisYakushiinLogFile.path}");
      yakushiinLogger.i(
        "应用文件夹文档位置：${yakushiinRuntimeEnvironment.appDocumentsDirectory.uri}",
      );
      yakushiinLogger.i(
        "应用文件夹支持目录位置：${yakushiinRuntimeEnvironment.appSupportDirectory.uri}",
      );
      yakushiinLogger.i(
        "应用文件夹缓存目录位置：${yakushiinRuntimeEnvironment.appCacheDirectory.uri}",
      );
      // yakushiinLogger.i(
      //   "应用文件夹外部存储目录位置：${yakushiinRuntimeEnvironment.externalStorageDirectory?.uri}",
      // );
      yakushiinLogger.i(
        "运行时主存储目录位置：${yakushiinRuntimeEnvironment.mainDirectory.uri}",
      );
    } catch (e) {
      yakushiinLogger.w("不支持输出日志到文件的平台!");
      yakushiinLogger.e("移除旧日志文件失败:$e");
      enabledWriteLocal = false;
    }
  }

  @override
  void output(OutputEvent event) async {
    if (enabledWriteLocal) {
      try {
        for (var content in event.lines) {
          await yakushiinLogFile!.writeAsString(
            content + Platform.lineTerminator,
            mode: FileMode.append,
            flush: true,
          );
        }
      } catch (e) {
        yakushiinLogger.e("写入日志到本地失败:$e");
      }
    }
  }
}
