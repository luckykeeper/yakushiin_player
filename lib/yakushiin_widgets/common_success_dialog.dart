// yakushiin_player
// @CreateTime    : 2025/03/28 23:52
// @Author        : Luckykeeper
// @Email         : luckykeeper@luckykeeper.site
// @Project       : yakushiin_player

import 'package:flutter/material.dart';
import '../theme/font.dart';

Future<dynamic> commonSuccessDialog(
  BuildContext context,
  String titleText,
  String contentText,
  String acknowledgeText, {
  Function? interactiveFunction,
  String customImageAssetsLocation =
      "assets/images/operationSuccessYakushiin.jpg",
  double customImageWidth = 200,
  Widget? customContent,
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
                  builder: (context) {
                    if (customImageAssetsLocation.length > 1) {
                      return Image.asset(
                        customImageAssetsLocation,
                        width: customImageWidth,
                      );
                    } else {
                      return Container();
                    }
                  },
                ),
              ],
            ),
            Builder(
              builder: (context) {
                if (customContent == null) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [Text(contentText, style: styleFontSimkai)],
                  );
                } else {
                  return customContent;
                }
              },
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
