// yakushiin_player
// @CreateTime    : 2025/03/28 20:48
// @Author        : Luckykeeper
// @Email         : luckykeeper@luckykeeper.site
// @Project       : yakushiin_player

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:yakushiin_player/model/gateway_associate/noa_player_v2_playlist.dart';
import 'package:yakushiin_player/model/runtime.dart';
import 'package:yakushiin_player/model/version.dart';
import 'package:yakushiin_player/model/yakushiin_logger.dart';

class NoaPlayerV2Msg {
  String? token;
  int? statusCode;
  String? statusMessage;
  List<NoaPlayerV2PlayList>? playList;
  bool isSuccess = false;

  NoaPlayerV2Msg({
    this.token,
    this.statusCode,
    this.statusMessage,
    this.playList,
  });

  NoaPlayerV2Msg.fromJson(Map<String, dynamic> json) {
    token = json['token'];
    statusCode = json['statusCode'];
    statusMessage = json['statusMessage'];
    if (json['playList'] != null) {
      playList = <NoaPlayerV2PlayList>[];
      json['playList'].forEach((v) {
        playList!.add(NoaPlayerV2PlayList.fromJson(v));
      });
    }
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['token'] = token;
    data['statusCode'] = statusCode;
    data['statusMessage'] = statusMessage;
    if (playList != null) {
      data['playList'] = playList!.map((v) => v.toJson()).toList();
    }
    return data;
  }

  Future<NoaPlayerV2Msg> getNoaHandlerVideoListV2() async {
    isSuccess = false;
    var gatewayInfo = yakushiinRuntimeEnvironment.dataEngineForGatewaySetting
        .getAt(0);
    if (gatewayInfo == null ||
        gatewayInfo.gatewayAddress.isEmpty ||
        gatewayInfo.gatewayToken.isEmpty) {
      statusCode = 401;
      statusMessage = "没有设置网关信息，必须先设置网关信息！";
      return this;
    }
    try {
      final yakushiinRequestClient = Dio();
      var response = await yakushiinRequestClient.post<String>(
        gatewayInfo.gatewayAddress,
        data: gatewayInfo.toJson(),
        options: Options(
          headers: {HttpHeaders.userAgentHeader: yakushininPlayerUserAgent},
        ),
      );
      if (response.statusCode == 200) {
        var status = NoaPlayerV2Msg.fromJson(jsonDecode(response.data!));
        if (status.statusCode == 200) {
          isSuccess = true;
          statusMessage = status.statusMessage;
          statusCode = status.statusCode;
          playList = status.playList;
        } else {
          isSuccess = false;
          statusMessage = status.statusMessage;
          statusCode = status.statusCode;
        }
      } else {
        isSuccess = false;
        statusMessage = response.statusMessage;
        statusCode = response.statusCode;
      }
    } catch (e) {
      yakushiinLogger.e("⛔网关交互失败:$e");
      isSuccess = false;
      statusMessage = "N/A | ${gatewayInfo.gatewayAddress} | $e";
      return this;
    }
    return this;
  }
}
