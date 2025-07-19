// yakushiin_player
// @CreateTime    : 2025/03/28 23:52
// @Author        : Luckykeeper
// @Email         : luckykeeper@luckykeeper.site
// @Project       : yakushiin_player

import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yakushiin_player/model/gateway_associate/noa_player_v2_msg.dart';
import 'package:yakushiin_player/model/gateway_associate/noa_player_v2_playlist.dart';
import 'package:yakushiin_player/model/runtime.dart';
import 'package:yakushiin_player/model/version.dart';
import 'package:yakushiin_player/subfunction/launch_url.dart';
import 'package:yakushiin_player/theme/font.dart';
import 'package:yakushiin_player/yakushiin_widgets/commin_question_dialog.dart';
import 'package:yakushiin_player/yakushiin_widgets/common_error_dialog.dart';
import 'package:yakushiin_player/yakushiin_widgets/sys_info_bar.dart';

class WelcomePage extends ConsumerStatefulWidget {
  const WelcomePage({super.key});

  @override
  ConsumerState<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends ConsumerState<WelcomePage> {
  @override
  void initState() {
    super.initState();
    try {
      FlutterNativeSplash.remove();
    } catch (e) {
      debugPrint("FlutterNativeSplash: $e");
    }
  }

  Future<Future> _goodByeYuuka() async {
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("提示", style: styleFontSimkai),
          content: Text("你确定要退出嘛?", style: styleFontSimkai),
          actions: [
            TextButton(
              onPressed: Navigator.of(context).pop,
              child: Text("取消", style: styleFontSimkai),
            ),
            TextButton(
              onPressed: () {
                if (yakushiinRuntimeEnvironment.isDesktopPlatform) {
                  exit(0);
                } else {
                  // https://github.com/flutter/flutter/issues/66631
                  // 以下方法在移动端生效
                  SystemChannels.platform.invokeListMethod(
                    'SystemNavigator.pop',
                  );
                }
              },
              child: Text("确定", style: styleFontSimkai),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Size scrSize = MediaQuery.of(context).size;
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          child: Row(
            children: [
              Text("Welcome YakushiinPlayer", style: styleFontSimkaiBold),
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
      drawer: SafeArea(
        child: Drawer(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              ListTile(
                leading: const Icon(Icons.sync),
                title: Text("同步", style: styleFontSimkai),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, "/syncPlayList");
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: Text("设置", style: styleFontSimkai),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, "/settings");
                },
              ),
              Flexible(
                child: Container(
                  alignment: Alignment.bottomLeft,
                  child: ListTile(
                    leading: const Icon(Icons.exit_to_app),
                    title: Text("退出", style: styleFontSimkai),
                    onTap: () async {
                      _goodByeYuuka();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        children: [
          Column(
            children: [
              const Row(
                children: [
                  Text(
                    "Welcome YakushiinPlayer",
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
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 28.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () async {
                                  var v2Msg =
                                      await NoaPlayerV2Msg()
                                          .getNoaHandlerVideoListV2();
                                  if (v2Msg.isSuccess) {
                                    List<Widget> playListBtnListWidget = [];
                                    for (
                                      var i = 0;
                                      i < v2Msg.playList!.length;
                                      i++
                                    ) {
                                      var thisList = v2Msg.playList![i];
                                      playListBtnListWidget.add(
                                        ElevatedButton.icon(
                                          onPressed: () async {
                                            for (var music
                                                in thisList.musicList!) {
                                              music.videoMd5 = music.videoUrl!;
                                              music.subTitleMd5 =
                                                  music.subTitleUrl!;
                                            }
                                            ref.read(currentPlayList).id =
                                                thisList.id;
                                            ref
                                                .read(currentPlayList)
                                                .musicList = thisList.musicList;
                                            ref
                                                    .read(currentPlayList)
                                                    .playListName =
                                                thisList.playListName;
                                            Navigator.pop(context);
                                            Navigator.pushNamed(
                                              context,
                                              "/yakushiinPlayer",
                                            );
                                          },
                                          label: Text(
                                            "${thisList.playListName}",
                                            style: styleFontSimkaiBold,
                                          ),
                                          icon: Icon(
                                            Icons.playlist_play_rounded,
                                          ),
                                        ),
                                      );
                                    }
                                    commonQuestionDialog(
                                      context,
                                      "网关播放列表获取成功，请选择",
                                      playListBtnListWidget,
                                      "",
                                      "取消播放",
                                      doNotShowCancelText: true,
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
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Text(
                                    "从网关拉取数据在线播放（需要联网登录）",
                                    style: styleFontSimkai,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Container(height: scrSize.height / 60),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Text(
                                    "从本地拉取数据离线播放（需要先同步）",
                                    style: styleFontSimkai,
                                  ),
                                ),
                                onPressed: () async {
                                  if (yakushiinRuntimeEnvironment
                                          .dataEngineForV2PlayList
                                          .length >
                                      0) {
                                    List<Widget> playListBtnListWidget = [];
                                    for (
                                      var i = 0;
                                      i <
                                          yakushiinRuntimeEnvironment
                                              .dataEngineForV2PlayList
                                              .length;
                                      i++
                                    ) {
                                      var thisList = yakushiinRuntimeEnvironment
                                          .dataEngineForV2PlayList
                                          .getAt(i);
                                      if (thisList != null) {
                                        playListBtnListWidget.add(
                                          ElevatedButton.icon(
                                            onPressed: () async {
                                              ref.read(currentPlayList).id =
                                                  thisList.id;
                                              ref
                                                      .read(currentPlayList)
                                                      .musicList =
                                                  thisList.musicList;
                                              ref
                                                      .read(currentPlayList)
                                                      .playListName =
                                                  thisList.playListName;
                                              Navigator.pop(context);
                                              Navigator.pushNamed(
                                                context,
                                                "/yakushiinPlayer",
                                              );
                                            },
                                            label: Text(
                                              "${thisList.playListName}",
                                              style: styleFontSimkaiBold,
                                            ),
                                            icon: Icon(
                                              Icons.playlist_play_rounded,
                                            ),
                                          ),
                                        );
                                      }
                                    }
                                    commonQuestionDialog(
                                      context,
                                      "本地播放列表获取成功，请选择",
                                      playListBtnListWidget,
                                      "",
                                      "取消播放",
                                      doNotShowCancelText: true,
                                    );
                                  } else {
                                    BotToast.showSimpleNotification(
                                      duration: const Duration(seconds: 2),
                                      hideCloseButton: false,
                                      backgroundColor: Colors.yellow[200],
                                      title: "⚠本地播放列表为空，请先同步",
                                      titleStyle: styleFontSimkai,
                                    );
                                  }
                                  // var result = await NoaHandlerVideoList()
                                  //     .getLocalVideoList();
                                  // if (result.isSuccess) {
                                  //   ref.read(currentPlayList).isSuccess =
                                  //       result.isSuccess;
                                  //   ref.read(currentPlayList).statusCode =
                                  //       result.statusCode;
                                  //   ref.read(currentPlayList).statusString =
                                  //       result.statusString;
                                  //   ref.read(currentPlayList).videoList =
                                  //       result.videoList;

                                  // } else {
                                  //   BotToast.showSimpleNotification(
                                  //       duration: const Duration(seconds: 2),
                                  //       hideCloseButton: false,
                                  //       backgroundColor: Colors.pink[200],
                                  //       title:
                                  //           "⛔获取本地播放列表失败，原因是：${result.statusString}",
                                  //       titleStyle: styleFontLxwk);
                                  // }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Container(height: scrSize.height / 30),
              Builder(
                builder: (context) {
                  if (yakushiinRuntimeEnvironment.isDesktopPlatform) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          "assets/images/Yakushiin-fit-0.75x.png",
                          width: scrSize.width / 2,
                        ),
                      ],
                    );
                  } else {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          "assets/images/Yakushiin-fit-0.75x.png",
                          width: scrSize.width / 2,
                        ),
                      ],
                    );
                  }
                },
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text("↑大小姐可爱捏", style: styleFontSimkai),
                  Container(height: 20),
                  Text(
                    "Welcome YakushiinPlayer, 艾玛酱音乐播放器 ${appVersion}_$buildTime | Powered by Luckykeeper",
                    style: styleFontSimkai,
                  ),
                  Container(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(width: 20),
                      ElevatedButton.icon(
                        onPressed: () async {
                          try {
                            await launchUrlWithBrowser(
                              "https://github.com/luckykeeper",
                            );
                          } catch (e) {
                            BotToast.showSimpleNotification(
                              duration: const Duration(seconds: 2),
                              hideCloseButton: false,
                              backgroundColor: Colors.pink[300],
                              title: "链接打开失败:$e",
                              titleStyle: styleFontSimkai,
                            );
                          }
                        },
                        label: Text("Github", style: styleFontSimkai),
                        icon: const FaIcon(FontAwesomeIcons.github),
                      ),
                      Container(width: 20),
                      ElevatedButton.icon(
                        onPressed: () async {
                          try {
                            await launchUrlWithBrowser(
                              "https://luckykeeper.site",
                            );
                          } catch (e) {
                            BotToast.showSimpleNotification(
                              duration: const Duration(seconds: 2),
                              hideCloseButton: false,
                              backgroundColor: Colors.pink[300],
                              title: "链接打开失败:$e",
                              titleStyle: styleFontSimkai,
                            );
                          }
                        },
                        label: Text("Blog", style: styleFontSimkai),
                        icon: const FaIcon(FontAwesomeIcons.blog),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
