// yakushiin_player
// @CreateTime    : 2025/03/28 23:52
// @Author        : Luckykeeper
// @Email         : luckykeeper@luckykeeper.site
// @Project       : yakushiin_player

import 'dart:async';
import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yakushiin_player/model/runtime.dart';
import 'package:yakushiin_player/model/yakushiin_background_downloader.dart';
import 'package:yakushiin_player/model/yakushiin_logger.dart';
import 'package:yakushiin_player/subfunction/get_total_size_of_files_in_dir.dart';
import 'package:yakushiin_player/theme/font.dart';
import 'package:yakushiin_player/yakushiin_widgets/commin_question_dialog.dart';
import 'package:yakushiin_player/yakushiin_widgets/common_error_dialog.dart';
import 'package:yakushiin_player/yakushiin_widgets/common_success_dialog.dart';
import 'package:yakushiin_player/yakushiin_widgets/sys_info_bar.dart';

class SyncPlayListPage extends StatefulWidget {
  const SyncPlayListPage({super.key});

  @override
  State<SyncPlayListPage> createState() => _SyncPlayListPageState();
}

class _SyncPlayListPageState extends State<SyncPlayListPage> {
  int localMusicCount = 0;
  int localMusicCacheCount = 0;
  String gatewayMusicTotal = "未获取";
  String localCacheSize = "N/a";

  // updateInfo 并发保护：避免并发调用共享计数器叠加导致计数异常
  bool _updatingInfo = false;
  bool _infoUpdatePending = false;

  // 全局后台下载器：离开本页面后下载依旧继续
  final YakushiinBackgroundDownloader yakushiinBackgroundDownloader =
      YakushiinBackgroundDownloader.instance;
  int lastDoneCount = 0;
  bool lastRunning = false;
  bool resultDialogShown = false;

  Future<void> updateInfo() async {
    // 并发保护：只允许一个实例在跑，期间的新请求合并为一次补跑
    if (_updatingInfo) {
      _infoUpdatePending = true;
      return;
    }
    _updatingInfo = true;
    try {
      do {
        _infoUpdatePending = false;
        // 使用局部变量统计，统计完成后一次性赋值，避免中途被 UI 读到半途值
        var totalMusic = 0;
        var cachedMusic = 0;
        if (yakushiinRuntimeEnvironment.dataEngineForV2PlayList.length > 0) {
          try {
            for (
              var i = 0;
              i < yakushiinRuntimeEnvironment.dataEngineForV2PlayList.length;
              i++
            ) {
              var thisList = yakushiinRuntimeEnvironment
                  .dataEngineForV2PlayList
                  .getAt(i);
              if (thisList == null) continue;
              for (var music in thisList.musicList ?? const []) {
                totalMusic++;
                File thisMusicFile = File(
                  "${yakushiinRuntimeEnvironment.musicDir.path}${Platform.pathSeparator}${music.videoMd5}",
                );
                if (await thisMusicFile.exists()) {
                  cachedMusic++;
                }
              }
            }
            setState(() {
              localMusicCount = totalMusic;
              localMusicCacheCount = cachedMusic;
              // 歌单落库后即为网关最新清单，网关数量直接取自数据库
              gatewayMusicTotal = "$totalMusic";
            });
          } catch (e) {
            yakushiinLogger.e("updateInfo 拉取数据库歌单信息失败！异常信息：$e");
          }
        } else {
          setState(() {
            localMusicCount = 0;
            localMusicCacheCount = 0;
            gatewayMusicTotal = "0";
          });
        }

        double localCacheSizeDouble =
            await getTotalSizeOfFilesInDir(yakushiinRuntimeEnvironment.musicDir) /
            1024 /
            1024;
        setState(() {
          localCacheSize = "$localCacheSizeDouble";
        });
      } while (_infoUpdatePending);
    } finally {
      _updatingInfo = false;
    }
  }

  /// 下载器状态变化回调：驱动 UI 刷新 & 文件完成计数刷新缓存统计
  void _onDownloaderChanged() {
    final state = yakushiinBackgroundDownloader.progressNotifier.value;
    if (state.doneCount != lastDoneCount) {
      lastDoneCount = state.doneCount;
      updateInfo();
    }
    // 新一轮同步开始，重置弹窗标记
    if (state.running && !lastRunning) {
      resultDialogShown = false;
    }
    // 流程结束（成功/失败）且页面仍在展示时，弹结果对话框（只弹一次）
    if (!state.running && !resultDialogShown && state.message.isNotEmpty) {
      resultDialogShown = true;
      if (state.success) {
        commonSuccessDialog(
          context,
          "✅全部同步完成",
          "本地歌单已经成功和网关同步啦~",
          "好~",
        );
      } else {
        commonErrorDialog(
          context,
          "⛔同步失败",
          state.message,
          "啊这",
        );
      }
    }
    lastRunning = state.running;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    yakushiinBackgroundDownloader.progressNotifier.addListener(
      _onDownloaderChanged,
    );

    Timer(Duration(milliseconds: 500), () async {
      await updateInfo();
    });
  }

  @override
  void dispose() {
    yakushiinBackgroundDownloader.progressNotifier.removeListener(
      _onDownloaderChanged,
    );
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Size scrSize = MediaQuery.of(context).size;
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          child: Row(
            children: [
              Text("同步歌单", style: styleFontSimkaiBold),
              Expanded(child: Text("")),
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
      body: ListView(
        children: [
          Column(
            children: [
              Row(
                children: [
                  Text(
                    "从网关同步歌单数据ヾ(≧▽≦*)o",
                    style: TextStyle(
                      fontSize: 20,
                      fontFamily: fontSimkaiFamily,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const Divider(),
              systemInfoBar,
              Padding(
                padding: const EdgeInsets.only(top: 28.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          "网关歌曲清单数量：$gatewayMusicTotal",
                          style: TextStyle(
                            fontFamily: "simkai",
                            color: Colors.green[300],
                            overflow: TextOverflow.clip,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          "本地歌曲清单数量：$localMusicCount",
                          style: TextStyle(
                            fontFamily: "simkai",
                            color: Colors.green[300],
                            overflow: TextOverflow.clip,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          "本地已缓存歌曲数量：$localMusicCacheCount",
                          style: TextStyle(
                            fontFamily: "simkai",
                            color: Colors.green[300],
                            overflow: TextOverflow.clip,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          "本地已缓存歌曲占用：$localCacheSize MB",
                          style: TextStyle(
                            fontFamily: "simkai",
                            color: Colors.green[300],
                            overflow: TextOverflow.clip,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          ValueListenableBuilder<YakushiinDownloadState>(
            valueListenable: yakushiinBackgroundDownloader.progressNotifier,
            builder: (context, state, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "当前正在处理歌曲：${state.nowHandlingName}",
                    style: TextStyle(
                      fontFamily: "simkai",
                      color: Colors.green[300],
                      overflow: TextOverflow.clip,
                    ),
                  ),
                  if (state.totalCount > 0)
                    Text(
                      "后台下载进度（音乐+字幕）：${state.doneCount}/${state.totalCount} 个文件",
                      style: TextStyle(
                        fontFamily: "simkai",
                        color: Colors.green[300],
                        overflow: TextOverflow.clip,
                      ),
                    ),
                  if (state.skippedCount > 0)
                    Text(
                      "已跳过网关已删除文件：${state.skippedCount} 个（本地游离文件将在收尾时清理）",
                      style: TextStyle(
                        fontFamily: "simkai",
                        color: Colors.orange[300],
                        overflow: TextOverflow.clip,
                      ),
                    ),
                  if (state.downloadProgress != null)
                    Text(
                      "当前歌曲下载进度👇",
                      style: TextStyle(
                        fontFamily: "simkai",
                        color: Colors.green[300],
                        overflow: TextOverflow.clip,
                      ),
                    ),
                  if (state.downloadProgress != null)
                    LinearProgressIndicator(
                      value: state.downloadProgress,
                      backgroundColor: Colors.pinkAccent,
                    ),
                ],
              );
            },
          ),
          if (localMusicCount != 0 &&
              (localMusicCacheCount / localMusicCount != 1))
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "总体下载进度👇",
                  style: TextStyle(
                    fontFamily: "simkai",
                    color: Colors.green[300],
                    overflow: TextOverflow.clip,
                  ),
                ),
              ],
            ),
          if (localMusicCount != 0 &&
              (localMusicCacheCount / localMusicCount != 1))
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: localMusicCacheCount / localMusicCount,
                  backgroundColor: Colors.pinkAccent,
                ),
              ],
            ),
          Container(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text("拉取歌单并同步到本地", style: styleFontSimkai),
                  ),
                  onPressed: () async {
                    // 后台下载：交由全局下载器执行，离开页面 / 退到后台均可继续下载
                    if (yakushiinBackgroundDownloader.isRunning) {
                      BotToast.showSimpleNotification(
                        duration: const Duration(seconds: 2),
                        hideCloseButton: false,
                        backgroundColor: Colors.yellow,
                        title: "⚠已有同步任务正在进行中，请等待完成！",
                        titleStyle: styleFontSimkai,
                      );
                      return;
                    }
                    BotToast.showSimpleNotification(
                      duration: const Duration(seconds: 3),
                      hideCloseButton: false,
                      backgroundColor: Colors.green[300],
                      title: "✅开始同步！支持后台下载，可离开此页面边听歌边下载~",
                      titleStyle: styleFontSimkai,
                    );
                    await yakushiinBackgroundDownloader.startSync();
                  },
                ),
              ),
            ],
          ),
          Container(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text("清空视频缓存", style: styleFontSimkai),
                  ),
                  onPressed: () async {
                    commonQuestionDialog(
                      context,
                      "确定要清空所有本地缓存吗？",
                      [
                        Row(
                          children: [
                            Text("请注意此操作是不可撤销的！", style: styleFontSimkai),
                          ],
                        ),
                      ],
                      "我再想想",
                      "确定删除",
                      interactiveFunction: () async {
                        try {
                          await yakushiinRuntimeEnvironment
                              .dataEngineForV2PlayList
                              .clear();
                          if (await yakushiinRuntimeEnvironment.musicDir
                              .exists()) {
                            await yakushiinRuntimeEnvironment.musicDir.delete(
                              recursive: true,
                            );
                          }
                          if (!await yakushiinRuntimeEnvironment.musicDir
                              .exists()) {
                            await yakushiinRuntimeEnvironment.musicDir.create(
                              recursive: true,
                            );
                          }
                          BotToast.showSimpleNotification(
                            duration: const Duration(seconds: 2),
                            hideCloseButton: false,
                            backgroundColor: Colors.green[300],
                            title: "✅缓存清理完成！",
                            titleStyle: styleFontSimkai,
                          );
                          await updateInfo();
                          commonSuccessDialog(
                            context,
                            "✅缓存清理完成",
                            "本地缓存已经清理",
                            "好~",
                          );
                        } catch (e) {
                          BotToast.showSimpleNotification(
                            duration: const Duration(seconds: 2),
                            hideCloseButton: false,
                            backgroundColor: Colors.pink[200],
                            title: "⛔缓存清理失败:$e",
                            titleStyle: styleFontSimkai,
                          );
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
