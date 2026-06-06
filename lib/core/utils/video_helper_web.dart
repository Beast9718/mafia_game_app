// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

String createVideoUrl(String base64String) {
  final bytes = base64Decode(base64String);
  final blob = html.Blob([bytes], 'video/mp4');
  return html.Url.createObjectUrlFromBlob(blob);
}

void revokeVideoUrl(String url) {
  try {
    html.Url.revokeObjectUrl(url);
  } catch (e) {
    // Ignore error
  }
}
