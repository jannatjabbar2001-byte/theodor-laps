import 'package:video_player/video_player.dart';

Future<VideoPlayerController> createVideoController(String source) async {
  return VideoPlayerController.networkUrl(Uri.parse(source));
}
