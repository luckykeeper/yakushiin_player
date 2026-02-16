// yakushiin_player
// @CreateTime    : 2026/02/15 23:05
// @Author        : Luckykeeper
// @Email         : luckykeeper@luckykeeper.site
// @Project       : yakushiin_player

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:yakushiin_player/model/yakushiin_logger.dart';

late MediaKitAudioHandler yakushiinBackgroundPlayerHandler;

class MediaKitAudioHandler extends BaseAudioHandler {
  // 可被页面设置的回调
  Future<void> Function()? onPlay;
  Future<void> Function()? onPause;
  Future<void> Function()? onNext;
  Future<void> Function()? onPrevious;
  Future<void> Function()? onStop;
  Future<void> Function(Duration position)? onSeek; // 注意参数
  Future<void> Function(AudioServiceRepeatMode mode)? onSetRepeatMode;
  Future<void> Function(double volume)? onSetVolume;
  // 无需创建 Player

  @override
  Future<void> play() async {
    yakushiinLogger.i("AudioServcies => play!");
    if (onPlay != null) await onPlay!();
  }

  @override
  Future<void> pause() async {
    // 国产安卓暂停后无法在通知栏继续播放，底层 api 的问题，如果想修，需要 fork 源码改
    // https://github.com/ryanheise/audio_service/issues/1115
    yakushiinLogger.i("AudioServcies => pause!");
    if (onPause != null) await onPause!();
  }

  @override
  Future<void> skipToNext() async {
    yakushiinLogger.i("AudioServcies => skipToNext!");
    if (onNext != null) await onNext!();
  }

  @override
  Future<void> skipToPrevious() async {
    yakushiinLogger.i("AudioServcies => skipToPrevious!");
    if (onPrevious != null) await onPrevious!();
  }

  @override
  Future<void> stop() async {
    yakushiinLogger.i("AudioServcies => stop!");
    if (onStop != null) await onStop!();
    // 停止后可能需要更新状态
  }

  @override
  Future<void> seek(Duration position) async {
    yakushiinLogger.i("AudioServcies => seek!");
    if (onSeek != null) await onSeek!(position);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    yakushiinLogger.i("AudioServcies => setRepeatMode!");
    if (onSetRepeatMode != null) await onSetRepeatMode!(repeatMode);
    // 更新 playbackState 中的 repeatMode
    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
  }

  // 可选：自定义方法供页面更新播放状态
  void updatePlaybackState({
    bool? playing,
    Duration? position,
    Duration? bufferedPosition,
    MediaItem? newItem,
  }) {
    if (newItem != null) {
      mediaItem.add(newItem);
    }

    final isPlaying = playing ?? playbackState.value.playing;
    final controls = [
      MediaControl.skipToPrevious,
      isPlaying ? MediaControl.pause : MediaControl.play,
      MediaControl.skipToNext,
      MediaControl.stop,
    ];

    playbackState.add(
      playbackState.value.copyWith(
        controls: controls,
        playing: isPlaying,
        updatePosition: position ?? playbackState.value.updatePosition,
        bufferedPosition:
            bufferedPosition ?? playbackState.value.bufferedPosition, // 传入缓冲
        speed: 1.0,
        androidCompactActionIndices: const [0, 1, 2],
      ),
    );
  }

  MediaKitAudioHandler() {
    _setupAudioSessionInterruptions();
  }

  Future<void> _setupAudioSessionInterruptions() async {
    final session = await AudioSession.instance;
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        // 中断开始
        switch (event.type) {
          case AudioInterruptionType.duck:
            // 系统会自动降低音量，无需处理
            break;
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            // 需要暂停播放
            onPause?.call();
            break;
        }
      } else {
        // 中断结束
        switch (event.type) {
          case AudioInterruptionType.duck:
            // 系统自动恢复音量
            break;
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            // 恢复播放
            onPlay?.call();
            break;
        }
      }
    });

    // 如果希望拔出耳机时自动暂停，可以取消下面注释
    // session.becomingNoisyEventStream.listen((_) {
    //   // 音频输出设备断开，可选择暂停
    //   onPause?.call();
    // });
    // 根据需求3，我们不处理 noisy 事件，因此保持注释
  }
}
