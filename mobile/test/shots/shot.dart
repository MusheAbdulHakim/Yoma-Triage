// Local tool, not part of `flutter test`: renders screens with the real fonts at
// 360×640 dp (×3) into build/shots/, for checking layouts against the Stitch designs
// without an emulator. Run: flutter test test/shots/<name>_shot.dart (not part of the default run: only *_test.dart files are)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/theme/yoma_theme.dart';

Future<void> loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      loader.addFont(File(f).readAsBytes().then((b) => ByteData.sublistView(b)));
    }
    await loader.load();
  }

  const dir = 'assets/fonts/atkinson_hyperlegible_next';
  await family(yomaFontFamily, [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold'])
      '$dir/AtkinsonHyperlegibleNext-$w.ttf',
  ]);
  final home = Platform.environment['HOME'];
  await family('MaterialIcons', [
    '$home/flutter-3.44.8/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
}

/// Pumps [screen] on a 360×640 dp phone (24 dp status bar, 24 dp gesture bar).
Future<void> pumpPhone(WidgetTester tester, Widget screen,
    {Size size = const Size(360, 640), double textScale = 1}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 72, bottom: 72);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(RepaintBoundary(
    key: const Key('shot'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildYomaTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: screen,
    ),
  ));
  await settle(tester);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')));
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = File('build/shots/$name.png')..createSync(recursive: true);
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
