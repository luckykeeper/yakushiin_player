// yakushiin_player
// @CreateTime    : 2025/03/28 23:52
// @Author        : Luckykeeper
// @Email         : luckykeeper@luckykeeper.site
// @Project       : yakushiin_player

import 'package:flutter/material.dart';

import '../theme/font.dart';

Future<dynamic> commonQuestionDialog(
  BuildContext context,
  String titleText,
  List<Widget> contentWidgetList,
  String cancelText,
  String acknowledgeText, {
  Function? interactiveFunction,
  bool doNotShowCancelText = false,
  bool makeDialogScrollView = false,
}) {
  return showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(titleText, style: styleFontSimkai),
        content: Builder(
          builder: (context) {
            if (makeDialogScrollView) {
              return SizedBox(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: contentWidgetList,
                  ),
                ),
              );
            } else {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: contentWidgetList,
              );
            }
          },
        ),
        actions: [
          Builder(
            builder: (context) {
              if (doNotShowCancelText) {
                return Container();
              } else {
                return TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text(cancelText, style: styleFontSimkai),
                );
              }
            },
          ),
          TextButton(
            onPressed: () {
              if (interactiveFunction == null) {
                Navigator.of(context).pop();
              } else {
                interactiveFunction();
                Navigator.of(context).pop();
              }
            },
            child: Text(acknowledgeText, style: styleFontSimkai),
          ),
        ],
      );
    },
  );
}
