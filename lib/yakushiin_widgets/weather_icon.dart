// yakushiin_player
// @CreateTime    : 2025/03/30 10:47
// @Author        : Luckykeeper
// @Email         : luckykeeper@luckykeeper.site
// @Project       : yakushiin_player

import 'package:flutter/material.dart';

class WeatherIconWidget extends StatelessWidget {
  final String iconCode;

  const WeatherIconWidget({super.key, required this.iconCode});

  @override
  Widget build(BuildContext context) {
    final iconUrl = 'https://openweathermap.org/img/wn/$iconCode@2x.png';

    return Image.network(
      iconUrl,
      width: 50,
      height: 50,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Center(child: CircularProgressIndicator(value: null));
      },
      errorBuilder: (context, error, stackTrace) {
        return Icon(Icons.error);
      },
    );
  }
}
