// yakushiin_player
// @CreateTime    : 2025/03/28 20:48
// @Author        : Luckykeeper
// @Email         : luckykeeper@luckykeeper.site
// @Project       : yakushiin_player

import 'package:hive_ce/hive.dart';

class NoaPlayerV2Music extends HiveObject {
  int? id;
  int? playListID;
  String? videoName;
  String? videoUrl;
  String? videoShareUrl;
  String? videoMd5;
  String? subTitleName;
  String? subTitleUrl;
  String? subTitleLang;
  String? subTitleMd5;
  bool nowPlaying = false;

  NoaPlayerV2Music({
    this.id,
    this.playListID,
    this.videoName,
    this.videoUrl,
    this.videoShareUrl,
    this.videoMd5,
    this.subTitleName,
    this.subTitleUrl,
    this.subTitleLang,
    this.subTitleMd5,
  });

  NoaPlayerV2Music.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    playListID = json['playListID'];
    videoName = json['videoName'];
    videoUrl = json['videoUrl'];
    videoShareUrl = json['videoShareUrl'];
    videoMd5 = json['videoMd5'];
    subTitleName = json['subTitleName'];
    subTitleUrl = json['subTitleUrl'];
    subTitleLang = json['subTitleLang'];
    subTitleMd5 = json['subTitleMd5'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    data['playListID'] = playListID;
    data['videoName'] = videoName;
    data['videoUrl'] = videoUrl;
    data['videoShareUrl'] = videoShareUrl;
    data['videoMd5'] = videoMd5;
    data['subTitleName'] = subTitleName;
    data['subTitleUrl'] = subTitleUrl;
    data['subTitleLang'] = subTitleLang;
    data['subTitleMd5'] = subTitleMd5;
    return data;
  }
}
