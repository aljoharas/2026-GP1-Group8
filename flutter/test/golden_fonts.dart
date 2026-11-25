// Real fonts for golden tests, so text renders as glyphs instead of boxes.
// Same approach as wrapped_golden_test.dart: Roboto and Material Icons from the
// Flutter SDK. Goldens were made on macOS; other platforms rasterise text
// slightly differently, so run them with `--exclude-tags golden` there.

import 'dart:io';

import 'package:flutter/services.dart';

/// The Flutter SDK's root, from the env or from the test runner's location
/// (`bin/cache/artifacts/engine/<platform>/flutter_tester`).
String? _flutterRoot() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null) return env;
  var dir = File(Platform.resolvedExecutable).parent;
  while (dir.parent.path != dir.path) {
    if (File('${dir.path}/bin/flutter').existsSync()) return dir.path;
    dir = dir.parent;
  }
  return null;
}

Future<void> loadGoldenFonts() async {
  final root = _flutterRoot();
  if (root == null) throw StateError('Could not find the Flutter SDK to load fonts from');
  final fonts = Directory('$root/bin/cache/artifacts/material_fonts');
  Future<void> load(String family, Iterable<File> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await loader.load();
  }

  final files = fonts.listSync().whereType<File>().toList();
  await load('Roboto', files.where((f) => RegExp(r'/Roboto-[A-Za-z]+\.ttf$').hasMatch(f.path)));
  await load('MaterialIcons', files.where((f) => f.path.endsWith('MaterialIcons-Regular.otf')));
}
