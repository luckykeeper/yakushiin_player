// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hive_adapters.dart';

// **************************************************************************
// AdaptersGenerator
// **************************************************************************

class GatewaySettingAdapter extends TypeAdapter<GatewaySetting> {
  @override
  final int typeId = 0;

  @override
  GatewaySetting read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return GatewaySetting(
      id: fields[0] == null ? 0 : (fields[0] as num).toInt(),
      gatewayAddress: fields[1] as String,
      gatewayToken: fields[2] as String,
      weatherApiToken: fields[3] as String,
    );
  }

  @override
  void write(BinaryWriter writer, GatewaySetting obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.gatewayAddress)
      ..writeByte(2)
      ..write(obj.gatewayToken)
      ..writeByte(3)
      ..write(obj.weatherApiToken);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GatewaySettingAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class NoaPlayerV2PlayListAdapter extends TypeAdapter<NoaPlayerV2PlayList> {
  @override
  final int typeId = 1;

  @override
  NoaPlayerV2PlayList read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return NoaPlayerV2PlayList(
      id: (fields[0] as num?)?.toInt(),
      playListName: fields[1] as String?,
      musicList: (fields[2] as List?)?.cast<NoaPlayerV2Music>(),
    );
  }

  @override
  void write(BinaryWriter writer, NoaPlayerV2PlayList obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.playListName)
      ..writeByte(2)
      ..write(obj.musicList);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoaPlayerV2PlayListAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class NoaPlayerV2MusicAdapter extends TypeAdapter<NoaPlayerV2Music> {
  @override
  final int typeId = 2;

  @override
  NoaPlayerV2Music read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return NoaPlayerV2Music(
      id: (fields[0] as num?)?.toInt(),
      playListID: (fields[1] as num?)?.toInt(),
      videoName: fields[2] as String?,
      videoUrl: fields[3] as String?,
      videoShareUrl: fields[4] as String?,
      videoMd5: fields[5] as String?,
      subTitleName: fields[6] as String?,
      subTitleUrl: fields[7] as String?,
      subTitleLang: fields[8] as String?,
      subTitleMd5: fields[9] as String?,
    )..nowPlaying = fields[10] as bool;
  }

  @override
  void write(BinaryWriter writer, NoaPlayerV2Music obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.playListID)
      ..writeByte(2)
      ..write(obj.videoName)
      ..writeByte(3)
      ..write(obj.videoUrl)
      ..writeByte(4)
      ..write(obj.videoShareUrl)
      ..writeByte(5)
      ..write(obj.videoMd5)
      ..writeByte(6)
      ..write(obj.subTitleName)
      ..writeByte(7)
      ..write(obj.subTitleUrl)
      ..writeByte(8)
      ..write(obj.subTitleLang)
      ..writeByte(9)
      ..write(obj.subTitleMd5)
      ..writeByte(10)
      ..write(obj.nowPlaying);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoaPlayerV2MusicAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
