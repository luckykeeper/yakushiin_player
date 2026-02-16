// yakushiin_player
// @CreateTime    : 2025/03/28 21:57
// @Author        : Luckykeeper
// @Email         : luckykeeper@luckykeeper.site
// @Project       : yakushiin_player

import 'dart:io';

import 'package:hive_ce_flutter/adapters.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yakushiin_player/hive/hive_registrar.g.dart';
import 'package:yakushiin_player/model/gateway_associate/noa_player_v2_playlist.dart';
import 'package:yakushiin_player/model/gateway_setting.dart';
import 'package:yakushiin_player/model/hive_boxes.dart';
import 'package:yakushiin_player/model/yakushiin_logger.dart';

class YakushiinRuntimeEnvironment {
  bool isDesktopPlatform = false;
  bool isAndroidPlatform = false;
  String osVersion = "N/A";
  String dartRuntimeVersion = "N/A";
  late Directory appDocumentsDirectory;
  late Directory appSupportDirectory;
  late Directory? externalStorageDirectory;
  late Directory appCacheDirectory;
  late Directory mainDirectory; // 主写目录，日志、文件、缓存，PC是当前文件夹，移动端是应用文件夹
  late Directory musicDir;
  late Directory dbDir;
  late Directory cacheDir;

  late Box<GatewaySetting> dataEngineForGatewaySetting;
  late Box<NoaPlayerV2PlayList> dataEngineForV2PlayList;

  Future<void> init() async {
    if ((Platform.isWindows) || (Platform.isMacOS) || (Platform.isLinux)) {
      isDesktopPlatform = true;
    } else {
      isDesktopPlatform = false;
    }
    if (Platform.isAndroid) {
      isAndroidPlatform = true;
    }
    osVersion = Platform.operatingSystemVersion;
    dartRuntimeVersion = Platform.version;

    appDocumentsDirectory = await getApplicationDocumentsDirectory();
    appSupportDirectory = await getApplicationSupportDirectory();
    appCacheDirectory = await getApplicationCacheDirectory();
    try {
      externalStorageDirectory = await getExternalStorageDirectory();
    } catch (e) {
      yakushiinLogger.w("当前平台不支持外部存储:$e");
    }
    mainDirectory =
        isDesktopPlatform
            ? Directory.current
            : Platform.isAndroid
            ? externalStorageDirectory!
            : appDocumentsDirectory;

    musicDir = Directory("${mainDirectory.path}${Platform.pathSeparator}music");
    if (!await musicDir.exists()) {
      await musicDir.create();
    }
    dbDir = Directory(
      "${mainDirectory.path}${Platform.pathSeparator}dataEngine",
    );
    if (!await dbDir.exists()) {
      await dbDir.create();
    }
    cacheDir = Directory(
      "${appCacheDirectory.path}${Platform.pathSeparator}download",
    );
    if (!await cacheDir.exists()) {
      await cacheDir.create();
    }
    await Hive.initFlutter(dbDir.path);
    Hive.registerAdapters();
    dataEngineForGatewaySetting = await Hive.openBox<GatewaySetting>(
      gatewaySettingBox,
    );
    dataEngineForV2PlayList = await Hive.openBox<NoaPlayerV2PlayList>(
      noaPlayerV2PlayListBox,
    );
  }
}

final yakushiinRuntimeEnvironment = YakushiinRuntimeEnvironment();
