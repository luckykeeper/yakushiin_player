import 'package:hive_ce/hive.dart';
import 'package:yakushiin_player/model/gateway_associate/noa_player_v2_music.dart';
import 'package:yakushiin_player/model/gateway_associate/noa_player_v2_playlist.dart';
import 'package:yakushiin_player/model/gateway_setting.dart';

part 'hive_adapters.g.dart';

@GenerateAdapters([
  AdapterSpec<GatewaySetting>(),
  AdapterSpec<NoaPlayerV2PlayList>(),
  AdapterSpec<NoaPlayerV2Music>(),
])
class HiveAdapters {}
