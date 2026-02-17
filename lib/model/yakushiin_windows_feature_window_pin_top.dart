// yakushiin_player
// @CreateTime    : 2026/02/17 13:00
// @Author        : Luckykeeper
// @Email         : luckykeeper@luckykeeper.site
// @Project       : yakushiin_player
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yakushiin_player/theme/font.dart';

// 定义异步状态 provider
final alwaysOnTopProvider = AsyncNotifierProvider<AlwaysOnTopNotifier, bool>(
  () {
    return AlwaysOnTopNotifier();
  },
);

class AlwaysOnTopNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    // 初始化时获取当前置顶状态
    return await windowManager.isAlwaysOnTop();
  }

  // 切换置顶状态
  Future<void> toggle() async {
    // 获取当前状态（如果尚未加载完成，默认为 false）
    final current = state.valueOrNull ?? false;
    // 设置为加载状态
    state = const AsyncValue.loading();
    try {
      if (current) {
        await windowManager.setAlwaysOnTop(false);
      } else {
        await windowManager.setAlwaysOnTop(true);
      }
      // 重新获取最新状态，确保与实际一致
      final newState = await windowManager.isAlwaysOnTop();
      state = AsyncValue.data(newState);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }
}

// 按钮组件
class PinWindowButton extends ConsumerWidget {
  const PinWindowButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(alwaysOnTopProvider);

    return asyncState.when(
      data: (isOnTop) {
        return ElevatedButton.icon(
          onPressed: () => ref.read(alwaysOnTopProvider.notifier).toggle(),
          icon: Icon(
            isOnTop ? Icons.pin_drop_rounded : Icons.pin_drop_outlined,
          ),
          label: Text(isOnTop ? '取消置顶' : '置顶', style: styleFontSimkai),
        );
      },
      loading:
          () => ElevatedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.refresh_rounded),
            label: Text('加载中...', style: styleFontSimkai),
          ),
      error: (error, stack) => Text('错误: $error', style: styleFontSimkai),
    );
  }
}
