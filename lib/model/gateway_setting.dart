// yakushiin_player
// @CreateTime    : 2025/03/28 20:28
// @Author        : Luckykeeper
// @Email         : luckykeeper@luckykeeper.site
// @Project       : yakushiin_player

import 'package:hive_ce/hive.dart';

class GatewaySetting extends HiveObject {
  int id;
  String gatewayAddress;
  String gatewayToken;
  String weatherApiToken;
  bool tvMode;

  /// Anime4K 超分模式：off / A_HQ / B_HQ / C_HQ / A_Fast / B_Fast / C_Fast
  String anime4kMode;

  GatewaySetting({
    this.id = 0,
    required this.gatewayAddress,
    required this.gatewayToken,
    required this.weatherApiToken,
    this.tvMode = false,
    this.anime4kMode = "off",
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    // data['gateway_address'] = this.gatewayAddress;
    data['token'] = gatewayToken;
    return data;
  }
}
