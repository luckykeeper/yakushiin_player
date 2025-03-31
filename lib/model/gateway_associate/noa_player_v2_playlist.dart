// yakushiin_player
// @CreateTime    : 2025/03/28 20:48
// @Author        : Luckykeeper
// @Email         : luckykeeper@luckykeeper.site
// @Project       : yakushiin_player

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:yakushiin_player/model/gateway_associate/noa_player_v2_music.dart';

class NoaPlayerV2PlayList extends HiveObject with ChangeNotifier {
  int? id;
  String? playListName;
  List<NoaPlayerV2Music>? musicList;

  NoaPlayerV2PlayList({this.id, this.playListName, this.musicList});

  NoaPlayerV2PlayList.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    playListName = json['playListName'];
    if (json['musicList'] != null) {
      musicList = <NoaPlayerV2Music>[];
      json['musicList'].forEach((v) {
        musicList!.add(NoaPlayerV2Music.fromJson(v));
      });
    }
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    data['playListName'] = playListName;
    if (musicList != null) {
      data['musicList'] = musicList!.map((v) => v.toJson()).toList();
    }
    return data;
  }
}

final currentPlayList = ChangeNotifierProvider<NoaPlayerV2PlayList>((ref) {
  return NoaPlayerV2PlayList();
});
