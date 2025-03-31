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

  GatewaySetting({
    this.id = 0,
    required this.gatewayAddress,
    required this.gatewayToken,
    required this.weatherApiToken,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    // data['gateway_address'] = this.gatewayAddress;
    data['token'] = gatewayToken;
    return data;
  }
}
