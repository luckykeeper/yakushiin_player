// yakushiin_player
// @CreateTime    : 2025/03/28 23:52
// @Author        : Luckykeeper
// @Email         : luckykeeper@luckykeeper.site
// @Project       : yakushiin_player

import 'dart:async';
import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yakushiin_player/model/gateway_associate/noa_player_v2_msg.dart';
import 'package:yakushiin_player/model/runtime.dart';
import 'package:yakushiin_player/model/version.dart';
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
  String nowHandlingName = "N/a";
  String gatewayMusicTotal = "未获取";
  String localCacheSize = "N/a";
  double? downloadProgress;

  updateInfo() async {
    if (yakushiinRuntimeEnvironment.dataEngineForV2PlayList.length > 0) {
      try {
        NoaPlayerV2Msg localPlayList = NoaPlayerV2Msg(playList: []);
        for (
          var i = 0;
          i < yakushiinRuntimeEnvironment.dataEngineForV2PlayList.length;
          i++
        ) {
          var thisList = yakushiinRuntimeEnvironment.dataEngineForV2PlayList
              .getAt(i);
          if (thisList != null) {
            localPlayList.playList!.add(thisList);
          }
        }
        var gatewayMusicTotal = 0;
        localMusicCacheCount = 0;
        for (var playList in localPlayList.playList!) {
          for (var i = 0; i < playList.musicList!.length; i++) {
            gatewayMusicTotal++;
            File thisMusicFile = File(
              "${yakushiinRuntimeEnvironment.musicDir.path}${Platform.pathSeparator}${playList.musicList![i].videoMd5}",
            );
            if (await thisMusicFile.exists()) {
              localMusicCacheCount++;
            }
          }
        }
        localMusicCount = gatewayMusicTotal;
        setState(() {});
      } catch (e) {
        yakushiinLogger.e("initState 拉取数据库歌单信息失败！异常信息：$e");
      }
    } else {
      setState(() {
        localMusicCount = 0;
        localMusicCacheCount = 0;
      });
    }

    double localCacheSizeDouble =
        await getTotalSizeOfFilesInDir(yakushiinRuntimeEnvironment.musicDir) /
        1024 /
        1024;
    setState(() {
      localCacheSize = "$localCacheSizeDouble";
    });
  }

  Future<NoaPlayerV2Msg> downloadMusicInUI(String url, String md5) async {
    yakushiinLogger.i("下载文件:$url<=>>$md5 开始");
    var result = NoaPlayerV2Msg();
    final yakushiinRequestClient = Dio();
    try {
      if (!await yakushiinRuntimeEnvironment.cacheDir.exists()) {
        await yakushiinRuntimeEnvironment.cacheDir.create();
      }
      File downloadCacheFile = File(
        "${yakushiinRuntimeEnvironment.cacheDir.path}${Platform.pathSeparator}$md5",
      );
      yakushiinLogger.i("目标位置:${downloadCacheFile.path}");
      if (await downloadCacheFile.exists()) {
        yakushiinLogger.i("删除缓存文件夹内的未完成缓存文件:${downloadCacheFile.path}");
        await downloadCacheFile.delete();
      }
      await yakushiinRequestClient.download(
        url,
        "${yakushiinRuntimeEnvironment.cacheDir.path}${Platform.pathSeparator}$md5",
        queryParameters: yakushininPlayerUserAgentMap,
        onReceiveProgress: (int received, int total) async {
          setState(() {
            downloadProgress = received / total;
          });
        },
      );
      setState(() {
        downloadProgress = null;
      });
      if (!await yakushiinRuntimeEnvironment.musicDir.exists()) {
        await yakushiinRuntimeEnvironment.musicDir.create();
      }

      await downloadCacheFile.copy(
        "${yakushiinRuntimeEnvironment.musicDir.path}${Platform.pathSeparator}$md5",
      );

      await downloadCacheFile.delete();
    } catch (e) {
      result.isSuccess = false;
      result.statusMessage = "下载失败：$e";
      yakushiinLogger.e("下载文件:$url<=>>$md5 失败:$e");
      return result;
    }
    result.isSuccess = true;
    result.statusMessage = "下载完成";
    yakushiinLogger.i("下载文件:$url<=>>$md5 完成");
    return result;
  }

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();

    Timer(Duration(milliseconds: 500), () async {
      await updateInfo();
    });
  }

  @override
  void dispose() {
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "当前正在处理歌曲：$nowHandlingName",
                style: TextStyle(
                  fontFamily: "simkai",
                  color: Colors.green[300],
                  overflow: TextOverflow.clip,
                ),
              ),
            ],
          ),
          if (downloadProgress != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "当前歌曲下载进度👇",
                  style: TextStyle(
                    fontFamily: "simkai",
                    color: Colors.green[300],
                    overflow: TextOverflow.clip,
                  ),
                ),
              ],
            ),
          if (downloadProgress != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: downloadProgress,
                  backgroundColor: Colors.pinkAccent,
                ),
              ],
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
                    var v2Msg =
                        await NoaPlayerV2Msg().getNoaHandlerVideoListV2();
                    if (v2Msg.isSuccess) {
                      var gatewayMusicTotalInt = 0;
                      for (var playList in v2Msg.playList!) {
                        for (var i = 0; i < playList.musicList!.length; i++) {
                          gatewayMusicTotalInt++;
                        }
                      }
                      setState(() {
                        gatewayMusicTotal = "$gatewayMusicTotalInt";
                      });
                      BotToast.showSimpleNotification(
                        duration: const Duration(seconds: 2),
                        hideCloseButton: false,
                        backgroundColor: Colors.green[300],
                        title: "✅从网关拉取歌单信息成功！即将开始下载，请不要退出此页面！",
                        titleStyle: styleFontSimkai,
                      );
                      await yakushiinRuntimeEnvironment.dataEngineForV2PlayList
                          .clear();
                      for (var i = 0; i < v2Msg.playList!.length; i++) {
                        await yakushiinRuntimeEnvironment
                            .dataEngineForV2PlayList
                            .add(v2Msg.playList![i]);
                        for (var music in v2Msg.playList![i].musicList!) {
                          try {
                            setState(() {
                              nowHandlingName = "【音乐】：=> ${music.videoName}";
                            });
                            var thisMusicVideoFile = File(
                              "${yakushiinRuntimeEnvironment.musicDir.path}${Platform.pathSeparator}${music.videoMd5}",
                            );
                            if (!await thisMusicVideoFile.exists()) {
                              // 不存在，下载，存在，不操作
                              var downloadResult = await downloadMusicInUI(
                                "${music.videoUrl}",
                                "${music.videoMd5}",
                              );
                              if (!downloadResult.isSuccess) {
                                yakushiinLogger.e(
                                  "⛔同步歌单：下载失败（歌曲）:${downloadResult.statusMessage}",
                                );
                                BotToast.showSimpleNotification(
                                  duration: const Duration(seconds: 2),
                                  hideCloseButton: false,
                                  backgroundColor: Colors.pink[200],
                                  title:
                                      "⛔同步歌单：下载失败（歌曲）:${downloadResult.statusMessage}",
                                  titleStyle: styleFontSimkai,
                                );
                                setState(() {
                                  nowHandlingName =
                                      "⛔同步歌单：下载失败（歌曲）:${downloadResult.statusMessage}";
                                });
                                return;
                              }
                              await updateInfo();
                            }

                            if (music.subTitleMd5 != null &&
                                music.subTitleMd5!.isNotEmpty) {
                              setState(() {
                                nowHandlingName =
                                    "【字幕】：=> ${music.videoName}-${music.subTitleName}";
                              });
                              var thisMusicSubTitleFile = File(
                                "${yakushiinRuntimeEnvironment.musicDir.path}${Platform.pathSeparator}${music.subTitleMd5}",
                              );
                              if (!await thisMusicSubTitleFile.exists()) {
                                // 不存在，下载，存在，不操作
                                var downloadResult = await downloadMusicInUI(
                                  "${music.subTitleUrl}",
                                  "${music.subTitleMd5}",
                                );
                                if (!downloadResult.isSuccess) {
                                  yakushiinLogger.e(
                                    "⛔同步歌单：下载失败（字幕）:${downloadResult.statusMessage}",
                                  );
                                  BotToast.showSimpleNotification(
                                    duration: const Duration(seconds: 2),
                                    hideCloseButton: false,
                                    backgroundColor: Colors.pink[200],
                                    title:
                                        "⛔同步歌单：下载失败（字幕）:${downloadResult.statusMessage}",
                                    titleStyle: styleFontSimkai,
                                  );
                                  setState(() {
                                    nowHandlingName =
                                        "⛔同步歌单：下载失败（字幕）:${downloadResult.statusMessage}";
                                  });
                                  return;
                                }
                                await updateInfo();
                              }
                            }
                          } catch (e) {
                            yakushiinLogger.e("⛔同步歌单：下载失败:$e");
                            BotToast.showSimpleNotification(
                              duration: const Duration(seconds: 2),
                              hideCloseButton: false,
                              backgroundColor: Colors.pink[200],
                              title: "⛔同步歌单：下载失败:$e",
                              titleStyle: styleFontSimkai,
                            );
                            break;
                          }
                        }
                      }
                      // 清空缓存文件夹
                      if (!await yakushiinRuntimeEnvironment.cacheDir
                          .exists()) {
                        await yakushiinRuntimeEnvironment.cacheDir.delete(
                          recursive: true,
                        );
                        await yakushiinRuntimeEnvironment.cacheDir.create();
                      }
                      // 清空没有 md5 索引的文件
                      var matchMusicMd5Count = 0;
                      var matchSubTitleMd5Count = 0;
                      var matchDeleteCount = 0;
                      var files =
                          yakushiinRuntimeEnvironment.musicDir.listSync();
                      for (var file in files) {
                        if (file is File && await file.exists()) {
                          var md5Matched = false;
                          for (var playList in v2Msg.playList!) {
                            for (
                              var i = 0;
                              i < playList.musicList!.length;
                              i++
                            ) {
                              if (file.path ==
                                  "${yakushiinRuntimeEnvironment.musicDir.path}${Platform.pathSeparator}${playList.musicList![i].videoMd5!}") {
                                // yakushiinLogger.d("检查索引=>音乐文件匹配：${file.path}");
                                matchMusicMd5Count++;
                                md5Matched = true;
                                break;
                              }
                              if (file.path ==
                                  "${yakushiinRuntimeEnvironment.musicDir.path}${Platform.pathSeparator}${playList.musicList![i].subTitleMd5!}") {
                                // yakushiinLogger.d("检查索引=>字幕文件匹配：${file.path}");
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
                      updateInfo();
                      setState(() {
                        nowHandlingName = "全部处理完成!";
                      });
                      BotToast.showSimpleNotification(
                        duration: const Duration(seconds: 2),
                        hideCloseButton: false,
                        backgroundColor: Colors.green[300],
                        title: "✅全部同步完成！",
                        titleStyle: styleFontSimkai,
                      );
                      commonSuccessDialog(
                        context,
                        "✅全部同步完成",
                        "本地歌单已经成功和网关同步啦~",
                        "好~",
                      );
                    } else {
                      BotToast.showSimpleNotification(
                        duration: const Duration(seconds: 2),
                        hideCloseButton: false,
                        backgroundColor: Colors.pink[200],
                        title:
                            "⛔从网关拉取歌单信息失败！服务器返回：${v2Msg.statusCode} | ${v2Msg.statusMessage}",
                        titleStyle: styleFontSimkai,
                      );
                      commonErrorDialog(
                        context,
                        "⛔从网关拉取歌单信息失败！",
                        "服务器返回：${v2Msg.statusCode} | ${v2Msg.statusMessage}",
                        "啊这",
                      );
                    }
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
                          await yakushiinRuntimeEnvironment.musicDir.delete(
                            recursive: true,
                          );
                          BotToast.showSimpleNotification(
                            duration: const Duration(seconds: 2),
                            hideCloseButton: false,
                            backgroundColor: Colors.green[300],
                            title: "✅缓存清理完成！",
                            titleStyle: styleFontSimkai,
                          );
                          updateInfo();
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
