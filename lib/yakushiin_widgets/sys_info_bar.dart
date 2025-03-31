// yakushiin_player
// @CreateTime    : 2025/03/28 23:52
// @Author        : Luckykeeper
// @Email         : luckykeeper@luckykeeper.site
// @Project       : yakushiin_player

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:yakushiin_player/theme/font.dart';

Widget systemInfoBar = Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Column(
      children: [
        Row(
          children: [
            Text(
              "OS：【${Platform.operatingSystemVersion} | ${Platform.numberOfProcessors} cores | ${Platform.localeName}】",
              style: TextStyle(
                fontFamily: fontSimkaiFamily,
                color: Colors.cyan[300],
                overflow: TextOverflow.clip,
              ),
            ),
          ],
        ),
      ],
    ),
    Column(
      children: [
        Text(
          "Runtime：【${Platform.version}】",
          style: TextStyle(
            fontFamily: fontSimkaiFamily,
            color: Colors.cyan[300],
            overflow: TextOverflow.clip,
          ),
        ),
      ],
    ),
  ],
);
