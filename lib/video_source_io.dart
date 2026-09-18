import 'dart:io';

import 'package:video_player/video_player.dart';

Future<VideoPlayerController> createVideoController(String source) async {
  if (source.startsWith('http://') || source.startsWith('https://')) {
    return VideoPlayerController.networkUrl(Uri.parse(source));
  }
  return VideoPlayerController.file(File(source));
}
