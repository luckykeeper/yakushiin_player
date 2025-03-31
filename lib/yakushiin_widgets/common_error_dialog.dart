// yakushiin_player
// @CreateTime    : 2025/03/28 23:52
// @Author        : Luckykeeper
// @Email         : luckykeeper@luckykeeper.site
// @Project       : yakushiin_player

import 'package:flutter/material.dart';
import '../theme/font.dart';

Future<dynamic> commonErrorDialog(
  BuildContext context,
  String titleText,
  String contentText,
  String acknowledgeText, {
  Function? interactiveFunction,
  String customImageAssetsLocation =
      "assets/images/operationFailedYakushiin.jpg",
  double customImageWidth = 200,
}) {
  return showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(titleText, style: styleFontSimkai),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Builder(
                  builder:
                      (context) => Image.asset(
                        customImageAssetsLocation,
                        width: customImageWidth,
                      ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(child: Text(contentText, style: styleFontSimkai)),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (interactiveFunction == null) {
                Navigator.of(context).pop();
              } else {
                interactiveFunction();
              }
            },
            child: Text(acknowledgeText, style: styleFontSimkai),
          ),
        ],
      );
    },
  );
}
