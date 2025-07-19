// yakushiin_player
// @CreateTime    : 2025/03/28 22:22
// @Author        : Luckykeeper
// @Email         : luckykeeper@luckykeeper.site
// @Project       : yakushiin_player

import 'dart:io';

import 'package:logger/logger.dart';
import 'package:yakushiin_player/model/runtime.dart';

var yakushiinLogger = Logger(
  printer: PrettyPrinter(
    methodCount: 2,
    errorMethodCount: 8,
    lineLength: 120,
    colors: true,
    printEmojis: true,
    dateTimeFormat: DateTimeFormat.dateAndTime,
  ),
  output: MultiOutput([ConsoleOutput(), yakushiinLoggerInstance]),
);

var yakushiinLoggerInstance = YakushiinLogger();

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
