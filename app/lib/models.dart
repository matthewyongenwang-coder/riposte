import 'dart:math' as math;

import 'package:flutter/painting.dart';

enum Fencer { a, b }

extension FencerNames on Fencer {
  String get label => this == Fencer.a ? 'Fencer A' : 'Fencer B';
  String get letter => this == Fencer.a ? 'A' : 'B';
  Fencer get other => this == Fencer.a ? Fencer.b : Fencer.a;
}

enum TrackerKind { vit, csrt }

extension TrackerNames on TrackerKind {
  String get label => this == TrackerKind.vit ? 'ViT' : 'CSRT';
}

int _int(Object? v) => (v as num?)?.toInt() ?? 0;
double _double(Object? v) => (v as num?)?.toDouble() ?? 0;

class ClipInfo {
  const ClipInfo({
    required this.path,
    required this.name,
    required this.width,
    required this.height,
    required this.frames,
    required this.fps,
    required this.sizeBytes,
    this.measured = false,
  });

  factory ClipInfo.fromJson(Map<String, dynamic> j) => ClipInfo(
        path: j['path'] as String,
        name: j['name'] as String,
        width: _int(j['width']),
        height: _int(j['height']),
        frames: math.max(_int(j['frames']), 1),
        fps: _double(j['fps']) > 0 ? _double(j['fps']) : 30,
        sizeBytes: _int(j['size_bytes']),
      );

  final String path;
  final String name;
  final int width;
  final int height;
  final int frames;
  final double fps;
  final int sizeBytes;

  /// True once the engine has decoded the clip and counted the real frames.
  /// The file header count can be wrong: one clip claims 127 and has 120.
  final bool measured;

  Size get size => Size(width.toDouble(), height.toDouble());

  ClipInfo withMeasured({required int frames, required double fps}) => ClipInfo(
        path: path,
        name: name,
        width: width,
        height: height,
        frames: math.max(frames, 1),
        fps: fps > 0 ? fps : this.fps,
        sizeBytes: sizeBytes,
        measured: true,
      );
}

class FrameImage {
  const FrameImage({required this.index, required this.image, required this.width, required this.height});

  factory FrameImage.fromJson(Map<String, dynamic> j) => FrameImage(
        index: _int(j['index']),
        image: j['image'] as String,
        width: _int(j['width']),
        height: _int(j['height']),
      );

  final int index;
  final String image;
  final int width;
  final int height;
}

/// A box in video pixels, not screen pixels. The tracker only ever sees
/// these numbers, so they are kept in the same space it works in.
class Box {
  const Box(this.x, this.y, this.w, this.h);

  factory Box.fromCorners(Offset a, Offset b) => Box(
        math.min(a.dx, b.dx),
        math.min(a.dy, b.dy),
        (a.dx - b.dx).abs(),
        (a.dy - b.dy).abs(),
      );

  final double x;
  final double y;
  final double w;
  final double h;

  Rect get rect => Rect.fromLTWH(x, y, w, h);

  List<int> toJson() => [x.round(), y.round(), w.round(), h.round()];

  bool get isUsable => w >= 8 && h >= 8;

  /// A mask and torso box is about 1.2 tall for every 1 wide, a full body
  /// box about 1.7. The same threshold main.py warns at.
  bool get looksFullBody => w > 0 && h / w > 1.5;
}

class RunEvent {
  const RunEvent({required this.kind, required this.frame, required this.seconds, required this.who});

  factory RunEvent.fromJson(Map<String, dynamic> j) => RunEvent(
        kind: j['kind'] as String? ?? '',
        frame: _int(j['frame']),
        seconds: _double(j['t_sec']),
        who: j['who'] as String?,
      );

  final String kind;
  final int frame;
  final double seconds;
  final String? who;
}

class FencerStats {
  const FencerStats({required this.trackedPct, required this.posePct});

  factory FencerStats.fromJson(Map<String, dynamic> j) =>
      FencerStats(trackedPct: _double(j['tracked_pct']), posePct: _double(j['pose_pct']));

  final double trackedPct;
  final double posePct;
}

class RunSummary {
  const RunSummary({required this.frames, required this.fencers, required this.events, this.tracker, this.error});

  factory RunSummary.fromJson(Map<String, dynamic> j) {
    if (j['error'] != null) {
      return RunSummary(frames: 0, fencers: const [], events: const [], error: j['error'] as String);
    }
    return RunSummary(
      frames: _int(j['frames']),
      fencers: [
        for (final f in (j['fencers'] as List? ?? const [])) FencerStats.fromJson(f as Map<String, dynamic>),
      ],
      events: [
        for (final e in (j['events'] as List? ?? const [])) RunEvent.fromJson(e as Map<String, dynamic>),
      ],
      tracker: j['tracker'] as String?,
    );
  }

  final int frames;
  final List<FencerStats> fencers;
  final List<RunEvent> events;
  final String? tracker;
  final String? error;
}

class RunResult {
  const RunResult({
    required this.folder,
    required this.video,
    required this.csv,
    required this.trace,
    required this.seconds,
    required this.summary,
    required this.startFrame,
  });

  factory RunResult.fromEvent(Map<String, dynamic> j, {required int startFrame}) => RunResult(
        folder: j['folder'] as String,
        video: j['video'] as String,
        csv: j['csv'] as String,
        trace: j['trace'] as String,
        seconds: _double(j['seconds']),
        summary: RunSummary.fromJson((j['summary'] as Map?)?.cast<String, dynamic>() ?? const {}),
        startFrame: startFrame,
      );

  final String folder;
  final String video;
  final String csv;
  final String trace;
  final double seconds;
  final RunSummary summary;
  final int startFrame;
}
