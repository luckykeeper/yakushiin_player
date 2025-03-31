// yakushiin_player
// @CreateTime    : 2025/03/28 23:52
// @Author        : Luckykeeper
// @Email         : luckykeeper@luckykeeper.site
// @Project       : yakushiin_player

import 'dart:async';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yakushiin_player/model/gateway_setting.dart';
import 'package:yakushiin_player/model/runtime.dart';
import 'package:yakushiin_player/model/yakushiin_logger.dart';
import 'package:yakushiin_player/theme/font.dart';
import 'package:yakushiin_player/yakushiin_widgets/sys_info_bar.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  TextEditingController gatewayAddressController = TextEditingController();
  TextEditingController gatewayTokenController = TextEditingController();
  TextEditingController weatherApiTokenController = TextEditingController();
  final GlobalKey _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();

    Timer(Duration(milliseconds: 1), () async {
      try {
        setState(() {
          gatewayAddressController.text =
              "${yakushiinRuntimeEnvironment.dataEngineForGatewaySetting.getAt(0)?.gatewayAddress}";
          gatewayTokenController.text =
              "${yakushiinRuntimeEnvironment.dataEngineForGatewaySetting.getAt(0)?.gatewayToken}";
          weatherApiTokenController.text =
              "${yakushiinRuntimeEnvironment.dataEngineForGatewaySetting.getAt(0)?.weatherApiToken}";
        });
      } catch (e) {
        yakushiinLogger.e("initState 拉取网关配置失败或尚未配置过网关信息！异常信息：$e");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Size scrSize = MediaQuery.of(context).size;
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          child: Row(
            children: [
              Text("设置", style: styleFontSimkaiBold),
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
              const Row(
                children: [
                  Text(
                    "设置网关连接参数ヾ(≧▽≦*)o",
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
              Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  children: [
                    TextFormField(
                      controller: gatewayAddressController,
                      decoration: InputDecoration(
                        labelText: "网关地址",
                        labelStyle: styleFontSimkai,
                        hintText: "请输入 noaHandler 或兼容网关的地址",
                        hintStyle: styleFontSimkai,
                        errorStyle: styleFontSimkai,
                        helperStyle: styleFontSimkai,
                        icon: Icon(Icons.api),
                      ),
                      validator: (v) {
                        return v!.trim().isNotEmpty ? null : "网关地址不能为空";
                      },
                    ),
                    TextFormField(
                      controller: gatewayTokenController,
                      decoration: InputDecoration(
                        labelText: "Token",
                        labelStyle: styleFontSimkai,
                        hintText: "网关通信 Token",
                        hintStyle: styleFontSimkai,
                        errorStyle: styleFontSimkai,
                        helperStyle: styleFontSimkai,
                        icon: Icon(Icons.lock),
                      ),
                      obscureText: true,
                      validator: (v) {
                        return v!.trim().length > 5 ? null : "token 长度过短";
                      },
                    ),
                    TextFormField(
                      controller: weatherApiTokenController,
                      decoration: InputDecoration(
                        labelText: "天气服务 API Key",
                        labelStyle: styleFontSimkai,
                        hintText: "OpenWeatherMap 的 Api Key 可不设置，此时无法使用天气功能",
                        hintStyle: styleFontSimkai,
                        errorStyle: styleFontSimkai,
                        helperStyle: styleFontSimkai,
                        icon: Icon(Icons.api_rounded),
                      ),
                      obscureText: true,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 28.0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Text(
                                      "保存网关数据到数据库",
                                      style: styleFontSimkai,
                                    ),
                                  ),
                                  onPressed: () async {
                                    if ((_formKey.currentState as FormState)
                                        .validate()) {
                                      try {
                                        await yakushiinRuntimeEnvironment
                                            .dataEngineForGatewaySetting
                                            .clear();
                                        await yakushiinRuntimeEnvironment
                                            .dataEngineForGatewaySetting
                                            .add(
                                              GatewaySetting(
                                                gatewayAddress:
                                                    gatewayAddressController
                                                        .text,
                                                gatewayToken:
                                                    gatewayTokenController.text,
                                                weatherApiToken:
                                                    weatherApiTokenController
                                                        .text,
                                              ),
                                            );
                                        BotToast.showSimpleNotification(
                                          duration: const Duration(seconds: 2),
                                          hideCloseButton: false,
                                          backgroundColor: Colors.green[300],
                                          title: "✅更新网关配置信息成功！",
                                          titleStyle: styleFontSimkai,
                                        );
                                      } catch (e) {
                                        yakushiinLogger.e(
                                          "更新数据库网关信息失败！异常信息：$e",
                                        );
                                        BotToast.showSimpleNotification(
                                          duration: const Duration(seconds: 2),
                                          hideCloseButton: false,
                                          backgroundColor: Colors.pink[200],
                                          title: "⛔更新网关配置信息失败！异常信息：$e",
                                          titleStyle: styleFontSimkai,
                                        );
                                      }
                                    }
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
              ),
            ],
          ),
        ],
      ),
    );
  }
}
