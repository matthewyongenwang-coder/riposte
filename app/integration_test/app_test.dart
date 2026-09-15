// End to end: the real app, the real engine, a real competition clip.
//
//   flutter test integration_test/app_test.dart -d macos \
//     --dart-define=RIPOSTE_TEST_CLIP="/path/to/IMG_1135 3.MOV"
//
// The check that matters most is the last one. Boxes are drawn in screen
// pixels and the tracker works in video pixels, so the test reads the trace
// the tracker wrote and confirms the boxes arrived where they were drawn.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:riposte/frame_view.dart';
import 'package:riposte/main.dart';
import 'package:riposte/results.dart';
import 'package:riposte/workspace.dart';
import 'package:video_player/video_player.dart';

const clip = String.fromEnvironment('RIPOSTE_TEST_CLIP');

Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 90)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out after $timeout waiting for $finder');
}

Offset videoToScreen(WidgetTester tester, Size video, Offset point) {
  final rect = tester.getRect(find.byType(FrameView));
  final fitted = applyBoxFit(BoxFit.contain, video, rect.size).destination;
  final left = rect.left + (rect.width - fitted.width) / 2;
  final top = rect.top + (rect.height - fitted.height) / 2;
  final scale = fitted.width / video.width;
  return Offset(left + point.dx * scale, top + point.dy * scale);
}

Future<void> drawBox(WidgetTester tester, Size video, List<int> box) async {
  final from = videoToScreen(tester, video, Offset(box[0].toDouble(), box[1].toDouble()));
  final to = videoToScreen(tester, video, Offset((box[0] + box[2]).toDouble(), (box[1] + box[3]).toDouble()));
  final gesture = await tester.startGesture(from);
  for (var i = 1; i <= 12; i++) {
    await gesture.moveTo(Offset.lerp(from, to, i / 12)!);
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('open a clip, box both fencers, track, see the results', (tester) async {
    expect(clip, isNotEmpty, reason: 'Pass --dart-define=RIPOSTE_TEST_CLIP=/path/to/a/clip');

    await tester.pumpWidget(const RiposteApp());
    await pumpUntil(tester, find.byType(Workspace));

    final state = tester.state<WorkspaceState>(find.byType(Workspace));
    await state.openClip(clip);
    await pumpUntil(tester, find.descendant(of: find.byType(FrameView), matching: find.byType(Image)));

    // The portland-still benchmark boxes, so the result is comparable.
    const boxA = [240, 430, 175, 215];
    const boxB = [1470, 455, 230, 190];
    const video = Size(1920, 1080);
    await drawBox(tester, video, boxA);
    await drawBox(tester, video, boxB);
    expect(find.text('Track this phrase'), findsOneWidget, reason: 'Run should be enabled once both boxes exist');

    state.framesToProcess = 30;
    await tester.pump();
    await tester.tap(find.text('Track this phrase'));
    await pumpUntil(tester, find.byType(ResultsView), timeout: const Duration(minutes: 5));
    expect(find.text('Done'), findsOneWidget);

    final result = tester.widget<ResultsView>(find.byType(ResultsView)).result;
    final trace = jsonDecode(File(result.trace).readAsStringSync()) as Map<String, dynamic>;
    final header = trace['header'] as Map<String, dynamic>;

    for (final (label, got, want) in [
      ('Fencer A', header['seed_box_a'] as List, boxA),
      ('Fencer B', header['seed_box_b'] as List, boxB),
    ]) {
      for (var i = 0; i < 4; i++) {
        final diff = ((got[i] as num) - want[i]).abs();
        expect(diff, lessThanOrEqualTo(3), reason: '$label box value $i: drew $want, tracker got $got');
      }
    }
    expect(header['start_frame'], 0);
    expect(header['max_frames'], 30);
    expect(header['tracker'], 'vit');
    expect((trace['frames'] as List).length, 30);
    expect(File(result.video).existsSync(), isTrue);
    expect(File(result.csv).existsSync(), isTrue);

    // And the annotated clip should actually play inside the app.
    await pumpUntil(tester, find.byType(VideoPlayer), timeout: const Duration(seconds: 30));
  });
}
