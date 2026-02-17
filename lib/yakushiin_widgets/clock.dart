// yakushiin_player
// @CreateTime    : 2026/02/17 13:19
// @Author        : Luckykeeper
// @Email         : luckykeeper@luckykeeper.site
// @Project       : yakushiin_player

import 'package:flutter/material.dart';
import 'dart:async';

/// 一个实时显示当前时间的组件，格式为 HH:mm:ss
class Clock extends StatefulWidget {
  const Clock({super.key, required this.clockTextStyle});
  final TextStyle clockTextStyle;

  @override
  State<Clock> createState() => _ClockState();
}

class _ClockState extends State<Clock> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // 每秒更新一次
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _now = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 格式化时分秒，补零到两位
    final hours = _now.hour.toString().padLeft(2, '0');
    final minutes = _now.minute.toString().padLeft(2, '0');
    final seconds = _now.second.toString().padLeft(2, '0');
    final timeStr = '$hours:$minutes:$seconds';

    return Text(timeStr, style: widget.clockTextStyle);
  }
}
