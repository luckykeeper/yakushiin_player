# YakushiinPlayer ProGuard 规则
# 背景：path_provider_android 2.3.1 的 Pigeon 通道在 release 下报 channel-error
# （详见 pubspec.yaml dependency_overrides 注释），已回退到 2.2.19 并验证 R8 下正常。
# 以下规则用于保护 Flutter 插件注册与平台通道类，防止未来升级时再被 R8 剥离。

# Flutter 插件注册器与插件类（含 Pigeon 生成的通道类）
-keep class io.flutter.plugins.** { *; }

# 保留 FlutterPlugin 生命周期回调（反射调用）
-keepclassmembers class * implements io.flutter.embedding.engine.plugins.FlutterPlugin {
    public void onAttachedToEngine(io.flutter.embedding.engine.plugins.FlutterPluginBinding);
    public void onDetachedFromEngine(io.flutter.embedding.engine.plugins.FlutterPluginBinding);
}

# Pigeon 生成代码
-keep class * extends io.flutter.plugin.common.BasicMessageChannel$MessageHandler { *; }
-keep class * extends io.flutter.plugin.common.MethodChannel$MethodCallHandler { *; }
