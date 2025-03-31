// yakushiin_player
// @CreateTime    : 2025/03/29 09:54
// @Author        : Luckykeeper
// @Email         : luckykeeper@luckykeeper.site
// @Project       : yakushiin_player

import 'dart:io';

Future<double> getTotalSizeOfFilesInDir(final FileSystemEntity file) async {
  if (file is File && await file.exists()) {
    int length = await file.length();
    return double.parse(length.toString());
  }
  if (file is Directory && await file.exists()) {
    List children = file.listSync();
    double total = 0;
    if (children.isNotEmpty) {
      for (final FileSystemEntity child in children) {
        total += await getTotalSizeOfFilesInDir(child);
      }
    }
    return total;
  }
  return 0;
}
