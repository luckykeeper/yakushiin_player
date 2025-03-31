// yakushiin_player
// @CreateTime    : 2025/03/28 23:03
// @Author        : Luckykeeper
// @Email         : luckykeeper@luckykeeper.site
// @Project       : yakushiin_player

import 'package:url_launcher/url_launcher.dart';

Future<void> launchUrlWithBrowser(String url) async {
  Uri parsedUrl = Uri.parse(url);
  if (!await launchUrl(parsedUrl)) {
    throw Exception('Could not launch $url');
  }
}
